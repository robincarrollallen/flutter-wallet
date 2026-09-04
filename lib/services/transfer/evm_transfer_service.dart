import '../../domain/wallet.dart';
import '../../enums/chain_kind.dart';
import '../evm_transaction_service.dart';
import '../wallet_key_service.dart';
import 'chain_transfer_service.dart';

/// EVM 系（Ethereum / Polygon / BSC / Base / Arbitrum …）的转账实现。
///
/// 职责仅是「解析签名私钥 + 按原生币/代币分派」，交易构造与广播下沉在
/// [EvmTransactionService]。
class EvmTransferService implements ChainTransferService {
  const EvmTransferService(this._keyService, {EvmTransactionService transactions = const EvmTransactionService()})
    : _transactions = transactions;

  final WalletKeyService _keyService;
  final EvmTransactionService _transactions;

  @override
  ChainKind get kind => ChainKind.evm;

  @override
  Future<TransferResult> send(TransferRequest request, Wallet wallet) async {
    // 私钥明文仅在本次调用内使用，不写入字段或日志。
    final privateKey = await _keyService.resolveEvmSigningKey(wallet);
    final token = request.token;
    if (token == null) {
      return _transactions.sendNative(
        chain: request.chain,
        privateKeyHex: privateKey,
        fromAddress: request.from,
        to: request.to,
        amount: request.amount,
        deductFeeFromAmount: request.deductFeeFromAmount,
        speed: request.speed,
      );
    }
    // 代币转账没有 deductFeeFromAmount：手续费付原生币，从代币里扣不出来。
    return _transactions.sendToken(
      chain: request.chain,
      token: token,
      privateKeyHex: privateKey,
      fromAddress: request.from,
      to: request.to,
      amount: request.amount,
      speed: request.speed,
    );
  }
}
