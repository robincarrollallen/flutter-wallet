import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:on_chain/tron/tron.dart';

import '../blockchain/chain_registry.dart';
import '../blockchain/units.dart';
import '../data/datasource/remote/chain_balance_api.dart';
import '../data/datasource/remote/tron_service.dart';
import '../enums/evm_send_status.dart';

/// Tron 转账：让节点补齐区块引用 → **回解校验** → 本地签名 → 广播 → 轮询回执。
///
/// 与 [EvmTransactionService] 同层：只做链上交互，不认识钱包与私钥来源。
///
/// 与 EVM 的两处根本差异：
/// - **费用模型**：Tron 用带宽/能量，没有 gasPrice × gasLimit。原生 TRX 的 EOA 转账
///   在免费带宽够用时不花钱，带宽不足才烧约 0.267 TRX。既然没有可选档位，
///   [FeeSpeed] 在这里没有意义，调用方传什么都忽略。
/// - **交易构造**：区块引用（refBlockBytes / refBlockHash / expiration）必须取自
///   最新区块，这里交给节点的 `wallet/createtransaction` 生成——但**绝不闭眼签**，
///   见 [_verifyMatches]。
class TronTransactionService {
  /// [provider] / [balances] 都只为测试留的注入口，生产代码用默认值即可。
  const TronTransactionService({TronProvider? provider, ChainBalanceApi balances = const ChainBalanceApi()})
    : _injected = provider,
      _balances = balances;

  final TronProvider? _injected;

  /// 余额查询复用既有实现（`wallet/getaccount`），不在这里重写一份：
  /// 它已经处理了「未激活账户返回 {} = 真实的 0」这个业务空值。
  final ChainBalanceApi _balances;

  /// 等待回执的超时与轮询间隔。Tron 出块 3 秒一个，比以太坊快，
  /// 因此间隔取得比 EVM 那边的 2 秒更贴近出块节奏即可。
  static const Duration _receiptTimeout = Duration(seconds: 60);
  static const Duration _receiptPollInterval = Duration(seconds: 3);

  TronProvider _providerFor(Chain chain) => _injected ?? tronProviderFor(chain);

  /// 发送原生 TRX，返回 (交易哈希, 实际发送金额, 上链状态)。
  ///
  /// [privateKey] 为原始 32 字节 secp256k1 私钥，仅在本次调用内使用。
  /// [fromAddress] 为钱包展示的 T 开头 base58 地址，必须与私钥派生地址一致。
  /// [amount] 为用户输入的十进制字符串，按 [Chain.decimals]（TRX = 6）换算成 sun。
  ///
  /// 刻意没有 `deductFeeFromAmount`：Tron 原生转账通常零费用，且费用取决于账户
  /// 当前带宽而非交易本身，没有 EVM 那种「金额 + feeCap」的确定上限可以先减掉。
  /// 因此 MAX 全额转出就是余额本身，由第 3 步的余额校验兜底，
  /// 返回的 sentAmount 恒等于入参金额。
  Future<({String hash, String sentAmount, EvmSendStatus status})> sendNative({
    required Chain chain,
    required List<int> privateKey,
    required String fromAddress,
    required String to,
    required String amount,
  }) async {
    final provider = _providerFor(chain);

    // 1. 私钥 → 地址，与钱包地址核对。口径与 EVM 一致，只是 Tron 地址大小写敏感，
    //    不能像 0x 地址那样 toLowerCase 后比。
    final signer = TronPrivateKey.fromBytes(privateKey);
    final owner = signer.publicKey().toAddress();
    final expectedFrom = fromAddress.trim();
    if (owner.toAddress() != expectedFrom) {
      throw Exception('签名地址与钱包地址不一致');
    }

    // 2. 金额换算成 sun（TRX decimals = 6，不是 18）。
    final value = parseUnits(amount, chain.decimals);
    if (value <= BigInt.zero) throw Exception('转账金额必须大于 0');

    final recipient = TronAddress(to.trim());

    // 3. 余额校验：不足直接报错，绝不静默改小金额（与 EVM 手输金额同一原则）。
    final balance = await _balances.fetchNativeBalance(chain, expectedFrom);
    if (value > balance) {
      throw Exception(
        '余额不足：本次需 ${formatUnits(value, chain.decimals)} ${chain.symbol}，'
        '可用 ${formatUnits(balance, chain.decimals)} ${chain.symbol}',
      );
    }

    // 4. 让节点构造交易（它负责填最新区块引用与过期时间）。
    final unsigned = await provider.request(
      TronRequestCreateTransaction(ownerAddress: owner, toAddress: recipient, amount: value),
    );

    // 5. 签名前逐字段回解校验——这是本方法的安全支点，别删。
    _verifyMatches(unsigned, owner: owner, to: recipient, amount: value);

    // 6. 本地签名并广播。txID 是 rawData 的 sha256，签的就是它。
    final signature = signer.sign(BytesUtils.fromHexString(unsigned.rawData.txID));
    final signed = Transaction(rawData: unsigned.rawData, signature: [signature]);
    final broadcast = await provider.request(
      TronRequestBroadcastHex(transaction: BytesUtils.toHexString(signed.toBuffer())),
    );
    if (!broadcast.result) {
      throw Exception('广播失败：${broadcast.message ?? broadcast.code ?? '节点未说明原因'}');
    }

    return (
      hash: broadcast.txid,
      sentAmount: formatUnits(value, chain.decimals),
      status: await waitForReceipt(chain, broadcast.txid, provider: provider),
    );
  }

