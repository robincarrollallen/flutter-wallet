import '../enums/transaction_status.dart';
import '../enums/transaction_direction.dart';

export '../enums/transaction_status.dart';
export '../enums/transaction_direction.dart';

/// 一笔交易记录。字段全部来自发送时已知的信息 + 事后回填的上链状态。
///
/// 刻意冗余存了 [symbol]：代币可能被用户从目录里隐藏、远程目录也可能变更，
/// 而历史记录必须永远显示得出来——它描述的是「当时发生了什么」，不该依赖当下的目录。
class TransactionRecord {
  const TransactionRecord({
    required this.transactionHash,
    required this.walletId,
    required this.chainId,
    required this.symbol,
    required this.fromAddress,
    required this.toAddress,
    required this.amount,
    required this.submittedAt,
    this.tokenIdentifier,
    this.status = TransactionStatus.pending,
    this.direction = TransactionDirection.outgoing,
  });

  /// 交易哈希。与 [chainId] 一起构成这条记录的唯一键。
  final String transactionHash;

  /// 发起这笔交易的钱包 id，用于多钱包筛选。
  final String walletId;

  /// 所在链 id，对应 `SupportedChains.byId`。
  final String chainId;

  /// 代币标识「EVM/Tron 合约地址、Solana mint、Sui/Aptos coin type」；null 表示原生币。
  final String? tokenIdentifier;

  /// 币种符号，发送当时的快照。
  final String symbol;

  /// 发送方地址
  final String fromAddress;

  /// 接收方地址
  final String toAddress;

  /// 十进制金额字符串，与 `TransferRequest.amount` 同口径。
  final String amount;

  /// 本机提交这笔交易的时刻（不是上链时刻——上链时刻要查链才知道）。
  final DateTime submittedAt;

  /// 上链状态，广播时先记下，之后可由 [copyWith] 回填。
  final TransactionStatus status;

  /// 相对当前钱包的方向。
  final TransactionDirection direction;

  /// 去重与合并用的唯一键：同一个哈希在不同链上是两笔交易。
  String get identity => '$chainId:$transactionHash';

  /// 是否为原生币转账。
  bool get isNativeCoin => tokenIdentifier == null;

  TransactionRecord copyWith({TransactionStatus? status}) {
    return TransactionRecord(
      transactionHash: transactionHash,
      walletId: walletId,
      chainId: chainId,
      tokenIdentifier: tokenIdentifier,
      symbol: symbol,
      fromAddress: fromAddress,
      toAddress: toAddress,
      amount: amount,
      submittedAt: submittedAt,
      status: status ?? this.status,
      direction: direction,
    );
  }

  Map<String, dynamic> toJson() => {
    'transactionHash': transactionHash,
    'walletId': walletId,
    'chainId': chainId,
    'tokenIdentifier': tokenIdentifier,
    'symbol': symbol,
    'fromAddress': fromAddress,
    'toAddress': toAddress,
    'amount': amount,
    'submittedAt': submittedAt.toIso8601String(),
    'status': status.name,
    'direction': direction.name,
  };

  /// 反序列化。缺字段或类型不对一律返回 null，由调用方整条丢弃——
  /// 历史记录宁可少一条，也不能因脏数据让整个列表恢复失败。
  static TransactionRecord? fromJson(Map<String, dynamic> json) {
    final transactionHash = json['transactionHash'];
    final walletId = json['walletId'];
    final chainId = json['chainId'];
    final symbol = json['symbol'];
    final fromAddress = json['fromAddress'];
    final toAddress = json['toAddress'];
    final amount = json['amount'];
    final submittedAt = DateTime.tryParse(json['submittedAt'] as String? ?? '');
    if (transactionHash is! String ||
        walletId is! String ||
        chainId is! String ||
        symbol is! String ||
        fromAddress is! String ||
        toAddress is! String ||
        amount is! String ||
        submittedAt == null) {
      return null;
    }

    return TransactionRecord(
      transactionHash: transactionHash,
      walletId: walletId,
      chainId: chainId,
      tokenIdentifier: json['tokenIdentifier'] as String?,
      symbol: symbol,
      fromAddress: fromAddress,
      toAddress: toAddress,
      amount: amount,
      submittedAt: submittedAt,
      status: TransactionStatus.values.asNameMap()[json['status']] ?? TransactionStatus.pending,
      direction: TransactionDirection.values.asNameMap()[json['direction']] ?? TransactionDirection.outgoing,
    );
  }
}
