import 'package:on_chain/sui/sui.dart';

import 'package:wallet_core/chains.dart';
import 'package:wallet_core/rpc.dart';

import '../model/models.dart';
import 'transfer/transfer_result.dart';

/// Sui 转账：取 coin 对象与 gas 行情 → 本地构造 PTB → dry run 定预算 → 本地签名 → 提交。
/// 只做链上交互，不认识钱包与私钥来源。
class SuiTransactionService {
  /// [provider] 只为测试留的注入口，生产代码用默认值即可。
  ///
  /// **没有 `balances` 注入口**，与 Aptos / Solana 那几个服务不同：Sui 的余额与
  /// 「拿哪些 coin 对象付款」是同一份数据——`suix_getCoins` 一次就把两者都给了。
  /// 再叫一次 [ChainBalanceApi] 只会引入第二个可能与之打架的事实来源：
  /// 两次查询之间余额变了，就会出现「按 A 校验、拿 B 付款」。
  const SuiTransactionService({SuiProvider? provider}) : _injected = provider;

  final SuiProvider? _injected;

  /// 原生币的 coin 类型。`suix_getCoins` 的 `coinType` 省略时也是它，
  /// 但显式传更清楚，也与代币路径共用同一个参数位置（代币传 `token.identifier`）。
  static const String _nativeCoinType = '0x2::sui::SUI';

  /// 一次交易最多取用多少个 coin 对象来付款。
  ///
  /// Sui 的「gas smashing」会把 `gasData.payment` 里的多个 coin 自动合并成一个，
  /// 所以碎片多的账户也能凑出足额——但不能无限放：每个 payment 对象都要进 BCS、
  /// 都要被验证者加载，太多会把交易撑过体积上限、也会推高 computation。
  ///
  /// 取 256：这**就是协议硬上限**（testnet 协议版本 137 实测
  /// `sui_getProtocolConfig` 的 `max_gas_payment_objects = 256`），多一个都会被链上
  /// 直接拒。所以这里不是「留了余量的自选值」，而是压在天花板上——**没有放大空间**，
  /// 想调大得先确认协议真的放宽了。
  ///
  /// 碎片超过 256 的账户不会因此卡死：一次转账会把取用的这些合并成一个，
  /// 碎片数每发一笔就掉一大截。
  static const int _maxGasPaymentObjects = 256;

  /// 一次代币转账最多取用多少个代币 coin 对象。
  ///
  /// 与 [_maxGasPaymentObjects] 是**两个不同的量**，不要合并：gas 那边靠 gas smashing
  /// 隐式合并、不占 PTB 输入；代币这边每个 coin 都要显式做成一个 object 输入、
  /// 再进 `MergeCoins` 的 sources，占的是交易体积与 computation。
  ///
  /// 取 32：**这是成本考量下的自选值，不是协议限制**——协议那边
  /// `max_input_objects = 2048`（testnet 协议版本 137 实测），离得很远。
  /// 与 [_maxGasPaymentObjects] 压在硬上限上的情况正相反，这个数是可以调的，
  /// 调大只会让碎片多的账户单笔更贵、合并得更彻底。
  ///
  /// 目前**没有实测依据**，只是个够覆盖常见碎片量的保守值。等真实碎片场景出现后
  /// 按「多一个对象多花多少 gas」重新校准，别凭感觉改。
  ///
  /// 碎片多于这个数时，本次会合并最大的 32 个——合并完账户里的碎片就少了，
  /// 下一笔自然能覆盖到剩下的。
  static const int _maxTokenCoinInputs = 32;

  /// dry run 时先声明的预算上限常量，1 SUI。
  ///
  /// 只是个够用的占位值：真正写进交易的预算由 dry run 的结果 [_gasBudgetFor] 现算。
  /// 但它不能随便取大——dry run 同样校验「预算不超过付款 coin 的总额」，
  /// 填一个超过账户余额的数会让余额不多的账户在 dry run 这一步就被判失败，
  /// 于是连「这笔要花多少」都问不出来。所以实际用的是它与账户余额的较小者。
  static final BigInt _provisionalGasBudgetCap = BigInt.from(1000000000);

