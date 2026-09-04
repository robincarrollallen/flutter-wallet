import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../blockchain/chain_registry.dart';
import '../blockchain/token_catalog.dart';
import '../dto/request/send_tx_request.dart';
import '../domain/wallet.dart';
import '../providers/token_catalog_provider.dart';
import 'transfer/chain_transfer_service.dart';
import 'transfer/evm_transfer_service.dart';
import 'wallet_key_service.dart';

/// 转账编排：校验请求 → 解析链与代币 → 按 [ChainKind] 查表分发给各链实现。
///
/// 这里只做编排，不碰私钥、不构造交易、不访问数据：
/// - 签名与广播在 `services/transfer/` 下的各 [ChainTransferService] 实现里；
/// - 余额查询与行情在 `data/repository/`。
///
/// 新增一条链的转账支持，只需写一个实现类并在 [walletServiceProvider] 里注册，
/// 本类无需改动。
class WalletService {
  const WalletService({required this.transferServices, required this.catalog});

  /// 各链类型的转账实现；缺席的链类型即「暂未支持」。
  final Map<ChainKind, ChainTransferService> transferServices;

  /// 用于把 [SendTxRequest.tokenIdentifier] 解析成 [Token]。
  final TokenCatalog catalog;

  /// 发起转账。[wallet] 供各实现解析签名私钥（明文仅在该次调用内使用）。
  ///
  /// 返回 (交易哈希, 实际发送金额, 上链状态)——仅原生币且
  /// [SendTxRequest.deductFeeFromAmount] 为 true（MAX 全额转出）时，
  /// 实际金额才可能小于入参。
  Future<TransferResult> sendTransaction(SendTxRequest request, Wallet wallet) async {
    final chainId = request.chainId;
    if (chainId == null) {
      throw ArgumentError('sendTransaction 缺少 chainId');
    }
    final chain = SupportedChains.byId(chainId);

    // 目录里查不到就报错，绝不降级成「转原生币」——那会把用户的一笔代币转账
    // 悄悄变成一笔以太转账。
    final identifier = request.tokenIdentifier;
    final token = identifier == null ? null : catalog.findToken(chainId, identifier);
    if (identifier != null && token == null) {
      throw StateError('代币目录中找不到 $identifier（${chain.name}）');
    }

    final service = transferServices[chain.kind];
    if (service == null) {
      throw UnsupportedError('${chain.name} 转账暂未支持');
    }

    return service.send(
      TransferRequest(
        chain: chain,
        token: token,
        from: request.from,
        to: request.to,
        amount: request.amount,
        deductFeeFromAmount: request.deductFeeFromAmount,
        speed: request.speed,
      ),
      wallet,
    );
  }
}

/// 定义 provider，供各 provider / UI 注入使用。
///
/// 各链转账实现在这里注册：接入新链时在 map 里加一行即可。
final walletServiceProvider = Provider<WalletService>((ref) {
  final keyService = ref.watch(walletKeyServiceProvider);
  return WalletService(
    transferServices: {ChainKind.evm: EvmTransferService(keyService)},
    catalog: ref.watch(tokenCatalogProvider),
  );
});
