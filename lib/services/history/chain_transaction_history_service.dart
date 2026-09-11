import '../../blockchain/chain_registry.dart';
import '../../domain/transaction_record.dart';

/// 单条链（准确说是单个 [ChainKind]）的历史查询实现。
///
/// 与 `ChainTransferService` 同构：新增一条链的历史支持 = 新增一个实现类 +
/// 在 `transactionHistoryServiceProvider` 的 map 里加一行。
///
/// 目前这张 map 是空的——本机发起的交易走本地记录已经够用，收款方向的历史需要
/// 区块浏览器 / 索引器（Etherscan、Blockscout、TronGrid 等），留到接入时再填。
abstract interface class ChainTransactionHistoryService {
  /// 本实现负责的链类型，用作分发表的键。
  ChainKind get kind;

  /// 是否真的能查历史。接了 API 但缺 key 之类的情况可以在运行期返回 false。
  bool get supportsHistory;

  /// 拉取 [address] 在 [chain] 上的交易历史。[walletId] 只用于回填到记录上。
  Future<List<TransactionRecord>> fetch({
    required Chain chain,
    required String address,
    required String walletId,
  });
}
