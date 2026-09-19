import 'package:wallet_core/chains.dart';

import '../../model/models.dart';
import '../solana_transaction_service.dart';
import 'chain_transfer_service.dart';
import '../../crypto/private_key_resolver.dart';

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

  @override
  bool get supportsToken => true;

  @override
  Future<TransactionStatus> queryStatus(Chain chain, String transactionHash, {int? validUntilBlock}) {
    // 单次查询：给一个短到只够发一轮请求的超时。查不到交易时，若已越过失效高度
    // 就判为过期，否则视为仍在打包中。
    return _transactions.waitForReceipt(chain, transactionHash, validUntilBlock: validUntilBlock, timeout: _singleQueryTimeout);
  }

  @override
  Future<TransferResult> send(TransferRequest request, Wallet wallet) async {
    final token = request.token;
    final privateKey = await _keyResolver.resolveSigningKeyBytes(wallet, request.chain); // 获取私钥明文

    try {
      // 代币转账不接 deductFeeFromAmount：费用以 SOL 支付、转出的是代币，
      // 两本账不通，扣无可扣。代币的 MAX 就是代币余额本身（与 EVM / Tron 一致）。
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
