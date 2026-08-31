import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../constants/currency_symbols.dart';
import '../persistent_notifier.dart';
import '../../enums/prefs_key.dart';

/// 可选法币列表：直接取内置符号表的键——表里有符号才显示得出金额。
/// 该表已对齐 CoinGecko `/simple/supported_vs_currencies` 的全部法币（46 种），
/// 增删币种改那张表即可，此处自动跟随；从表中移除的币种由 [CurrencyNotifier.fromJson]
/// 校验拦下，老用户存过的失效代码会回退到 [defaultCurrencyCode]。
final List<String> supportedCurrencyCodes = defaultCurrencySymbols.keys.toList();

/// 全局计价法币（ISO 4217 代码，大写，如 'USD' / 'CNY'）。
///
/// 价格由 CoinGecko 按该币种直接返回（`vs_currency=xxx`），不做本地汇率换算，
/// 因此切换币种会让 [marketsProvider] 重新取数——缓存按币种分键，互不覆盖。
class CurrencyNotifier extends Notifier<String> with PersistentNotifier<String> {
  @override
  PrefsKey get persistKey => PrefsKey.fiatCurrency;

  @override
  Map<String, dynamic> toJson(String state) => {'code': state};

  @override
  String fromJson(Map<String, dynamic> json, String fallback) {
    final code = json['code'];
    // 存档里的币种可能已从 supportedCurrencyCodes 中移除，校验后再用。
    if (code is String && supportedCurrencyCodes.contains(code)) return code;
    return fallback;
  }

  @override
  String build() => restore(defaultCurrencyCode);

  void set(String code) {
    final c = code.toUpperCase();
    if (c == state || !supportedCurrencyCodes.contains(c)) return;
    state = c; // 自动落盘
  }
}

final currencyProvider = NotifierProvider<CurrencyNotifier, String>(CurrencyNotifier.new);

/// 当前法币的货币符号，供 [AmountText] / [formatAmount] 前置展示。
final currencySymbolProvider = Provider<String>((ref) => currencySymbolOf(ref.watch(currencyProvider)));
