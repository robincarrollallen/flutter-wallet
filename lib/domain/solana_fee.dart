import '../enums/fee_speed.dart';
import 'fee_quote.dart';

/// 一个档位下 Solana 转账的费用报价。
///
/// Solana 的费用是两块，只有后一块分档：
/// - **签名费**（base fee）：5000 lamport × 签名数，链上固定价，给多少都不会更快；
/// - **优先费**（priority fee）：`优先单价 × 计算单元数`，这才是拥堵时的竞价部分。
class SolanaFeeQuote implements FeeQuote {
  const SolanaFeeQuote({required this.speed, required this.baseFee, required this.priorityFee});

  final FeeSpeed speed;

  /// 签名费，三档共享（与 EIP-1559 的 baseFee 三档共享是同一个道理）。
  final BigInt baseFee;

  /// 本档的优先费。链不拥堵时各档都可能是 0，此时三档显示同一个数是**事实**，不是 bug。
  final BigInt priorityFee;

  @override
  BigInt get expectedFee => baseFee + priorityFee;

  /// Solana 的费用在签名那一刻就完全确定：签名数已知、优先单价与计算单元上限都由
  /// 交易自己写死，不存在 EIP-1559 那种「打包前 baseFee 还会涨」的浮动。
  /// 所以上限恒等于预计实付。
  @override
  BigInt get maxFee => expectedFee;
}

/// 一次 Solana 原生转账的费用基准与租金豁免快照。
///
/// 与 [EvmGasBasis] 同一角色：存三档共享的原始数据，档位差异由 [quoteFor] 现算。
class SolanaFeeEstimate {
  const SolanaFeeEstimate({
    required this.baseFeeLamports,
    required this.computeUnitLimit,
    required this.priceByPercentile,
    required this.rentExemptMinimum,
    required this.recipientBalance,
  });

  /// 签名费，由 `getFeeForMessage` 实查（不写死 5000：每签名费是链上可调参数）。
  final BigInt baseFeeLamports;

  /// 本次交易声明的计算单元上限。优先费 = 优先单价 × 它，所以它直接决定费用。
  final int computeUnitLimit;

  /// 分位 -> 优先单价（micro-lamport / 计算单元），取自近期区块的实际成交价。
  final Map<int, BigInt> priceByPercentile;

  /// 租金豁免线：一个 0 字节数据的账户要长期存活所需的最低余额。
  ///
  /// **各网不同**，所以必须实查 `getMinimumBalanceForRentExemption` 而不能写死：
  /// 实测 devnet 是 650240 lamport，与常被引用的 890880 并不一致。
  final BigInt rentExemptMinimum;

  /// 收款方当前余额。为 0 表示这个地址在链上还不存在。
  final BigInt recipientBalance;

  /// 某档的优先单价（micro-lamport / 计算单元）。查不到该分位按 0 计——
  /// 不拥堵时不付优先费是正确行为，不该拿别的分位来顶。
  BigInt priceFor(FeeSpeed speed) => priceByPercentile[speed.rewardPercentile] ?? BigInt.zero;

  /// 某档的完整报价。
  SolanaFeeQuote quoteFor(FeeSpeed speed) => SolanaFeeQuote(
    speed: speed,
    baseFee: baseFeeLamports,
    priorityFee: priorityFeeLamports(priceFor(speed), computeUnitLimit),
  );

  /// 三档报价，直接喂给 [NetworkFeeSelector]。
  Map<FeeSpeed, SolanaFeeQuote> get quotes => {for (final speed in FeeSpeed.values) speed: quoteFor(speed)};

  /// 收款方是否是一个尚未上链的新账户。
  bool get createsRecipient => recipientBalance == BigInt.zero;

  /// 若本次转入 [amount] 后收款方仍达不到豁免线，返回还差多少 lamport；够则返回 0。
  ///
  /// 注意是「转入后的余额」而非「转入金额」与豁免线比——收款方原本就有 0.0008 SOL 时，
  /// 再转 0.0001 就已经够了，拿金额单独去比会把这笔正常交易误判成失败。
  BigInt shortfallFor(BigInt amount) {
    final after = recipientBalance + amount;
    if (after >= rentExemptMinimum) return BigInt.zero;
    return rentExemptMinimum - after;
  }
}

/// 每 lamport 对应的 micro-lamport 数。优先单价以 micro-lamport 计价，换算时要除掉。
final BigInt _microLamportsPerLamport = BigInt.from(1000000);

/// 优先单价（micro-lamport / 计算单元）× 计算单元数 → lamport，**向上取整**。
///
/// 向上取整而非截断：链上按同样的方式收，截断会让估算比实际少，
/// MAX 全额转出时就会差那么一点点而在链上失败。
BigInt priorityFeeLamports(BigInt microLamportsPerComputeUnit, int computeUnitLimit) {
  if (microLamportsPerComputeUnit <= BigInt.zero || computeUnitLimit <= 0) return BigInt.zero;
  final total = microLamportsPerComputeUnit * BigInt.from(computeUnitLimit);
  return (total + _microLamportsPerLamport - BigInt.one) ~/ _microLamportsPerLamport;
}

/// 从近期区块的优先费样本里取各分位价。样本为空时返回空表（= 各档都不付优先费）。
///
/// 样本里含大量 0 是正常的——链不拥堵时绝大多数交易本来就不付优先费，
/// 此时低分位取到 0 正是我们想要的结果。
Map<int, BigInt> pricePercentiles(List<int> samples, Iterable<int> percentiles) {
  if (samples.isEmpty) return const {};
  final sorted = [...samples]..sort();
  return {
    for (final percentile in percentiles)
      percentile: BigInt.from(sorted[((sorted.length - 1) * percentile / 100).round().clamp(0, sorted.length - 1)]),
  };
}
