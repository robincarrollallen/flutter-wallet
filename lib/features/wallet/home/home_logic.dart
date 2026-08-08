import '../../../core/format/amount_formatter.dart';

/// 首页的纯逻辑：与状态/UI 无关，便于单测和复用。
class HomeLogic {
  const HomeLogic._();

  /// 把法币金额格式化为带千分位的展示文案，例如 4321.0 -> "$4,321.00"。
  /// [symbol] 传当前计价法币的符号（currencySymbolProvider）。
  /// 仅用于非 widget 的纯文本场景；UI 展示请优先用全局 AmountText（符号自动跟随）。
  static String formatFiat(double value, {String symbol = '\$'}) => formatAmount(value, symbol: symbol);
}
