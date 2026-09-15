import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/transaction_record.dart';
import '../../../providers/core/service_provider.dart';
import '../../../providers/modules/transaction/transaction_history_provider.dart';
import '../../../providers/modules/wallet/wallet_provider.dart';
import 'logic.dart';

/// 历史列表的筛选条件：链 + 收发方向。
///
/// 钱包维度不开放给用户选——历史页是从首页当前钱包进来的，
/// 展示的就是这个钱包的交易，跟着 [activeWalletProvider] 走即可。
class TransactionHistoryFilter {
  const TransactionHistoryFilter({this.chainId, this.direction});

  /// 只看这条链；null = 全部链。
  final String? chainId;

  /// 只看这个方向；null = 全部类型。
  final TransactionDirection? direction;
}

/// 当前筛选条件。默认「全部链 + 全部类型」。
///
/// 两个 setter 都得能把自己那一维置回 null（「全部」），所以不用 copyWith 的
/// 可选参数语义——那样传 null 表示「不改」，恰好表达不了「清空」。改成各自重建，
/// 顺带把另一维从 state 里带过来，避免切链时把方向选择清掉。
class TransactionHistoryFilterNotifier extends Notifier<TransactionHistoryFilter> {
  @override
  TransactionHistoryFilter build() => const TransactionHistoryFilter();

  void selectChain(String? chainId) => state = TransactionHistoryFilter(chainId: chainId, direction: state.direction);

  void selectDirection(TransactionDirection? direction) =>
      state = TransactionHistoryFilter(chainId: state.chainId, direction: direction);

  /// 一键回到「全部链 + 全部类型」。筛空了的空态给用户的出口。
  void clear() => state = const TransactionHistoryFilter();
}

final transactionHistoryFilterProvider = NotifierProvider<TransactionHistoryFilterNotifier, TransactionHistoryFilter>(
  TransactionHistoryFilterNotifier.new,
);

/// 当前钱包的全部历史记录，未按链筛选。链选择器的选项从这里取。
final walletTransactionHistoryProvider = Provider<List<TransactionRecord>>((ref) {
  return filterTransactions(ref.watch(transactionHistoryProvider), walletId: ref.watch(activeWalletProvider)?.id);
});

/// 应用链与方向筛选后的历史记录，最新在前。
final filteredTransactionHistoryProvider = Provider<List<TransactionRecord>>((ref) {
  final filter = ref.watch(transactionHistoryFilterProvider);
  return sortByTimeDescending(
    filterTransactions(
      ref.watch(walletTransactionHistoryProvider),
      chainId: filter.chainId,
      direction: filter.direction,
    ),
  );
});

/// 链选择器的可选项：当前钱包持有地址的链 + 历史里出现过的链。
///
/// 取钱包持有的链而不是只取历史里出现过的链——否则新用户一笔交易都没有时选项为空，
/// 选择器等于没有；用 `SupportedChains.all` 又会把钱包根本没有地址的链也列进来。
/// 并上历史里出现过的链是兜底：某条链后来被移出钱包，它的旧记录仍然筛得到。
final selectableChainsProvider = Provider<List<String>>((ref) {
  final walletChainIds = ref.watch(activeWalletProvider)?.chainsWithAddress.map((chain) => chain.id) ?? const [];
  return List.unmodifiable({
    ...walletChainIds,
    for (final record in ref.watch(walletTransactionHistoryProvider)) record.chainId,
  });
});

/// 翻页进度。游标按链分开存：各链翻页快慢天然不同步，合成一个全局游标会互相拖累。
class TransactionHistoryPagingState {
  const TransactionHistoryPagingState({this.cursors = const {}, this.isLoadingMore = false});

  /// chainId -> 下一页游标。为空表示所有链都翻到底了（或者还没拉过第一页）。
  final Map<String, String> cursors;

  final bool isLoadingMore;

  bool get hasMore => cursors.isNotEmpty;
}

/// 历史页的翻页与刷新：回填 pending 状态、拉远程历史、记住各链翻到哪儿了。
class TransactionHistoryPagingNotifier extends Notifier<TransactionHistoryPagingState> {
  @override
  TransactionHistoryPagingState build() => const TransactionHistoryPagingState();

  /// 下拉刷新与首帧都走这里：回填 pending 状态 + 重新拉第一页远程历史。
  ///
  /// 两件事互不依赖，失败也互不影响：链上状态查不到就维持 pending，远程拉不到
  /// 就是没有新数据——刷新永远不会失败到需要给用户报错。
  Future<void> refresh() async {
    await Future.wait([_refillPendingStatuses(), _fetchRemoteHistory()]);
  }

  /// 翻下一页。只查还有游标的链，已经到底的链不再打扰。
  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMore) return;
    state = TransactionHistoryPagingState(cursors: state.cursors, isLoadingMore: true);
    try {
      await _fetchRemoteHistory(cursors: state.cursors);
    } finally {
      // 失败时保留原游标：这一页没拉到，下次点「加载更多」还能从同一个位置重试。
      state = TransactionHistoryPagingState(cursors: state.cursors, isLoadingMore: false);
    }
  }

  /// 对仍是 pending 的记录再查一次链，把结果写回。
  Future<void> _refillPendingStatuses() async {
    final pending = pendingRecordsToRefresh(ref.read(transactionHistoryProvider));
    if (pending.isEmpty) return;

    final walletService = ref.read(walletServiceProvider);
    final queried = await Future.wait(
      pending.map((record) async {
        try {
          return (
            record: record,
            status: await walletService.queryTransactionStatus(
              record.chainId,
              record.transactionHash,
              // 给得出失效高度的链（Solana），据此把死透的交易判成 expired，
              // 而不是让它在列表里永远显示「确认中」。
              validUntilBlock: record.validUntilBlock,
            ),
          );
        } catch (_) {
          // 节点抖动不该让记录状态发生任何变化，跳过这条。
          return (record: record, status: TransactionStatus.pending);
        }
      }),
    );

    final history = ref.read(transactionHistoryProvider.notifier);
    for (final outcome in queried) {
      if (outcome.status == TransactionStatus.pending) continue;
      history.updateStatus(outcome.record.chainId, outcome.record.transactionHash, outcome.status);
    }
  }

  /// 拉一页远程历史并合并，同时更新各链的翻页游标。
  ///
  /// [cursors] 为空即拉第一页。刷新拿到的游标会整个替换掉旧的——重新从头翻，
  /// 上一轮翻到哪儿不再有意义。
  Future<void> _fetchRemoteHistory({Map<String, String> cursors = const {}}) async {
    final wallet = ref.read(activeWalletProvider);
    if (wallet == null) return;

    final page = await ref.read(transactionHistoryServiceProvider).fetchAll(wallet, cursors: cursors);
    if (page.records.isNotEmpty) ref.read(transactionHistoryProvider.notifier).merge(page.records);
    state = TransactionHistoryPagingState(cursors: page.nextCursors, isLoadingMore: state.isLoadingMore);
  }
}

final transactionHistoryPagingProvider =
    NotifierProvider<TransactionHistoryPagingNotifier, TransactionHistoryPagingState>(
      TransactionHistoryPagingNotifier.new,
    );
