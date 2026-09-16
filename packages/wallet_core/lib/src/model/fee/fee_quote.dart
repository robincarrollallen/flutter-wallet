/// 某个档位下一笔交易的费用报价，以**原生币最小单位**计价。
///
/// 各链的费用模型差别很大（EVM 是 gasPrice × gasLimit、Solana 是签名费 + 优先费），
/// 但确认页的展示与选择只需要这两个数，所以抽出这个接口让
/// [NetworkFeeSelector] 能同时服务多条链，不必为每条链再写一遍选择器。
abstract interface class FeeQuote {
  /// 预计实付：按当前链上状态估算的真实账单，展示给用户看的就是它。
  BigInt get expectedFee;

  /// 出价上限：最坏情况下会被扣掉多少。余额校验与 MAX 扣减按它来，宁可保守。
  ///
  /// 费用在签名时就完全确定的链（如 Solana），它与 [expectedFee] 相等。
  BigInt get maxFee;
}
