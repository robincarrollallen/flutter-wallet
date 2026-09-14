import 'package:on_chain/solana/solana.dart';

import '../blockchain/chain_registry.dart';
import '../blockchain/units.dart';
import '../data/datasource/remote/solana_service.dart';
import '../domain/solana_fee.dart';
import '../enums/fee_speed.dart';
import 'transfer/transfer_result.dart';

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
  /// 不存任何数据。SPL 代币账户要按 165 字节算，那是另一条路径的事。
  static const int _plainAccountDataSize = 0;

  /// 本次交易声明的计算单元上限。
  ///
  /// **必须显式声明**：不声明的话每条指令按默认 200000 CU 计，而优先费 = 优先单价 ×
  /// 声明的上限（不是实际用量），拿默认值去算会高估几百倍，用户要多付几百倍的优先费。
  ///
  /// 实际用量：SystemProgram 转账 150 CU + 两条 ComputeBudget 指令各 150 CU = 450。
  /// 取 600 留一点余量——声明少了交易会因超限直接失败，而多声明这 150 CU 的代价
  /// 在任何现实价位下都不到 1 lamport，两头的代价完全不对等。
  static const int _computeUnitLimit = 600;

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
