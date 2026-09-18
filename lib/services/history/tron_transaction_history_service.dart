import 'package:on_chain/on_chain.dart';

import 'package:wallet_core/chains.dart';
import 'package:wallet_core/rpc.dart';

import '../../domain/transaction_record.dart';
import 'chain_transaction_history_service.dart';

/// Tron 的历史查询：TronGrid 的 `/transactions`（TRX）+ `/transactions/trc20`（TRC-20）。
///
/// 公共 TronGrid 不强制要 key，[supportsHistory] 恒为 true。
class TronTransactionHistoryService implements ChainTransactionHistoryService {
  const TronTransactionHistoryService();

  @override
  ChainKind get kind => ChainKind.tron;

  @override
  bool get supportsHistory => true;

  @override
  Future<TransactionHistoryPage> fetch({required Chain chain, required String address, required String walletId, String? cursor, int limit = 25}) async {
    // 两条接口各有各的 fingerprint，用 `|` 拼进一个游标里；顺序固定为「原生|代币」。
    final [nativeCursor, tokenCursor] = _splitCursor(cursor);
    final responses = await Future.wait([
      _request(chain: chain, address: address, path: '', fingerprint: nativeCursor, limit: limit),
      _request(chain: chain, address: address, path: '/trc20', fingerprint: tokenCursor, limit: limit),
    ]);

    return parseTronPage(nativeResponse: responses[0], tokenResponse: responses[1], chain: chain, address: address, walletId: walletId);
  }

  Future<Map<String, dynamic>> _request({required Chain chain, required String address, required String path, required String? fingerprint, required int limit}) async {
    // 上一页已经到底的那条接口传了空 fingerprint 会被当成「重新从头查」，直接跳过。
    if (fingerprint == '') return const {};
    final uri = Uri.parse('${chain.endpoint}/v1/accounts/$address/transactions$path').replace(queryParameters: {'limit': '$limit', 'order_by': 'block_timestamp,desc', 'fingerprint': ?fingerprint});
    return getJson(uri);
  }
}

/// 游标拆成「原生|代币」两段。null（第一页）时两段都是 null。
List<String?> _splitCursor(String? cursor) {
  if (cursor == null) return [null, null];
  final parts = cursor.split('|');
  return [parts.elementAtOrNull(0), parts.elementAtOrNull(1)];
}

/// 把 TronGrid 的两份响应解析成一页记录。纯函数，单测直接喂 fixture。
TransactionHistoryPage parseTronPage({
  required Map<String, dynamic> nativeResponse,
  required Map<String, dynamic> tokenResponse,
  required Chain chain,
  required String address,
  required String walletId,
}) {
  final records = [
    for (final entry in _dataOf(nativeResponse)) ?_parseNative(entry, chain: chain, address: address, walletId: walletId),
    for (final entry in _dataOf(tokenResponse)) ?_parseTrc20(entry, chain: chain, address: address, walletId: walletId),
  ];

  final nativeNext = _fingerprintOf(nativeResponse);
  final tokenNext = _fingerprintOf(tokenResponse);
  // 两条接口都到底了才算到底；只剩一条能翻时，另一条那段留空串，
  // 下一轮 `_request` 看到空串就不再打扰它。
  final exhausted = nativeNext == null && tokenNext == null;
  return TransactionHistoryPage(records: records, nextCursor: exhausted ? null : '${nativeNext ?? ''}|${tokenNext ?? ''}');
}

List<Map<String, dynamic>> _dataOf(Map<String, dynamic> response) {
  final data = response['data'];
  if (data is! List) return const [];
  return [
    for (final entry in data)
      if (entry is Map<String, dynamic>) entry,
  ];
}

String? _fingerprintOf(Map<String, dynamic> response) {
  final meta = response['meta'];
  if (meta is! Map<String, dynamic>) return null;
  // 没有 links.next 就是最后一页——fingerprint 字段本身在最后一页也还在。
  final hasNext = (meta['links'] as Map<String, dynamic>?)?['next'] != null;
  return hasNext ? meta['fingerprint'] as String? : null;
}

