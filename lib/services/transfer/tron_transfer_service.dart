import '../../domain/wallet.dart';
import '../../enums/chain_kind.dart';
import '../tron_transaction_service.dart';
import '../wallet_key_service.dart';
import 'chain_transfer_service.dart';

/// Tron 系（目前仅 Shasta 测试网）的转账实现。
///
/// 与 [EvmTransferService] 同构：只负责「解析签名私钥 + 分派」，
/// 交易构造、签名与广播下沉在 [TronTransactionService]。
class TronTransferService implements ChainTransferService {
  const TronTransferService(this._keyService, {TronTransactionService transactions = const TronTransactionService()})
    : _transactions = transactions;

  final WalletKeyService _keyService;
  final TronTransactionService _transactions;

  @override
  ChainKind get kind => ChainKind.tron;

  @override
  Future<TransferResult> send(TransferRequest request, Wallet wallet) async {
    // TRC-20 需要 triggersmartcontract + feeLimit 能量预算，是另一块工作量。
    // 在这里明确拦下，而不是让它掉进原生币分支——那会把一笔 USDT 转账
    // 变成一笔 TRX 转账。发送列表也已按 `_tokenTransferKinds` 提前过滤，
    // 这条是兜底。
    if (request.token != null) {
      throw UnsupportedError('${request.token!.symbol} 转账暂未支持（${request.chain.name}）');
    }

    // 私钥明文仅在本次调用内使用，不写入字段或日志，用完立刻清零（异常路径也清）。
    final privateKey = await _keyService.resolveSigningKeyBytes(wallet, request.chain);
    try {
      return await _transactions.sendNative(
        chain: request.chain,
        privateKey: privateKey,
        fromAddress: request.from,
        to: request.to,
        amount: request.amount,
      );
    } finally {
      wipeKey(privateKey);
    }
  }
}
