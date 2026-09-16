import 'package:wallet_core/chains.dart';
import 'package:wallet_core/rpc.dart';
import '../../domain/transaction_record.dart';
import 'chain_transaction_history_service.dart';

/// Solana 的历史查询：`getSignaturesForAddress` 列签名，再批量 `getTransaction` 取详情。
///
/// 不需要 key —— 公共 RPC 就能查，所以 [supportsHistory] 恒为 true。
class SolanaTransactionHistoryService implements ChainTransactionHistoryService {
  const SolanaTransactionHistoryService();

  @override
  ChainKind get kind => ChainKind.solana;

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
    // 游标就是上一页最后一条签名：Solana 的翻页是「从这条往更早取」。
    final signatures = await jsonRpcCall(chain.endpoint, 'getSignaturesForAddress', [
      address,
      {'limit': limit, 'before': ?cursor},
    ]);
    if (signatures is! List || signatures.isEmpty) return TransactionHistoryPage.empty;

    final hashes = [
      for (final entry in signatures)
        if (entry is Map<String, dynamic> && entry['signature'] is String) entry['signature'] as String,
    ];
    if (hashes.isEmpty) return TransactionHistoryPage.empty;

    // 一条交易一次 getTransaction，能批就批：devnet 公共节点接受批量请求。
    final calls = [
      for (final hash in hashes)
        (
          method: 'getTransaction',
          params: <Object?>[
            hash,
            {'encoding': 'jsonParsed', 'maxSupportedTransactionVersion': 0},
          ],
        ),
    ];
    final details = chain.supportsRpcBatch
        ? await jsonRpcBatch(chain.endpoint, calls)
        : await Future.wait(calls.map((call) => jsonRpcCall(chain.endpoint, call.method, call.params)));

    final records = [
      for (var index = 0; index < hashes.length; index++)
        if (details[index] case final Map<String, dynamic> detail)
          ?parseSolanaTransaction(detail, hash: hashes[index], chain: chain, address: address, walletId: walletId),
    ];

    // 满页才有下一页；游标取本页最后一条签名，而不是最后一条成功解析的记录——
    // 解析失败的条目也占了一个位置，跳过它会让翻页原地打转。
    return TransactionHistoryPage(records: records, nextCursor: hashes.length >= limit ? hashes.last : null);
  }
}

/// 把一条 `getTransaction` 的结果解析成记录。纯函数，单测直接喂 fixture。
///
/// 金额不去解析指令，而是看余额差：一条交易可能含多条指令、多层 CPI，
/// 余额差是唯一一个「这笔交易对我这个地址的净效果」的可靠口径。
TransactionRecord? parseSolanaTransaction(
  Map<String, dynamic> detail, {
  required String hash,
  required Chain chain,
  required String address,
  required String walletId,
}) {
  final meta = detail['meta'];
  if (meta is! Map<String, dynamic>) return null;

  final accountKeys = _accountKeys(detail);
  final ownIndex = accountKeys.indexOf(address);
  if (ownIndex < 0) return null;

  final blockTimeSeconds = detail['blockTime'];
  final blockTime = blockTimeSeconds is int
      ? DateTime.fromMillisecondsSinceEpoch(blockTimeSeconds * 1000, isUtc: true)
      : DateTime.now().toUtc();
  final fee = BigInt.tryParse('${meta['fee']}') ?? BigInt.zero;
  // 只有第一个账户（fee payer）承担手续费，别的账户看到的余额差里不含它。
  final paidFee = ownIndex == 0;

  final tokenDelta = _tokenDelta(meta, address: address);
  final (amount, tokenIdentifier, symbol) =
      tokenDelta ?? _nativeDelta(meta, ownIndex, fee: fee, paidFee: paidFee, chain: chain);
  if (amount == BigInt.zero) return null;

  final outgoing = amount.isNegative;
  final counterparty = _counterparty(meta, accountKeys, ownIndex: ownIndex, outgoing: outgoing);

  return TransactionRecord(
    transactionHash: hash,
    walletId: walletId,
    chainId: chain.id,
    tokenIdentifier: tokenIdentifier,
    symbol: symbol,
    fromAddress: outgoing ? address : counterparty,
    toAddress: outgoing ? counterparty : address,
    amount: formatUnits(amount.abs(), tokenDelta != null ? _tokenDecimals(meta, address) : chain.decimals),
    submittedAt: blockTime,
    confirmedAt: blockTime,
    feeAmount: paidFee ? formatUnits(fee, chain.decimals) : null,
    blockNumber: detail['slot'] as int?,
    status: meta['err'] == null ? TransactionStatus.confirmed : TransactionStatus.failed,
    direction: outgoing ? TransactionDirection.outgoing : TransactionDirection.incoming,
  );
}

