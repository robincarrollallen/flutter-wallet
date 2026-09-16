// hide TokenStandard：on_chain 的 Metaplex 里也有一个同名枚举，与本仓库的
// `enums/token_standard.dart`（经 blockchain/token.dart 传入）撞名。本文件要的是后者。
import 'package:on_chain/solana/solana.dart' hide TokenStandard;

import 'package:wallet_core/chains.dart';
import 'package:wallet_core/rpc.dart';
import '../model/models.dart';
import 'transfer/transfer_result.dart';

/// 一笔 SPL 转账要用到的两个代币账户，以及发送方的代币余额。
///
/// SPL 的余额不在钱包地址上，而在「钱包地址 + mint」派生出的关联代币账户（ATA）里。
/// 这一步把「转给谁」翻译成「写哪个账户」，估费与发送都要先过这里。
typedef _TokenAccounts = ({
  SolAddress mint,
  SolAddress source, // 发送方 ATA
  SolAddress destination, // 收款方 ATA
  bool sourceExists, // 发送方 ATA 是否已存在（不存在即它从没持有过这个币）
  BigInt sourceBalance, // 发送方代币余额（source 不存在时为 0）
  bool createsDestination, // 本次是否要顺带创建收款方 ATA
});

/// Solana 转账：取最新 blockhash → 本地构造交易 → 本地签名 → 广播 → 查签名状态。
/// 只做链上交互，不认识钱包与私钥来源。
class SolanaTransactionService {
  /// [provider] 只为测试留的注入口，生产代码用默认值即可。
  const SolanaTransactionService({SolanaProvider? provider}) : _injected = provider;

  final SolanaProvider? _injected;

  /// 查询签名状态的默认超时：只够发一轮请求。
  ///
  /// 与 EVM / Tron 同一原则——广播链路不等上链，查不到即视为仍在打包中，
  /// 状态交给结果页与历史页各自轮询回填。
  static const Duration _receiptTimeout = Duration(seconds: 1);

  /// 单次调用内多轮查询的间隔。Solana 出块约 400ms，但状态传播要慢一些，取 1 秒。
  /// 默认超时下只会发一轮，这个值仅对显式传长超时的调用方有意义。
  static const Duration _receiptPollInterval = Duration(seconds: 1);

  /// 租金豁免按「0 字节数据的账户」算——原生 SOL 转账的收款方就是这样一个纯余额账户，
  /// 不存任何数据。SPL 代币账户另算，见 [_tokenAccountDataSize]。
  static const int _plainAccountDataSize = 0;

  /// SPL 代币账户（ATA）的数据长度，新建 ATA 的租金豁免线按它算。
  ///
  /// 取 `on_chain` 里的布局跨度而不是写死 165：这个数是 SPL Token 账户结构决定的，
  /// 让定义结构的那一方去算，改了也不会两处对不上。
  static final int _tokenAccountDataSize = SolanaTokenAccountUtils.accountSize;

  /// 本次交易声明的计算单元上限。
  ///
  /// **必须显式声明**：不声明的话每条指令按默认 200000 CU 计，而优先费 = 优先单价 ×
  /// 声明的上限（不是实际用量），拿默认值去算会高估几百倍，用户要多付几百倍的优先费。
  ///
  /// 实际用量：SystemProgram 转账 150 CU + 两条 ComputeBudget 指令各 150 CU = 450。
  /// 取 600 留一点余量——声明少了交易会因超限直接失败，而多声明这 150 CU 的代价
  /// 在任何现实价位下都不到 1 lamport，两头的代价完全不对等。
  static const int _computeUnitLimit = 600;

  /// SPL 代币转账的计算单元上限，同样按实际用量留余量（理由见 [_computeUnitLimit]）。
  ///
  /// transferChecked 实测约 4500 CU，加两条 ComputeBudget 各 150，取 6000。
  static const int _tokenComputeUnitLimit = 6000;

  /// 上一条再加一条「创建收款方 ATA」指令时的上限。
  /// 创建 ATA 约 20000 CU（要给新账户分配空间并初始化），取 30000。
  static const int _tokenWithAtaComputeUnitLimit = 30000;

