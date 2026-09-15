import '../../domain/transaction_record.dart';
import '../../domain/wallet.dart';
import '../../enums/chain_kind.dart';
import 'chain_transaction_history_service.dart';

export 'chain_transaction_history_service.dart';

/// 一次 [TransactionHistoryService.fetchAll] 的结果：汇总的记录 + 每条链各自的下一页游标。
///
/// 游标按 chainId 分开存：各链翻页进度天然不同步（有的链两页就到底了，
/// 有的还剩十页），合成一个全局游标会把它们互相拖累。
class WalletHistoryPage {
  const WalletHistoryPage({required this.records, this.nextCursors = const {}});

  final List<TransactionRecord> records;

  /// chainId -> 下一页游标。某条链到底或失败时它的键不出现在这里。
  final Map<String, String> nextCursors;

  /// 还有链能继续翻。
  bool get hasMore => nextCursors.isNotEmpty;
}

/// 远程交易历史的编排：按钱包持有地址的链逐条查，汇总成一份记录列表。
///
/// 没有对应实现的链直接跳过，因此 [chainServices] 为空时整个方法是 no-op——
/// 调用方（历史页下拉刷新）无需判断当前有没有接入 explorer。
class TransactionHistoryService {
  const TransactionHistoryService({this.chainServices = const {}});

  /// 各链类型的历史查询实现；缺席的链类型即「暂不支持查历史」。
  final Map<ChainKind, ChainTransactionHistoryService> chainServices;

  /// 是否有任何一条链能查历史。UI 据此决定要不要显示「同步中」之类的提示。
  bool get hasAnySupport => chainServices.values.any((service) => service.supportsHistory);

  /// 拉取 [wallet] 名下所有已支持链的一页历史。
  ///
  /// [cursors] 为空表示拉第一页（下拉刷新即传空）；否则只翻 [cursors] 里点到名的链——
  /// 已经到底的链不会再被打扰。
  ///
  /// 单条链失败不影响其余链：一个 explorer 挂了不该让整页刷新失败，
  /// 失败的那条链这次就是没有新数据，下次刷新再补。失败与「到底了」在结果里
  /// 长得一样（都不出现在 nextCursors 里），代价是失败的链要等下次下拉刷新
  /// 才能重试，换来的是调用方完全不用处理错误。
  Future<WalletHistoryPage> fetchAll(Wallet wallet, {Map<String, String> cursors = const {}, int limit = 25}) async {
    final queries = <Future<({String chainId, TransactionHistoryPage page})>>[];
    for (final chain in wallet.chainsWithAddress) {
      final service = chainServices[chain.kind];
      final address = wallet.addressFor(chain);
      if (service == null || !service.supportsHistory || address == null) continue;
      // 翻页时只查还有下一页的链：cursors 非空却没有这条链，说明它已经到底。
      final cursor = cursors[chain.id];
      if (cursors.isNotEmpty && cursor == null) continue;

      queries.add(
        service
            .fetch(chain: chain, address: address, walletId: wallet.id, cursor: cursor, limit: limit)
            .then((page) => (chainId: chain.id, page: page))
            .catchError((_) => (chainId: chain.id, page: TransactionHistoryPage.empty)),
      );
    }

    final perChain = await Future.wait(queries);
    return WalletHistoryPage(
      records: [for (final outcome in perChain) ...outcome.page.records],
      nextCursors: {for (final outcome in perChain) outcome.chainId: ?outcome.page.nextCursor},
    );
  }
}
