import '../../blockchain/chain_registry.dart';
import '../../domain/wallet.dart';
import '../private_key_resolver.dart';
import '../solana_transaction_service.dart';
import 'chain_transfer_service.dart';

/// 历史页回填状态时的单次查询超时：只够发一轮 `getSignatureStatuses`。
const _singleQueryTimeout = Duration(seconds: 1);

/// Solana 系（目前仅 Devnet）的转账实现。
///
/// 与 [EvmTransferService] / [TronTransferService] 同构：只负责「解析签名私钥 + 分派」，
/// 交易构造、签名与广播下沉在 [SolanaTransactionService]。
class SolanaTransferService implements ChainTransferService {
  /// 命名参数直接写成私有字段的 initializing formal：调用处仍是 `transactions:`
  /// （Dart 会去掉下划线取公开名），少一行转发。
  const SolanaTransferService(this._keyResolver, {this._transactions = const SolanaTransactionService()});

  final PrivateKeyResolver _keyResolver; // 私钥解析器
  final SolanaTransactionService _transactions; // Solana 交易服务

  @override
  ChainKind get kind => ChainKind.solana;

  @override
  bool get supportsNative => true;

  /// SPL 代币转账尚未接入：它要先确认收款方的关联代币账户（ATA）是否存在，
  /// 不存在还得在同一笔交易里创建，与原生转账不是一条路径。留待单独实现。
  @override
  bool get supportsToken => false;

  @override
  Future<TransactionStatus> queryStatus(Chain chain, String transactionHash, {int? validUntilBlock}) {
    // 单次查询：给一个短到只够发一轮请求的超时。查不到交易时，若已越过失效高度
    // 就判为过期，否则视为仍在打包中。
    return _transactions.waitForReceipt(
      chain,
      transactionHash,
      validUntilBlock: validUntilBlock,
      timeout: _singleQueryTimeout,
    );
  }

  @override
  Future<TransferResult> send(TransferRequest request, Wallet wallet) async {
    final token = request.token;
    // 提前挡住：发送页已按 supportsToken 过滤过，走到这里说明调用方绕过了闸门。
    // 放行会让一笔 SPL 转账被当成原生 SOL 转账发出去——金额语义完全不同。
    if (token != null) {
      throw UnsupportedError('${request.chain.name} 代币转账暂未支持');
    }

    final privateKey = await _keyResolver.resolveSigningKeyBytes(wallet, request.chain); // 获取私钥明文

    try {
      return await _transactions.sendNative(
        chain: request.chain,
        privateKey: privateKey,
        fromAddress: request.from,
        to: request.to,
        amount: request.amount,
        speed: request.speed,
        deductFeeFromAmount: request.deductFeeFromAmount,
      );
    } finally {
      wipeKey(privateKey); // 清零私钥明文
    }
  }
}