  /// dry run 实测净费用之上留的余量：`净费用 × 3 ÷ 2 + 1000000`（0.001 SUI）。
  ///
  /// 必须留：dry run 跑的是当前状态，真正执行时链上状态已经变了（收款方可能刚被
  /// 别人建好、存储返还也会随之不同），用量会有出入。**两头的代价不对等**——
  /// 预算少了交易直接 InsufficientGas 失败且 gas 照扣，多了只是多冻一会儿、
  /// 执行完就退回。
  ///
  /// 加法项不能省：净费用可能因为存储返还而接近 0，只乘 1.5 倍等于没留余量。
  static BigInt _gasBudgetFor(BigInt netGasFee) => netGasFee * BigInt.from(3) ~/ BigInt.two + BigInt.from(1000000);

  /// Sui 协议要求的最低预算。低于它交易在校验阶段就被拒。
  static final BigInt _minimumGasBudget = BigInt.from(2000);

  /// dry run 的探测金额，固定 1 MIST。
  ///
  /// **刻意不用用户填的金额**：费用与转多少无关（实测见 [estimateNativeFee]），
  /// 而 MAX 全额转出时拿全额去探会让 dry run 因余额不足而失败。用最小值探，
  /// 既保证探得动，又不影响结果。
  static final BigInt _probeValue = BigInt.one;

  /// 单次状态查询的默认超时：只够发一轮请求。
  ///
  /// 与 EVM / Solana / Tron / Aptos 同一原则——广播链路不等上链，查不到即视为仍在
  /// 打包中，状态交给结果页与历史页各自轮询回填。
  static const Duration _receiptTimeout = Duration(seconds: 1);

  /// 单次调用内多轮查询的间隔。默认超时下只会发一轮，这个值仅对显式传长超时的调用方有意义。
  static const Duration _receiptPollInterval = Duration(seconds: 1);

  SuiProvider _providerFor(Chain chain) => _injected ?? suiProviderFor(chain);

  /// 估算一笔原生 SUI 转账的三档费用。
  ///
  /// **不需要私钥**，这是 Sui 相对 Aptos 的关键差别，也是这里敢用 dry run 估费的原因：
  /// `sui_dryRunTransactionBlock` 只吃 `txBytes`，既不校验签名也不校验公钥。
  /// 而 Aptos 的 `/transactions/simulate` 会拿 authenticator 里的公钥推 auth key 去比对，
  /// 于是「模拟」等价于「解锁私钥」，进一次确认页就要弹一次生物识别——它因此只能
  /// 退而用静态 gas 上限。Sui 没有这个代价，确认页显示的就是链上实测值。
  ///
  /// **没有 `amount` 参数**，与 Aptos 的估费入口同形：一笔转账花多少钱与转多少**无关**。
  /// 这一点是 2026-09-18 在 testnet 上实测确认的——同一份 coin 与预算下，
  /// 转 1 MIST 与转 0.01 SUI 的 dry run 结果一字不差（净费用都是 1997880）。
  /// 道理也直白：费用由计算量与**对象数量**决定，而 split 出来的 coin 对象大小固定
  /// （u64 是定宽的），金额只是写在里面的一个数。
  ///
  /// 加一个不参与计算的参数，只会让调用方以为它有用，还会让用户每敲一个数字就多发一轮请求。
  Future<SuiFeeEstimate> estimateNativeFee({required Chain chain, required String from, required String to}) async {
    final provider = _providerFor(chain);
    final sender = _parseAddress(from, '发送方');
    final recipient = _parseAddress(to, '收款方');

    final (coins, gasPrice) = await (_loadNativeCoins(provider, sender), _loadReferenceGasPrice(provider)).wait;

    return _estimateFee(provider: provider, sender: sender, recipient: recipient, coins: coins, gasPrice: gasPrice);
  }

