import '../enums/fee_speed.dart';
import 'fee_quote.dart';

/// 一个档位下 Aptos 转账的费用报价。
///
/// Aptos 是「gas 单价 × gas 用量」，与 EVM 同形，但有两点不同：
/// - 用量分两个数：[gasUsed] 是模拟执行的实际消耗，[maxGasAmount] 是交易里写死的上限；
/// - **链上按上限预扣、按实际结算**。所以 [expectedFee] 按实际算、[maxFee] 按上限算，
///   两者不相等——这和 Solana「签名即确定、两者相等」正好相反。
class AptosFeeQuote implements FeeQuote {
  const AptosFeeQuote({required this.speed, required this.gasUnitPrice, required this.gasUsed, required this.maxGasAmount});

  final FeeSpeed speed;

  /// 本档的 gas 单价（octa / gas unit），取自 `/estimate_gas_price`。
  final BigInt gasUnitPrice;

  /// 模拟执行实测的 gas 消耗。结算按它收。
  final BigInt gasUsed;

  /// 交易里声明的 gas 上限。发送期间账户要冻住 `上限 × 单价`，执行完退回未用部分。
  final BigInt maxGasAmount;

  @override
  BigInt get expectedFee => gasUnitPrice * gasUsed;

  /// 余额校验与 MAX 扣减都按它来：链上是按上限预扣的，拿实际消耗去算会让
  /// 「刚好够」的边界判反——预扣不过就直接进不了内存池。
  @override
  BigInt get maxFee => gasUnitPrice * maxGasAmount;
}

/// 一次 Aptos 原生转账的费用基准。
///
/// 与 [EvmGasBasis] / [SolanaFeeEstimate] 同一角色：存三档共享的原始数据，
/// 档位差异由 [quoteFor] 现算。
///
/// **三档是链上真实给的，不是本地编的倍数**：`/estimate_gas_price` 直接返回
/// de-prioritized / regular / prioritized 三个单价（AIP-34），正好对上
/// [FeeSpeed] 的三档。链空闲时三个值相同、三档显示同一个数，那是**事实**。
class AptosFeeEstimate {
  /// 不是 const 构造：字段清一色 BigInt，`BigInt` 字面量不是编译期常量。
  AptosFeeEstimate({required this.deprioritizedGasUnitPrice, required this.gasUnitPrice, required this.prioritizedGasUnitPrice, required this.gasUsed, required this.maxGasAmount});

  /// 「缓慢」档单价。节点可能不返回这一项，缺失时由构造方回落到 [gasUnitPrice]。
  final BigInt deprioritizedGasUnitPrice;

  /// 「普通」档单价，即节点推荐值。
  final BigInt gasUnitPrice;

  /// 「快速」档单价。
  final BigInt prioritizedGasUnitPrice;

  /// 模拟执行实测的 gas 消耗（与单价无关，三档共享）。
  final BigInt gasUsed;

  /// 本次交易将声明的 gas 上限 = [gasUsed] 上留余量，见 `AptosTransactionService`。
  final BigInt maxGasAmount;

  /// 某档的 gas 单价。
  BigInt priceFor(FeeSpeed speed) => switch (speed) {
    FeeSpeed.slow => deprioritizedGasUnitPrice,
    FeeSpeed.normal => gasUnitPrice,
    FeeSpeed.fast => prioritizedGasUnitPrice,
  };

  /// 某档的完整报价。
  AptosFeeQuote quoteFor(FeeSpeed speed) => AptosFeeQuote(speed: speed, gasUnitPrice: priceFor(speed), gasUsed: gasUsed, maxGasAmount: maxGasAmount);

  /// 三档报价，直接喂给 `NetworkFeeSelector`。
  Map<FeeSpeed, AptosFeeQuote> get quotes => {for (final speed in FeeSpeed.values) speed: quoteFor(speed)};
}