/// TRX 转账。只认 TransferContract：合约调用、质押、投票等也在这个列表里，
/// 但它们不是「谁给谁转了多少」，放进历史只会让列表变成一堆看不懂的条目。
TransactionRecord? _parseNative(Map<String, dynamic> entry, {required Chain chain, required String address, required String walletId}) {
  final contract = (entry['raw_data'] as Map<String, dynamic>?)?['contract'];
  if (contract is! List || contract.isEmpty) return null;
  final first = contract.first;
  if (first is! Map<String, dynamic> || first['type'] != 'TransferContract') return null;

  final value = (first['parameter'] as Map<String, dynamic>?)?['value'];
  if (value is! Map<String, dynamic>) return null;

  final from = _toBase58(value['owner_address']);
  final to = _toBase58(value['to_address']);
  final amount = BigInt.tryParse('${value['amount']}');
  final hash = entry['txID'] as String?;
  final timestamp = entry['block_timestamp'];
  if (from == null || to == null || amount == null || hash == null || timestamp is! int) return null;

  final blockTime = DateTime.fromMillisecondsSinceEpoch(timestamp, isUtc: true);
  final ret = (entry['ret'] as List?)?.firstOrNull;
  final outcome = ret is Map<String, dynamic> ? ret : const <String, dynamic>{};
  final succeeded = outcome['contractRet'] == 'SUCCESS';
  final fee = BigInt.tryParse('${outcome['fee']}');

  return TransactionRecord(
    transactionHash: hash,
    walletId: walletId,
    chainId: chain.id,
    symbol: chain.symbol,
    fromAddress: from,
    toAddress: to,
    amount: formatUnits(amount, chain.decimals),
    submittedAt: blockTime,
    confirmedAt: blockTime,
    feeAmount: fee == null ? null : formatUnits(fee, chain.decimals),
    blockNumber: (entry['blockNumber'] ?? entry['block']) as int?,
    status: succeeded ? TransactionStatus.confirmed : TransactionStatus.failed,
    direction: from == address ? TransactionDirection.outgoing : TransactionDirection.incoming,
  );
}

/// TRC-20 转账。这个接口的地址已经是 base58，不需要转换。
TransactionRecord? _parseTrc20(Map<String, dynamic> entry, {required Chain chain, required String address, required String walletId}) {
  final hash = entry['transaction_id'] as String?;
  final from = entry['from'] as String?;
  final to = entry['to'] as String?;
  final amount = BigInt.tryParse('${entry['value']}');
  final timestamp = entry['block_timestamp'];
  final tokenInfo = entry['token_info'];
  if (hash == null || from == null || to == null || amount == null || timestamp is! int) return null;

  final decimals = (tokenInfo as Map<String, dynamic>?)?['decimals'] as int? ?? 0;
  final blockTime = DateTime.fromMillisecondsSinceEpoch(timestamp, isUtc: true);

  return TransactionRecord(
    transactionHash: hash,
    walletId: walletId,
    chainId: chain.id,
    tokenIdentifier: tokenInfo?['address'] as String?,
    symbol: tokenInfo?['symbol'] as String? ?? '',
    fromAddress: from,
    toAddress: to,
    amount: formatUnits(amount, decimals),
    submittedAt: blockTime,
    confirmedAt: blockTime,
    // 这个接口只给转账事件，不给手续费与失败标记——能出现在这里就是成功了。
    status: TransactionStatus.confirmed,
    direction: from == address ? TransactionDirection.outgoing : TransactionDirection.incoming,
  );
}

/// TronGrid 的原生接口返回 41 开头的 hex 地址，钱包里存的是 base58，得换。
String? _toBase58(Object? hexAddress) {
  if (hexAddress is! String || hexAddress.isEmpty) return null;
  try {
    return TronAddress(hexAddress).address;
  } catch (_) {
    return null;
  }
}
