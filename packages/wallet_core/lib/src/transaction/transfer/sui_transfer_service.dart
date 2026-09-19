import 'package:wallet_core/chains.dart';

import '../../model/models.dart';
import '../sui_transaction_service.dart';
import 'chain_transfer_service.dart';
import '../../crypto/private_key_resolver.dart';

/// 历史页回填状态时的单次查询超时：只够发一轮 `sui_getTransactionBlock`。
const _singleQueryTimeout = Duration(seconds: 1);

/// Sui 系（目前仅 Testnet）的转账实现。
///
/// 与 [EvmTransferService] / [SolanaTransferService] / [TronTransferService] /
/// [AptosTransferService] 同构：只负责「解析签名私钥 + 分派」，交易构造、签名与
/// 提交下沉在 [SuiTransactionService]。
class SuiTransferService implements ChainTransferService {
  const SuiTransferService(this._keyResolver, {this._transactions = const SuiTransactionService()});

  final PrivateKeyResolver _keyResolver; // 私钥解析器
  final SuiTransactionService _transactions; // Sui 交易服务

  @override
  ChainKind get kind => ChainKind.sui;

  @override
  bool get supportsNative => true;

  /// 代币转账只覆盖 Sui 的 **`Coin<T>`** 标准（[TokenStandard.suiCoin]）；
  /// 标准对不上的代币由 `SuiTransactionService` 在校验 identifier 时明确报错。
  ///
  /// 声明成 true 之后，Sui 代币会出现在 `SendLogic.assetsOf` 的可发送列表里。
  /// 目录里现有的那枚 USDC 正是 `Coin<T>`，所以这个标志与实际能力是对得上的。
  @override
  bool get supportsToken => true;

  @override
  Future<TransactionStatus> queryStatus(Chain chain, String transactionHash, {int? validUntilBlock}) {
    // validUntilBlock 对 Sui 恒为 null（它的失效按 epoch 不按区块高度），
    // 签名里保留这个参数只是为了实现 ChainTransferService 的统一契约。
    return _transactions.waitForReceipt(chain, transactionHash, timeout: _singleQueryTimeout);
  }

  @override
  Future<TransferResult> send(TransferRequest request, Wallet wallet) async {
    final token = request.token;
    final privateKey = await _keyResolver.resolveSigningKeyBytes(wallet, request.chain); // 获取私钥明文

    try {
      // 代币转账不接 deductFeeFromAmount：费用以 SUI 支付、转出的是代币，
      // 两本账不通，扣无可扣。代币的 MAX 就是代币余额本身（与其余四条链一致）。
      if (token != null) {
        return await _transactions.sendToken(chain: request.chain, token: token, privateKey: privateKey, fromAddress: request.from, to: request.to, amount: request.amount, speed: request.speed);
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
