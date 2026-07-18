import '../../../../core/responsive/screen_adapter.dart';

/// 钱包管理面板的纯逻辑：与状态/UI 无关，便于单测和复用。
class WalletManagementLogic {
  const WalletManagementLogic._();

  /// 拖动下拉超过该比例（行程的 30%）则判定为关闭。
  static const double _closeRatio = 0.3;

  /// 快速向下甩动的速度阈值（像素/秒），超过即判定为关闭。
  static const double _closeVelocity = 700;

  /// 面板顶部留白：状态栏高度 + 固定间距，保证各机型一致。
  static double headerGap(double topPadding) => topPadding + 10.s;

  /// 计算当前展开进度（0~1）：
  /// 拖动时用 1 - dragOffset/panelHeight；否则跟随路由转场动画值。
  /// 取两者较小值：进入未完成时受转场约束，拖动下拉时受拖动约束。
  static double panelProgress({
    required double routeValue,
    required double dragOffset,
    required double panelHeight,
  }) {
    final dragValue = panelHeight > 0 ? (1 - dragOffset / panelHeight) : 1.0;
    return (routeValue < dragValue ? routeValue : dragValue).clamp(0.0, 1.0);
  }

  /// 拖动结束时是否应关闭面板（下拉过半行程或快速甩动）。
  static bool shouldClose({
    required double dragOffset,
    required double panelHeight,
    required double velocity,
  }) {
    return dragOffset > panelHeight * _closeRatio || velocity > _closeVelocity;
  }
}
