/// 把数值格式化为带千分位的金额文案。纯函数,与 UI/状态无关。
///
/// - [showSymbol]：是否前置货币符号 [symbol]。
/// - [decimals]：保留小数位数（0 表示不带小数）。
///
/// 例：formatAmount(4321.5) -> "$4,321.50"；
///     formatAmount(4321.5, showSymbol: false, decimals: 0) -> "4,322"。
String formatAmount(
  double value, {
  bool showSymbol = true,
  String symbol = '\$',
  int decimals = 2,
}) {
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
