import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/modules/balance_visibility_provider.dart';
import '../../providers/modules/currency_provider.dart';
import '../format/amount_formatter.dart';

/// 全局金额展示组件：是否隐藏从缓存（[balanceHiddenProvider]）读取，
/// 调用方只关心数值与格式。
///
/// 两种用法：
/// - 默认构造：传入数值 [value]，按 [showSymbol]/[symbol]/[decimals] 格式化法币。
///   [symbol] 不传时取当前计价法币的符号（[currencySymbolProvider]），
///   切换法币后全应用的金额符号自动跟随。
/// - [AmountText.raw]：传入已成型的文案（如代币数量 "1.5 ETH"），只负责隐藏掩码。
class AmountText extends ConsumerWidget {
  /// 掩码字符。
  static const String maskChar = '*';

  const AmountText(
    this.value, {
    super.key,
    this.showSymbol = true,
    this.symbol,
    this.decimals = 2,
    this.maskLength = 3,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
  }) : raw = null;

  /// 直接展示一段已格式化好的文案，仅套用隐藏掩码（不再格式化数值）。
  const AmountText.raw(
    String text, {
    super.key,
    this.maskLength = 3,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
  }) : raw = text,
       value = 0,
       showSymbol = false,
       symbol = null,
       decimals = 0;

  /// 待格式化的数值（[raw] 为 null 时生效）。
  final double value;

  /// 已成型文案（非 null 时跳过数值格式化）。
  final String? raw;

  final bool showSymbol;

  /// 货币符号；null 表示跟随当前计价法币。
  final String? symbol;
  final int decimals;

  /// 隐藏时掩码字符个数（默认 3，可传入显示更多）。
  final int maskLength;

  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hidden = ref.watch(balanceHiddenProvider);
    final text = hidden
        ? maskChar * maskLength
        : (raw ??
              formatAmount(
                value,
                showSymbol: showSymbol,
                symbol: symbol ?? ref.watch(currencySymbolProvider),
                decimals: decimals,
              ));
    return Text(
      text,
      style: style,
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}
