import 'dart:async';
import 'dart:io' show Platform;

import 'package:PiliPlus/grpc/dyn.dart';
import 'package:PiliPlus/http/dynamics.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/msg.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:get/get.dart';

/// 本地通知服务：动态更新 & UP 开播提醒
///
/// 说明：这是「本地轮询 + 系统通知」，不是 B站服务端推送。
/// App 运行时按间隔拉取，发现新动态/新开播就发本地通知。
/// App 被系统彻底杀掉后不再工作（第三方客户端拿不到 B站推送凭证）。
class LocalNotifyService {
  LocalNotifyService._();
  static final instance = LocalNotifyService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  Timer? _timer;
  bool _inited = false;
  bool _polling = false;

  /// 上次看到的动态未读数，用于判断「增加」
  int? _lastDynCount;

  /// 上次正在直播的 uid → 名字，用于判断「新开播」
  final Map<int, String> _lastLive = {};

  /// 上次的消息未读总数（私信/@/回复/点赞/系统）
  int? _lastMsgCount;

  /// 动态未读数回调：由 MainController 注册，用它同步底部角标。
  /// 通知轮询本来就把 dynRed 拉回来了，角标不必再单独轮询一遍。
  void Function(int count)? onDynCount;

  /// 是否有通知权限
  bool get _canNotify =>
      Pref.enableMsgNotif || Pref.enableDynNotif || Pref.enableLiveNotif;

