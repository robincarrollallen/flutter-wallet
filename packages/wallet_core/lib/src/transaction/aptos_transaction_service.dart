import 'package:on_chain/aptos/aptos.dart';

import 'package:wallet_core/chains.dart';
import 'package:wallet_core/rpc.dart';

import '../model/models.dart';
import 'transfer/transfer_result.dart';

/// Aptos 转账：取序列号与 gas 行情 → 本地构造 → 模拟执行定 gas → 本地签名 → 提交。
/// 只做链上交互，不认识钱包与私钥来源。
class AptosTransactionService {
  /// [provider] / [balances] 都只为测试留的注入口，生产代码用默认值即可。
  /// 命名参数直接写成私有字段的 initializing formal：调用处仍是 `balances:`
  /// （Dart 会去掉下划线取公开名），少一行转发。
  const AptosTransactionService({AptosProvider? provider, this._balances = const ChainBalanceApi()})
    : _injected = provider;

  final AptosProvider? _injected;
  final ChainBalanceApi _balances;

  /// 原生 APT 转账走 `0x1::aptos_account::transfer`，而**不是** `0x1::coin::transfer`。
  ///
  /// 差别只在收款方从未上链时：前者顺带把账户建出来，后者直接失败。对用户来说
  /// 「转给一个新地址」是最平常的操作，不该因为选错入口而报一句看不懂的 Move 错误。
  static const String _transferModule = 'aptos_account';
  static const String _transferFunction = 'transfer';

  /// 交易的有效期窗口。
  ///
  /// 超过这个时刻仍未上链，链上直接丢弃。取 60 秒是在两种代价之间选：太短会让
  /// 网络稍抖一下就白发一次，太长则会让一笔「看起来失败了」的交易在几分钟后突然上链，
  /// 而用户此时多半已经重发过一笔。
  static const Duration _expirationWindow = Duration(seconds: 60);

  /// 模拟执行时先声明的 gas 上限。
  ///
  /// 只是个够用的占位值：真正写进交易的上限由模拟结果 [_maxGasAmountFor] 现算。
  /// 但它不能随便取大——Aptos 在模拟时同样按「上限 × 单价」检查账户余额够不够预扣，
  /// 填 SDK 默认的 200000 会让余额不多的账户在模拟这一步就被判余额不足。
  ///
  /// 取 30000：实测最贵的情形（顺带建号）是 10336 gas，留约 3 倍余量。
  /// 低于实际用量会让模拟直接 OUT_OF_GAS，那时连「这笔要花多少」都问不出来。
  static final BigInt _provisionalMaxGasAmount = BigInt.from(30000);

  /// 模拟出的 gas 用量之上留的余量：`gasUsed × 3 ÷ 2 + 200`。
  ///
  /// 必须留：模拟跑的是当前状态，真正执行时链上状态已经变了（收款方可能刚被别人
  /// 建好、也可能没有），用量会有出入。**两头的代价不对等**——上限少了交易直接
  /// OUT_OF_GAS 失败且 gas 照扣，多了只是多冻一会儿、执行完就退回。
  static BigInt _maxGasAmountFor(BigInt gasUsed) => gasUsed * BigInt.from(3) ~/ BigInt.two + BigInt.from(200);

  /// 模拟执行时使用的探测金额。
  ///
  /// **刻意不用用户填的金额**：一笔转账消耗多少 gas 与转多少无关（只与收款方账户
  /// 存不存在有关，而收款方是真实地址，这一点模拟得到），但金额填成「全部余额」时
  /// 模拟会因为付不起预扣而失败。用 1 octa 探测，MAX 全额转出才估得出费用——
  /// 而估费与发送走的是同一个探测值，确认页显示的数和实扣的数才会是同一个。
  static final BigInt _probeAmount = BigInt.one;