  /// 估算一笔代币转账的三档费用。费用以 **SUI** 计价，不是以代币计价。
  ///
  /// 与 [estimateNativeFee] 一样**没有 `amount`**：代币转账的费用由命令序列与
  /// 对象数量决定，而 [_selectTokenCoins] 的选取不看金额，所以金额进不了结果。
  Future<SuiFeeEstimate> estimateTokenFee({required Chain chain, required Token token, required String from, required String to}) async {
    // 标准校验放在一切之前：不支持的代币不该产生任何网络请求。
    _verifyTokenSupported(token, chain);

    final provider = _providerFor(chain);
    final sender = _parseAddress(from, '发送方');
    final recipient = _parseAddress(to, '收款方');

    final (gasCoins, tokenCoins, gasPrice) = await (_loadNativeCoins(provider, sender), _loadTokenCoins(provider, sender, token), _loadReferenceGasPrice(provider)).wait;

    // 必须显式判空：代币 coin 为空时 [_estimateFee] 会走进原生分支（从 gas coin 拆），
    // 于是把一笔代币转账的费用估成 SUI 转账的费用——静默估错比报错糟得多。
    if (tokenCoins.isEmpty) throw Exception('${token.symbol} 余额不足：账户没有该代币');

    return _estimateFee(provider: provider, sender: sender, recipient: recipient, coins: gasCoins, gasPrice: gasPrice, tokenCoins: _selectTokenCoins(tokenCoins));
  }

  /// 发送原生 SUI，返回 (交易哈希, 实际发送金额, 上链状态, null)。
  ///
  /// [deductFeeFromAmount] 仅在「全额转出（MAX）」场景传 true：此时若
  /// 「金额 + 费用」超过余额，自动把费用从转出额中扣除，扣完不为正则抛异常。
  /// 默认 false——手输金额是明确意图，余额不足必须报错。
  Future<TransferResult> sendNative({
    required Chain chain,
    required List<int> privateKey,
    required String fromAddress,
    required String to,
    required String amount,
    FeeSpeed speed = FeeSpeed.defaultSpeed,
    bool deductFeeFromAmount = false,
  }) async {
    final provider = _providerFor(chain);

    // 1. 私钥 → 地址，与钱包地址核对。
    //    两边都过一遍 SuiAddress 再比：Sui 地址有大小写与前导零的写法差异，
    //    直接比字符串会把合法的一致判成不一致。
    final signer = SuiED25519PrivateKey.fromBytes(privateKey);
    final account = SuiEd25519Account(signer);
    final sender = account.toAddress();
    if (sender != _parseAddress(fromAddress, '发送方')) {
      throw Exception('签名地址与钱包地址不一致');
    }

    // 2. 金额换算成 MIST（SUI decimals = 9）。
    // 非 final：MAX 全额转出时会在第 5 步被扣减。
    var value = parseUnits(amount, chain.decimals);
    if (value <= BigInt.zero) throw Exception('转账金额必须大于 0');

    final recipient = _parseAddress(to, '收款方');

    // 3. 网络身份、coin 对象、gas 行情——三项互不依赖，并发取。
    //    余额不单独查：coin 列表本身就是余额（见构造函数的说明）。
    final (chainIdentifier, coins, referenceGasPrice) = await (provider.request(const SuiRequestGetChainIdentifier()), _loadNativeCoins(provider, sender), _loadReferenceGasPrice(provider)).wait;

    // 节点只提供 coin 对象、gas 行情与 dry run 结果，这些都改不了收款方和金额。
    // 但先确认它确实是这条链：敌对节点可以拿主网数据来应答，让测试网 UI 签出
    // 一笔在主网上同样有效的交易。校验必须在签名**之前**。
    chain.ensureGenesisHash(chainIdentifier);

    // 4. dry run 定费用与预算，与确认页走的是同一段代码（[_estimateFee]），
    //    显示的数和实扣的数才会是同一个。
    final estimate = await _estimateFee(provider: provider, sender: sender, recipient: recipient, coins: coins, gasPrice: referenceGasPrice);
    final quote = estimate.quoteFor(speed);

    // 5. 余额校验。按**预算**算而不是按净费用：链上是按预算整额冻结的，
    //    拿净费用去比会在「刚好够」的边界上放过一笔冻不住、进不了内存池的交易。
    final balance = _totalBalanceOf(coins);
    final fee = quote.maxFee;
    if (value + fee > balance) {
      // 默认不扣：手输金额是明确意图，余额不足必须报错，**绝不**静默改小后广播。
      if (!deductFeeFromAmount) {
        throw Exception(
          '余额不足：本次需 ${formatUnits(value + fee, chain.decimals)} ${chain.symbol}'
          '（含网络费用上限 ${formatUnits(fee, chain.decimals)}），'
          '可用 ${formatUnits(balance, chain.decimals)} ${chain.symbol}',
        );
      }
      value = balance - fee;
      if (value <= BigInt.zero) throw Exception('余额不足以支付网络费用');
      // 不必重新 dry run：改小金额只改 PTB 里那个 u64 输入，命令序列与对象数量都没变，
      // 费用不会因此变化。拿原预算减一次就是准的。
      //
      // 扣的是预算、实收的是净费用，所以 MAX 之后账户里会剩下
      // `预算 - 净费用` 的零头。这是 Sui 预算冻结机制的必然结果，不是算错了：
      // 想扣得刚好，就得赌实际消耗一分不差地等于预算，赌输了整笔交易失败。
    }

    // 6. 本地构造 + 签名 + 提交。
    final transaction = _buildTransfer(sender: sender, recipient: recipient, value: value, gasPayment: coins, gasPrice: quote.gasPrice, gasBudget: quote.gasBudget);

    // 签的是 intent message（serializeSign），发的是不带 intent 的交易本体，
    // 两者不是同一串字节，不能互换——发错了节点会报签名无效。
    final signature = account.signTransaction(transaction.serializeSign());
    final response = await provider.request(SuiRequestExecuteTransactionBlock(txBytes: transaction.toVariantBcsBase64(), signatures: [signature.toVariantBcsBase64()]));

    // digest 由交易内容算出，本地算得出来。节点回的那个必须与之相等——不等意味着
    // 提交上去的不是我们签的这笔，后续所有状态查询都会查错对象。
    if (response.digest != transaction.txHash()) {
      throw Exception('节点返回的交易哈希与本地不一致');
    }

    return (
      hash: response.digest,
      sentAmount: formatUnits(value, chain.decimals),
      // 提交成功即返回，不在这里等上链：状态先记 pending，由结果页与历史页回填。
      status: TransactionStatus.pending,
      // Sui 的 expiration 用的是 **epoch** 而不是区块高度，塞进这个字段会被 Solana
      // 那套「当前高度是否越过失效高度」的判定误读成一个近乎为 0 的高度而误判为过期。
      validUntilBlock: null,
    );
  }

