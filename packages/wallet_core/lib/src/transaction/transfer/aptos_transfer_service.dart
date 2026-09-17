import 'package:wallet_core/chains.dart';
import '../../model/models.dart';
import '../aptos_transaction_service.dart';
import 'chain_transfer_service.dart';
import '../../crypto/private_key_resolver.dart';

/// 历史页回填状态时的单次查询超时：只够发一轮 `GET /transactions/by_hash/{hash}`。
const _singleQueryTimeout = Duration(seconds: 1);

/// Aptos 系（目前仅 Testnet）的转账实现。
///
/// 与 [EvmTransferService] / [SolanaTransferService] / [TronTransferService] 同构：
/// 只负责「解析签名私钥 + 分派」，交易构造、签名与提交下沉在 [AptosTransactionService]。
class AptosTransferService implements ChainTransferService {
  const AptosTransferService(this._keyResolver, {this._transactions = const AptosTransactionService()});

  final PrivateKeyResolver _keyResolver; // 私钥解析器
  final AptosTransactionService _transactions; // Aptos 交易服务

  @override
  ChainKind get kind => ChainKind.aptos;

  @override
  bool get supportsNative => true;

  /// 代币（Coin / Fungible Asset）转账尚未实现。
  ///
  /// 声明成 false 而不是在 [send] 里抛异常了事：发送列表的 `SendLogic.assetsOf`
  /// 读的就是这个标志，它为 false 时 Aptos 的代币压根不会出现在可发送列表里——
  /// 让用户选完、填完地址、到确认页才被告知发不出去，是更差的一种诚实。
  @override
  bool get supportsToken => false;

  @override
  Future<TransactionStatus> queryStatus(Chain chain, String transactionHash, {int? validUntilBlock}) {
    // validUntilBlock 对 Aptos 恒为 null（它的失效是时间戳不是区块高度），
    // 签名里保留这个参数只是为了实现 ChainTransferService 的统一契约。
    return _transactions.waitForReceipt(chain, transactionHash, timeout: _singleQueryTimeout);
  }

  @override
  Future<TransferResult> send(TransferRequest request, Wallet wallet) async {
    // 与 supportsToken 呼应的兜底：UI 已经把代币过滤掉了，但非 UI 调用方仍可能走到这里，
    // 而「悄悄按原生币发出去」会把一笔本该失败的代币转账变成一笔真的 APT 转账。
    if (request.token != null) {
      throw UnsupportedError('${request.chain.name} 暂不支持代币转账');
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
