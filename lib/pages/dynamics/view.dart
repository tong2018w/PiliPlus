import 'package:PiliPlus/common/widgets/scroll_physics.dart'
    show dynamicHorizontalDragRecognizer, tabBarView;
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models/common/dynamic/dynamics_type.dart';
import 'package:PiliPlus/models/common/dynamic/up_panel_position.dart';
import 'package:PiliPlus/models/dynamics/up.dart';
import 'package:PiliPlus/pages/common/common_page.dart';
import 'package:PiliPlus/pages/dynamics/controller.dart';
import 'package:PiliPlus/pages/dynamics/widgets/up_panel.dart';
import 'package:PiliPlus/pages/dynamics_create/view.dart';
import 'package:PiliPlus/pages/dynamics_tab/view.dart';
import 'package:PiliPlus/pages/dynamics_up/up_page_view.dart';
import 'package:PiliPlus/pages/main/controller.dart';
import 'package:PiliPlus/utils/extension/get_ext.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart' hide DraggableScrollableSheet;

class DynamicsPage extends StatefulWidget {
  const DynamicsPage({super.key});

  @override
  State<DynamicsPage> createState() => _DynamicsPageState();
}

class _DynamicsPageState extends CommonPageState<DynamicsPage>
    with AutomaticKeepAliveClientMixin {
  final _dynamicsController = Get.putOrFind(DynamicsController.new);
  UpPanelPosition get upPanelPosition => _dynamicsController.upPanelPosition;
  late final MainController _mainController = Get.find<MainController>();

  static const double _upBarHeight = 76;

  @override
  bool get wantKeepAlive => true;

  /// 发布按钮：和旁边头像项严格同构。
  ///
  /// 之前是 38px「淡蓝实心圆 + 加号 + 发布」，在一排照片头像里像一坨色块，
  /// 很跳。改成 38px 空心描边圆（和头像同尺寸、同圆形），浅色描边 + 加号，
  /// 视觉重量和未选中头像相当；占宽 70 与头像列完全一致，不再突兀。
  Widget _createDynamicBtn(ColorScheme colorScheme, {bool isRight = true}) =>
      SizedBox(
        width: 70,
        height: _upBarHeight,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => CreateDynPanel.onCreateDyn(context),
          child: Column(
            spacing: 4,
            mainAxisSize: .min,
            mainAxisAlignment: .center,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: .circle,
                  border: Border.all(
                    color: colorScheme.outline.withValues(alpha: 0.5),
                    width: 1.4,
                  ),
                ),
                child: Icon(
                  Icons.add,
                  size: 20,
                  color: colorScheme.outline,
                ),
              ),
              Text(
                '发布',
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.1,
                  color: colorScheme.outline,
                ),
              ),
            ],
          ),
        ),
      );

  Widget upPanelPart(ColorScheme colorScheme) {
    final isTop = upPanelPosition == .top;
    final needBg = upPanelPosition.index > 2;
    return Material(
      type: needBg ? .canvas : .transparency,
      color: needBg ? colorScheme.surface : null,
      child: SizedBox(
        width: isTop ? null : 64,
        height: isTop ? 76 : null,
        child: NotificationListener<ScrollEndNotification>(
          onNotification: (notification) {
            final metrics = notification.metrics;
            if (metrics.pixels >= metrics.maxScrollExtent - 300) {
              _dynamicsController.onLoadMore();
            }
            return false;
          },
          child: Obx(
            () => _buildUpPanel(_dynamicsController.loadingState.value),
          ),
        ),
      ),
    );
  }

  Widget _buildUpPanel(LoadingState<FollowUpModel> upState) {
    return switch (upState) {
      Loading() => const SizedBox.shrink(),
      Success(:final response) => UpPanel(
        upData: response,
        dynamicsController: _dynamicsController,
      ),
      Error() => Center(
        child: IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: _dynamicsController.onReload,
        ),
      ),
    };
  }

  /// 吸顶的 UP 头像栏：发布按钮悬浮固定在最右，头像栏铺满整行横向滚动。
  ///
  /// 之前用 Row(Expanded(头像栏) + 按钮)，按钮占了 70px 独立宽度，
  /// 把头像栏挤窄、最后一个 UP 被压在按钮边上只露半个。
  /// 改成 Stack：头像栏铺满、右侧留 70px padding，按钮叠在最右，
  /// 这样按钮固定不动、和头像同一栏，头像滑动也碰不到它。
  Widget _upBar(ColorScheme colorScheme) {
    return Stack(
      alignment: Alignment.centerRight,
      children: [
        Positioned.fill(
          child: NotificationListener<ScrollEndNotification>(
            onNotification: (notification) {
              final metrics = notification.metrics;
              if (metrics.pixels >= metrics.maxScrollExtent - 300) {
                _dynamicsController.onLoadMore();
              }
              return false;
            },
            child: Obx(
              () => _buildUpPanel(_dynamicsController.loadingState.value),
            ),
          ),
        ),
        // 右侧渐变遮罩，让头像滑到按钮下面时有个柔和过渡
        IgnorePointer(
          child: Container(
            width: 76,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  colorScheme.surface.withValues(alpha: 0),
                  colorScheme.surface,
                ],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
            ),
          ),
        ),
        _createDynamicBtn(colorScheme),
      ],
    );
  }

  /// 吸顶的 UP 头像栏
  ///
  /// 对齐官方动态页：头像栏固定不动，滚动时不收起。
  /// 之前那套「随滚动收起」每帧都在改列表可用高度，整页反复重新布局，
  /// 加上头像列表跟着重建，就成了滑动发涩的主因。
  Widget _pinnedUpBar(ColorScheme colorScheme) {
    return RepaintBoundary(
      child: Material(
        type: .canvas,
        color: colorScheme.surface,
        child: SizedBox(
          width: double.infinity,
          height: _upBarHeight,
          child: _upBar(colorScheme),
        ),
      ),
    );
  }

  /// 「只保留 UP 主栏」布局：头像栏吸顶 + 当前 UP 的动态流
  Widget _buildUpOnly(BuildContext context, ColorScheme colorScheme) {
    return Scaffold(
      primary: false,
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.transparent,
      body: onBuild(
        Column(
          children: [
            _pinnedUpBar(colorScheme),
            const Expanded(child: DynUpPageView()),
          ],
        ),
      ),
    );
  }

  bool get checkPage =>
      _mainController.navigationBars[0] != .dynamics &&
      _mainController.selectedIndex.value == 0;

  @override
  bool onNotificationType1(UserScrollNotification notification) {
    if (checkPage) {
      return false;
    }
    return super.onNotificationType1(notification);
  }

  @override
  bool onNotificationType2(ScrollNotification notification) {
    if (checkPage) {
      return false;
    }
    return super.onNotificationType2(notification);
  }

  /// 顶部分类指示器：一排跟随手势的小圆点（不含文字）
  ///
  /// 取代原来的 [TabBar]：横向滑动切换分类时圆点连续跟随，
  /// 当前分类显示为稍长的胶囊，点圆点可直达对应分类。
  Widget _dynTabIndicator(ColorScheme colorScheme) {
    final tabController = _dynamicsController.tabController;
    final animation = tabController.animation;
    const tabTypes = DynamicsTabType.values;

    Widget buildIndicator(double position) {
      return Row(
        mainAxisSize: .min,
        children: [
          for (int i = 0; i < tabTypes.length; i++)
            GestureDetector(
              behavior: .opaque,
              onTap: () => _toDynTab(i),
              child: SizedBox(
                height: 28,
                child: Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    width:
                        4 + 8 * (1 - (position - i).abs()).clamp(0.0, 1.0),
                    height: 4.5,
                    margin: const .symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(
                        alpha:
                            .22 +
                            .78 * (1 - (position - i).abs()).clamp(0.0, 1.0),
                      ),
                      borderRadius: const .all(.circular(2.25)),
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    }

    final Widget child;
    if (animation == null) {
      child = buildIndicator(tabController.index.toDouble());
    } else {
      child = AnimatedBuilder(
        animation: animation,
        builder: (context, _) => buildIndicator(animation.value),
      );
    }
    return Center(child: child);
  }

  void _toDynTab(int index) {
    final tabController = _dynamicsController.tabController;
    if (tabController.index != index) {
      tabController.animateTo(index);
      _dynamicsController.animateToTop();
    } else {
      _dynamicsController.animateToTop();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colorScheme = ColorScheme.of(context);

    if (_dynamicsController.upOnlyMode) {
      return _buildUpOnly(context, colorScheme);
    }

    Widget? drawer;
    Widget? endDrawer;

    Widget? leading;
    Widget actions;

    final swipeSensitivity = Pref.dynSwipeSensitivity;
    final useUpPageView = _dynamicsController.useUpPageView;

    Widget child = tabBarView(
      controller: _dynamicsController.tabController,
      recognizer: () =>
          dynamicHorizontalDragRecognizer(swipeSensitivity),
      children: DynamicsTabType.values
          .map(
            (e) => e == .up && useUpPageView
                ? const DynUpPageView()
                : DynamicsTabPage(dynamicsType: e),
          )
          .toList(),
    );

    switch (upPanelPosition) {
      case .top:
        child = Column(
          children: [
            upPanelPart(colorScheme),
            Expanded(child: child),
          ],
        );
        actions = _createDynamicBtn(colorScheme);
      case .leftFixed:
        child = Row(
          children: [
            upPanelPart(colorScheme),
            Expanded(child: child),
          ],
        );
        actions = _createDynamicBtn(colorScheme);
      case .rightFixed:
        child = Row(
          children: [
            Expanded(child: child),
            upPanelPart(colorScheme),
          ],
        );
        actions = _createDynamicBtn(colorScheme);
      case .leftDrawer:
        drawer = upPanelPart(colorScheme);
        actions = _createDynamicBtn(colorScheme);
        leading = const DrawerButton();
      case .rightDrawer:
        endDrawer = upPanelPart(colorScheme);
        leading = _createDynamicBtn(colorScheme, isRight: false);
        actions = const EndDrawerButton();
    }

    return Scaffold(
      primary: false,
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.transparent,
      appBar: PreferredSize(
        preferredSize: const .fromHeight(40),
        child: Row(
          children: [
            ?leading,
            Expanded(child: _dynTabIndicator(colorScheme)),
            actions,
          ],
        ),
      ),
      drawer: drawer,
      endDrawer: endDrawer,
      body: onBuild(child),
    );
  }
}
