import '../../blockchain/chain_registry.dart';
import '../../domain/wallet.dart';
import '../evm_transaction_service.dart';
import '../private_key_resolver.dart';
import 'chain_transfer_service.dart';

/// 历史页回填状态时的单次查询超时：只够发一轮 `eth_getTransactionReceipt`。
const _singleQueryTimeout = Duration(seconds: 1);

/// EVM 「Ethereum / Polygon / BSC / Base / Arbitrum」的转账实现
class EvmTransferService implements ChainTransferService {
  const EvmTransferService(this._keyResolver, {EvmTransactionService transactions = const EvmTransactionService()})
    : _transactions = transactions;

  final PrivateKeyResolver _keyResolver; // 私钥解析器
  final EvmTransactionService _transactions; // EVM 交易服务

  @override
  ChainKind get kind => ChainKind.evm;

  @override
  bool get supportsNative => true;

  @override
  bool get supportsToken => true;

  @override
  Future<TransactionStatus> queryStatus(Chain chain, String transactionHash) {
    // 单次查询：给一个短到只够发一轮请求的超时，拿不到回执即视为仍在打包中。
    return _transactions.waitForReceipt(chain.endpoint, transactionHash, timeout: _singleQueryTimeout);
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
          speed: request.speed,
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
        speed: request.speed,
      );
    } finally {
      wipeKey(privateKey); // 清零私钥明文
    }
  }
}
