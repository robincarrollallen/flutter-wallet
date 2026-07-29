/// 【状态数据】UI 直接使用的余额模型。
/// 由 service 层从 BalanceResponse(DTO) 转换而来：原始最小单位 -> 可读金额。
class AccountBalance {
  const AccountBalance({
    required this.address,
    required this.amount,
    required this.symbol,
    this.price = 0,
    this.logoUrl,
  });

  final String address;

  /// 已按 decimals 换算后的可读金额，例如 "1.2345"。
  final String amount;
  final String symbol;

  /// 该币种当前单价，计价法币由 [currencyProvider] 决定（默认 USD）。
  /// 用于折算总资产价值。
  final double price;

  /// 该币种图标 URL（来自 CoinGecko，动态获取，可能为 null）。
  final String? logoUrl;

  /// 数值化后的持仓数量（解析失败按 0 计）。
  double get amountValue => double.tryParse(amount) ?? 0;

  /// 该币种持仓折算的法币总价值（与 [price] 同币种）。
  double get fiatValue => amountValue * price;
}