  SolanaProvider _providerFor(Chain chain) => _injected ?? solanaProviderFor(chain);

  /// 估算一笔原生 SOL 转账的三档费用，并一并取回租金豁免判断所需的数据。
  ///
  /// 这个入口自己取 blockhash，供确认页的估费 provider 直接调用；[sendNative] 不走这里，
  /// 它自己取一次再传给 [_estimateWith]，好让估费与签名共用同一个 blockhash。
  Future<SolanaFeeEstimate> estimateNativeFee({
    required Chain chain,
    required String from,
    required String to,
    required String amount,
  }) async {
    final provider = _providerFor(chain);
    final blockhash = await provider.request(const SolanaRequestGetLatestBlockhash());

    return _estimateWith(
      provider: provider,
      owner: SolAddress(from.trim()),
      recipient: SolAddress(to.trim()),
      lamports: parseUnits(amount, chain.decimals),
      blockhash: blockhash.blockhash,
    );
  }

  /// 估费本体：问链上要签名费与近期优先费行情，同时取回租金豁免线与收款方余额。
  ///
  /// blockhash 由调用方给而不是在这里取，[sendNative] 才能把它和签名那次复用成同一个，
  /// 少一轮往返。也因此不需要 [Chain]——金额已经换算过，这里只跟链上打交道。
  ///
  /// **只问一次 `getFeeForMessage`，不是每档问一次**：拿优先单价为 0 的消息问出签名费，
  /// 三档的优先费再按 `单价 × 计算单元上限` 本地算。这个公式与链上收费口径一致，
  /// 算出来是精确值，没必要为三档各发一轮请求。
  Future<SolanaFeeEstimate> _estimateWith({
    required SolanaProvider provider,
    required SolAddress owner,
    required SolAddress recipient,
    required BigInt lamports,
    required SolAddress blockhash,
  }) async {
    final message = _buildTransaction(
      owner: owner,
      recipient: recipient,
      lamports: lamports,
      blockhash: blockhash,
      computeUnitPrice: BigInt.zero,
    ).serializeMessageString(encoding: TransactionSerializeEncoding.base64);

    // 记录并发（`.wait`）而不是 Future.wait 列表：四个请求返回类型不同，
    // 列表会被推断成公共父类型，逼着调用处再 cast 回来。
    final (fee, rentExemptMinimum, recipientBalance, recentFees) = await (
      provider.request(SolanaRequestGetFeeForMessage(encodedMessage: message)),
      provider.request(const SolanaRequestGetMinimumBalanceForRentExemption(size: _plainAccountDataSize)),
      provider.request(SolanaRequestGetBalance(account: recipient)),
      // 带上本次要写入的两个账户：Solana 的费率市场是**局部**的，按账户分别竞价，
      // 不问账户拿到的是全局行情，可能与这两个账户的实际拥堵程度差很远。
      provider.request(SolanaRequestGetRecentPrioritizationFees(addresses: [owner, recipient])),
    ).wait;

    return SolanaFeeEstimate(
      // getFeeForMessage 对已过期的 blockhash 会返回 null。刚取回来的不该过期，
      // 真遇上就按每签名费的标称值兜底，不让估费失败连累到发送。
      baseFeeLamports: fee ?? _lamportsPerSignature,
      computeUnitLimit: _computeUnitLimit,
      priceByPercentile: pricePercentiles(
        recentFees.map((sample) => sample.prioritizationFee).toList(),
        FeeSpeed.values.map((speed) => speed.rewardPercentile),
      ),
      rentExemptMinimum: rentExemptMinimum,
      recipientBalance: recipientBalance,
    );
  }

  /// 每签名费的标称值，仅在 `getFeeForMessage` 返回 null 时兜底。
  static final BigInt _lamportsPerSignature = BigInt.from(5000);

