import '../../blockchain/chain_registry.dart';
import '../../domain/transaction_record.dart';

/// 一页历史记录 + 下一页的游标。
///
/// 游标是不透明字符串，不是页码：四家接口的翻页机制完全不同（Etherscan 是页码、
/// TronGrid 是 fingerprint、mempool.space 是 after_txid、Solana 是 before 签名），
/// 统一成一个由各实现自己解释的串，编排层和 UI 都不用认识它们的差别。
class TransactionHistoryPage {
  const TransactionHistoryPage({required this.records, this.nextCursor});

  /// 空页：查不到、不支持、或已经到底。
  static const empty = TransactionHistoryPage(records: []);

  final List<TransactionRecord> records;

  /// 下一页的游标；null = 没有更多了。
  final String? nextCursor;
}

/// 单条链（准确说是单个 [ChainKind]）的历史查询实现。
///
/// 与 `ChainTransferService` 同构：新增一条链的历史支持 = 新增一个实现类 +
/// 在 `transactionHistoryServiceProvider` 的 map 里加一行。
abstract interface class ChainTransactionHistoryService {
  /// 本实现负责的链类型，用作分发表的键。
  ChainKind get kind;

  /// 是否真的能查历史。接了 API 但缺 key 之类的情况可以在运行期返回 false。
  bool get supportsHistory;

  /// 拉取 [address] 在 [chain] 上的一页交易历史。
  ///
  /// [walletId] 只用于回填到记录上；[cursor] 为 null 表示拉第一页。
  Future<TransactionHistoryPage> fetch({
    required Chain chain,
    required String address,
    required String walletId,
    String? cursor,
    int limit,
  });
}
