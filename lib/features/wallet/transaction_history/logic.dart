import '../../../domain/transaction_record.dart';

// 交易历史纯逻辑：与状态/UI 无关，便于单测与复用。

/// 本地保留的交易记录上限。超出后丢弃最旧的——历史越久价值越低，
/// 而 SharedPreferences 存的是单个 JSON 字符串，不设上限迟早撑爆。
const int maximumTransactionHistoryCount = 200;

/// 按提交时刻倒序（最新在前）。时刻相同的按 identity 兜底，保证排序稳定。
List<TransactionRecord> sortByTimeDescending(Iterable<TransactionRecord> records) {
  final sorted = records.toList();
  sorted.sort((first, second) {
    final byTime = second.submittedAt.compareTo(first.submittedAt);
    return byTime != 0 ? byTime : second.identity.compareTo(first.identity);
  });
  return List.unmodifiable(sorted);
}

/// 把一批新记录并入已有列表：同 identity 的以 [incoming] 为准，最后倒序 + 截断。
///
/// 「以新为准」是给远程合并用的——链上查回来的状态一定比本地广播时记下的更权威。
/// 但 [submittedAt] 保留本地的：本机知道自己何时按下发送，远程只知道打包时刻。
List<TransactionRecord> mergeTransactions(
  Iterable<TransactionRecord> existing,
  Iterable<TransactionRecord> incoming, {
  int maximum = maximumTransactionHistoryCount,
}) {
  final merged = {for (final record in existing) record.identity: record};
  for (final fresh in incoming) {
    final local = merged[fresh.identity];
    merged[fresh.identity] = local == null
        ? fresh
        : TransactionRecord(
            transactionHash: fresh.transactionHash,
            walletId: fresh.walletId,
            chainId: fresh.chainId,
            tokenIdentifier: fresh.tokenIdentifier,
            symbol: fresh.symbol,
            fromAddress: fresh.fromAddress,
            toAddress: fresh.toAddress,
            amount: fresh.amount,
            submittedAt: local.submittedAt,
            status: fresh.status,
            direction: fresh.direction,
          );
  }
  return List.unmodifiable(sortByTimeDescending(merged.values).take(maximum));
}

/// 按钱包 / 链筛选。两个条件都为 null 表示不限。
List<TransactionRecord> filterTransactions(
  Iterable<TransactionRecord> records, {
  String? walletId,
  String? chainId,
}) {
  return List.unmodifiable(
    records.where((record) {
      if (walletId != null && record.walletId != walletId) return false;
      if (chainId != null && record.chainId != chainId) return false;
      return true;
    }),
  );
}

/// 按「本地日历日」分组，日期倒序、组内也倒序。列表用它渲染日期分隔标题。
///
/// 键取当天零点：同一天的不同时刻必须落进同一组，直接拿 [DateTime] 当键会因为
/// 时分秒不同而每条一组。
Map<DateTime, List<TransactionRecord>> groupByDay(Iterable<TransactionRecord> records) {
  final grouped = <DateTime, List<TransactionRecord>>{};
  for (final record in sortByTimeDescending(records)) {
    final submitted = record.submittedAt.toLocal();
    final day = DateTime(submitted.year, submitted.month, submitted.day);
    grouped.putIfAbsent(day, () => []).add(record);
  }
  return Map.unmodifiable(grouped);
}

/// 地址缩略展示：`0x1234…abcd`。太短的地址原样返回，缩了反而看不出是什么。
String shortenAddress(String address, {int headLength = 6, int tailLength = 4}) {
  final trimmed = address.trim();
  if (trimmed.length <= headLength + tailLength + 1) return trimmed;
  return '${trimmed.substring(0, headLength)}…${trimmed.substring(trimmed.length - tailLength)}';
}

/// 待回填状态的记录：只有 pending 需要再查链，且一次最多查 [maximum] 条，
/// 避免历史很长时下拉刷新打出几百个 RPC 请求。
List<TransactionRecord> pendingRecordsToRefresh(Iterable<TransactionRecord> records, {int maximum = 20}) {
  return List.unmodifiable(
    sortByTimeDescending(records).where((record) => record.status == TransactionStatus.pending).take(maximum),
  );
}
