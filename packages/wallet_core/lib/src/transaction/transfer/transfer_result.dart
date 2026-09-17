import '../../model/models.dart';

export '../../model/enums/transaction_status.dart';

/// 转账结果：(交易哈希, 实际发送金额, 上链状态, 交易失效高度)。
///
/// 实际金额仅在原生币 MAX 扣费场景才可能小于入参金额。
///
/// [validUntilBlock] 是「这笔交易最晚能在哪个区块高度上链」，过了就永远不会上链了。
/// 目前只有 Solana 给得出这个数（`getLatestBlockhash` 的 `lastValidBlockHeight`），
/// 其余链传 null —— 它们没有这么确定的失效点，只能继续按 pending 等下去。
/// 拿它是为了把「一直没确认」和「已经死透了」区分开，见 [TransactionStatus.expired]。
typedef TransferResult = ({String hash, String sentAmount, TransactionStatus status, int? validUntilBlock});
