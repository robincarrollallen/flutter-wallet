import '../enums/fee_speed.dart';

/// 某个档位下的 EVM 费率（每 gas 单价），EIP-1559 与 legacy 二选一。
class EvmFeeRate {
  const EvmFeeRate.eip1559({
    required BigInt this.baseFee,
    required BigInt this.maxFeePerGas,
    required BigInt this.maxPriorityFeePerGas,
  }) : eip1559 = true,
       gasPrice = null;

  const EvmFeeRate.legacy(BigInt this.gasPrice)
    : eip1559 = false,
      baseFee = null,
      maxFeePerGas = null,
      maxPriorityFeePerGas = null;

  final bool eip1559;

  /// 最新区块的 baseFee，三档共享；legacy 链为 null。
  final BigInt? baseFee;
  final BigInt? maxFeePerGas;
  final BigInt? maxPriorityFeePerGas;
  final BigInt? gasPrice;

  /// 预计实际扣费单价：baseFee + 小费。链上多退少补，按此估算最接近真实账单。
  BigInt get effectiveGasPrice => eip1559 ? baseFee! + maxPriorityFeePerGas! : gasPrice!;

  /// 出价上限单价：baseFee 涨到余量顶格时的单价，余额校验按它来。
  BigInt get capGasPrice => eip1559 ? maxFeePerGas! : gasPrice!;
}

/// 一个档位的完整报价：费率 × gasLimit。
class EvmFeeQuote {
  const EvmFeeQuote({required this.speed, required this.rate, required this.gasLimit});

  final FeeSpeed speed;
  final EvmFeeRate rate;
  final BigInt gasLimit;

  /// 预计实付（展示用）。
  BigInt get expectedFee => rate.effectiveGasPrice * gasLimit;

  /// 费用上限（余额校验 / MAX 扣减用）。
  BigInt get maxFee => rate.capGasPrice * gasLimit;
}

/// 全网费率基准：三个档位共享的原始数据，档位差异由 [rateFor] 派生。
///
/// 会落盘（见 `EvmGasBasisNotifier`），所以带上 [fetchedAt]——
/// baseFee 每 12 秒一变，读出来必须能判断新旧，不能当新鲜数据直接用。
class EvmGasBasis {
  const EvmGasBasis.eip1559({
    required BigInt this.baseFee,
    required Map<int, BigInt> this.tipByPercentile,
    required this.fetchedAt,
  }) : gasPrice = null;

  const EvmGasBasis.legacy(BigInt this.gasPrice, {required this.fetchedAt}) : baseFee = null, tipByPercentile = null;

  /// 最新区块 baseFee；null 表示该链没有 EIP-1559，走 legacy。
  final BigInt? baseFee;

  /// 分位 -> 小费。
  final Map<int, BigInt>? tipByPercentile;
  final BigInt? gasPrice;
  final DateTime fetchedAt;

  EvmFeeRate rateFor(FeeSpeed speed) {
    final base = baseFee;
    if (base == null) return EvmFeeRate.legacy(scaleFee(gasPrice!, speed.legacyMultiplier));
    final tip = tipByPercentile![speed.rewardPercentile] ?? BigInt.zero;
    return EvmFeeRate.eip1559(
      baseFee: base,
      // 上限 = baseFee × 档位余量 + 小费：档位越高越抗打包前 baseFee 上涨。
      maxFeePerGas: scaleFee(base, speed.baseFeeHeadroom) + tip,
      maxPriorityFeePerGas: tip,
    );
  }

  Map<String, dynamic> toJson() => {
    if (baseFee != null) 'baseFee': baseFee!.toString(),
    if (gasPrice != null) 'gasPrice': gasPrice!.toString(),
    if (tipByPercentile != null)
      'tips': {for (final entry in tipByPercentile!.entries) '${entry.key}': entry.value.toString()},
    'at': fetchedAt.millisecondsSinceEpoch,
  };

  /// 脏数据 / 缺字段一律返回 null，由调用方当作没缓存过。
  static EvmGasBasis? fromJson(Object? json) {
    if (json is! Map) return null;
    final at = json['at'];
    if (at is! int) return null;
    final fetchedAt = DateTime.fromMillisecondsSinceEpoch(at);
    final baseFee = BigInt.tryParse('${json['baseFee']}');
    final tips = json['tips'];
    if (baseFee != null && tips is Map) {
      final parsed = <int, BigInt>{};
      for (final entry in tips.entries) {
        final percentile = int.tryParse('${entry.key}');
        final tip = BigInt.tryParse('${entry.value}');
        if (percentile != null && tip != null) parsed[percentile] = tip;
      }
      if (parsed.isEmpty) return null;
      return EvmGasBasis.eip1559(baseFee: baseFee, tipByPercentile: parsed, fetchedAt: fetchedAt);
    }
    final gasPrice = BigInt.tryParse('${json['gasPrice']}');
    return gasPrice == null ? null : EvmGasBasis.legacy(gasPrice, fetchedAt: fetchedAt);
  }
}

/// 按倍率缩放费用。整数运算，避免 BigInt→double 的精度丢失。
BigInt scaleFee(BigInt value, double multiplier) => value * BigInt.from((multiplier * 100).round()) ~/ BigInt.from(100);
