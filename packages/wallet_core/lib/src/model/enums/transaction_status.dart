/// 广播后的上链结果。
///
/// [failed] 与 [expired] 的**资金语义完全不同**，不能合成一个值：
/// - [failed]：交易上了链但执行失败，**手续费已经扣掉**，钱没转出去；
/// - [expired]：交易压根没上链（Solana 的 blockhash 过期、EVM 的交易被丢出内存池），
///   **一分钱手续费都没扣**，链上查不到这个哈希，重发一笔即可。
///
/// 把过期报成 [pending] 会让用户一直等一笔永远不会到来的确认；报成 [failed] 又会让他
/// 以为手续费白花了。所以单独成一态。
enum TransactionStatus { confirmed, failed, pending, expired }

extension TransactionStatusX on TransactionStatus {
  /// 是否为终态：不会再变，轮询可以停了。
  bool get isFinal => this != TransactionStatus.pending;
}
