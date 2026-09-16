/// 十进制金额字符串 -> 最小单位 BigInt（不经过 double，避免精度丢失）。
/// 小数位超过 [decimals] 时抛 [FormatException]。
BigInt parseUnits(String amount, int decimals) {
  final s = amount.trim();
  if (s.isEmpty || !RegExp(r'^\d+(\.\d+)?$').hasMatch(s)) {
    throw FormatException('金额格式非法: $amount');
  }
  final parts = s.split('.');
  final whole = parts[0];
  final fraction = parts.length > 1 ? parts[1] : '';
  if (fraction.length > decimals) {
    throw FormatException('小数位超过精度上限 $decimals: $amount');
  }
  final padded = fraction.padRight(decimals, '0');
  return BigInt.parse(whole + (decimals == 0 ? '' : padded));
}

/// 最小单位 BigInt -> 十进制金额字符串（[parseUnits] 的逆运算，去尾零）。
String formatUnits(BigInt value, int decimals) {
  if (decimals == 0) return value.toString();
  final divisor = BigInt.from(10).pow(decimals);
  final whole = value ~/ divisor;
  final fraction = value.remainder(divisor).toString().padLeft(decimals, '0');
  final trimmed = fraction.replaceFirst(RegExp(r'0+$'), '');
  return trimmed.isEmpty ? whole.toString() : '$whole.$trimmed';
}
