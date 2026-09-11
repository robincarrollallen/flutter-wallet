import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/transaction_record.dart';
import '../../../enums/prefs_key.dart';
import '../../../features/wallet/transaction_history/logic.dart';
import '../../core/persistent_notifier.dart';

/// 交易历史：本机发起过的交易，最新在前，持久化到 SharedPreferences。
///
/// 目前只有发送成功时会写入；后续接入区块浏览器 API 后，收款方向的记录走
/// [merge] 并进来，列表与详情无需改动。
class TransactionHistoryNotifier extends Notifier<List<TransactionRecord>>
    with PersistentNotifier<List<TransactionRecord>> {
  @override
  List<TransactionRecord> build() => restore(const []);

  @override
  PrefsKey get persistKey => PrefsKey.transactionHistory;

  @override
  Map<String, dynamic> toJson(List<TransactionRecord> state) => {
    'records': state.map((record) => record.toJson()).toList(),
  };

  @override
  List<TransactionRecord> fromJson(Map<String, dynamic> json, List<TransactionRecord> fallback) {
    final raw = json['records'];
    if (raw is! List) return fallback;
    return sortByTimeDescending(
      raw.whereType<Map<String, dynamic>>().map(TransactionRecord.fromJson).whereType<TransactionRecord>(),
    );
  }

  /// 记录一笔刚广播出去的交易。同链同哈希视为同一笔，覆盖旧值。
  void record(TransactionRecord record) => state = mergeTransactions(state, [record]);

  /// 合并一批记录（远程拉回的历史）。
  void merge(Iterable<TransactionRecord> records) => state = mergeTransactions(state, records);

  /// 回填某笔交易的上链状态。找不到对应记录时静默忽略。
  void updateStatus(String chainId, String transactionHash, TransactionStatus status) {
    final identity = '$chainId:$transactionHash';
    final target = state.where((record) => record.identity == identity).firstOrNull;
    if (target == null || target.status == status) return;
    state = List.unmodifiable([
      for (final record in state)
        if (record.identity == identity) record.copyWith(status: status) else record,
    ]);
  }

  /// 清空全部历史。
  void clear() => state = const [];
}

final transactionHistoryProvider = NotifierProvider<TransactionHistoryNotifier, List<TransactionRecord>>(
  TransactionHistoryNotifier.new,
);
