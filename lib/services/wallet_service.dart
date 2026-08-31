import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../blockchain/chain_registry.dart';
import '../dto/request/send_tx_request.dart';
import '../domain/wallet.dart';
import 'evm_transaction_service.dart';
import 'wallet_key_service.dart';
import '../enums/evm_send_status.dart';

/// 转账编排：校验请求 → 按链类型分发 → 解析签名私钥 → 委托各链交易服务广播。
///
/// 这里是编排与签名，不是数据访问——余额查询与行情已下沉到
/// `data/repository/`，故本类不再承担取数职责。
class WalletService {
  const WalletService({this.keyService});

  /// 签名私钥解析器；发送转账必需。
  final WalletKeyService? keyService;

  /// 发起转账：按链类型分发。EVM 已接入真实签名广播；其余链暂未支持。
  /// [wallet] 用于解析签名私钥（私钥明文仅在本次调用内使用）。
  /// 返回 (交易哈希, 实际发送金额, 上链状态)——仅 [SendTxRequest.deductFeeFromAmount]
  /// 为 true（MAX 全额转出）时，实际金额才可能小于入参。
  Future<({String hash, String sentAmount, EvmSendStatus status})> sendTransaction(
    SendTxRequest request,
    Wallet wallet,
  ) async {
    final chainId = request.chainId;
    if (chainId == null) {
      throw ArgumentError('sendTransaction 缺少 chainId');
    }
    final chain = SupportedChains.byId(chainId);
    switch (chain.kind) {
      case ChainKind.evm:
        final keys = keyService;
        if (keys == null) {
          throw StateError('WalletService 未注入 WalletKeyService，无法签名');
        }
        final privateKey = await keys.resolveEvmSigningKey(wallet);
        return const EvmTransactionService().sendNative(
          chain: chain,
          privateKeyHex: privateKey,
          fromAddress: request.from,
          to: request.to,
          amount: request.amount,
          deductFeeFromAmount: request.deductFeeFromAmount,
        );
      case ChainKind.bitcoin:
      case ChainKind.solana:
      case ChainKind.tron:
      case ChainKind.sui:
      case ChainKind.aptos:
        throw UnsupportedError('${chain.name} 转账暂未支持');
    }
  }
}

/// 定义 provider，供各 provider / UI 注入使用。
final walletServiceProvider = Provider<WalletService>(
  (ref) => WalletService(keyService: ref.watch(walletKeyServiceProvider)),
);
