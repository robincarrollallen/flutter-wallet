import '../../blockchain/chain_registry.dart';
import '../../domain/wallet.dart';
import '../tron_transaction_service.dart';
import '../private_key_resolver.dart';
import 'chain_transfer_service.dart';

/// 历史页回填状态时的单次查询超时：只够发一轮 `wallet/gettransactionbyid`。
const _singleQueryTimeout = Duration(seconds: 1);

/// Tron 系（目前仅 Shasta 测试网）的转账实现。
///
/// 与 [EvmTransferService] 同构：只负责「解析签名私钥 + 分派」，
/// 交易构造、签名与广播下沉在 [TronTransactionService]。
class TronTransferService implements ChainTransferService {
  const TronTransferService(this._keyResolver, {TronTransactionService transactions = const TronTransactionService()})
    : _transactions = transactions;

  final PrivateKeyResolver _keyResolver; // 私钥解析器
  final TronTransactionService _transactions; // 波场交易服务

  @override
  ChainKind get kind => ChainKind.tron;

  @override
  bool get supportsNative => true;

  @override
  bool get supportsToken => true;

  @override
  Future<TransactionStatus> queryStatus(Chain chain, String transactionHash) {
    // 单次查询：给一个短到只够发一轮请求的超时，查不到交易即视为仍在打包中。
    return _transactions.waitForReceipt(chain, transactionHash, timeout: _singleQueryTimeout);
  }

  @override
  Future<TransferResult> send(TransferRequest request, Wallet wallet) async {
    final privateKey = await _keyResolver.resolveSigningKeyBytes(wallet, request.chain); // 获取私钥明文

    try {
      final token = request.token; // 代币实例

      /// 如果代币实例为空，则发送原生币
      if (token == null) {
        return await _transactions.sendNative(
          chain: request.chain,
          privateKey: privateKey,
          fromAddress: request.from,
          to: request.to,
          amount: request.amount,
          deductFeeFromAmount: request.deductFeeFromAmount,
        );
      }

      /// 如果代币实例不为空，则发送代币
      return await _transactions.sendToken(
        chain: request.chain,
        token: token,
        privateKey: privateKey,
        fromAddress: request.from,
        to: request.to,
        amount: request.amount,
      );
    } finally {
      wipeKey(privateKey); // 清零私钥明文
    }
  }
}