  /// 发送 Sui 代币（`Coin<T>` 标准），返回 (交易哈希, 实际发送金额, 上链状态, null)。
  ///
  /// **没有 `deductFeeFromAmount`**，与 EVM / Solana / Tron / Aptos 的代币路径一致：
  /// 费用以 SUI 支付、转出的是代币，两本账不通，扣无可扣。代币的 MAX 就是代币余额本身。
  Future<TransferResult> sendToken({
    required Chain chain,
    required Token token,
    required List<int> privateKey,
    required String fromAddress,
    required String to,
    required String amount,
    FeeSpeed speed = FeeSpeed.defaultSpeed,
  }) async {
    // 0. 标准校验放在一切之前：不支持的代币不该产生任何网络请求，更不该走到签名。
    _verifyTokenSupported(token, chain);

    final provider = _providerFor(chain);

    // 1. 私钥 → 地址，与钱包地址核对（同原生路径）。
    final signer = SuiED25519PrivateKey.fromBytes(privateKey);
    final account = SuiEd25519Account(signer);
    final sender = account.toAddress();
    if (sender != _parseAddress(fromAddress, '发送方')) {
      throw Exception('签名地址与钱包地址不一致');
    }

    // 2. 金额按 **token.decimals** 换算，**不是** chain.decimals。
    //    USDC 是 6 位而 SUI 是 9 位，用错这一处会差三个数量级。
    final value = parseUnits(amount, token.decimals);
    if (value <= BigInt.zero) throw Exception('转账金额必须大于 0');

    final recipient = _parseAddress(to, '收款方');

    // 3. 网络身份、SUI coin（付 gas）、代币 coin（转出）、gas 行情——四项互不依赖，并发取。
    final (chainIdentifier, gasCoins, allTokenCoins, referenceGasPrice) = await (
      provider.request(const SuiRequestGetChainIdentifier()),
      _loadNativeCoins(provider, sender),
      _loadTokenCoins(provider, sender, token),
      _loadReferenceGasPrice(provider),
    ).wait;

    // 校验必须在签名**之前**：敌对节点可以拿主网数据来应答，让测试网 UI 签出
    // 一笔在主网上同样有效的交易。
    chain.ensureGenesisHash(chainIdentifier);

    // 同 estimateTokenFee：空代币 coin 会让 _buildTransfer 退化成原生路径，
    // 那会把 SUI 当成代币转出去。必须在这里拦住。
    if (allTokenCoins.isEmpty) throw Exception('${token.symbol} 余额不足：账户没有该代币');

    final tokenCoins = _selectTokenCoins(allTokenCoins);

    // 4. 代币余额校验。比的是**选中的**这几个 coin，不是总余额——只有它们会进这笔交易。
    final selectedBalance = _totalBalanceOf(tokenCoins);
    if (value > selectedBalance) {
      final totalBalance = _totalBalanceOf(allTokenCoins);
      // 总额够、选中的不够 = 碎片太多。这两种情况要分开说：否则用户看着余额充足
      // 却被拒，只会以为是 bug，而实际上再发一笔就会好（合并会减少碎片）。
      if (value <= totalBalance) {
        throw Exception(
          '${token.symbol} 碎片过多：本次最多能动用 $_maxTokenCoinInputs 个 coin'
          '（合计 ${formatUnits(selectedBalance, token.decimals)}），'
          '不足以转出 ${formatUnits(value, token.decimals)}。先转一笔小额可合并碎片。',
        );
      }
      throw Exception(
        '${token.symbol} 余额不足：本次需 ${formatUnits(value, token.decimals)}，'
        '可用 ${formatUnits(totalBalance, token.decimals)}',
      );
    }

    // 5. dry run 定费用与预算，与确认页走同一段代码、同一组 coin。
    final estimate = await _estimateFee(provider: provider, sender: sender, recipient: recipient, coins: gasCoins, gasPrice: referenceGasPrice, tokenCoins: tokenCoins);
    final quote = estimate.quoteFor(speed);

    // 6. **另一本账**：gas 以 SUI 支付，代币再多也付不了手续费。
    final nativeBalance = _totalBalanceOf(gasCoins);
    if (quote.maxFee > nativeBalance) {
      throw Exception(
        '${chain.symbol} 不足以支付网络费：需 ${formatUnits(quote.maxFee, chain.decimals)} ${chain.symbol}，'
        '可用 ${formatUnits(nativeBalance, chain.decimals)} ${chain.symbol}',
      );
    }

    // 7. 本地构造 + 签名 + 提交。
    final transaction = _buildTransfer(sender: sender, recipient: recipient, value: value, gasPayment: gasCoins, gasPrice: quote.gasPrice, gasBudget: quote.gasBudget, tokenCoins: tokenCoins);

    final signature = account.signTransaction(transaction.serializeSign());
    final response = await provider.request(SuiRequestExecuteTransactionBlock(txBytes: transaction.toVariantBcsBase64(), signatures: [signature.toVariantBcsBase64()]));

    if (response.digest != transaction.txHash()) {
      throw Exception('节点返回的交易哈希与本地不一致');
    }

    return (
      hash: response.digest,
      // 按**代币精度**格式化回去，与第 2 步的换算对称。
      sentAmount: formatUnits(value, token.decimals),
      status: TransactionStatus.pending,
      validUntilBlock: null,
    );
  }