  /// 发送原生 SOL，返回 (交易签名, 实际发送金额, 上链状态, 交易失效高度)。
  ///
  /// [privateKey] 为原始 32 字节 ed25519 种子（`PrivateKeyResolver` 对 Solana 给的就是它），
  /// 仅在本次调用内使用。[fromAddress] 为钱包展示的 base58 地址，必须与私钥派生地址一致。
  /// [amount] 为用户输入的十进制字符串，按 [Chain.decimals]（SOL = 9）换算成 lamport。
  ///
  /// [speed] 决定优先费档位——只影响优先费，签名费三档同价。
  ///
  /// [deductFeeFromAmount] 仅在「全额转出（MAX）」场景传 true：此时若
  /// 「金额 + 费用」超过余额，自动把费用从转出额中扣除，扣完不为正则抛异常，
  /// 实际金额随结果返回。默认 false——手输金额是明确意图，余额不足必须报错。
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
    //    fromSeed 而非 fromBytes：解析器给的是 32 字节种子，不是 64 字节 keypair。
    //    base58 地址大小写敏感，不能像 0x 地址那样 toLowerCase 后比。
    final signer = SolanaPrivateKey.fromSeed(privateKey);
    final owner = signer.publicKey().toAddress();
    final expectedFrom = fromAddress.trim();
    if (owner.address != expectedFrom) {
      throw Exception('签名地址与钱包地址不一致');
    }

    // 2. 金额换算成 lamport（SOL decimals = 9）。
    // 非 final：MAX 全额转出时会在第 5 步被扣减。
    var value = parseUnits(amount, chain.decimals);
    if (value <= BigInt.zero) throw Exception('转账金额必须大于 0');

    final recipient = SolAddress(to.trim());

    // 3. 取一次 blockhash，估费与下面第 7 步的签名共用同一个。
    //    发送方余额与估费并发发出——两者互不依赖，串行等于白等一轮。
    final latest = await provider.request(const SolanaRequestGetLatestBlockhash());
    final (estimate, balance) = await (
      _estimateWith(
        provider: provider,
        owner: owner,
        recipient: recipient,
        lamports: value,
        blockhash: latest.blockhash,
      ),
      provider.request(SolanaRequestGetBalance(account: owner)),
    ).wait;

    // 4. 锁定本档报价。优先单价要原样写进交易，估费与实扣才会是同一个数。
    final quote = estimate.quoteFor(speed);
    final fee = quote.expectedFee;

    // 5. 余额校验：金额 + 网络费一起算，只比金额会放过一批注定在链上失败的交易。
    if (value + fee > balance) {
      // 默认不扣：手输金额是明确意图，余额不足必须报错，**绝不**静默改小后广播。
      if (!deductFeeFromAmount) {
        throw Exception(
          '余额不足：本次需 ${formatUnits(value + fee, chain.decimals)} ${chain.symbol}'
          '（含网络费用约 ${formatUnits(fee, chain.decimals)}），'
          '可用 ${formatUnits(balance, chain.decimals)} ${chain.symbol}',
        );
      }
      value = balance - fee;
      if (value <= BigInt.zero) throw Exception('余额不足以支付网络费用');
      // 不必像 EVM 那样二次收敛：Solana 的费用由签名数与本档优先单价决定，与金额无关，
      // 金额改小不会让费用变化，拿原费用去减一次就是准的。
    }

    // 6. 租金豁免校验（Solana 独有）。放在扣费之后，校验的才是**真正会发出去的**金额。
    _verifyRentExempt(chain: chain, estimate: estimate, value: value, balance: balance, fee: fee);

    // 7. 本地构造 + 签名 + 广播。
    //
    // **刻意没有 Tron 那套「回解校验」**：Tron 之所以要逐字段比对，是因为待签字节由
    // 节点的 `wallet/createtransaction` 给出，节点有机会把收款方或金额换掉。Solana 的
    // 交易完全在本地构造，节点只提供一个 blockhash——它改不了这笔转账转给谁、转多少，
    // 所以这里没有对应的信任缺口要堵。别当成漏了一道检查。
    //
    // blockhash 复用第 3 步取的那个，**不要**在这里再取一次：那是一轮白费的往返，
    // 而且会让 lastValidBlockHeight 与估费时的不一致。
    final transaction = _buildTransaction(
      owner: owner,
      recipient: recipient,
      lamports: value,
      blockhash: latest.blockhash,
      computeUnitPrice: estimate.priceFor(speed),
    );
    transaction.sign([signer]);

