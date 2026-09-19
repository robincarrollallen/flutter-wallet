import '../enums/fee_speed.dart';
import 'fee_quote.dart';

/// 一个档位下 Sui 转账的费用报价。
///
/// Sui 的费用由三部分构成：`computationCost + storageCost - storageRebate`。
/// 前两项是支出，第三项是**退款**——这笔转账会拆出一个新的 coin object（占存储、
/// 收存储费），同时销毁作为输入的旧 object（退回它当初付的存储押金）。
/// 净额因此可能很小，极端情况下甚至是负的（退得比花得多）。
///
/// 与 Aptos 同形的一点：[expectedFee] 与 [maxFee] **不相等**。链上按 `gasBudget`
/// 整额冻结，执行完只结算实际用量、余下退回。所以余额校验与 MAX 扣减一律用 [maxFee]。
class SuiFeeQuote implements FeeQuote {
  const SuiFeeQuote({required this.speed, required this.gasPrice, required this.netGasFee, required this.gasBudget});

  final FeeSpeed speed;

  /// 本档的 gas 单价（MIST / gas unit）。
  final BigInt gasPrice;

  /// dry run 实测的净费用：`computationCost + storageCost - storageRebate`，
  /// 已在构造方夹到非负（见 `SuiTransactionService`）。结算按它收。
  final BigInt netGasFee;

  /// 交易里声明的预算。发送期间账户要冻住整个预算，执行完退回未用部分。
  final BigInt gasBudget;

  @override
  BigInt get expectedFee => netGasFee;

  /// 余额校验与 MAX 扣减都按它来：链上是按预算整额冻结的，拿净费用去算会让
  /// 「刚好够」的边界判反——冻不住就直接进不了内存池。
  @override
  BigInt get maxFee => gasBudget;
}

/// 一次 Sui 原生转账的费用基准。
///
/// 与 [AptosFeeEstimate] / [EvmGasBasis] / [SolanaFeeEstimate] 同一角色：
/// 存三档共享的原始数据，档位差异由 [quoteFor] 现算。
///
/// **三档里只有「快速」是本地编的**，这一点与 Aptos / Solana 不同，不要照抄它们的
/// 注释去理解：Aptos 的三档来自 `/estimate_gas_price` 返回的三个真实单价，
/// Solana 的三档来自近期区块优先费的分位数，都是链上给的；Sui 没有对应接口——
/// 它的 reference gas price 在一个 epoch 内**恒定**，且是链上接受的**下限**
/// （低于它交易直接被拒）。所以：
///
/// - 「缓慢」与「普通」都等于 [referenceGasPrice]。两档同价是**事实**：
///   Sui 上没有「出价更低、等得更久」这个选项，慢档无处可慢。
/// - 「快速」按 [_fastMultiplierPercent] 加价。加价在 Sui 上确实有用（验证者按
///   gas price 对交易做共识排序），但**倍数是本地定的**，链上没给这个数。
class SuiFeeEstimate {
  /// 不是 const 构造：字段清一色 BigInt，`BigInt` 字面量不是编译期常量。
  SuiFeeEstimate({required this.referenceGasPrice, required this.netGasFee, required this.gasBudget});

  /// `suix_getReferenceGasPrice`，当前 epoch 的参考单价，也是链上接受的下限。
  final BigInt referenceGasPrice;

  /// dry run 实测的净费用（按 [referenceGasPrice] 跑出来的）。
  final BigInt netGasFee;

  /// 本次交易将声明的预算，见 `SuiTransactionService` 的 `_gasBudgetFor`。
  final BigInt gasBudget;

  /// 「快速」档在参考价之上的加价百分比。
  ///
  /// 取 120（即 1.2 倍）：Sui 的排序按 gas price 做，高一点就够进前面，
  /// 而多出的部分**只在真的用掉时才付**（结算按实际用量 × 单价），
  /// 所以加价的代价远小于 EVM 那种全额付出的小费。
  static final BigInt _fastMultiplierPercent = BigInt.from(120);
  static final BigInt _hundred = BigInt.from(100);

  /// 某档的 gas 单价。
  BigInt priceFor(FeeSpeed speed) => switch (speed) {
    // 低于参考价一律被拒，所以慢档没有更便宜的余地，与普通档同价。
    FeeSpeed.slow || FeeSpeed.normal => referenceGasPrice,
    FeeSpeed.fast => referenceGasPrice * _fastMultiplierPercent ~/ _hundred,
  };

  /// 某档的完整报价。
  ///
  /// 费用与预算都按单价等比放大：dry run 只在参考价下跑过一次，换个单价再跑一遍
  /// 不会得到新信息（gas **用量**与单价无关，Sui 的存储费也不乘单价——
  /// 但这里仍整体等比放大，理由见下），却要多发一轮请求。
  ///
  /// 等比放大是**偏保守**的近似：存储费那部分其实不随单价变，所以快速档的真实费用
  /// 比这里算出来的低一点。偏高的代价只是确认页数字保守、MAX 少发一点点；
  /// 偏低的代价是 MAX 全额转出预留不够被链上拒收。两头不对等，选偏高的那边。
  SuiFeeQuote quoteFor(FeeSpeed speed) {
    final price = priceFor(speed);
    if (price == referenceGasPrice) {
      return SuiFeeQuote(speed: speed, gasPrice: price, netGasFee: netGasFee, gasBudget: gasBudget);
    }
    return SuiFeeQuote(speed: speed, gasPrice: price, netGasFee: netGasFee * price ~/ referenceGasPrice, gasBudget: gasBudget * price ~/ referenceGasPrice);
  }

  /// 三档报价，直接喂给 `NetworkFeeSelector`。
  Map<FeeSpeed, SuiFeeQuote> get quotes => {for (final speed in FeeSpeed.values) speed: quoteFor(speed)};
}
