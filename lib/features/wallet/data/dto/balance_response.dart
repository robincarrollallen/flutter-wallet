/// 【接口数据 / 响应数据】从后端 API 反序列化得到的余额信息（DTO）。
/// 由 service 层解析；进入 UI 前通常会转换为状态模型，不直接长期持有。
class BalanceResponse {
  const BalanceResponse({
    required this.address,
    required this.balance,
    required this.symbol,
    this.decimals = 18,
  });

  final String address;
  final String balance;
  final String symbol;
  final int decimals;

  factory BalanceResponse.fromJson(Map<String, dynamic> json) {
    return BalanceResponse(
      address: json['address'] as String,
      balance: json['balance'] as String,
      symbol: json['symbol'] as String,
      decimals: (json['decimals'] as num?)?.toInt() ?? 18,
    );
  }
}