  /// 查询一笔已广播交易的当前上链状态。
  Future<TransactionStatus> waitForReceipt(Chain chain, String transactionHash, {SuiProvider? provider, Duration timeout = _receiptTimeout, Duration interval = _receiptPollInterval}) async {
    final rpc = provider ?? _providerFor(chain);
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final status = await _statusOnce(rpc, transactionHash);
      if (status.isFinal) return status;
      await Future<void>.delayed(interval);
    }
    return TransactionStatus.pending;
  }

  /// 查一次状态。查不到（节点对未知 digest 报错）按 pending 处理。
  ///
  /// 这里 catch 得比较宽：限流与网络故障同样会走到这条分支，而把它们报成「失败」
  /// 会让一笔其实已经上链的交易在历史里显示成红叉。pending 是唯一不会撒谎的答案。
  Future<TransactionStatus> _statusOnce(SuiProvider provider, String transactionHash) async {
    try {
      final response = await provider.request(SuiRequestGetTransactionBlock(transactionDigest: transactionHash, options: const SuiApiTransactionBlockResponseOptions(showEffects: true)));
      final effects = response.effects;
      // 没带 effects 回来就是还没执行完，成败无从谈起。
      if (effects == null) return TransactionStatus.pending;
      // 执行完了才有成败可言：failure 是上链后被 Move 层拒绝，gas 照扣，
      // 属于确定的失败——与「没上链」的 expired 不是一回事。
      return effects.status.status.isSuccess ? TransactionStatus.confirmed : TransactionStatus.failed;
    } catch (_) {
      return TransactionStatus.pending;
    }
  }

  /// 构造一笔转账的 PTB。
  ///
  /// 原生路径（[tokenCoins] 为空）：从 **gas coin** 里拆出要转的金额再转走。
  /// 这么做而不是显式挑一个 coin 对象来拆，是为了借上 Sui 的 gas smashing——
  /// `gasData.payment` 里的多个 coin 会先被合并成一个，于是碎片账户不必先发一笔
  /// merge 交易就能转出接近全部余额，也不会出现「拿来转账的 coin 恰好被选去付 gas」
  /// 这种自我冲突。
  ///
  /// 代币路径（[tokenCoins] 非空）：代币散在若干个 `Coin<T>` object 里，**不能**从
  /// gas coin 拆——那是 SUI。所以先把选中的代币 coin `MergeCoins` 成一个，
  /// 再从它 `SplitCoins` 出要转的金额。gas 仍由 [gasPayment] 里的 SUI 单独支付，
  /// 两套对象互不占用，不会出现原生路径那种「拿来转账的 coin 恰好被选去付 gas」的冲突。
  SuiTransactionDataV1 _buildTransfer({
    required SuiAddress sender,
    required SuiAddress recipient,
    required BigInt value,
    required List<SuiApiCoinResponse> gasPayment,
    required BigInt gasPrice,
    required BigInt gasBudget,
    List<SuiApiCoinResponse> tokenCoins = const [],
  }) {
    // 输入 0 是金额、输入 1 是收款方，两条路径共用；代币路径在其后追加 object 输入。
    final inputs = <SuiCallArg<Object?>>[SuiCallArgPure.u64(value), SuiCallArgPure.address(recipient)];
    final commands = <SuiCommand>[];

    // 要拆的那个 coin：原生是 gas coin 本身，代币是合并后的第一个代币 object。
    final SuiArgument source;
    if (tokenCoins.isEmpty) {
      source = SuiArgumentGasCoin();
    } else {
      // 代币 coin 从输入 2 开始排。
      const firstTokenInput = 2;
      for (final coin in tokenCoins) {
        inputs.add(SuiCallArgObject(SuiObjectArgImmOrOwnedObject(coin.toObjectRef())));
      }
      source = SuiArgumentInput(firstTokenInput);
      // 只有一个 coin 时不需要 merge——空 sources 的 MergeCoins 是条没有意义的命令，
      // 白付一份 computation，还会让「合并了几个」这件事在链上记录得不实。
      if (tokenCoins.length > 1) {
        commands.add(SuiCommandMergeCoins(destination: source, sources: [for (var i = 1; i < tokenCoins.length; i++) SuiArgumentInput(firstTokenInput + i)]));
      }
    }

    // 从 source 拆出输入 0 那么多，结果落在最后一条 Result 上。
    commands.add(SuiCommandSplitCoins(coin: source, amounts: [SuiArgumentInput(0)]));
    final splitResultIndex = commands.length - 1;
    // 输入 1 是收款方：把上一步拆出来的那个 coin 转给他。
    commands.add(SuiCommandTransferObjects(objects: [SuiArgumentResult(splitResultIndex)], address: SuiArgumentInput(1)));

    final programmable = SuiProgrammableTransaction(inputs: inputs, commands: commands);

    return SuiTransactionDataV1(
      kind: SuiTransactionKindProgrammableTransaction(programmable),
      sender: sender,
      gasData: SuiGasData(payment: gasPayment.map((coin) => coin.toObjectRef()).toList(), owner: sender, price: gasPrice, budget: gasBudget),
      // 不设失效 epoch：Sui 的 epoch 约一天一换，拿它当有效期窗口太粗
      // （要么几乎不失效，要么在换 epoch 的瞬间把正常交易也废掉）。
      // 防重放靠的是 coin 对象的 version——同一笔交易第二次提交时输入对象已经变了，
      // 链上会直接拒绝，不需要额外的时间窗口。
      expiration: const SuiTransactionExpirationNone(),
    );
  }

  /// dry run 一次，得出这笔交易的净费用与预算。
  ///
  /// 估费与发送共用它，两处的数才对得上。
  ///
  /// 探测金额固定 1 个最小单位（原生是 1 MIST，代币是 1 个 token 最小单位），
  /// 不用用户填的金额：费用与金额无关（见 [estimateNativeFee]），而 MAX 全额转出时
  /// 拿全额去探，会因为「预算 + 转出额 > 余额」让 dry run 失败——那时连
  /// 「这笔要花多少」都问不出来。
  ///
  /// [tokenCoins] 非空即代币路径。代币路径的 dry run 同样要用**发送时那一组** coin
  /// （由 [_selectTokenCoins] 选出后一路传下来）：合并几个 coin 直接决定手续费，
  /// 两处选得不一样，确认页显示的数就不是实扣的数。
  Future<SuiFeeEstimate> _estimateFee({
    required SuiProvider provider,
    required SuiAddress sender,
    required SuiAddress recipient,
    required List<SuiApiCoinResponse> coins,
    required BigInt gasPrice,
    List<SuiApiCoinResponse> tokenCoins = const [],
  }) async {
    final balance = _totalBalanceOf(coins);
    if (balance <= BigInt.zero) throw Exception('账户没有可用的 SUI，无法支付网络费用');

    // 预算上限，两条路径的约束不同：
    //
    // **原生**必须给转出额留出空档，不能等于余额。这里曾经写成 `min(上限, 余额)`，
    // 在「余额刚好等于上限」时会让预算吃满整个余额，于是连 1 MIST 都转不出去，
    // dry run 直接判 failure。而 failure 的响应里 gasUsed 是**半截数**
    // （storageCost 只算到中断那一刻），拿它当费用会少算一半——2026-09-18 在 testnet
    // 上就是这么显示成 0.001009 而实扣 0.002 的。
    //
    // **代币**不需要这个空档：转出的是代币 object，SUI 只出 gas，预算吃满 SUI 余额
    // 也不会跟转出额抢。别把两条「统一」成一种写法——统一成代币那种，原生就退回上面那个 bug。
    final budgetCeiling = tokenCoins.isEmpty ? balance - _probeValue : balance;
    if (budgetCeiling <= BigInt.zero) throw Exception('余额不足以支付网络费用');
    final provisionalBudget = _clampBudget(budgetCeiling < _provisionalGasBudgetCap ? budgetCeiling : _provisionalGasBudgetCap);

    final probe = _buildTransfer(sender: sender, recipient: recipient, value: _probeValue, gasPayment: coins, gasPrice: gasPrice, gasBudget: provisionalBudget, tokenCoins: tokenCoins);

    final dryRun = await provider.request(SuiRequestDryRunTransactionBlock(txBytes: probe.toVariantBcsBase64()));

    // **失败的 dry run 绝不能当成估价用**。它照样带回一份 gasUsed，但那是执行中断
    // 那一刻的半截账，比真实费用小——直接用下去会让确认页显示一个偏低的数，
    // 更糟的是让 MAX 预留不足、把一笔注定被拒的交易放出去。
    final status = dryRun.effects.status;
    if (!status.status.isSuccess) {
      throw Exception('网络费用估算失败：${status.error ?? '节点未说明原因'}');
    }

    final gasUsed = dryRun.effects.gasUsed;
    // 存储返还可能大于支出（销毁的旧对象退的押金比新对象收的多），净额因此可能为负。
    // 夹到 0 而不是让负数流下去：下游要拿它算预算和「还能转多少」，
    // 一个负的费用会让这两处都算出比实际更宽松的数。
    final netGasFee = _clampToZero(gasUsed.computationCost + gasUsed.storageCost - gasUsed.storageRebate);

    return SuiFeeEstimate(referenceGasPrice: gasPrice, netGasFee: netGasFee, gasBudget: _clampBudget(_gasBudgetFor(netGasFee)));
  }

  /// 取发送方名下的 SUI coin 对象。
  ///
  /// 它同时是三样东西的来源：可用余额、gas 付款对象、以及转账要拆的那个 coin。
  /// 一次取齐是刻意的——分头去查会让三者对应到不同时刻的链上状态。
  /// **不在这里抛错**，哪怕一个 coin 都没查到也照样返回空列表：这个方法总是在
  /// `await (…).wait` 里跑，而 `.wait` 会把里面抛出的异常包成 `ParallelWaitError`
  /// ——那不是 `Exception` 的子类型，会让确认页的错误分支落到最兜底的
  /// 「发送失败，请稍后重试」，把「账户没有可用的 SUI」这种能指导用户下一步的
  /// 具体话术整个吃掉。校验一律放在 `.wait` 之后。
  Future<List<SuiApiCoinResponse>> _loadNativeCoins(SuiProvider provider, SuiAddress owner) async {
    final response = await provider.request(SuiRequestGetCoins(owner: owner, coinType: _nativeCoinType));
    final coins = response.data;
    if (coins.length <= _maxGasPaymentObjects) return coins;

    // 碎片过多时只取最大的那几个：要凑足额，从大的拿起最省对象数。
    final sorted = [...coins]..sort((left, right) => right.balance.compareTo(left.balance));
    return sorted.take(_maxGasPaymentObjects).toList();
  }

  /// 取发送方名下某个代币的 coin 对象。
  ///
  /// 与 [_loadNativeCoins] 分开调用（`coinType` 不同的两次 `suix_getCoins`）：
  /// 代币转账要动的是代币 object，付 gas 要用的是 SUI object，两者不能混。
  /// 同 [_loadNativeCoins]：**不在这里抛错**，空列表由调用方在 `.wait` 之后判。
  Future<List<SuiApiCoinResponse>> _loadTokenCoins(SuiProvider provider, SuiAddress owner, Token token) async {
    final response = await provider.request(SuiRequestGetCoins(owner: owner, coinType: token.identifier));
    return response.data;
  }

  /// 选出本次要用的代币 coin：按余额降序取前 [_maxTokenCoinInputs] 个。
  ///
  /// **刻意不看转账金额**。选取一旦与金额相关，手续费就成了金额的函数——
  /// 确认页每改一次金额都要重跑 dry run，而且估费与发送两处必须保证选出同一组，
  /// 否则就是「显示的数 ≠ 实扣的数」（原生路径正因这类不一致翻过车）。
  /// 固定选取从根上没有这个问题：同一个账户状态下，估费与发送必然选出同一组。
  ///
  /// 代价是碎片多时会合并得比必要的多、单笔略贵；但合并完账户就只剩一个 coin，
  /// 下一笔自动变便宜——这个代价只付一次，顺带把碎片理干净了。
  static List<SuiApiCoinResponse> _selectTokenCoins(List<SuiApiCoinResponse> coins) {
    if (coins.length <= _maxTokenCoinInputs) return coins;
    final sorted = [...coins]..sort((left, right) => right.balance.compareTo(left.balance));
    return sorted.take(_maxTokenCoinInputs).toList();
  }

  /// 代币必须是 Sui 的 `Coin<T>` 标准，且 identifier 是个合法形状的 coin type。
  ///
  /// 判断方向与 Aptos 的同名方法**相反**：Aptos 拒绝带 `::` 的 identifier
  /// （那是它不支持的旧 Coin 标准，它只收 Fungible Asset 的裸地址），
  /// 而 Sui 的 coin type 本来就是 `包::模块::类型`，没有 `::` 反而是错的。
  void _verifyTokenSupported(Token token, Chain chain) {
    if (token.standard != TokenStandard.suiCoin) {
      throw UnsupportedError('${token.symbol} 不是 Sui 代币，无法在 ${chain.name} 上转账');
    }
    if (!token.identifier.contains('::')) {
      throw UnsupportedError('${token.symbol} 的 coin type 格式不对：应形如 0x…::usdc::USDC');
    }
  }

  Future<BigInt> _loadReferenceGasPrice(SuiProvider provider) => provider.request(const SuiRequestGetReferenceGasPrice());

  static BigInt _totalBalanceOf(List<SuiApiCoinResponse> coins) => coins.fold(BigInt.zero, (sum, coin) => sum + coin.balance);

  static BigInt _clampToZero(BigInt value) => value < BigInt.zero ? BigInt.zero : value;

  /// 预算不得低于协议下限，否则交易在校验阶段就被拒。
  static BigInt _clampBudget(BigInt budget) => budget < _minimumGasBudget ? _minimumGasBudget : budget;

  /// 解析并校验一个 Sui 地址，出错时说清是哪一方的地址不对。
  SuiAddress _parseAddress(String address, String role) {
    try {
      return SuiAddress(address);
    } catch (_) {
      throw Exception('$role地址不是合法的 Sui 地址：$address');
    }
  }
}