  /// 单次状态查询的默认超时：只够发一轮请求。
  ///
  /// 与 EVM / Solana / Tron 同一原则——广播链路不等上链，查不到即视为仍在打包中，
  /// 状态交给结果页与历史页各自轮询回填。
  static const Duration _receiptTimeout = Duration(seconds: 1);

  /// 单次调用内多轮查询的间隔。默认超时下只会发一轮，这个值仅对显式传长超时的调用方有意义。
  static const Duration _receiptPollInterval = Duration(seconds: 1);

  AptosProvider _providerFor(Chain chain) => _injected ?? aptosProviderFor(chain);

  /// 估算一笔原生 APT 转账的三档费用。
  ///
  /// **没有 `amount` 参数**，与 EVM / Solana / Tron 的估费入口不同形：那几条链的
  /// 费用都随金额变（gasLimit、交易字节数），Aptos 不变——一笔转账消耗多少 gas 由
  /// 它做了什么决定，与转多少无关。加一个不参与计算的参数，只会让调用方以为它有用。
  /// **不走模拟执行**，理由见 [_gasCapFor]。
  Future<AptosFeeEstimate> estimateNativeFee({required Chain chain, required String from, required String to}) async {
    final provider = _providerFor(chain);
    final sender = _parseAddress(from, '发送方');
    final recipient = _parseAddress(to, '收款方');

    final (context, recipientExists) = await (
      _loadContext(provider, sender, chain),
      _accountExists(provider, recipient),
    ).wait;

    final cap = _gasCapFor(recipientExists: recipientExists);
    return AptosFeeEstimate(
      deprioritizedGasUnitPrice: context.deprioritizedGasUnitPrice,
      gasUnitPrice: context.gasUnitPrice,
      prioritizedGasUnitPrice: context.prioritizedGasUnitPrice,
      // 没模拟就没有「实际消耗」这个数。报成与上限相等而不是编一个更小的值：
      // 编出来的「预计实付」会比真实值低，用户按它算余额就会差那一点点。
      gasUsed: cap,
      maxGasAmount: cap,
    );
  }

  /// 估费用的 gas 上限。
  ///
  /// **估费不能用模拟执行**，尽管模拟才是准的：Aptos 的 `/transactions/simulate`
  /// 虽然不校验签名，却**校验 authenticator 里的公钥**——拿它算出 auth key 与账户
  /// 当前的比对，对不上一律 `INVALID_AUTH_KEY`。而公钥只能从私钥推出来，
  /// 于是「模拟」就等价于「解锁私钥」：进一次确认页就解一次锁（导入钱包还要弹一次
  /// 生物识别），代价远超估费本身的价值。所以估费退而用静态上限，
  /// 真正的用量由 [sendNative] 在签名那一刻模拟出来。
  ///
  /// 两个档的差别只在收款方账户存不存在：不存在时 `aptos_account::transfer` 会
  /// 顺带建号，那一步的 gas 比纯转账高一个数量级。
  static BigInt _gasCapFor({required bool recipientExists}) =>
      recipientExists ? _transferGasCap : _accountCreationGasCap;

  /// 收款方已存在时的 gas 上限。**testnet 实测 62**（2026-09 两笔真实转账），取 300。
  ///
  /// 留约 5 倍余量：上限只影响预扣、执行完退回，估高的代价只是确认页的数字偏保守；
  /// 估低的代价是 MAX 全额转出预留不够，那笔交易会被链上直接拒收。
  static final BigInt _transferGasCap = BigInt.from(300);

  /// 收款方尚未上链时的 gas 上限：多一步建号。**testnet 实测 10336**，取 16000。
  ///
  /// 与上一档差了两个数量级，所以这两档必须分开——建号那一笔按 300 去估，
  /// 会把 0.0103 APT 的费用说成 0.00003。
  static final BigInt _accountCreationGasCap = BigInt.from(16000);

