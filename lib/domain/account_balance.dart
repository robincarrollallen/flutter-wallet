/// 【状态数据】UI 直接使用的余额模型。
/// 由 service 层从 BalanceResponse(DTO) 转换而来：原始最小单位 -> 可读金额。
class AccountBalance {
  const AccountBalance({
    required this.address,
    required this.amount,
    required this.symbol,
    this.price = 0,
    this.logoUrl,
    this.utxo,
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

  /// BTC 专有的三口径明细；其他链没有 UTXO 模型，恒为 null。
  final UtxoBreakdown? utxo;

  /// 数值化后的持仓数量（解析失败按 0 计）。
  double get amountValue => double.tryParse(amount) ?? 0;

  /// 该币种持仓折算的法币总价值（与 [price] 同币种）。
  double get fiatValue => amountValue * price;
}

/// 【状态数据】BTC 的余额明细：同一笔持仓在三种口径下的三个数字。
///
/// 单独成类，而不是往 [AccountBalance] 上加两个可空字段：UTXO 是比特币独有的
/// 概念，摊平进通用模型后，十条 EVM 链都要背着永远为 null 的字段，UI 也得逐个
/// 判空。收进一个对象，「有没有明细」只需判一次。
///
/// 三个都是**已按 decimals 换算的十进制字符串**，与 [AccountBalance.amount] 同一约定。
class UtxoBreakdown {
  const UtxoBreakdown({required this.confirmed, required this.pending, required this.spendable});

  final String confirmed; // 已确认：进了块的部分
  final String pending; // 待确认收入（含自己交易找回来的零）
  final String spendable; // 可花 = 已确认 + 自己的未确认找零

  double get pendingValue => double.tryParse(pending) ?? 0;
  double get spendableValue => double.tryParse(spendable) ?? 0;

  /// 有没有值得单独提示的待确认金额。UI 据此决定要不要多渲染一行。
  bool get hasPending => pendingValue > 0;
}
