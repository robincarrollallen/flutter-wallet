/// 【请求数据】发起转账时提交给后端 / 节点的请求体。
/// 仅用于序列化为 API 入参，不在 UI 中长期持有。
class SendTxRequest {
  const SendTxRequest({required this.from, required this.to, required this.amount, this.chainId});

  final String from;
  final String to;
  final String amount;
  final String? chainId;

  Map<String, dynamic> toJson() {
    return {'from': from, 'to': to, 'amount': amount, if (chainId != null) 'chainId': chainId};
  }
}