  /// 估算一笔 Aptos 代币转账的三档费用。
  ///
  /// 与 [estimateNativeFee] 同样**没有 `amount`**、同样**不走模拟**（理由见 [_gasCapFor]）。
  ///
  /// 但比原生少一档：代币只用 [_tokenTransferGasCap] 一个上限，不区分「收款方要不要
  /// 建存储」。原生那边靠 [_accountExists] 分得出两档，代币这边分不出——FA 的开销
  /// 差异取决于收款方有没有**这一种资产**的主存储，而余额端点对「没有存储」返回的是
  /// 0 而不是 404（实测），从外面看不出区别。所以一律按「要建存储」估，宁可偏保守。
  Future<AptosFeeEstimate> estimateTokenFee({
    required Chain chain,
    required Token token,
    required String from,
    required String to,
  }) async {
    _verifyTokenSupported(token, chain);
    final provider = _providerFor(chain);
    final context = await _loadContext(provider, _parseAddress(from, '发送方'), chain);
    // to 仍然解析一遍：地址不合法要在估费阶段就报出来，而不是等用户点了发送。
    _parseAddress(to, '收款方');

    return AptosFeeEstimate(
      deprioritizedGasUnitPrice: context.deprioritizedGasUnitPrice,
      gasUnitPrice: context.gasUnitPrice,
      prioritizedGasUnitPrice: context.prioritizedGasUnitPrice,
      gasUsed: _tokenTransferGasCap,
      maxGasAmount: _tokenTransferGasCap,
    );
  }

  /// 代币转账的 gas 上限。**testnet 实测两笔**（2026-09）：
  /// 收款方没有该资产的主存储时 5715（要建存储），已有则只要 149。
  ///
  /// 取 9000——按**贵的那档**留约 1.6 倍余量，与原生的 [_accountCreationGasCap] 同一
  /// 比例。刻意不按 149 那档估：两档差了近 40 倍，而从外面分不出收款方属于哪一档
  /// （见 [estimateTokenFee]），按便宜的估会把一笔 0.0057 APT 的费用说成 0.00015。
  static final BigInt _tokenTransferGasCap = BigInt.from(9000);

  /// 账户在链上存不存在。节点对未上链的账户返回 404，SDK 抛 RPCError。
  Future<bool> _accountExists(AptosProvider provider, AptosAddress address) async {
    try {
      await provider.request(AptosRequestGetAccount(address: address));
      return true;
    } catch (_) {
      // 限流与网络故障也会走到这里。此时按「不存在」处理，即取更高的那档上限——
      // 估高了只是多冻一会儿，估低了会让 MAX 全额转出付不起预扣而发不出去。
      return false;
    }
  }

  /// 发送原生 APT，返回 (交易哈希, 实际发送金额, 上链状态, 交易失效高度)。
  ///
  /// [privateKey] 为原始 32 字节 ed25519 私钥（`PrivateKeyResolver` 对 Aptos 给的就是它），
  /// 仅在本次调用内使用。[fromAddress] 为钱包展示的 0x 地址，必须与私钥派生地址一致。
  /// [amount] 为用户输入的十进制字符串，按 [Chain.decimals]（APT = 8）换算成 octa。
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
    //    两边都过一遍 AptosAddress 再比：Aptos 地址有「前导零省略」的短写法
    //    （0x1 与 0x000…01 是同一个地址），直接比字符串会把合法的一致判成不一致。
    final signer = AptosED25519PrivateKey.fromBytes(privateKey);
    final sender = signer.publicKey.toAddress();
    if (sender != _parseAddress(fromAddress, '发送方')) {
      throw Exception('签名地址与钱包地址不一致');
    }

    // 2. 金额换算成 octa（APT decimals = 8）。
    // 非 final：MAX 全额转出时会在第 5 步被扣减。
    var value = parseUnits(amount, chain.decimals);
    if (value <= BigInt.zero) throw Exception('转账金额必须大于 0');

    final recipient = _parseAddress(to, '收款方');

