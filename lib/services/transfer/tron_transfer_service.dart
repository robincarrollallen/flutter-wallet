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
    // 私钥明文仅在本次调用内使用，不写入字段或日志，用完立刻清零（异常路径也清）。
    final privateKey = await _keyService.resolveSigningKeyBytes(wallet, request.chain);
    try {
      final token = request.token;
      if (token == null) {
        return await _transactions.sendNative(
          chain: request.chain,
          privateKey: privateKey,
          fromAddress: request.from,
          to: request.to,
          amount: request.amount,
        );
      }
      return await _transactions.sendToken(
        chain: request.chain,
        token: token,
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
