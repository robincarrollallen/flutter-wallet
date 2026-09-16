import 'package:wallet_core/wallet_core.dart';
import '../enums/transaction_direction.dart';

export 'package:wallet_core/wallet_core.dart' show TransactionStatus;
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
    this.validUntilBlock,
    this.feeAmount,
    this.blockNumber,
    this.confirmedAt,
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

  /// 这笔交易最晚能在哪个区块高度上链，过了就永远不会上链了。
  ///
  /// 只有给得出这个数的链才有值（目前是 Solana 的 `lastValidBlockHeight`），其余为 null。
  /// 回填状态时靠它把「还在等」和「已经死透」区分开，见 [TransactionStatus.expired]。
  final int? validUntilBlock;

  /// 这笔交易实际花掉的手续费，原生币十进制字符串，与 [amount] 同口径。
  ///
  /// 以下三个字段都要查链 / 查浏览器才知道，本机广播时一律为 null，回填后才有值。
  final String? feeAmount;

  /// 打包这笔交易的区块高度。与 [validUntilBlock] 不是一回事——那个是失效上界。
  final int? blockNumber;

  /// 上链时刻。[submittedAt] 始终是「本机按下发送的时刻」，两者语义不同：
  /// 从浏览器拉回来的收款记录本机压根没提交过，那种情况下两个字段都取区块时间。
  final DateTime? confirmedAt;

  /// 上链状态，广播时先记下，之后可由 [copyWith] 回填。
  final TransactionStatus status;

  /// 相对当前钱包的方向。
  final TransactionDirection direction;

  /// 去重与合并用的唯一键：同一个哈希在不同链上是两笔交易。
  String get identity => '$chainId:$transactionHash';

  /// 是否为原生币转账。
  bool get isNativeCoin => tokenIdentifier == null;

  /// 覆盖式复制。所有参数都是「给了就换、不给就留」——可空字段没有「改回 null」的语义，
  /// 因为它们只会从 null 被回填成有值，不会倒过来。
  TransactionRecord copyWith({
    String? transactionHash,
    String? walletId,
    String? chainId,
    String? tokenIdentifier,
    String? symbol,
    String? fromAddress,
    String? toAddress,
    String? amount,
    DateTime? submittedAt,
    int? validUntilBlock,
    String? feeAmount,
    int? blockNumber,
    DateTime? confirmedAt,
    TransactionStatus? status,
    TransactionDirection? direction,
  }) {
    return TransactionRecord(
      transactionHash: transactionHash ?? this.transactionHash,
      walletId: walletId ?? this.walletId,
      chainId: chainId ?? this.chainId,
      tokenIdentifier: tokenIdentifier ?? this.tokenIdentifier,
      symbol: symbol ?? this.symbol,
      fromAddress: fromAddress ?? this.fromAddress,
      toAddress: toAddress ?? this.toAddress,
      amount: amount ?? this.amount,
      submittedAt: submittedAt ?? this.submittedAt,
      validUntilBlock: validUntilBlock ?? this.validUntilBlock,
      feeAmount: feeAmount ?? this.feeAmount,
      blockNumber: blockNumber ?? this.blockNumber,
      confirmedAt: confirmedAt ?? this.confirmedAt,
      status: status ?? this.status,
      direction: direction ?? this.direction,
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
    if (validUntilBlock != null) 'validUntilBlock': validUntilBlock,
    if (feeAmount != null) 'feeAmount': feeAmount,
    if (blockNumber != null) 'blockNumber': blockNumber,
    if (confirmedAt != null) 'confirmedAt': confirmedAt!.toIso8601String(),
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
      // 本次之前落盘的记录没有这个字段，读成 null 即可——那些链本来也判不了过期。
      validUntilBlock: json['validUntilBlock'] as int?,
      feeAmount: json['feeAmount'] as String?,
      blockNumber: json['blockNumber'] as int?,
      confirmedAt: DateTime.tryParse(json['confirmedAt'] as String? ?? ''),
      status: TransactionStatus.values.asNameMap()[json['status']] ?? TransactionStatus.pending,
      direction: TransactionDirection.values.asNameMap()[json['direction']] ?? TransactionDirection.outgoing,
    );
  }
}