    // 3. 序列号、链 id、三档 gas 单价、发送方余额——四项互不依赖，并发取。
    final (context, balance) = await (
      _loadContext(provider, sender, chain),
      _balances.fetchNativeBalance(chain, sender.address),
    ).wait;

    // 4. 模拟执行，定出这笔交易的 gas 用量与上限。
    //    用本档单价模拟，模拟时的预扣校验才与真正提交时是同一个口径。
    final gasUnitPrice = context.priceFor(speed);
    final gasUsed = await _simulateGasUsed(
      provider: provider,
      context: context,
      probePayload: _nativeTransferPayload(recipient, _probeAmount),
      gasUnitPrice: gasUnitPrice,
      publicKey: signer.publicKey,
    );
    final maxGasAmount = _maxGasAmountFor(gasUsed);

    // 5. 余额校验。按**上限**算而不是按实际消耗：链上是按 `上限 × 单价` 预扣的，
    //    拿实际消耗去比会在「刚好够」的边界上放过一笔进不了内存池的交易。
    final fee = gasUnitPrice * maxGasAmount;
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
      // 不必像 EVM 那样二次收敛：gas 用量由交易做了什么决定，与金额无关，
      // 金额改小不会让费用变化，拿原费用去减一次就是准的。
      //
      // 扣的是上限、实收的是实际消耗，所以 MAX 之后账户里会剩下
      // `(上限 - 实际) × 单价` 的零头。这是 Aptos 预扣机制的必然结果，不是算错了：
      // 想扣得刚好，就得赌实际消耗一分不差地等于上限，赌输了整笔交易失败。
    }

    // 6. 本地构造 + 签名 + 提交。
    //
    // 节点只提供序列号、gas 行情、模拟结果与 **chainId**。前三项改不了收款方和金额，
    // 但 chainId 会写进待签交易：必须与注册表钉死的测试网值比对，否则敌对节点
    // 可以把主网 chainId=1 塞进来，让测试网 UI 签出主网有效交易。
    final transaction = _buildTransaction(
      context: context,
      payload: _nativeTransferPayload(recipient, value),
      gasUnitPrice: gasUnitPrice,
      maxGasAmount: maxGasAmount,
    );
    final signed = AptosSignedTransaction(
      rawTransaction: transaction,
      authenticator: AptosTransactionAuthenticatorEd25519(
        publicKey: signer.publicKey,
        signature: AptosEd25519Signature(signer.sign(transaction.signingSerialize()).signature),
      ),
    );

    final pending = await provider.request(AptosRequestSubmitTransaction(signedTransactionData: signed.toBcs()));

    // 哈希由交易内容算出，本地算得出来。节点回的那个必须与之相等——不等意味着
    // 提交上去的不是我们签的这笔，后续所有状态查询都会查错对象。
    //
    // 比之前先归一化大小写与 `0x` 前缀：SDK 的 `txHash()` 回的是**不带前缀**的小写
    // 十六进制，而节点回的带 `0x`。直接比字符串会让这条本来该沉默的校验每次都误报。
    if (_normalizeHash(pending.hash) != _normalizeHash(signed.txHash())) {
      throw Exception('节点返回的交易哈希与本地不一致');
    }

    return (
      // 用节点回的那个：它带 `0x`，与区块浏览器链接和后续按哈希查询的口径一致。
      hash: pending.hash,
      sentAmount: formatUnits(value, chain.decimals),
      // 提交成功即返回，不在这里等上链：状态先记 pending，由结果页与历史页回填。
      status: TransactionStatus.pending,
      // Aptos 的失效是**时间戳**不是区块高度，塞进这个字段会被 Solana 那套
      // 「当前高度是否越过失效高度」的判定误读成一个近乎为 0 的高度而误判为过期。
      validUntilBlock: null,
    );
  }

  /// 发送 Aptos 代币（Fungible Asset），返回 (交易哈希, 实际发送金额, 上链状态, null)。
  ///
  /// **没有 `deductFeeFromAmount`**，与 EVM / Solana / Tron 的代币路径一致：费用以 APT
  /// 支付、转出的是代币，两本账不通，扣无可扣。代币的 MAX 就是代币余额本身。
  Future<TransferResult> sendToken({
    required Chain chain,
    required Token token,
    required List<int> privateKey,
    required String fromAddress,
    required String to,
    required String amount,
    FeeSpeed speed = FeeSpeed.defaultSpeed,
  }) async {
    // 1. 代币标准校验，放在一切之前——这一条挡住的是「拿别的链的代币来这里转」。
    _verifyTokenSupported(token, chain);

    final provider = _providerFor(chain);

    // 2. 私钥 → 地址，与钱包地址核对（理由同 sendNative）。
    final signer = AptosED25519PrivateKey.fromBytes(privateKey);
    final sender = signer.publicKey.toAddress();
    if (sender != _parseAddress(fromAddress, '发送方')) {
      throw Exception('签名地址与钱包地址不一致');
    }

    // 3. 金额按**代币**精度换算（USDC 是 6 位，APT 是 8 位）。
    //    拿 chain.decimals 去换会让一笔 1 USDC 变成 0.01 USDC。
    final value = parseUnits(amount, token.decimals);
    if (value <= BigInt.zero) throw Exception('转账金额必须大于 0');

    final metadata = _parseAddress(token.identifier, '代币');
    final recipient = _parseAddress(to, '收款方');

    // 4. 上下文、代币余额、原生币余额——三项互不依赖，并发取。
    final (context, tokenBalance, nativeBalance) = await (
      _loadContext(provider, sender, chain),
      _balances.fetchTokenBalance(chain, token, sender.address),
      _balances.fetchNativeBalance(chain, sender.address),
    ).wait;

    // 5. 代币余额校验。不足即报错，**绝不**静默改小后提交。
    if (value > tokenBalance) {
      throw Exception(
        '${token.symbol} 余额不足：本次需 ${formatUnits(value, token.decimals)}，'
        '可用 ${formatUnits(tokenBalance, token.decimals)}',
      );
    }

    // 6. 模拟执行定 gas。探测金额用 1 个最小单位，理由同 sendNative。
    final gasUnitPrice = context.priceFor(speed);
    final gasUsed = await _simulateGasUsed(
      provider: provider,
      context: context,
      probePayload: _fungibleAssetTransferPayload(metadata, recipient, _probeAmount),
      gasUnitPrice: gasUnitPrice,
      publicKey: signer.publicKey,
    );
    final maxGasAmount = _maxGasAmountFor(gasUsed);

    // 7. 原生币够不够付费——与第 5 步分开的第二本账。代币再多也付不了 gas。
    final fee = gasUnitPrice * maxGasAmount;
    if (fee > nativeBalance) {
      throw Exception(
        '${chain.symbol} 不足以支付网络费：需约 ${formatUnits(fee, chain.decimals)} ${chain.symbol}，'
        '可用 ${formatUnits(nativeBalance, chain.decimals)} ${chain.symbol}',
      );
    }

    // 8. 本地构造 + 签名 + 提交，与 sendNative 同一套。
    final transaction = _buildTransaction(
      context: context,
      payload: _fungibleAssetTransferPayload(metadata, recipient, value),
      gasUnitPrice: gasUnitPrice,
      maxGasAmount: maxGasAmount,
    );
    final signed = AptosSignedTransaction(
      rawTransaction: transaction,
      authenticator: AptosTransactionAuthenticatorEd25519(
        publicKey: signer.publicKey,
        signature: AptosEd25519Signature(signer.sign(transaction.signingSerialize()).signature),
      ),
    );

    final pending = await provider.request(AptosRequestSubmitTransaction(signedTransactionData: signed.toBcs()));
    if (_normalizeHash(pending.hash) != _normalizeHash(signed.txHash())) {
      throw Exception('节点返回的交易哈希与本地不一致');
    }

    return (
      hash: pending.hash,
      // 按代币精度格式化：这个字符串会原样进历史记录与结果页。
      sentAmount: formatUnits(value, token.decimals),
      status: TransactionStatus.pending,
      validUntilBlock: null,
    );
  }

  /// 这枚代币能不能在 Aptos 上转。不能就抛 [UnsupportedError]。
  ///
  /// 两道，缺一不可：
  /// - 标准不是 [TokenStandard.aptosCoin]：拿别的链的代币来这里转，与 EVM / Solana /
  ///   Tron 的同位检查一致。
  /// - **identifier 含 `::`**：那是旧的 Coin 标准（`0x1::aptos_coin::AptosCoin` 这种
  ///   类型结构），要走 `0x1::aptos_account::transfer_coins<T>`，与 Fungible Asset
  ///   的入口函数完全不同。`TokenStandard` 只有一个 `aptosCoin` 盖住了两种形态，
  ///   枚举分不出来，只能看 identifier 的形状。
  ///
  ///   本项目只实现了 FA：目录里没有任何 Coin 标准的代币可供验证，而一条发得出去
  ///   却没人验过的转账路径，比一句「暂不支持」危险得多。
  void _verifyTokenSupported(Token token, Chain chain) {
    if (token.standard != TokenStandard.aptosCoin) {
      throw UnsupportedError('${token.symbol} 不是 Aptos 代币，无法在 ${chain.name} 上转账');
    }
    if (token.identifier.contains('::')) {
      throw UnsupportedError('${token.symbol} 是 Aptos Coin 标准代币，本项目目前只支持 Fungible Asset');
    }
  }

  /// 取一次「构造交易所需的链上上下文」：序列号、链 id、三档 gas 单价。
  ///
  /// 三个请求互不依赖，并发发出。序列号必须实查——它由账户当前状态决定，
  /// 猜错了交易会被链上以 SEQUENCE_NUMBER_TOO_OLD/NEW 拒绝。
  Future<_SenderContext> _loadContext(AptosProvider provider, AptosAddress sender, Chain chain) async {
    final (account, ledger, gas) = await (
      provider.request(AptosRequestGetAccount(address: sender)),
      provider.request(AptosRequestGetLedgerInfo()),
      provider.request(AptosRequestEstimateGasPrice()),
    ).wait;

    chain.ensureAptosChainId(ledger.chainId);

    final regular = BigInt.from(gas.gasEstimate);
    return _SenderContext(
      sender: sender,
      sequenceNumber: account.sequenceNumber,
      chainId: ledger.chainId,
      // 节点没返回「缓慢」档时回落到推荐值，而不是自己往下打折：
      // 单价低于链上最低要求的交易会被直接拒收，省下的那点钱换不来任何东西。
      deprioritizedGasUnitPrice: BigInt.from(gas.deprioritizedGasEstimate ?? gas.gasEstimate),
      gasUnitPrice: regular,
      prioritizedGasUnitPrice: BigInt.from(gas.prioritizedGasEstimate),
    );
  }

  /// 用零签名跑一次模拟执行，返回实测 gas 消耗。
  ///
  /// 模拟**不校验签名**（所以签名位填 64 个零即可），但**校验公钥**：节点会拿
  /// [publicKey] 算出 auth key 与账户当前的比对，对不上直接回 `INVALID_AUTH_KEY`。
  /// 所以模拟拿不到「不需要密钥」这个便利——公钥必须是发送方真正的那把。
  ///
  /// 模拟失败（余额不足、收款方地址不合法、Move 层报错等）在这里就抛出来，
  /// 附上节点给的 `vm_status`：那是唯一能说清「为什么这笔发不出去」的信息。
  /// [probePayload] 由调用方用 [_probeAmount] 建好传进来——这个方法不认识「转账」
  /// 这件事，原生与代币都能用它。
  Future<BigInt> _simulateGasUsed({
    required AptosProvider provider,
    required _SenderContext context,
    required AptosTransactionPayload probePayload,
    required BigInt gasUnitPrice,
    required AptosED25519PublicKey publicKey,
  }) async {
    final probe = _buildTransaction(
      context: context,
      payload: probePayload,
      gasUnitPrice: gasUnitPrice,
      maxGasAmount: _provisionalMaxGasAmount,
    );
    final unsigned = AptosSignedTransaction(
      rawTransaction: probe,
      authenticator: AptosTransactionAuthenticatorEd25519(
        publicKey: publicKey,
        signature: AptosEd25519Signature(List<int>.filled(_ed25519SignatureLength, 0)),
      ),
    );

    final results = await provider.request(AptosRequestSimulateTransaction(signedTransactionData: unsigned.toBcs()));
    if (results.isEmpty) throw Exception('模拟执行没有返回结果');

    final simulated = results.first;
    if (!simulated.success) {
      throw Exception('这笔交易会在链上失败：${simulated.vmStatus}');
    }
    return simulated.gasUsed;
  }

  /// ed25519 签名长度。模拟用的零签名要填满这个长度，SDK 会校验。
  static const int _ed25519SignatureLength = 64;

  /// 把一个 payload 包成未签名交易。估费、模拟与发送共用，保证三者算的是同一笔。
  ///
  /// 收 payload 而不是「收款方 + 金额」：原生与代币的入口函数不同（见
  /// [_nativeTransferPayload] / [_fungibleAssetTransferPayload]），但外面这层
  /// 序列号、gas、过期时刻、链 id 是一模一样的。
  AptosRawTransaction _buildTransaction({
    required _SenderContext context,
    required AptosTransactionPayload payload,
    required BigInt gasUnitPrice,
    required BigInt maxGasAmount,
  }) {
    return AptosRawTransaction(
      sender: context.sender,
      sequenceNumber: context.sequenceNumber,
      transactionPayload: payload,
      maxGasAmount: maxGasAmount,
      gasUnitPrice: gasUnitPrice,
      expirationTimestampSecs: BigInt.from(DateTime.now().add(_expirationWindow).millisecondsSinceEpoch ~/ 1000),
      chainId: context.chainId,
    );
  }

  /// 原生 APT 转账的 payload：`0x1::aptos_account::transfer(to, amount)`。
  AptosTransactionPayload _nativeTransferPayload(AptosAddress recipient, BigInt value) {
    return AptosTransactionPayloadEntryFunction(
      entryFunction: AptosTransactionEntryFunction(
        moduleId: AptosModuleId(address: AptosAddress.one, name: _transferModule),
        functionName: _transferFunction,
        args: [recipient, MoveU64(value)],
      ),
    );
  }

  /// Fungible Asset 转账的 payload：
  /// `0x1::primary_fungible_store::transfer<0x1::fungible_asset::Metadata>(metadata, to, amount)`。
  ///
  /// 与原生那条的三点不同，每一点错了都会让交易在链上被拒：
  /// - **要带类型参数**。`transfer` 的签名是 `<T: key>`，少了它 Move 层对不上。
  /// - **实参是三个**，metadata 在最前面——它指明转的是哪一种资产。
  /// - 走 `primary_fungible_store` 而不是 `fungible_asset`：前者会在收款方没有这个
  ///   资产的主存储时顺带建一个，后者要求调用方自己把 store 对象找出来。
  ///   「转给一个没持有过这个币的人」是最平常的操作，不该因此失败。
  AptosTransactionPayload _fungibleAssetTransferPayload(AptosAddress metadata, AptosAddress recipient, BigInt value) {
    return AptosTransactionPayloadEntryFunction(
      entryFunction: AptosTransactionEntryFunction(
        moduleId: AptosConstants.primaryFungibleStoreModule,
        functionName: _transferFunction,
        typeArgs: [AptosConstants.fungibleAssetMetadataTypeTag],
        args: [metadata, recipient, MoveU64(value)],
      ),
    );
  }

  /// 交易哈希归一化：去掉 `0x` 前缀、统一小写。仅用于比对，不用于展示。
  static String _normalizeHash(String hash) {
    final lower = hash.toLowerCase();
    return lower.startsWith('0x') ? lower.substring(2) : lower;
  }

  /// 地址解析，把 SDK 的异常换成说得清是哪一头出了问题的文案。
  AptosAddress _parseAddress(String address, String role) {
    try {
      return AptosAddress(address.trim());
    } catch (_) {
      throw Exception('$role地址不是合法的 Aptos 地址');
    }
  }

  /// 查一笔交易的上链状态。
  ///
  /// 提交返回哈希只代表节点收下了，不代表已上链。刚提交时查到的是 pending_transaction
  /// （节点内存池里那一条）属正常。默认超时只够发一轮，即「查一次当前状态」；
  /// 传长超时才会变成真正的轮询。
  ///
  /// **不返回 [TransactionStatus.expired]**：Aptos 的失效判定要拿交易的
  /// `expiration_timestamp_secs` 和链上账本时间比，而交易一旦过期就会被彻底丢弃、
  /// 按哈希查不到任何东西——此时「过期了」和「还没传播开」在这个接口上长得一模一样。
  /// 与其猜，不如一律按 pending 处理，让结果页继续轮询。
  Future<TransactionStatus> waitForReceipt(
    Chain chain,
    String transactionHash, {
    AptosProvider? provider,
    Duration timeout = _receiptTimeout,
    Duration interval = _receiptPollInterval,
  }) async {
    final rpc = provider ?? _providerFor(chain);
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final status = await _statusOnce(rpc, transactionHash);
      if (status.isFinal) return status;
      await Future<void>.delayed(interval);
    }
    return TransactionStatus.pending;
  }

  /// 查一次状态。查不到（节点对未知哈希返回 404，SDK 抛 RPCError）按 pending 处理。
  ///
  /// 这里 catch 得比较宽：限流与网络故障同样会走到这条分支，而把它们报成「失败」
  /// 会让一笔其实已经上链的交易在历史里显示成红叉。pending 是唯一不会撒谎的答案。
  Future<TransactionStatus> _statusOnce(AptosProvider provider, String transactionHash) async {
    try {
      final transaction = await provider.request(AptosRequestGetTransactionByHash(transactionHash));
      return switch (transaction) {
        // 执行完了才有成败可言：success 为 false 的是上链后被 Move 层拒绝，
        // gas 照扣，属于确定的失败。
        AptosApiUserTransaction(success: final success) =>
          success ? TransactionStatus.confirmed : TransactionStatus.failed,
        // 还在内存池里排队。
        _ => TransactionStatus.pending,
      };
    } catch (_) {
      return TransactionStatus.pending;
    }
  }
}

/// 构造一笔交易所需的、与「转给谁转多少」无关的链上上下文。
///
/// 单独成类是因为它要在估费、模拟、发送三处之间传递：三者必须用**同一份**序列号与
/// 链 id，分头各取一次会让估出来的那笔和发出去的那笔不是同一笔。
class _SenderContext {
  _SenderContext({
    required this.sender,
    required this.sequenceNumber,
    required this.chainId,
    required this.deprioritizedGasUnitPrice,
    required this.gasUnitPrice,
    required this.prioritizedGasUnitPrice,
  });

  final AptosAddress sender;
  final BigInt sequenceNumber;
  final int chainId;
  final BigInt deprioritizedGasUnitPrice;
  final BigInt gasUnitPrice;
  final BigInt prioritizedGasUnitPrice;

  BigInt priceFor(FeeSpeed speed) => switch (speed) {
    FeeSpeed.slow => deprioritizedGasUnitPrice,
    FeeSpeed.normal => gasUnitPrice,
    FeeSpeed.fast => prioritizedGasUnitPrice,
  };
}
