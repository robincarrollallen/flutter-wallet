/// 【状态数据】钱包跨链总资产的聚合结果。
///
/// 为什么不是裸 double：部分链取数失败时我们仍然出总额（只跳过失败的那几条），
/// 这时 double 无法表达「一共 5 条链，只算进了 3 条」。UI 必须能看出数字不完整，
/// 否则用户会把缩水后的金额当成真实资产——这比不显示数字更危险。
class WalletTotal {
  const WalletTotal({required this.value, this.failedChainIds = const []});

  /// 空值：无钱包 / 无地址时使用。const 可构造，UI 兜底分支直接引用即可。
  static const empty = WalletTotal(value: 0);

  /// 取数成功的那些链折算后的法币合计。
  final double value;

  /// 取数失败被跳过的链 id，顺序与 [SupportedChains.all] 一致。
  /// 存 id 而非计数，UI 才能把具体链名报给用户。
  final List<String> failedChainIds;

  /// 数据不完整——UI 据此展示「部分链取数失败」提示。
  bool get isPartial => failedChainIds.isNotEmpty;
}
