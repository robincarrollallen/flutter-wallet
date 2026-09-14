/// 把数值格式化为带千分位的金额文案。纯函数,与 UI/状态无关。
///
/// - [showSymbol]：是否前置货币符号 [symbol]。
/// - [symbol]：货币符号。调用方自行传入当前法币的符号
///   （UI 层用 AmountText / currencySymbolProvider 即可自动带上）。
/// - [decimals]：保留小数位数（0 表示不带小数）。
///
/// 例：formatAmount(4321.5) -> "$4,321.50"；
///     formatAmount(4321.5, symbol: '¥') -> "¥4,321.50"；
///     formatAmount(4321.5, showSymbol: false, decimals: 0) -> "4,322"。
String formatAmount(double value, {bool showSymbol = true, String symbol = '\$', int decimals = 2}) {
  final fixed = value.abs().toStringAsFixed(decimals);
  final parts = fixed.split('.');
  final intPart = parts[0];
  final buffer = StringBuffer();
  for (var i = 0; i < intPart.length; i++) {
    if (i > 0 && (intPart.length - i) % 3 == 0) buffer.write(',');
    buffer.write(intPart[i]);
  }
  final sign = value < 0 ? '-' : '';
  final sym = showSymbol ? symbol : '';
  final dec = decimals > 0 ? '.${parts[1]}' : '';
  return '$sign$sym$buffer$dec';
}

/// 把一笔**法币小额**格式化成展示文案：大于 0 但不足最小显示单位时给 `<$0.01`，
/// 而不是四舍五入成 `$0.00`。
///
/// `$0.00` 是有歧义的——用户分不出「便宜到不足一分」和「价格没取到、兜底成 0」，
/// 而这两件事的含义完全不同。Solana 的转账手续费约 $0.0005，正好卡在这个坑上：
/// 一笔真实存在的费用被显示成 0，看起来像是估费坏了。
///
/// 真正的 0（[value] 为 0 或负）仍照实显示 `$0.00`——调用方若拿不到单价，
/// 应当整段省略法币部分，而不是传 0 进来。
///
/// 例：formatFiatFee(0.00050945) -> "<$0.01"；
///     formatFiatFee(0.004) -> "<$0.01"；
///     formatFiatFee(0.005) -> "$0.01"（这一档四舍五入后有得显示，不必加 `<`）；
///     formatFiatFee(1.5, symbol: '¥') -> "¥1.50"。
String formatFiatFee(double value, {String symbol = '\$', int decimals = 2}) {
  // 阈值取「四舍五入后仍为 0」的上界：低于它才需要 `<`，到了它就有得显示了。
  final smallest = 0.5 / _pow10(decimals);
  if (value > 0 && value < smallest) {
    return '<${formatAmount(smallest * 2, symbol: symbol, decimals: decimals)}';
  }
  return formatAmount(value, symbol: symbol, decimals: decimals);
}

/// 10 的整数次幂。只服务 [formatFiatFee] 的阈值计算，位数很小，循环足够。
double _pow10(int exponent) {
  var result = 1.0;
  for (var i = 0; i < exponent; i++) {
    result *= 10;
  }
  return result;
}