    final signature = await provider.request(
      SolanaRequestSendTransaction(
        // 编码两头必须一致：交易按 base64 序列化，就要告诉节点按 base64 解。
        encodedTransaction: transaction.serializeString(
          encoding: TransactionSerializeEncoding.base64,
          verifySignatures: true,
        ),
        encoding: SolanaRequestEncoding.base64,
        // 预检按 confirmed 即可：要求 finalized 会让刚上链的余额变化迟迟不可见，
        // 明明够付的交易反而被预检打回。
        commitment: Commitment.confirmed,
      ),
    );

    return (
      hash: signature,
      sentAmount: formatUnits(value, chain.decimals),
      // 广播成功即返回，不在这里等上链：状态先记 pending，由结果页与历史页回填。
      status: TransactionStatus.pending,
      // 带上失效高度：过了它这笔交易就永远不会上链，回填时才判得出「死了」还是「还在等」。
      validUntilBlock: latest.lastValidBlockHeight,
    );
  }

  /// 租金豁免校验：收款方与发送方转账后都必须满足「余额为 0，或不低于豁免线」。
  ///
  /// Solana 要求每个账户的余额不低于一条豁免线，否则账户会被链上回收。这带来两个
  /// 在别的链上不存在的失败模式，都要在广播前拦下来，否则用户只会看到节点的英文报错：
  /// - 向新地址转一笔太小的钱 → 收款账户创建不出来，交易失败；
  /// - 把自己的余额转到只剩一点点（不是转空）→ 自己的账户反而会被回收。
  void _verifyRentExempt({
    required Chain chain,
    required SolanaFeeEstimate estimate,
    required BigInt value,
    required BigInt balance,
    required BigInt fee,
  }) {
    final shortfall = estimate.shortfallFor(value);
    if (shortfall > BigInt.zero) {
      final minimum = estimate.rentExemptMinimum - estimate.recipientBalance;
      throw Exception(
        '收款方余额过低：Solana 要求账户余额不低于租金豁免线'
        '（${formatUnits(estimate.rentExemptMinimum, chain.decimals)} ${chain.symbol}），'
        '本次至少需转 ${formatUnits(minimum, chain.decimals)} ${chain.symbol}',
      );
    }

    // 发送方转出后的余额：0 是合法的（账户被清空并回收，这是用户的明确意图），
    // 卡在 0 与豁免线之间才是要拦的——那会让账户被动消失。
    final remaining = balance - value - fee;
    if (remaining > BigInt.zero && remaining < estimate.rentExemptMinimum) {
      throw Exception(
        '转出后余额将低于租金豁免线'
        '（${formatUnits(estimate.rentExemptMinimum, chain.decimals)} ${chain.symbol}），'
        '账户可能被链上回收。请减少转出金额，或选择全额转出',
      );
    }
  }

  /// 组装一笔原生 SOL 转账交易（未签名）。估费与发送共用，保证两者算的是同一笔。
  ///
  /// 三条指令的顺序无所谓，但**两条 ComputeBudget 指令都得在**，且要和估费时一致：
  /// 少了 SetComputeUnitLimit，优先费会按默认 200000 CU 计；少了 SetComputeUnitPrice，
  /// 这笔交易就是不付优先费的，拥堵时挤不进区块。
  SolanaTransaction _buildTransaction({
    required SolAddress owner,
    required SolAddress recipient,
    required BigInt lamports,
    required SolAddress blockhash,
    required BigInt computeUnitPrice,
  }) {
    return SolanaTransaction(
      payerKey: owner,
      recentBlockhash: blockhash,
      instructions: [
        ComputeBudgetProgram.setComputeUnitLimit(
          layout: const ComputeBudgetSetComputeUnitLimitLayout(units: _computeUnitLimit),
        ),
        ComputeBudgetProgram.setComputeUnitPrice(
          layout: ComputeBudgetSetComputeUnitPriceLayout(microLamports: computeUnitPrice),
        ),
        SystemProgram.transfer(
          layout: SystemTransferLayout(lamports: lamports),
          from: owner,
          to: recipient,
        ),
      ],
    );
  }

  // ───────────────────────── SPL 代币转账 ─────────────────────────

  /// 派生两个 ATA 地址并查清它们在链上的状态。
  ///
  /// ATA 地址是**本地派生**的（`owner + tokenProgram + mint` 三个种子做 PDA），不发请求；
  /// 发请求的只有后面那两次 `getAccountInfo`，且并发发出。
  ///
  /// 发送方那次用 `getAccountInfo` 而不是 `getTokenAccountBalance`：账户不存在时后者是
  /// RPC 报错，要靠 catch 才能和网络故障区分开——而账户数据里本来就带着余额，
  /// 一次 `getAccountInfo` 就同时回答了「在不在」和「有多少」，还少一次往返。
  Future<_TokenAccounts> _resolveTokenAccounts({
    required SolanaProvider provider,
    required Token token,
    required SolAddress owner,
    required SolAddress recipient,
  }) async {
    final mint = SolAddress(token.identifier.trim());
    final source = _associatedTokenAccountOf(mint: mint, owner: owner);
    final destination = _associatedTokenAccountOf(mint: mint, owner: recipient);

    final (sourceInfo, destinationInfo) = await (
      provider.request(SolanaRequestGetAccountInfo(account: source)),
      provider.request(SolanaRequestGetAccountInfo(account: destination)),
    ).wait;

    return (
      mint: mint,
      source: source,
      destination: destination,
      sourceExists: sourceInfo != null,
      sourceBalance: sourceInfo == null
          ? BigInt.zero
          : SolanaTokenAccount.fromBuffer(data: sourceInfo.toBytesData(), address: source).amount,
      createsDestination: destinationInfo == null,
    );
  }

  /// 派生 `(owner, mint)` 的关联代币账户地址。
  ///
  /// `allowOwnerOffCurve` 保持默认的 false：曲线外的地址通常是某个程序的 PDA
  /// （常见的误操作是把一个代币账户地址当成钱包地址粘进来），给它派生 ATA 再转过去，
  /// 钱大概率再也取不出来。宁可在这里报错也不放行。
  SolAddress _associatedTokenAccountOf({required SolAddress mint, required SolAddress owner}) {
    try {
      return AssociatedTokenAccountProgramUtils.associatedTokenAccount(mint: mint, owner: owner).address;
    } on SolanaPluginException {
      throw Exception('该地址不能作为代币收款地址，请确认填的是钱包地址而不是代币账户地址');
    }
  }

  /// 估算一笔 SPL 代币转账的三档费用，并带回「要不要为收款方建 ATA」及那笔租金。
  ///
  /// 与 [estimateNativeFee] 同构：自取 blockhash，供确认页的估费 provider 直接调用。
  Future<SolanaFeeEstimate> estimateTokenFee({
    required Chain chain,
    required Token token,
    required String from,
    required String to,
    required String amount,
  }) async {
    final provider = _providerFor(chain);
    final owner = SolAddress(from.trim());
    final recipient = SolAddress(to.trim());

    final (blockhash, accounts) = await (
      provider.request(const SolanaRequestGetLatestBlockhash()),
      _resolveTokenAccounts(provider: provider, token: token, owner: owner, recipient: recipient),
    ).wait;

    return _estimateTokenWith(
      provider: provider,
      token: token,
      accounts: accounts,
      owner: owner,
      recipient: recipient,
      value: parseUnits(amount, token.decimals),
      blockhash: blockhash.blockhash,
    );
  }

  /// 代币估费本体。[accounts] 由调用方给，[sendToken] 才能与自己的校验共用同一次查询。
  ///
  /// 与原生路径 [_estimateWith] 的三处实质差异，都不是可省的细节：
  /// - 计算单元上限随「要不要建 ATA」变，而它直接决定优先费；
  /// - 要建 ATA 时多问一次 165 字节的租金豁免线，那笔钱由发送方垫付；
  /// - 优先费要按**本次真正会写入的账户**问行情（Solana 的费率市场是按账户分别竞价的），
  ///   代币转账写的是两个 ATA，不是钱包地址本身——拿钱包地址去问，问的是另一本账。
  Future<SolanaFeeEstimate> _estimateTokenWith({
    required SolanaProvider provider,
    required Token token,
    required _TokenAccounts accounts,
    required SolAddress owner,
    required SolAddress recipient,
    required BigInt value,
    required SolAddress blockhash,
  }) async {
    final computeUnitLimit = accounts.createsDestination ? _tokenWithAtaComputeUnitLimit : _tokenComputeUnitLimit;
    final message = _buildTokenTransaction(
      token: token,
      accounts: accounts,
      owner: owner,
      recipient: recipient,
      value: value,
      blockhash: blockhash,
      computeUnitPrice: BigInt.zero,
      computeUnitLimit: computeUnitLimit,
    ).serializeMessageString(encoding: TransactionSerializeEncoding.base64);

    // 不建 ATA 时租金恒为 0，就不必为它发一轮请求——但仍要摆成一个 Future，
    // 好和另外两个一起进 `.wait`（记录字面量不支持 if 元素）。
    final ataRentRequest = accounts.createsDestination
        ? provider.request(SolanaRequestGetMinimumBalanceForRentExemption(size: _tokenAccountDataSize))
        : Future.value(BigInt.zero);

    final (fee, recentFees, ataRent) = await (
      provider.request(SolanaRequestGetFeeForMessage(encodedMessage: message)),
      provider.request(
        SolanaRequestGetRecentPrioritizationFees(addresses: [owner, accounts.source, accounts.destination]),
      ),
      ataRentRequest,
    ).wait;

    return SolanaFeeEstimate(
      baseFeeLamports: fee ?? _lamportsPerSignature,
      computeUnitLimit: computeUnitLimit,
      priceByPercentile: pricePercentiles(
        recentFees.map((sample) => sample.prioritizationFee).toList(),
        FeeSpeed.values.map((speed) => speed.rewardPercentile),
      ),
      // 收款方 SOL 账户的租金账与代币转账无关（转的是代币，对方 SOL 余额不变），
      // 传 0 让 shortfallFor / createsRecipient 天然失效——约定见 SolanaFeeEstimate 类注释。
      rentExemptMinimum: BigInt.zero,
      recipientBalance: BigInt.zero,
      ataRentLamports: ataRent,
    );
  }

  /// 发送 SPL 代币，返回 (交易签名, 实际发送金额, 上链状态, 交易失效高度)。
  ///
  /// **没有 `deductFeeFromAmount`**：网络费与 ATA 租金都以 SOL 支付，而转出的是代币，
  /// 两本账不通，费用根本无从「从转出额里扣」。代币的 MAX 就是代币余额本身，
  /// SOL 够不够付费用是另一条独立的校验（第 5 步）。这与 EVM / Tron 的代币路径一致。
  Future<TransferResult> sendToken({
    required Chain chain,
    required Token token,
    required List<int> privateKey,
    required String fromAddress,
    required String to,
    required String amount,
    FeeSpeed speed = FeeSpeed.defaultSpeed,
  }) async {
    if (token.standard != TokenStandard.spl) {
      throw UnsupportedError('${token.symbol} 不是 SPL 代币，无法在 ${chain.name} 上转账');
    }

    final provider = _providerFor(chain);

    // 1. 私钥 → 地址，与钱包地址核对（同 sendNative：base58 大小写敏感，不可 lowerCase）。
    final signer = SolanaPrivateKey.fromSeed(privateKey);
    final owner = signer.publicKey().toAddress();
    if (owner.address != fromAddress.trim()) {
      throw Exception('签名地址与钱包地址不一致');
    }

    // 2. 金额按 **token.decimals** 换算，不是 chain.decimals。
    //    SOL 是 9 位而多数 SPL 代币是 6 位，用错这一个数会差出一千倍。
    final value = parseUnits(amount, token.decimals);
    if (value <= BigInt.zero) throw Exception('转账金额必须大于 0');

    final recipient = SolAddress(to.trim());

    // 3. blockhash / 两个 ATA 的状态 / 发送方 SOL 余额，三件事互不依赖，并发取。
    //    blockhash 取一次，估费与第 7 步的签名共用（同 sendNative）。
    final (latest, accounts, solBalance) = await (
      provider.request(const SolanaRequestGetLatestBlockhash()),
      _resolveTokenAccounts(provider: provider, token: token, owner: owner, recipient: recipient),
      provider.request(SolanaRequestGetBalance(account: owner)),
    ).wait;

    // 4. 代币账户与代币余额校验。
    if (!accounts.sourceExists) {
      throw Exception('你还没有 ${token.symbol} 代币账户，无法转出');
    }
    if (value > accounts.sourceBalance) {
      throw Exception(
        '${token.symbol} 余额不足：本次需 ${formatUnits(value, token.decimals)}，'
        '可用 ${formatUnits(accounts.sourceBalance, token.decimals)}',
      );
    }

    final estimate = await _estimateTokenWith(
      provider: provider,
      token: token,
      accounts: accounts,
      owner: owner,
      recipient: recipient,
      value: value,
      blockhash: latest.blockhash,
    );

    // 5. SOL 余额校验：网络费与 ATA 租金都从 SOL 里出，与代币余额是两本账，必须单独校验。
    //    比的是「费用 + 租金」的合计——只比费用，会在要建 ATA 时把需求少算几百倍。
    //
    //    **刻意不做原生路径的 `_verifyRentExempt`**：那条管的是「转出后自己的 SOL 余额
    //    卡在 0 与豁免线之间」，而这里转出的是代币，SOL 只减少费用那一点点，
    //    落进那个区间的前提是余额本来就已经在豁免线附近——那属于用户的 SOL 账户状态，
    //    不是这笔代币转账造成的，拦在这里只会让人摸不着头脑。
    final cost = estimate.lamportsCostFor(speed);
    if (cost > solBalance) {
      final rentNote = estimate.createsTokenAccount
          ? '（含为收款方创建代币账户的租金 ${formatUnits(estimate.ataRentLamports, chain.decimals)}）'
          : '';
      throw Exception(
        '${chain.symbol} 不足以支付网络费：需约 ${formatUnits(cost, chain.decimals)} ${chain.symbol}$rentNote，'
        '可用 ${formatUnits(solBalance, chain.decimals)}',
      );
    }

    // 6. 本地构造 + 签名 + 广播。交易完全在本地构造，节点只提供 blockhash，
    //    改不了转给谁、转多少——与 sendNative 同理，这里没有 Tron 那种回解校验的缺口。
    final transaction = _buildTokenTransaction(
      token: token,
      accounts: accounts,
      owner: owner,
      recipient: recipient,
      value: value,
      blockhash: latest.blockhash,
      computeUnitPrice: estimate.priceFor(speed),
      computeUnitLimit: estimate.computeUnitLimit,
    );
    transaction.sign([signer]);

    final signature = await provider.request(
      SolanaRequestSendTransaction(
        encodedTransaction: transaction.serializeString(
          encoding: TransactionSerializeEncoding.base64,
          verifySignatures: true,
        ),
        encoding: SolanaRequestEncoding.base64,
        commitment: Commitment.confirmed,
      ),
    );

    return (
      hash: signature,
      // 按 token.decimals 格式化：与第 2 步同一口径，用 chain.decimals 会显示成千分之一。
      sentAmount: formatUnits(value, token.decimals),
      status: TransactionStatus.pending,
      validUntilBlock: latest.lastValidBlockHeight,
    );
  }

  /// 组装一笔 SPL 代币转账交易（未签名）。估费与发送共用，保证两者算的是同一笔。
  ///
  /// 指令顺序要求：两条 ComputeBudget 在最前（理由同 [_buildTransaction]），
  /// 创建 ATA 必须排在转账**之前**——否则转账会写进一个还不存在的账户，整笔失败。
  SolanaTransaction _buildTokenTransaction({
    required Token token,
    required _TokenAccounts accounts,
    required SolAddress owner,
    required SolAddress recipient,
    required BigInt value,
    required SolAddress blockhash,
    required BigInt computeUnitPrice,
    required int computeUnitLimit,
  }) {
    return SolanaTransaction(
      payerKey: owner,
      recentBlockhash: blockhash,
      instructions: [
        ComputeBudgetProgram.setComputeUnitLimit(
          layout: ComputeBudgetSetComputeUnitLimitLayout(units: computeUnitLimit),
        ),
        ComputeBudgetProgram.setComputeUnitPrice(
          layout: ComputeBudgetSetComputeUnitPriceLayout(microLamports: computeUnitPrice),
        ),
        // Idempotent 变体：估费与广播之间若有人抢先把这个 ATA 建好了（收款方自己收了
        // 另一笔、或用户连点两次），普通的 create 会因「账户已存在」让整笔交易失败，
        // 而 idempotent 版本此时直接跳过。多付的代价只有那点 CU。
        if (accounts.createsDestination)
          AssociatedTokenAccountProgram.associatedTokenAccountIdempotent(
            payer: owner,
            associatedToken: accounts.destination,
            owner: recipient,
            mint: accounts.mint,
          ),
        // transferChecked 而非 transfer：它把 decimals 一并写进指令，由链上比对 mint 的
        // 真实精度。万一代币目录里的 decimals 与链上不符，这笔交易会**失败**，
        // 而不是照着错的精度把金额转错几个数量级——那是不可逆的。
        SPLTokenProgram.transferChecked(
          layout: SPLTokenTransferCheckedLayout(amount: value, decimals: token.decimals),
          source: accounts.source,
          mint: accounts.mint,
          destination: accounts.destination,
          owner: owner,
        ),
      ],
    );
  }

  /// 查询 `getSignatureStatuses`，直到拿到终态或超时（返回 pending）。
  ///
  /// 广播返回签名只代表节点收下了，不代表已上链。刚广播时查不到（返回 null）属正常。
  /// 默认超时只够发一轮，即「查一次当前状态」；传长超时才会变成真正的轮询。
  ///
  /// [validUntilBlock] 是这笔交易的失效高度（来自广播时的 `lastValidBlockHeight`）。
  /// 给了它才判得出 [TransactionStatus.expired]：签名查不到 **且** 当前高度已经越过
  /// 失效高度，这笔交易就永远不可能上链了。不给（或别的链没有这个概念）则一律按
  /// pending 处理——那正是本次要修掉的「永远显示确认中」。
  Future<TransactionStatus> waitForReceipt(
    Chain chain,
    String signature, {
    int? validUntilBlock,
    SolanaProvider? provider,
    Duration timeout = _receiptTimeout,
    Duration interval = _receiptPollInterval,
  }) async {
    final rpc = provider ?? _providerFor(chain);
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final statuses = await rpc.request(
        // 刚广播的交易在最近状态缓存里，但历史页回填的可能是几分钟前那笔，
        // 已经滚出缓存了——不开 searchTransactionHistory 会永远查不到，卡在 pending。
        SolanaRequestGetSignatureStatuses(signatures: [signature], searchTransactionHistory: true),
      );
      final status = statuses.isEmpty ? null : statuses.first;
      if (status != null) {
        final resolved = _statusOf(status);
        if (resolved.isFinal) return resolved;
      } else if (validUntilBlock != null) {
        // 只在「查不到」时才问高度：查得到就说明已上链，高度再大也与它无关。
        final height = await rpc.request(const SolanaRequestGetBlockHeight());
        if (height > validUntilBlock) return TransactionStatus.expired;
      }
      await Future<void>.delayed(interval);
    }
    return TransactionStatus.pending;
  }

  /// 从签名状态判断这笔交易到底成没成。
  ///
  /// `err != null` 优先：一笔已 finalized 但执行失败的交易，两个字段是同时有值的，
  /// 只看 confirmationStatus 会把它报成「已确认」。
  /// `processed` 不算确认——它只表示某个节点见过，仍可能因分叉被回滚。
  static TransactionStatus _statusOf(SignatureStatus status) {
    if (status.err != null) return TransactionStatus.failed;
    return switch (status.confirmationStatus) {
      TransactionConfirmationStatus.confirmed || TransactionConfirmationStatus.finalized => TransactionStatus.confirmed,
      _ => TransactionStatus.pending,
    };
  }
}
