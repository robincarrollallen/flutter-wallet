/// 网络费档位：同一笔交易可以出更高的价钱换取更靠前的打包顺序。
///
/// EIP-1559 下 baseFee 由协议按区块拥堵算出，全网同价、无论如何都要付，
/// 用户能调的只有两样：给验证者的小费 [rewardPercentile]，
/// 以及为 baseFee 上涨预留的余量 [baseFeeHeadroom]（决定 maxFeePerGas 的上限）。
/// 所以三档共享同一个 baseFee，只在小费与余量上分档。
///
/// [legacyMultiplier] 仅用于没有 baseFee 的老链：那里没有小费概念，
/// 只能对 `eth_gasPrice` 整体缩放，倍率法在这种场景下才是对的。
enum FeeSpeed {
  slow('缓慢', '小费最低，确认可能较慢', rewardPercentile: 10, baseFeeHeadroom: 1.5, legacyMultiplier: 0.9),
  normal('普通', '推荐档位，按近期区块中位小费出价', rewardPercentile: 50, baseFeeHeadroom: 2.0, legacyMultiplier: 1.0),
  fast('快速', '小费高于近九成交易，优先被打包', rewardPercentile: 90, baseFeeHeadroom: 3.0, legacyMultiplier: 1.25);

  const FeeSpeed(
    this.label,
    this.description, {
    required this.rewardPercentile,
    required this.baseFeeHeadroom,
    required this.legacyMultiplier,
  });

  final String label;
  final String description;

  /// 取 `eth_feeHistory` 最近若干区块 reward 的第几分位作为本档小费。
  final int rewardPercentile;

  /// maxFeePerGas 中 baseFee 的倍数余量：档位越高越抗 baseFee 上涨。
  final double baseFeeHeadroom;

  /// legacy 链（区块无 baseFee）下对 `eth_gasPrice` 的缩放倍率。
  final double legacyMultiplier;

  static const FeeSpeed defaultSpeed = FeeSpeed.normal;
}
