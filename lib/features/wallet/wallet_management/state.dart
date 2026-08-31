/// 钱包管理面板的交互状态（不可变）：跟手拖动偏移 + 面板可移动行程。
/// 由 view 的 State 持有并通过 copyWith 整体替换，使数据与 UI 解耦。
class WalletManagementState {
  const WalletManagementState({this.dragOffset = 0, this.panelHeight = 0});

  /// 面板当前向下偏移像素（跟手拖动）。
  final double dragOffset;

  /// 面板可移动行程（build 时算出，供拖动回调换算进度用）。
  final double panelHeight;

  WalletManagementState copyWith({double? dragOffset, double? panelHeight}) {
    return WalletManagementState(
      dragOffset: dragOffset ?? this.dragOffset,
      panelHeight: panelHeight ?? this.panelHeight,
    );
  }
}
