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

  /// 代币转账只覆盖 **Fungible Asset** 标准；旧的 Coin 标准由
  /// `AptosTransactionService` 在解析 identifier 时明确报错。
  ///
  /// 声明成 true 之后，Aptos 代币会出现在 `SendLogic.assetsOf` 的可发送列表里。
  /// 目录里现有的那枚 USDC 正是 FA，所以这个标志与实际能力是对得上的。
  @override
  bool get supportsToken => true;

  @override
  Future<TransactionStatus> queryStatus(Chain chain, String transactionHash, {int? validUntilBlock}) {
    // validUntilBlock 对 Aptos 恒为 null（它的失效是时间戳不是区块高度），
    // 签名里保留这个参数只是为了实现 ChainTransferService 的统一契约。
    return _transactions.waitForReceipt(chain, transactionHash, timeout: _singleQueryTimeout);
  }

  @override
  Future<TransferResult> send(TransferRequest request, Wallet wallet) async {
    final token = request.token;
    final privateKey = await _keyResolver.resolveSigningKeyBytes(wallet, request.chain); // 获取私钥明文

    try {
      // 代币转账不接 deductFeeFromAmount：费用以 APT 支付、转出的是代币，
      // 两本账不通，扣无可扣。代币的 MAX 就是代币余额本身（与其余三条链一致）。
      if (token != null) {
        return await _transactions.sendToken(
          chain: request.chain,
          token: token,
          privateKey: privateKey,
          fromAddress: request.from,
          to: request.to,
          amount: request.amount,
          speed: request.speed,
        );
      }
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
