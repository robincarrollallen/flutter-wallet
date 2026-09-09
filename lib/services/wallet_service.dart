import '../blockchain/chain_registry.dart';
import '../blockchain/token_catalog.dart';
import '../dto/request/send_tx_request.dart';
import '../domain/wallet.dart';
import 'transfer/chain_transfer_service.dart';

/// 转账编排：校验请求 → 解析链与代币 → 按 [ChainKind] 查表分发给各链实现。
///
/// 这里只做编排，不碰私钥、不构造交易、不访问数据：
/// - 签名与广播在 `services/transfer/` 下的各 [ChainTransferService] 实现里；
/// - 余额查询与行情在 `data/repository/`。
///
/// 新增一条链的转账支持，只需写一个实现类并在 `providers/service_provider.dart`
/// 的 `walletServiceProvider` 里注册，本类无需改动。
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
    final chainId = request.chainId; // 链ID「链唯一标识」
    if (chainId == null) {
      throw ArgumentError('sendTransaction 缺少 chainId'); // 没有链ID抛出异常
    }

    final chain = SupportedChains.byId(chainId); // 根据链ID查找链实例
    final identifier = request.tokenIdentifier; // 代币标识「EVM/Tron 合约地址、Solana mint、Sui/Aptos coin type」
    final token = identifier == null ? null : catalog.findToken(chainId, identifier); // 根据链ID和代币标识查找代币实例
    if (identifier != null && token == null) {
      throw StateError('代币目录中找不到 $identifier（${chain.name}）'); // 代币目录中找不到代币抛出异常
    }

    final service = transferServices[chain.kind]; // 根据链类型查找转账实现方法
    if (service == null) {
      throw UnsupportedError('${chain.name} 转账暂未支持'); // 转账暂未支持抛出异常
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