  /// 校验节点返回的交易与本地意图完全一致，不一致即抛。
  ///
  /// `wallet/createtransaction` 省掉了我们自己取区块头拼 protobuf 的麻烦，但代价是
  /// 待签字节由**节点**给出。少了这一步，一个被劫持或有 bug 的节点就能把收款方
  /// 或金额换掉，而我们照签不误——钱转给谁将由节点决定。所以：便利照用，信任不给。
  void _verifyMatches(
    Transaction unsigned, {
    required TronAddress owner,
    required TronAddress to,
    required BigInt amount,
  }) {
    final contracts = unsigned.rawData.contract;
    if (contracts.length != 1) {
      throw Exception('节点返回的交易包含 ${contracts.length} 条合约，预期 1 条');
    }
    final contract = contracts.single.parameter.value;
    if (contract is! TransferContract) {
      throw Exception('节点返回的不是 TRX 转账交易（${contracts.single.type.name}）');
    }
    if (contract.ownerAddress != owner || contract.toAddress != to || contract.amount != amount) {
      throw Exception('节点返回的交易与本次转账不一致，已中止签名');
    }
  }

  /// 轮询 `wallet/gettransactionbyid`，直到确认/失败或超时（返回 pending）。
  ///
  /// 广播返回 result:true 只代表节点收下了，不代表已上链——与 EVM 那边先拿到
  /// txHash 再等 receipt 是同一回事。刚广播时查不到交易（返回 null）属正常，继续等。
  Future<EvmSendStatus> waitForReceipt(
    Chain chain,
    String txId, {
    TronProvider? provider,
    Duration timeout = _receiptTimeout,
    Duration interval = _receiptPollInterval,
  }) async {
    final rpc = provider ?? _providerFor(chain);
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final receipt = await rpc.request(TronRequestGetTransactionById(value: txId));
      if (receipt != null) return _statusOf(receipt);
      await Future<void>.delayed(interval);
    }
    return EvmSendStatus.pending;
  }

  /// 从回执判断这笔交易到底成没成。
  ///
  /// **刻意不用 SDK 的 `isSuccess`**：它只看 `ret` 字段，而节点对
  /// `wallet/gettransactionbyid` 返回的是 `ret: [{"contractRet": "REVERT"}]`——
  /// `ret` 缺席时 `isSuccess` 恒为 true，一笔被回滚的交易会被报成「已确认」。
  /// 这里以 `contractRet` 为准，两个字段任一表示失败就算失败。
  static EvmSendStatus _statusOf(TronGetTransactionByIdResponse receipt) {
    final failed = receipt.ret.any(
      (r) =>
          r.ret == TronResultCode.failed ||
          (r.contractRet != null && r.contractRet != TronContractResult.success),
    );
    return failed ? EvmSendStatus.failed : EvmSendStatus.confirmed;
  }
}