List<String> _accountKeys(Map<String, dynamic> detail) {
  final message = (detail['transaction'] as Map<String, dynamic>?)?['message'];
  final keys = (message as Map<String, dynamic>?)?['accountKeys'];
  if (keys is! List) return const [];
  return [
    for (final key in keys)
      if (key is Map<String, dynamic>) '${key['pubkey']}' else '$key',
  ];
}

/// 原生 SOL 的净变化。自己付了手续费时要把它刨掉，否则转出金额会虚高一个手续费。
(BigInt, String?, String) _nativeDelta(
  Map<String, dynamic> meta,
  int ownIndex, {
  required BigInt fee,
  required bool paidFee,
  required Chain chain,
}) {
  final pre = _balanceAt(meta['preBalances'], ownIndex);
  final post = _balanceAt(meta['postBalances'], ownIndex);
  final delta = post - pre;
  return (paidFee ? delta + fee : delta, null, chain.symbol);
}

BigInt _balanceAt(Object? balances, int index) {
  if (balances is! List || index >= balances.length) return BigInt.zero;
  return BigInt.tryParse('${balances[index]}') ?? BigInt.zero;
}

/// SPL 代币的净变化；这笔交易没动自己的代币账户时返回 null，调用方回落到原生币。
(BigInt, String?, String)? _tokenDelta(Map<String, dynamic> meta, {required String address}) {
  final pre = _ownTokenAmount(meta['preTokenBalances'], address);
  final post = _ownTokenAmount(meta['postTokenBalances'], address);
  if (pre == null && post == null) return null;

  final mint = post?.mint ?? pre!.mint;
  final delta = (post?.amount ?? BigInt.zero) - (pre?.amount ?? BigInt.zero);
  // 符号没处可取——SPL 的余额条目只给 mint 和数量。用 mint 前四位兜底，
  // 至少比空字符串认得出是哪种代币。
  return (delta, mint, mint.length > 4 ? mint.substring(0, 4) : mint);
}

int _tokenDecimals(Map<String, dynamic> meta, String address) =>
    _ownTokenAmount(meta['postTokenBalances'], address)?.decimals ??
    _ownTokenAmount(meta['preTokenBalances'], address)?.decimals ??
    0;

({BigInt amount, int decimals, String mint})? _ownTokenAmount(Object? balances, String address) {
  if (balances is! List) return null;
  for (final entry in balances) {
    if (entry is! Map<String, dynamic> || entry['owner'] != address) continue;
    final uiAmount = entry['uiTokenAmount'];
    if (uiAmount is! Map<String, dynamic>) continue;
    return (
      amount: BigInt.tryParse('${uiAmount['amount']}') ?? BigInt.zero,
      decimals: uiAmount['decimals'] as int? ?? 0,
      mint: '${entry['mint']}',
    );
  }
  return null;
}

/// 对手方：自己转出时取余额增加最多的账户，自己收款时取减少最多的。
///
/// 只能这么猜——一条交易里没有「收款人」这个字段，能看到的只有谁的余额动了多少。
String _counterparty(
  Map<String, dynamic> meta,
  List<String> accountKeys, {
  required int ownIndex,
  required bool outgoing,
}) {
  final pre = meta['preBalances'];
  final post = meta['postBalances'];
  var bestIndex = -1;
  var bestDelta = BigInt.zero;
  for (var index = 0; index < accountKeys.length; index++) {
    if (index == ownIndex) continue;
    final delta = _balanceAt(post, index) - _balanceAt(pre, index);
    final better = outgoing ? delta > bestDelta : delta < bestDelta;
    if (better) {
      bestDelta = delta;
      bestIndex = index;
    }
  }
  return bestIndex < 0 ? '' : accountKeys[bestIndex];
}
