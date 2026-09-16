import 'package:wallet_core/chains.dart';
import '../../data/datasource/remote/rest_client.dart';
import '../../domain/transaction_record.dart';
import 'chain_transaction_history_service.dart';

/// Etherscan V2 的统一入口：所有 EVM 链共用一个域名，靠 `chainid` 分流，
/// 所以这里不需要给每条链单独配 explorer API 地址。
const _etherscanV2Endpoint = 'https://api.etherscan.io/v2/api';

/// EVM 链的历史查询：Etherscan V2 的 `account.txlist`（原生币）+ `account.tokentx`（ERC-20）。
///
/// 两个接口各自返回一页，用同一个页码翻，任一边还满页就说明还有下一页。
/// 合并后交给上层按时间排序，这里不排。
class EvmTransactionHistoryService implements ChainTransactionHistoryService {
  const EvmTransactionHistoryService({required this.apiKey});

  /// Etherscan 的 API key，空串表示没配。
  final String apiKey;

  @override
  ChainKind get kind => ChainKind.evm;

  /// Etherscan 不给 key 也能调，但限流严到在多链并发下必然打满。
  /// 没配 key 就当这条链不支持查历史，好过让用户看着刷新转圈却永远没数据。
  @override
  bool get supportsHistory => apiKey.isNotEmpty;

  @override
  Future<TransactionHistoryPage> fetch({
    required Chain chain,
    required String address,
    required String walletId,
    String? cursor,
    int limit = 25,
  }) async {
    // Etherscan V2 用 chainid 区分链，配不出这个数的链查不了。
    final chainId = chain.evmChainId;
    if (chainId == null) return TransactionHistoryPage.empty;

    final page = int.tryParse(cursor ?? '1') ?? 1;
    final responses = await Future.wait([
      _request(chainId: chainId, action: 'txlist', address: address, page: page, limit: limit),
      _request(chainId: chainId, action: 'tokentx', address: address, page: page, limit: limit),
    ]);

    return parseEtherscanPage(
      nativeResults: responses[0],
      tokenResults: responses[1],
      chain: chain,
      address: address,
      walletId: walletId,
      page: page,
      limit: limit,
    );
  }

  /// 单次 Etherscan 调用，返回 `result` 数组。
  ///
  /// `status: "0"` 不一定是错：查不到交易的地址也走这条分支（message 为
  /// "No transactions found"），所以一律当空页处理，不抛。
  Future<List<dynamic>> _request({
    required int chainId,
    required String action,
    required String address,
    required int page,
    required int limit,
  }) async {
    final uri = Uri.parse(_etherscanV2Endpoint).replace(
      queryParameters: {
        'chainid': '$chainId',
        'module': 'account',
        'action': action,
        'address': address,
        'page': '$page',
        'offset': '$limit',
        'sort': 'desc',
        'apikey': apiKey,
      },
    );
    final json = await getJson(uri);
    final result = json['result'];
    return result is List ? result : const [];
  }
}

/// 把 Etherscan 的两个 result 数组解析成一页记录。纯函数，单测直接喂 fixture。
TransactionHistoryPage parseEtherscanPage({
  required List<dynamic> nativeResults,
  required List<dynamic> tokenResults,
  required Chain chain,
  required String address,
  required String walletId,
  required int page,
  required int limit,
}) {
  final records = [
    for (final entry in nativeResults)
      if (entry is Map<String, dynamic>)
        ?_parseEntry(entry, chain: chain, address: address, walletId: walletId, isToken: false),
    for (final entry in tokenResults)
      if (entry is Map<String, dynamic>)
        ?_parseEntry(entry, chain: chain, address: address, walletId: walletId, isToken: true),
  ];

  // 满页就假定还有下一页。Etherscan 不给总数，少查一页空页的代价远小于
  // 在这里猜错导致用户翻不到更早的记录。
  final hasMore = nativeResults.length >= limit || tokenResults.length >= limit;
  return TransactionHistoryPage(records: records, nextCursor: hasMore ? '${page + 1}' : null);
}

TransactionRecord? _parseEntry(
  Map<String, dynamic> entry, {
  required Chain chain,
  required String address,
  required String walletId,
  required bool isToken,
}) {
  final hash = entry['hash'] as String?;
  final from = entry['from'] as String?;
  final to = entry['to'] as String?;
  final value = BigInt.tryParse('${entry['value']}');
  final timestamp = int.tryParse('${entry['timeStamp']}');
  if (hash == null || from == null || to == null || value == null || timestamp == null) return null;

  // 代币的精度与符号取接口返回值，不查本地目录——历史记录必须显示得出没被收录的代币。
  final decimals = isToken ? int.tryParse('${entry['tokenDecimal']}') ?? 0 : chain.decimals;
  final blockTime = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000, isUtc: true);

  return TransactionRecord(
    transactionHash: hash,
    walletId: walletId,
    chainId: chain.id,
    tokenIdentifier: isToken ? entry['contractAddress'] as String? : null,
    symbol: isToken ? (entry['tokenSymbol'] as String? ?? '') : chain.symbol,
    fromAddress: from,
    toAddress: to,
    amount: formatUnits(value, decimals),
    // 远程记录没有「本机提交时刻」可言，两个时间都取区块时间。本地已有的同一笔
    // 交易在 mergeTransactions 里会把自己的 submittedAt 留下，不会被这里覆盖。
    submittedAt: blockTime,
    confirmedAt: blockTime,
    feeAmount: _parseFee(entry, chain.decimals),
    blockNumber: int.tryParse('${entry['blockNumber']}'),
    status: _parseStatus(entry, isToken: isToken),
    direction: from.toLowerCase() == address.toLowerCase()
        ? TransactionDirection.outgoing
        : TransactionDirection.incoming,
  );
}

/// 手续费 = gasUsed × gasPrice，换算成原生币。缺任一项就不给值，不猜。
String? _parseFee(Map<String, dynamic> entry, int decimals) {
  final gasUsed = BigInt.tryParse('${entry['gasUsed']}');
  final gasPrice = BigInt.tryParse('${entry['gasPrice']}');
  if (gasUsed == null || gasPrice == null) return null;
  return formatUnits(gasUsed * gasPrice, decimals);
}

/// tokentx 的条目不带失败标记——ERC-20 转账事件只有成功了才会被记下来，
/// 出现在这个列表里本身就意味着成功。
TransactionStatus _parseStatus(Map<String, dynamic> entry, {required bool isToken}) {
  if (isToken) return TransactionStatus.confirmed;
  final isError = '${entry['isError']}' == '1';
  final receiptFailed = '${entry['txreceipt_status']}' == '0';
  return isError || receiptFailed ? TransactionStatus.failed : TransactionStatus.confirmed;
}
