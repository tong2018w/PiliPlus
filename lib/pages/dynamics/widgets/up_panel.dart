import 'dart:math' as math;

import 'package:PiliPlus/common/assets.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/models/common/dynamic/up_panel_position.dart';
import 'package:PiliPlus/models/dynamics/up.dart';
import 'package:PiliPlus/pages/dynamics/controller.dart';
import 'package:PiliPlus/pages/live_follow/view.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/extension/num_ext.dart';
import 'package:PiliPlus/utils/feed_back.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

/// Live 入口的小呼吸点：有直播时缓慢脉动，提示可以点进去
class _LivePulse extends StatefulWidget {
  const _LivePulse();

  @override
  State<_LivePulse> createState() => _LivePulseState();
}

class _LivePulseState extends State<_LivePulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.35, end: 1.0).animate(_c),
      child: Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          shape: .circle,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

/// 直播头像外圈的渐变呼吸环
class _LiveRing extends StatefulWidget {
  const _LiveRing({required this.child});

  final Widget child;

  @override
  State<_LiveRing> createState() => _LiveRingState();
}

class _LiveRingState extends State<_LiveRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = _c.value;
        // 呼吸 + 缓慢旋转的粉紫渐变环，套在头像外圈
        return CustomPaint(
          foregroundPainter: _RingPainter(
            progress: t,
            color: color,
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final r = Rect.fromCircle(
      center: rect.center,
      radius: rect.shortestSide / 2 + 2.5,
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..shader = SweepGradient(
        startAngle: progress * math.pi * 2,
        endAngle: progress * math.pi * 2 + math.pi * 1.6,
        colors: [color.withValues(alpha: 0.15), color, color.withValues(alpha: 0.15)],
      ).createShader(r);
    canvas.drawArc(r, 0, math.pi * 2, false, paint);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress;
}

class UpPanel extends StatefulWidget {
  const UpPanel({
    super.key,
    required this.upData,
    required this.dynamicsController,
  });

  final FollowUpModel upData;
  final DynamicsController dynamicsController;

  @override
  State<UpPanel> createState() => _UpPanelState();
}

class _UpPanelState extends State<UpPanel> {
  late final controller = widget.dynamicsController;
  late final isTop = controller.upPanelPosition == UpPanelPosition.top;

  void toFollowPage() => Get.to(const LiveFollowPage());

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final upData = widget.upData;
    final upList = upData.upList;
    final liveList = upData.liveUsers?.items;
    return CustomScrollView(
      scrollDirection: isTop ? .horizontal : .vertical,
      physics: const AlwaysScrollableScrollPhysics(),
      controller: controller.scrollController,
      slivers: [
        SliverToBoxAdapter(
          child: InkWell(
            onTap: () => setState(() {
              controller.showLiveUp = !controller.showLiveUp;
            }),
            onLongPress: toFollowPage,
            onSecondaryTap: PlatformUtils.isMobile ? null : toFollowPage,
            child: Container(
              alignment: .center,
              height: isTop ? 76 : 60,
              // 原来 Live(0) 也占一大块还带箭头，挤得第一个头像没地方。
              // 没直播时收成紧凑纯文字入口，有直播时才带呼吸圆点和箭头
              padding: isTop ? const .only(left: 8, right: 2) : null,
              child: Text.rich(
                textAlign: .center,
                style: TextStyle(
                  fontSize: (upData.liveUsers?.count ?? 0) > 0 ? 13 : 11.5,
                  color: theme.colorScheme.primary,
                ),
                TextSpan(
                  children: [
                    if ((upData.liveUsers?.count ?? 0) > 0) ...[
                      const WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: _LivePulse(),
                      ),
                      const TextSpan(text: ' '),
                    ],
                    TextSpan(
                      text: (upData.liveUsers?.count ?? 0) > 0
                          ? 'Live(${upData.liveUsers!.count})'
                          : 'Live',
                    ),
                    if (!isTop) ...[
                      const TextSpan(text: '\n'),
                      WidgetSpan(
                        alignment: .middle,
                        child: Icon(
                          controller.showLiveUp
                              ? Icons.expand_less
                              : Icons.expand_more,
                          size: 12,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ] else if ((upData.liveUsers?.count ?? 0) > 0)
                      WidgetSpan(
                        alignment: .middle,
                        child: Icon(
                          controller.showLiveUp
                              ? Icons.keyboard_arrow_right
                              : Icons.keyboard_arrow_left,
                          color: theme.colorScheme.primary,
                          size: 14,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (controller.showLiveUp && liveList != null && liveList.isNotEmpty)
          SliverList.builder(
            itemCount: liveList.length,
            itemBuilder: (context, index) {
              return upItemBuild(theme, liveList[index]);
            },
          ),
        SliverToBoxAdapter(
          child: Obx(
            () => upItemBuild(
              theme,
              UpItem(face: '', uname: '全部动态', mid: -1),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Obx(
            () => upItemBuild(
              theme,
              UpItem(
                uname: '我',
                face: controller.accountService.face.value,
                mid: Accounts.main.mid,
              ),
            ),
          ),
        ),
        if (upList != null && upList.isNotEmpty)
          SliverList.builder(
            itemCount: upList.length,
            itemBuilder: (context, index) {
              // 逐 UP 横向分页滑动时，高亮跟随当前 UP
              return Obx(() => upItemBuild(theme, upList[index]));
            },
          ),
        if (isTop) const SliverToBoxAdapter(child: SizedBox(width: 8)),
        if (!isTop) const SliverToBoxAdapter(child: SizedBox(height: 200)),
      ],
    );
  }

  void _onSelect(UpItem item) {
    item.hasUpdate = false;
    controller.onSelectUp(item.mid);
    setState(() {});
  }

  Widget upItemBuild(ThemeData theme, UpItem item) {
    final currentMid = controller.currentMid;
    final isLive = item is LiveUserItem;
    // 只有「全部动态」和自己那一位算选中；原来是 currentMid == -1 就全高亮，
    // 导致头像栏一片全亮，看不出当前停在哪位 UP
    final isCurrent = isLive || currentMid == item.mid;

    final isAll = item.mid == -1;
    void toMemberPage() => Get.toNamed('/member?mid=${item.mid}');

    Widget avatar;
    if (isAll) {
      avatar = DecoratedBox(
        decoration: const BoxDecoration(
          shape: .circle,
          color: Color(0xFF5CB67B),
        ),
        child: Image.asset(
          width: 38,
          height: 38,
          cacheWidth: 38.cacheSize(context),
          Assets.logo2,
          color: Colors.white,
        ),
      );
    } else {
      avatar = Padding(
        padding: const .symmetric(horizontal: 4),
        child: NetworkImgLayer(
          width: 38,
          height: 38,
          src: item.face,
          type: .avatar,
        ),
      );
      if (isLive) {
        // 直播头像：外圈渐变呼吸环 + 右下角小 LIVE 标
        avatar = _LiveRing(
          child: Stack(
            clipBehavior: .none,
            children: [
              avatar,
              Positioned(
                bottom: -2,
                right: -8,
                child: IgnorePointer(
                  child: Container(
                    padding: const .symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: const .all(.circular(4)),
                    ),
                    child: const Text(
                      'LIVE',
                      style: TextStyle(
                        fontSize: 8,
                        height: 1.1,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      } else if (item.hasUpdate ?? false) {
        avatar = Stack(
          clipBehavior: .none,
          children: [
            avatar,
            Positioned(
              top: 0,
              right: 4,
              child: Badge(
                smallSize: 8,
                backgroundColor: theme.colorScheme.primary,
              ),
            ),
          ],
        );
      }
    }

    return SizedBox(
      height: 76,
      width: isTop ? 70 : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          feedBack();
          if (isLive) {
            PageUtils.toLiveRoom(item.roomId);
          } else {
            _onSelect(item);
          }
        },
        // onDoubleTap: isLive ? () => _onSelect(data) : null,
        onLongPress: !isAll ? toMemberPage : null,
        onSecondaryTap: !isAll && !PlatformUtils.isMobile ? toMemberPage : null,
        child: AnimatedOpacity(
          opacity: isCurrent ? 1 : 0.62,
          duration: const Duration(milliseconds: 170),
          curve: Curves.easeOutCubic,
          child: Column(
            spacing: 4,
            mainAxisSize: .min,
            mainAxisAlignment: .center,
            children: [
              avatar,
              Padding(
                padding: const .symmetric(horizontal: 4),
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 170),
                  curve: Curves.easeOutCubic,
                  style: TextStyle(
                    // 名字只在「确实是当前这位 UP」时高亮，
                    // live 头像保持全亮但不染成主题色
                    color: currentMid == item.mid
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outline,
                    height: 1.1,
                    fontSize: 12.5,
                  ),
                  child: Text(
                    isTop ? '${item.uname}\n' : item.uname!,
                    maxLines: 2,
                    textAlign: .center,
                    overflow: .ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
