import 'package:wallet_core/chains.dart';

import '../../../domain/transaction_record.dart';

// 交易历史纯逻辑：与状态/UI 无关，便于单测与复用。

/// 一条记录该显示成什么符号。
///
/// [TransactionRecord.symbol] 存的是**交易发生当时**的符号快照，原则上直接显示即可。
/// 但 Solana 是个例外：`getTransaction` 的余额条目只给 mint，给不出符号，所以
/// `SolanaTransactionHistoryService` 只能拿 mint 前四位兜底（显示成 `4zMM` 这种）。
/// 已经落盘的那些记录不会自己变好，于是渲染时再查一次目录把它们救回来。
///
/// 查不到就回退 [TransactionRecord.symbol]，快照语义因此没有丢：目录里没有的代币、
/// 被用户隐藏的代币，历史照样显示得出来——这正是当初要把符号冗余存一份的理由。
String displaySymbolOf(TransactionRecord record, TokenCatalog catalog) {
  final identifier = record.tokenIdentifier;
  if (identifier == null) return record.symbol; // 原生币的符号来自链配置，一定是对的
  return catalog.findToken(record.chainId, identifier)?.symbol ?? record.symbol;
}

/// 本地保留的交易记录上限。超出后丢弃最旧的——历史越久价值越低，
/// 而 SharedPreferences 存的是单个 JSON 字符串，不设上限迟早撑爆。
///
/// 这个数同时也是「能往回翻多深」：翻页拉回来的都是更旧的记录，上限卡在哪儿，
/// 用户就只能翻到哪儿——再往前翻，新拉的那页会在 merge 时立刻被截掉。
const int maximumTransactionHistoryCount = 500;

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
List<TransactionRecord> mergeTransactions(Iterable<TransactionRecord> existing, Iterable<TransactionRecord> incoming, {int maximum = maximumTransactionHistoryCount}) {
  final merged = {for (final record in existing) record.identity: record};
  for (final fresh in incoming) {
    final local = merged[fresh.identity];
    // 把 fresh 叠在 local 上，而不是逐字段手搓一个新记录——手搓过一次就漏了
    // validUntilBlock，往后每加一个字段都要再漏一次。copyWith 的「给了才换」正好
    // 是这里要的语义：远程给得出的字段以远程为准，远程给不出的（validUntilBlock
    // 只有本机广播时知道）保留本地的，而不是被 null 抹掉。
    merged[fresh.identity] = local == null
        ? fresh
        : local.copyWith(
            transactionHash: fresh.transactionHash,
            walletId: fresh.walletId,
            chainId: fresh.chainId,
            tokenIdentifier: fresh.tokenIdentifier,
            symbol: fresh.symbol,
            fromAddress: fresh.fromAddress,
            toAddress: fresh.toAddress,
            amount: fresh.amount,
            validUntilBlock: fresh.validUntilBlock,
            feeAmount: fresh.feeAmount,
            blockNumber: fresh.blockNumber,
            confirmedAt: fresh.confirmedAt,
            status: fresh.status,
            direction: fresh.direction,
          );
  }
  return List.unmodifiable(sortByTimeDescending(merged.values).take(maximum));
}

/// 按钱包 / 链 / 收发方向筛选。条件为 null 表示该维度不限。
List<TransactionRecord> filterTransactions(Iterable<TransactionRecord> records, {String? walletId, String? chainId, TransactionDirection? direction}) {
  return List.unmodifiable(
    records.where((record) {
      if (walletId != null && record.walletId != walletId) return false;
      if (chainId != null && record.chainId != chainId) return false;
      if (direction != null && record.direction != direction) return false;
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
  return List.unmodifiable(sortByTimeDescending(records).where((record) => record.status == TransactionStatus.pending).take(maximum));
}
