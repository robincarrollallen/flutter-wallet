import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/responsive/screen_adapter.dart';
import '../../../providers/modules/wallet_panel_progress_provider.dart';
import 'pages/wallet_list/view.dart';
import '../../../core/navigation/panel_routes.dart';
import '../../../router/routes.dart';
import 'logic.dart';
import 'state.dart';

/// 钱包管理页：列出全部钱包，点击切换当前钱包。
///
/// 由 [AppRoute.walletPanel] 以「从底部向上切入」的透明覆盖路由打开
/// （转场定义在 app_router）；面板内部的子页仍走自己的嵌套 Navigator。
class WalletManagementScreen extends ConsumerStatefulWidget {
  const WalletManagementScreen({super.key});

  @override
  ConsumerState<WalletManagementScreen> createState() => _WalletManagementScreenState();
}

class _WalletManagementScreenState extends ConsumerState<WalletManagementScreen> with SingleTickerProviderStateMixin {
  /// 面板拖拽/布局交互状态（不可变，整体替换）。
  var _state = const WalletManagementState();

  /// 面板内嵌套 Navigator 的 key：子页在面板内 push/pop。
  final _nestedNavKey = GlobalKey<NavigatorState>();

  /// 回弹 / 关闭的补间动画控制器。
  late final AnimationController _controller;
  Animation<double>? _animation;

  /// 进入/退出转场动画（由 Navigator 驱动），用于在 push/pop 时带动首页缩放。
  Animation<double>? _routeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 250))
      ..addListener(() {
        setState(() {
          _state = _state.copyWith(dragOffset: _animation?.value ?? _state.dragOffset);
        });
        _syncPanelProgress();
      });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 绑定路由转场动画：push/pop 时把进度同步给首页（缩放/还原）。
    final routeAnim = ModalRoute.of(context)?.animation;
    if (routeAnim != _routeAnimation) {
      _routeAnimation?.removeListener(_syncPanelProgress);
      _routeAnimation = routeAnim;
      _routeAnimation?.addListener(_syncPanelProgress);
    }
  }

  /// 把当前展开进度写入共享 notifier。
  void _syncPanelProgress() {
    ref.read(walletPanelProgressProvider).value = WalletManagementLogic.panelProgress(
      routeValue: _routeAnimation?.value ?? 1.0,
      dragOffset: _state.dragOffset,
      panelHeight: _state.panelHeight,
    );
  }

  @override
  void dispose() {
    _routeAnimation?.removeListener(_syncPanelProgress);
    _controller.dispose();
    super.dispose();
  }

  /// 用动画把 dragOffset 从当前值过渡到 [target]。
  void _animateTo(double target, {VoidCallback? onDone}) {
    _animation = Tween<double>(
      begin: _state.dragOffset,
      end: target,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _controller
      ..reset()
      ..forward().whenComplete(() => onDone?.call());
  }

  void _onDragUpdate(DragUpdateDetails details) {
    setState(() {
      _state = _state.copyWith(dragOffset: (_state.dragOffset + details.delta.dy).clamp(0.0, double.infinity));
    });
    _syncPanelProgress();
  }

  void _onDragEnd(DragEndDetails details, double panelHeight) {
    final shouldClose = WalletManagementLogic.shouldClose(
      dragOffset: _state.dragOffset,
      panelHeight: panelHeight,
      velocity: details.primaryVelocity ?? 0,
    );
    if (shouldClose) {
      // 继续下滑移出屏幕后关闭。
      _animateTo(
        panelHeight,
        onDone: () {
          if (mounted) Navigator.of(context).pop();
        },
      );
    } else {
      // 回弹归位。
      _animateTo(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final mediaQuery = MediaQuery.of(context);
    final screenHeight = mediaQuery.size.height;

    // 面板顶部留白：保证各机型距系统状态栏一致。
    final headerGap = WalletManagementLogic.headerGap(mediaQuery.padding.top);

    // 面板实际可移动行程 = 屏幕总高 - 顶部留白，缓存供拖动回调换算进度。
    final panelHeight = screenHeight - headerGap;
    _state = _state.copyWith(panelHeight: panelHeight);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          // 顶部透明留白区：动态适配刘海屏
          SizedBox(height: headerGap),

          // 下方不透明面板
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragUpdate: _onDragUpdate,
              // 传入计算好的面板实际行程
              onVerticalDragEnd: (details) => _onDragEnd(details, panelHeight),
              child: Transform.translate(
                offset: Offset(0, _state.dragOffset),
                child: Container(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(20.s)),
                  ),
                  child: SafeArea(
                    top: false, // 顶部间距已经由上面的 SizedBox 处理了
                    bottom: true, // 确保底部列表不被手机底部的“黑条”手势区遮挡
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 拖拽指示条（持久，不随子页变化）
                        Padding(
                          padding: EdgeInsets.only(top: 16.s),
                          child: Container(
                            width: 36.s,
                            height: 4.s,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(2.s),
                            ),
                          ),
                        ),
                        // 面板内容区：嵌套 Navigator，子页在面板内滑动切换。
                        Expanded(
                          child: NavigatorPopHandler(
                            onPopWithResult: (_) => _nestedNavKey.currentState?.maybePop(),
                            child: Navigator(
                              key: _nestedNavKey,
                              onGenerateRoute: (_) => panelRootRoute<void>(const WalletListPage()),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
