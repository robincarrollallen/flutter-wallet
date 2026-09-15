import '../../blockchain/chain_registry.dart';
import '../../blockchain/units.dart';
import '../../data/datasource/remote/rest_client.dart';
import '../../domain/transaction_record.dart';
import 'chain_transaction_history_service.dart';

/// Bitcoin 的历史查询：mempool.space 的 `/address/{addr}/txs`。
///
/// 这条链的 `endpoint` 本来就是 mempool.space 的 API，直接用即可，无需 key。
class BitcoinTransactionHistoryService implements ChainTransactionHistoryService {
  const BitcoinTransactionHistoryService();

  @override
  ChainKind get kind => ChainKind.bitcoin;

  @override
  bool get supportsHistory => true;

  @override
  Future<TransactionHistoryPage> fetch({
    required Chain chain,
    required String address,
    required String walletId,
    String? cursor,
    int limit = 25,
  }) async {
    // mempool.space 固定每页 25 条，翻页靠「从这个 txid 往更早取」，给不了 limit。
    final uri = Uri.parse('${chain.endpoint}/address/$address/txs').replace(queryParameters: {'after_txid': ?cursor});
    final entries = await getJsonArray(uri);
    return parseMempoolPage(entries: entries, chain: chain, address: address, walletId: walletId);
  }
}

/// 把 mempool.space 的交易数组解析成一页记录。纯函数，单测直接喂 fixture。
TransactionHistoryPage parseMempoolPage({
  required List<dynamic> entries,
  required Chain chain,
  required String address,
  required String walletId,
}) {
  final records = <TransactionRecord>[];
  String? lastTxid;
  for (final entry in entries) {
    if (entry is! Map<String, dynamic>) continue;
    lastTxid = entry['txid'] as String? ?? lastTxid;
    final record = _parseTransaction(entry, chain: chain, address: address, walletId: walletId);
    if (record != null) records.add(record);
  }
  // 空页才算到底：mempool.space 不给总数，也没有「还有更多」的标记。
  return TransactionHistoryPage(records: records, nextCursor: entries.isEmpty ? null : lastTxid);
}

/// UTXO 链没有「发送方 / 接收方」字段，只有一堆输入和输出，得自己算净额。
///
/// 净额 = 自己名下的输出总额 − 自己名下的输入总额。为正是收款，为负是付款，
/// 找零因为同时出现在输入和输出里而自动抵消掉，不会被当成一笔转账。
TransactionRecord? _parseTransaction(
  Map<String, dynamic> entry, {
  required Chain chain,
  required String address,
  required String walletId,
}) {
  final txid = entry['txid'] as String?;
  if (txid == null) return null;

  final inputs = entry['vin'] is List ? entry['vin'] as List : const [];
  final outputs = entry['vout'] is List ? entry['vout'] as List : const [];

  var spent = BigInt.zero;
  for (final input in inputs) {
    final previous = (input as Map<String, dynamic>?)?['prevout'];
    if (previous is! Map<String, dynamic>) continue;
    if (previous['scriptpubkey_address'] == address) spent += _valueOf(previous);
  }

  var received = BigInt.zero;
  String? counterparty;
  for (final output in outputs) {
    if (output is! Map<String, dynamic>) continue;
    if (output['scriptpubkey_address'] == address) {
      received += _valueOf(output);
    } else {
      // 付款时的对手方：第一个不是自己的输出。多输出交易只能取其一，
      // 取第一个比取最大的更贴近「用户按下发送时填的那个地址」。
      counterparty ??= output['scriptpubkey_address'] as String?;
    }
  }

  final net = received - spent;
  if (net == BigInt.zero) return null;

  final outgoing = net.isNegative;
  final fee = BigInt.tryParse('${entry['fee']}');
  final blockTime = _blockTime(entry['status']);
  final confirmed = (entry['status'] as Map<String, dynamic>?)?['confirmed'] == true;

  return TransactionRecord(
    transactionHash: txid,
    walletId: walletId,
    chainId: chain.id,
    symbol: chain.symbol,
    fromAddress: outgoing ? address : _firstInputAddress(inputs) ?? '',
    toAddress: outgoing ? (counterparty ?? '') : address,
    // 付款净额里含手续费，刨掉才是真正转出去的数额。
    amount: formatUnits(outgoing && fee != null ? net.abs() - fee : net.abs(), chain.decimals),
    submittedAt: blockTime,
    confirmedAt: confirmed ? blockTime : null,
    feeAmount: outgoing && fee != null ? formatUnits(fee, chain.decimals) : null,
    blockNumber: (entry['status'] as Map<String, dynamic>?)?['block_height'] as int?,
    status: confirmed ? TransactionStatus.confirmed : TransactionStatus.pending,
    direction: outgoing ? TransactionDirection.outgoing : TransactionDirection.incoming,
  );
}

BigInt _valueOf(Map<String, dynamic> output) => BigInt.tryParse('${output['value']}') ?? BigInt.zero;

String? _firstInputAddress(List<dynamic> inputs) {
  for (final input in inputs) {
    final previous = (input as Map<String, dynamic>?)?['prevout'];
    if (previous is Map<String, dynamic> && previous['scriptpubkey_address'] is String) {
      return previous['scriptpubkey_address'] as String;
    }
  }
  return null;
}

/// 未确认交易没有区块时间，用当下时刻顶上——它刚被广播，这个近似足够排序用。
DateTime _blockTime(Object? status) {
  final seconds = (status as Map<String, dynamic>?)?['block_time'];
  if (seconds is! int) return DateTime.now().toUtc();
  return DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
}
