import '../../enums/transaction_status.dart';

export '../../enums/transaction_status.dart';

/// 转账结果：(交易哈希, 实际发送金额, 上链状态)。
///
/// 实际金额仅在原生币 MAX 扣费场景才可能小于入参金额。
typedef TransferResult = ({String hash, String sentAmount, TransactionStatus status});