  Future<void> init() async {
    if (_inited) return;
    _inited = true;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinInit = DarwinInitializationSettings();
    await _plugin.initialize(
      const InitializationSettings(
        android: androidInit,
        iOS: darwinInit,
      ),
      onDidReceiveNotificationResponse: _onTap,
    );

    // 创建通知渠道（Android 8+）
    const channel = AndroidNotificationChannel(
      'piliplus_dyn_live',
      '动态与开播提醒',
      description: '关注的 UP 发布动态或开播时的本地提醒',
      importance: Importance.high,
      playSound: true,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  /// 请求通知权限（Android 13+），返回是否授予
  Future<bool> requestPermission() async {
    if (!kIsWeb && Platform.isAndroid) {
      final granted = await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      return granted ?? false;
    }
    if (Platform.isIOS) {
      final granted = await _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
      return granted ?? false;
    }
    return true;
  }

  /// 根据设置启动/停止轮询
  Future<void> syncPolling() async {
    await init();
    if (!_canNotify) {
      stop();
      return;
    }
    final granted = await requestPermission();
    if (!granted) {
      if (kDebugMode) debugPrint('通知权限未授予，不启动轮询');
      stop();
      return;
    }
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    final seconds = Pref.notifPollInterval.clamp(15, 3600).toInt();
    // 先跑一次建立基线（避免刚开启就把已有的当新的全推一遍）
    _pollOnce(initial: true);
    _timer = Timer.periodic(Duration(seconds: seconds), (_) => _pollOnce());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// 回到前台时立刻补一次检测。
  ///
  /// Android 会在 App 进后台后挂起 Flutter 的 Timer，轮询实际停摆；
  /// 用户切回来时补一次，至少不会「回来还看不到刚才的提醒」。
  Future<void> checkNow() async {
    if (!_canNotify) return;
    await _pollOnce();
  }

  Future<void> _pollOnce({bool initial = false}) async {
    if (_polling) return;
    _polling = true;
    try {
      if (Pref.enableMsgNotif) await _checkMsg(initial: initial);
      if (Pref.enableDynNotif) await _checkDynamic(initial: initial);
      if (Pref.enableLiveNotif) await _checkLive(initial: initial);
    } catch (e) {
      debugPrint('本地通知轮询错误: $e');
    } finally {
      _polling = false;
    }
  }

  /// 消息未读（私信 / @ / 回复 / 点赞 / 系统）增加时发通知
  ///
  /// 这是「来消息及时通知」的主体 —— 之前只做了动态红点和开播，
  /// 私信/回复/@ 完全没提醒，所以用户觉得「有未读但不提醒」。
  Future<void> _checkMsg({required bool initial}) async {
    var total = 0;
    // 私信
    final single = await MsgHttp.msgUnread();
    if (single case Success(:final response)) {
      total += response.followUnread +
          response.unfollowUnread +
          response.bizMsgFollowUnread +
          response.bizMsgUnfollowUnread +
          response.unfollowPushMsg +
          response.customUnread;
    }
    // @ / 回复 / 点赞 / 系统
    final feed = await MsgHttp.msgFeedUnread();
    if (feed case Success(:final response)) {
      total += response.at + response.reply + response.like + response.sysMsg;
    }

    final prev = _lastMsgCount;
    _lastMsgCount = total;
    if (initial || prev == null) return; // 首次只建基线
    if (total > prev) {
      await _show(
        id: 1000,
        title: '新消息',
        body: '有 ${total - prev} 条新的未读消息',
        payload: 'msg',
      );
    }
  }

  /// 动态未读增加时发通知
  Future<void> _checkDynamic({required bool initial}) async {
    final count = await DynGrpc.dynRed();
    if (count == null) return;
    // 顺手同步底部角标，避免和「检查未读动态」各轮询一次
    onDynCount?.call(count);
    final prev = _lastDynCount;
    _lastDynCount = count;
    debugPrint('动态未读: $prev -> $count (initial=$initial)');
    if (initial || prev == null) return; // 首次只建基线
    if (count > prev) {
      await _show(
        id: 1001,
        title: '动态更新',
        body: '有 ${count - prev} 条新的关注动态',
        payload: 'dyn',
      );
    }
  }

  /// 对比直播状态，新开播的 UP 发通知
  Future<void> _checkLive({required bool initial}) async {
    if (_lastLive.isEmpty && initial) {
      // 首次先拉一次建立基线，下面逻辑统一处理
    }
    // 关注的 uid 从账号信息取不到完整列表时，用动态页 liveUsers 的 mid。
    // 这里用 PiliPlus 已有的 followDynamic 拿到的直播列表。
    final live = await _fetchLiveUsers();
    if (live == null) return;

    final current = {for (final e in live.entries) e.key: e.value};
    if (initial) {
      _lastLive
        ..clear()
        ..addAll(current);
      return;
    }
    for (final entry in current.entries) {
      final wasLive = _lastLive.containsKey(entry.key);
      if (!wasLive) {
        await _show(
          id: 2000 + entry.key,
          title: '${entry.value} 开播了',
          body: '快去看直播',
          payload: 'live:${entry.key}',
        );
      }
    }
    _lastLive
      ..clear()
      ..addAll(current);
  }

  /// 拉取正在直播的 UP（mid → uname）
  Future<Map<int, String>?> _fetchLiveUsers() async {
    try {
      // followUp() 返回的 FollowUpModel.liveUsers 就是「正在直播」列表，
      // 是项目现成接口，比自己拉全量关注 uid 再逐个查状态轻得多
      final model = await DynamicsHttp.followUp();
      final live = model.dataOrNull?.liveUsers;
      if (live == null) return null;
      final result = <int, String>{};
      for (final item in live.items ?? const []) {
        result[item.mid] = item.uname ?? 'UP主';
      }
      return result;
    } catch (_) {
      return null;
    }
  }

  Future<void> _show({
    required int id,
    required String title,
    required String body,
    required String payload,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'piliplus_dyn_live',
      '动态与开播提醒',
      channelDescription: '关注的 UP 发布动态或开播时的本地提醒',
      importance: Importance.high,
      priority: Priority.high,
      ticker: 'PiliPlus 提醒',
    );
    const details = NotificationDetails(android: androidDetails);
    await _plugin.show(id, title, body, details, payload: payload);
  }

  void _onTap(NotificationResponse response) {
    // 点击通知目前不做跳转：service 层静态依赖 MainController 会形成
    // controller → service → controller 的循环 import，得不偿失。
    // 通知本身已经起到提醒作用，用户点开 App 自己进动态页即可。
    // 后续若要精确跳转，可通过 Get.key 或回调注入实现。
  }
}
