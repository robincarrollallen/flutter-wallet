/// 把 [formatUnits] 产出的精确金额字符串收敛成适合展示的长度。纯函数，与 UI/状态无关。
///
/// 与 [formatAmount] 的分工：那个格式化法币（double，固定两位小数），
/// 这个格式化币本位持仓（十进制字符串，位数随数量级变化）。
///
/// 三条约定，都是踩过坑才定下的：
///
/// 1. **只截断，不四舍五入。** 余额一旦被舍入成比实际更大的数
///    （0.049939… → 0.04994），用户照着展示值手输或点「最大」就会撞上
///    「余额不足」。宁可显示得比实际少一点，也不能多。
/// 2. **全程字符串运算，不经过 double。** 入参本身就是为了绕开 double 精度
///    才做成字符串的（见 [formatUnits]），这里再 parse 一次等于前功尽弃。
/// 3. **只用于展示。** 参与计算、比较、往返 [parseUnits] 的一律用原始精确值。
///
/// 小数位按数量级分档：整数部分越大，小数越不重要；反之亦然。
///
/// 例：formatTokenAmount('0.049939577316748207') -> "0.049939"；
///     formatTokenAmount('1234.56789')           -> "1,234.56"；
///     formatTokenAmount('0.00000000004')        -> "<0.00000001"。
String formatTokenAmount(String exact, {int? maxDecimals}) {
  final trimmed = exact.trim();
  // 非十进制字面量（异常值、已带符号的文案）原样返回，不做二次加工。
  if (!RegExp(r'^\d+(\.\d+)?$').hasMatch(trimmed)) return exact;

  final parts = trimmed.split('.');
  final whole = parts[0];
  final fraction = parts.length > 1 ? parts[1] : '';
  final decimals = maxDecimals ?? _decimalsFor(whole, fraction);

  // 截断（非四舍五入）后再去尾零：0.0500 -> 0.05，1.0000 -> 1。
  final truncated = fraction.length > decimals ? fraction.substring(0, decimals) : fraction;
  final significant = truncated.replaceFirst(RegExp(r'0+$'), '');

  final groupedWhole = _group(whole);
  if (significant.isNotEmpty) return '$groupedWhole.$significant';

  // 截断后小数全没了：要么本来就是整数，要么小到这个档位表示不出来。
  // 后者显示 0 会让用户以为余额为空，改用「小于最小可显示单位」。
  final isZero = BigInt.parse(whole) == BigInt.zero && !RegExp(r'[1-9]').hasMatch(fraction);
  if (!isZero && groupedWhole == '0') return '<0.${'0' * (decimals - 1)}1';
  return groupedWhole;
}

/// 按数量级选小数位：整数部分大到一定程度，小数就没有阅读价值了。
int _decimalsFor(String whole, String fraction) {
  final significantWhole = whole.replaceFirst(RegExp(r'^0+(?=.)'), '');
  if (significantWhole != '0') {
    if (significantWhole.length >= 4) return 2; // >= 1000
    return 4; // 1 ~ 999
  }
  if (fraction.startsWith('000')) return 8; // < 0.001，多给几位才看得出量级
  return 6; // 0.001 ~ 1
}

/// 整数部分加千分位，与 [formatAmount] 保持一致的观感。
String _group(String intPart) {
  final buffer = StringBuffer();
  for (var i = 0; i < intPart.length; i++) {
    if (i > 0 && (intPart.length - i) % 3 == 0) buffer.write(',');
    buffer.write(intPart[i]);
  }
  return buffer.toString();
}
