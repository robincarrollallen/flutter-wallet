import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:on_chain/tron/tron.dart';

import '../blockchain/chain_registry.dart';
import '../blockchain/token.dart';
import '../blockchain/units.dart';
import '../core/utils/erc20_abi.dart';
import '../data/datasource/remote/chain_balance_api.dart';
import '../data/datasource/remote/tron_service.dart';
import '../domain/tron_fee.dart';
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

  /// 能量估算的上浮比例（分子/分母），与 EVM 那边 gas 的 1.2 倍同一用意。
  static const int _energyBufferNum = 12;
  static const int _energyBufferDen = 10;

  TronProvider _providerFor(Chain chain) => _injected ?? tronProviderFor(chain);

  /// 估算一笔原生 TRX 转账的费用。
  ///
  /// 三次查询：发送方可用带宽、收款方是否已激活、链上费率。字节数不问节点，
  /// 由 [TronFeeCalculator.bandwidthFor] 本地推算——省一次往返，且能离线单测。
  Future<TronFeeEstimate> estimateNativeFee({
    required Chain chain,
    required String from,
    required String to,
    required String amount,
  }) async {
    final provider = _providerFor(chain);
    final owner = TronAddress(from.trim());
    final recipient = TronAddress(to.trim());
    final amountSun = parseUnits(amount, chain.decimals);

    final results = await Future.wait([
      provider.request(TronRequestGetAccountResource(address: owner)),
      _isActivated(provider, recipient),
      provider.request(TronRequestGetChainParameters()),
    ]);

    final resource = results[0] as AccountResourceModel;
    final activated = results[1] as bool;
    final rates = TronFeeRates.fromChainParameters(results[2] as TronChainParameters);

    return TronFeeCalculator.estimate(
      bandwidthNeeded: TronFeeCalculator.bandwidthFor(owner: owner, to: recipient, amountSun: amountSun),
      // 免费额度与质押所得分开传：激活账户时只有质押那档算数，见 estimate 的注释。
      // 不用 SDK 的 howManyBandwIth——它把两者加在一起，正好抹掉这个区分。
      freeBandwidth: _remaining(resource.freeNetLimit, resource.freeNetUsed),
      stakedBandwidth: _remaining(resource.netLimit, resource.netUsed),
      recipientActivated: activated,
      rates: rates,
    );
  }

  /// 估算一笔 TRC-20 转账的费用（带宽 + 能量）。
  ///
  /// 能量必须问节点：合约执行用量取决于实现（收款方是否已有余额槽、是否手续费
  /// 代币等），没有 21000 那样的常量可猜。走 `triggerconstantcontract` 做一次
  /// **只读**模拟，不上链、不花能量。
  Future<TronFeeEstimate> estimateTokenFee({
    required Chain chain,
    required Token token,
    required String from,
    required String to,
    required String amount,
  }) async {
    final provider = _providerFor(chain);
    final owner = TronAddress(from.trim());
    final recipient = TronAddress(to.trim());
    final value = parseUnits(amount, token.decimals);

    final results = await Future.wait([
      provider.request(TronRequestGetAccountResource(address: owner)),
      provider.request(TronRequestGetChainParameters()),
      _simulateTransfer(provider, owner: owner, token: token, to: recipient, amount: value),
    ]);

    final resource = results[0] as AccountResourceModel;
    final rates = TronFeeRates.fromChainParameters(results[1] as TronChainParameters);
    final energyUsed = results[2] as int;

    return TronFeeCalculator.estimateToken(
      bandwidthNeeded: TronFeeCalculator.bandwidthForToken(
        owner: owner,
        contract: TronAddress(token.identifier),
        parameter: _transferParameter(recipient, value),
      ),
      freeBandwidth: _remaining(resource.freeNetLimit, resource.freeNetUsed),
      stakedBandwidth: _remaining(resource.netLimit, resource.netUsed),
      // 上浮留余量：合约实际执行时链上状态可能已变（收款方余额槽从无到有等），
      // 估少了会 OUT_OF_ENERGY——能量照扣、钱没转到。
      energyNeeded: (energyUsed * _energyBufferNum) ~/ _energyBufferDen,
      energyAvailable: resource.howManyEnergy,
      rates: rates,
    );
  }

  /// 只读模拟一次 `transfer`，取它的能量消耗。
  ///
  /// **回滚的模拟必须当作失败**：余额不足时合约会 REVERT，此时 `energy_used`
  /// 只是回滚前那点消耗（实测约 2000，而真实转账要几万），拿它当估算会严重偏低。
  /// 节点在这种情况下 `result.result` 仍是 true，只在 message 里写 REVERT，
  /// 所以不能只看 result。
  Future<int> _simulateTransfer(
    TronProvider provider, {
    required TronAddress owner,
    required Token token,
    required TronAddress to,
    required BigInt amount,
  }) async {
    final result = await provider.request(
      TronRequestTriggerConstantContract(
        ownerAddress: owner,
        contractAddress: TronAddress(token.identifier),
        functionSelector: 'transfer(address,uint256)',
        parameter: _transferParameter(to, amount),
      ),
    );

    final message = result.result.message;
    if (!result.result.result || (message != null && message.contains('REVERT'))) {
      throw Exception('${token.symbol} 转账模拟失败：${message ?? '合约拒绝执行'}（余额是否足够？）');
    }
    final energy = result.energyUsed;
    if (energy == null || energy <= 0) {
      throw Exception('无法估算 ${token.symbol} 转账所需能量');
    }
    return energy;
  }

  /// `transfer(address,uint256)` 的 ABI 参数（不含选择器）。
  static String _transferParameter(TronAddress to, BigInt amount) =>
      encodeTrc20TransferParameter(to21Bytes: to.toBytes(), amount: amount);

  /// 某档带宽的剩余量。已用超过额度时按 0 计，不返回负数。
  static BigInt _remaining(BigInt limit, BigInt used) {
    final left = limit - used;
    return left > BigInt.zero ? left : BigInt.zero;
  }

  /// 收款方账户是否已上链。未激活的账户 `wallet/getaccount` 返回空对象 `{}`。
  ///
  /// 走 [TronProvider.requestDynamic] 而不是 `request`：后者会把响应喂给
  /// `TronAccountModel.fromJson`，而那个模型对 `create_time` 等字段用的是**非空
  /// parse**，字段缺失直接抛异常——偏偏「什么都没有」正是我们这里要识别的情形。
  /// `requestDynamic` 返回未经模型解析的原始 Map，既绕开了这个坑，
  /// 又仍然走注入的 provider（测试可替换）。
  Future<bool> _isActivated(TronProvider provider, TronAddress address) async {
    final json = await provider.requestDynamic(TronRequestGetAccount(address: address));
    return json.isNotEmpty && json['address'] != null;
  }

  /// 发送原生 TRX，返回 (交易哈希, 实际发送金额, 上链状态)。
  ///
  /// [privateKey] 为原始 32 字节 secp256k1 私钥，仅在本次调用内使用。
  /// [fromAddress] 为钱包展示的 T 开头 base58 地址，必须与私钥派生地址一致。
  /// [amount] 为用户输入的十进制字符串，按 [Chain.decimals]（TRX = 6）换算成 sun。
  ///
  /// [deductFeeFromAmount] 仅在「全额转出（MAX）」场景传 true：此时若
  /// 「金额 + 费用」超过余额，自动把费用从转出额中扣除，扣完不为正则抛异常，
  /// 实际金额随结果返回。默认 false——手输金额是明确意图，余额不足必须报错。
  Future<({String hash, String sentAmount, EvmSendStatus status})> sendNative({
    required Chain chain,
    required List<int> privateKey,
    required String fromAddress,
    required String to,
    required String amount,
    bool deductFeeFromAmount = false,
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
    // 非 final：MAX 全额转出时会在第 3 步被扣减。
    var value = parseUnits(amount, chain.decimals);
    if (value <= BigInt.zero) throw Exception('转账金额必须大于 0');

    final recipient = TronAddress(to.trim());

    // 3. 余额校验：金额 + 网络费一起算。带宽不足要烧 TRX、收款方未激活还要 1 TRX
    //    创建费，只比金额会放过一批注定在链上失败的交易。
    final balance = await _balances.fetchNativeBalance(chain, expectedFrom);
    final fee = await estimateNativeFee(chain: chain, from: expectedFrom, to: to, amount: amount);
    if (value + fee.feeSun > balance) {
      // 默认不扣：手输金额是明确意图，余额不足必须报错，**绝不**静默改小后广播。
      if (!deductFeeFromAmount) {
        throw Exception(
          '余额不足：本次需 ${formatUnits(value + fee.feeSun, chain.decimals)} ${chain.symbol}'
          '（含网络费用约 ${formatUnits(fee.feeSun, chain.decimals)}），'
          '可用 ${formatUnits(balance, chain.decimals)} ${chain.symbol}',
        );
      }
      value = balance - fee.feeSun;
      if (value <= BigInt.zero) throw Exception('余额不足以支付网络费用');
      // 不必像 EVM 那样二次收敛。EVM 要重估是因为 gasLimit 会随金额变（合约收款方），
      // 而这里金额只通过 **varint 长度** 影响带宽：金额变小 → varint 只可能更短 →
      // 带宽只可能更少 → 费用只可能更低。所以拿原费用去减恒偏保守，减完必然够付。
    }

    // 4. 让节点构造交易（它负责填最新区块引用与过期时间）。
    final unsigned = await provider.request(
      TronRequestCreateTransaction(ownerAddress: owner, toAddress: recipient, amount: value),
    );

    // 5. 签名前逐字段回解校验——这是本方法的安全支点，别删。
    _verifyMatches(unsigned, owner: owner, to: recipient, amount: value);

    // 6. 本地签名并广播。
    //
    // 传**未哈希的 rawData 字节**，不要传 txID：`TronPrivateKey.sign` 底层是
    // `TronSigner.signConst`，而它默认 `hashMessage: true`，会自己做一次 sha256。
    // txID 本身已经是 rawData 的 sha256，再传它等于 sha256(sha256(rawData))——
    // 签名在密码学上依然有效，但恢复出的是另一个地址，节点报
    // 「is signed by T... but it is not contained of permission」而拒收。
    final signature = signer.sign(unsigned.rawData.toBuffer());
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

  /// 发送 TRC-20 代币，返回 (交易哈希, 实际发送金额, 上链状态)。
  ///
  /// 与 [sendNative] 的差异：
  /// - 金额按 [Token.decimals] 换算，**不是** [Chain.decimals]；
  /// - 校验的是**代币余额**，而手续费（带宽 + 能量）付的是 TRX，是两本账，要分开验；
  /// - 交易由 `triggersmartcontract` 构造，必须带 `feeLimit`——它是「最多愿意为
  ///   能量烧多少 TRX」的上限，给小了链上会 OUT_OF_ENERGY：能量照扣、钱没转到。
  Future<({String hash, String sentAmount, EvmSendStatus status})> sendToken({
    required Chain chain,
    required Token token,
    required List<int> privateKey,
    required String fromAddress,
    required String to,
    required String amount,
  }) async {
    if (token.standard != TokenStandard.trc20) {
      throw UnsupportedError('${token.symbol} 不是 TRC-20 代币，无法在 ${chain.name} 上转账');
    }

    final provider = _providerFor(chain);
    final signer = TronPrivateKey.fromBytes(privateKey);
    final owner = signer.publicKey().toAddress();
    final expectedFrom = fromAddress.trim();
    if (owner.toAddress() != expectedFrom) {
      throw Exception('签名地址与钱包地址不一致');
    }

    final value = parseUnits(amount, token.decimals);
    if (value <= BigInt.zero) throw Exception('转账金额必须大于 0');
    final recipient = TronAddress(to.trim());
    final contract = TronAddress(token.identifier);

    // 代币余额：不足直接报错，绝不静默改小金额（与原生币手输金额同一原则）。
    final tokenBalance = await _balances.fetchTokenBalance(chain, token, expectedFrom);
    if (value > tokenBalance) {
      throw Exception(
        '${token.symbol} 余额不足：本次需 ${formatUnits(value, token.decimals)}，'
        '可用 ${formatUnits(tokenBalance, token.decimals)}',
      );
    }

    // 手续费走 TRX，与代币余额是两本账，必须单独校验。
    final fee = await estimateTokenFee(chain: chain, token: token, from: expectedFrom, to: to, amount: amount);
    final trxBalance = await _balances.fetchNativeBalance(chain, expectedFrom);
    if (fee.feeSun > trxBalance) {
      throw Exception(
        '${chain.symbol} 不足以支付网络费：需约 ${formatUnits(fee.feeSun, chain.decimals)} ${chain.symbol}，'
        '可用 ${formatUnits(trxBalance, chain.decimals)}',
      );
    }

    final unsigned = await provider.request(
      TronRequestTriggerSmartContract(
        ownerAddress: owner,
        contractAddress: contract,
        functionSelector: 'transfer(address,uint256)',
        parameter: _transferParameter(recipient, value),
        // 上限按估算出的能量折算，够付就行；留 buffer 已在 energyNeeded 里做过。
        feeLimit: fee.energyFeeSun > BigInt.zero ? fee.energyFeeSun : BigInt.one,
      ),
    );

    final transaction = unsigned.transaction;
    if (transaction == null || !unsigned.result.result) {
      throw Exception('构造 ${token.symbol} 转账交易失败：${unsigned.result.message ?? '节点未说明原因'}');
    }
    _verifyTokenCall(transaction.rawData, owner: owner, contract: contract, to: recipient, amount: value);

    final signature = signer.sign(transaction.rawData.toBuffer());
    final signed = Transaction(rawData: transaction.rawData, signature: [signature]);
    final broadcast = await provider.request(
      TronRequestBroadcastHex(transaction: BytesUtils.toHexString(signed.toBuffer())),
    );
    if (!broadcast.result) {
      throw Exception('广播失败：${broadcast.message ?? broadcast.code ?? '节点未说明原因'}');
    }

    return (
      hash: broadcast.txid,
      sentAmount: formatUnits(value, token.decimals),
      status: await waitForReceipt(chain, broadcast.txid, provider: provider),
    );
  }

  /// 校验节点返回的合约调用与本地意图一致，不一致即抛。
  ///
  /// 与 [_verifyMatches] 同一用意，只是要多比 calldata：合约调用的收款方与金额
  /// 都藏在 ABI 编码的 data 里，不比对就等于让节点决定这笔代币转给谁。
  void _verifyTokenCall(
    TransactionRaw raw, {
    required TronAddress owner,
    required TronAddress contract,
    required TronAddress to,
    required BigInt amount,
  }) {
    final contracts = raw.contract;
    if (contracts.length != 1) {
      throw Exception('节点返回的交易包含 ${contracts.length} 条合约，预期 1 条');
    }
    final call = contracts.single.parameter.value;
    if (call is! TriggerSmartContract) {
      throw Exception('节点返回的不是合约调用（${contracts.single.type.name}）');
    }
    if (call.ownerAddress != owner || call.contractAddress != contract) {
      throw Exception('节点返回的合约调用与本次转账不一致，已中止签名');
    }
    final expected = 'a9059cbb${_transferParameter(to, amount)}';
    final actual = BytesUtils.toHexString(call.data ?? const []);
    if (actual.toLowerCase() != expected.toLowerCase()) {
      throw Exception('节点返回的 calldata 与本次转账不一致，已中止签名');
    }
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
