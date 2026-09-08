import '../../enums/fee_speed.dart';

/// 【请求数据】发起转账时提交给后端 / 节点的请求体。
/// 仅用于序列化为 API 入参，不在 UI 中长期持有。
class SendTxRequest {
  const SendTxRequest({
    required this.from,
    required this.to,
    required this.amount,
    this.chainId,
    this.tokenIdentifier,
    this.deductFeeFromAmount = false,
    this.speed = FeeSpeed.defaultSpeed,
  });

  /// 转出地址「源地址」
  final String from;

  /// 接收地址「目标地址」
  final String to;

  /// 转出金额
  final String amount;

  /// 链ID「链唯一标识」(null 表示使用默认链: 根据钱包地址自动判断)
  final String? chainId;

  /// 要转的代币标识「EVM/Tron 合约地址、Solana mint、Sui/Aptos coin type」(null 表示转该链的原生币)
  final String? tokenIdentifier;

  /// 是否为「全额转出（MAX）」：仅该场景允许链上重估费用后从转出额中扣费(手输金额恒为 false——余额不足必须报错而非静默改小金额)
  final bool deductFeeFromAmount;

  /// 用户选择的网络费档位「缓慢/普通/快速」(默认普通)
  final FeeSpeed speed;

  /// 将请求体序列化为 JSON 对象。
  Map<String, dynamic> toJson() {
    return {
      'from': from,
      'to': to,
      'amount': amount,
      if (chainId != null) 'chainId': chainId,
      if (tokenIdentifier != null) 'tokenIdentifier': tokenIdentifier,
      'deductFeeFromAmount': deductFeeFromAmount,
      'speed': speed.name,
    };
  }
}
