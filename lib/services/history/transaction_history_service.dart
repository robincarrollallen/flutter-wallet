import '../../domain/transaction_record.dart';
import '../../domain/wallet.dart';
import '../../enums/chain_kind.dart';
import 'chain_transaction_history_service.dart';

export 'chain_transaction_history_service.dart';

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

  /// 拉取 [wallet] 名下所有已支持链的历史。
  ///
  /// 单条链失败不影响其余链：一个 explorer 挂了不该让整页刷新失败，
  /// 失败的那条链这次就是没有新数据，下次刷新再补。
  Future<List<TransactionRecord>> fetchAll(Wallet wallet) async {
    final queries = <Future<List<TransactionRecord>>>[];
    for (final chain in wallet.chainsWithAddress) {
      final service = chainServices[chain.kind];
      final address = wallet.addressFor(chain);
      if (service == null || !service.supportsHistory || address == null) continue;
      queries.add(
        service
            .fetch(chain: chain, address: address, walletId: wallet.id)
            .catchError((_) => const <TransactionRecord>[]),
      );
    }
    final perChain = await Future.wait(queries);
    return [for (final records in perChain) ...records];
  }
}
