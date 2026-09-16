import 'package:wallet_core/chains.dart';
import '../model/models.dart';
import '../tx/transfer/chain_transfer_service.dart';

/// 钱包业务编排：校验请求 → 解析链与代币 → 按 [ChainKind] 查表分发给各链实现(这里只做编排，不碰私钥、不构造交易、不访问数据)
class WalletService {
  const WalletService({required this.transferServices, required this.catalog});

  /// 各链类型的转账实现；缺席的链类型即「暂未支持」
  final Map<ChainKind, ChainTransferService> transferServices;

  /// 用于把 [SendTxRequest.tokenIdentifier] 解析成 [Token]。
  final TokenCatalog catalog;

  /// 查询一笔已广播交易的当前上链状态，供交易历史回填 pending 记录
  ///
  /// [validUntilBlock] 原样来自那条历史记录，用于判定「交易已过期、永远不会上链」，
  /// 只有给得出这个数的链（目前是 Solana）才会用到。
  Future<TransactionStatus> queryTransactionStatus(
    String chainId,
    String transactionHash, {
    int? validUntilBlock,
  }) async {
    final chain = SupportedChains.all.where((candidate) => candidate.id == chainId).firstOrNull; // 根据链ID查找链实例
    final service = chain == null ? null : transferServices[chain.kind]; // 根据链类型查找转账实现方法(walletServiceProvider 注入)
    // 链未知或该链类型没有转账实现时返回 [TransactionStatus.pending]
    if (chain == null || service == null) {
      return TransactionStatus.pending;
    }
    return service.queryStatus(chain, transactionHash, validUntilBlock: validUntilBlock);
  }

  /// 发起转账, 返回 (交易哈希, 实际发送金额, 上链状态)
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

    final service = transferServices[chain.kind]; // 根据链类型查找转账实现方法(walletServiceProvider 初始化注入)
    if (service == null) {
      throw UnsupportedError('${chain.name} 转账暂未支持'); // 转账暂未支持抛出异常
    }

    // 收款地址格式校验。发送页已经校验过一遍，这里**必须再校验一次**：
    // 那是 UI 的输入提示，而这里是资金出口——绕过 UI 的调用方（脚本、深链、
    // 以后的 WalletConnect）不该因此就完全没有把关。一笔转到格式非法地址的交易，
    // 轻则被节点拒收，重则真的把钱转进一个无人持有的地址，而后者不可逆。
    //
    // 放在「该链是否支持」之后：不支持的链要报「暂未支持」，先报地址格式会误导人。
    final addressError = AddressValidation.validate(chain, request.to);
    if (addressError != null) {
      throw ArgumentError(addressError);
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
