import '../../../i18n/translations.g.dart';
import '../../search/modules/pill/logic.dart';

/// 币种选择页的纯逻辑：查名与关键词匹配，与状态/UI 无关，便于单测。
class CurrencyLogic {
  const CurrencyLogic._();

  /// 英文名兜底表：base locale 的译文，同步构建且只建一次。
  /// 用于让中文界面下敲 `dollar` / `yen` 也能命中——用户的检索习惯未必跟随界面语言。
  static final Map<String, String> _englishNames = AppLocale.en.buildSync().currencyNames;

  /// 取币种的本地化名称；缺译时回退代码本身，不会出现空行。
  static String nameOf(Translations t, String code) => t.currencyNames[code] ?? code;

  /// 按关键词过滤币种代码。[query] 由本方法内部规整，调用方传原始输入即可。
  ///
  /// 命中任一即保留：币种代码、当前语言的名称、英文名。
  /// 中文无大小写之分，[normalizeQuery] 的转小写对中文是空操作，安全。
  static List<String> filter(List<String> codes, String query, Translations t) {
    final q = normalizeQuery(query);
    if (q.isEmpty) return codes;
    return codes.where((code) {
      if (code.toLowerCase().contains(q)) return true;
      if (nameOf(t, code).toLowerCase().contains(q)) return true;
      return (_englishNames[code] ?? '').toLowerCase().contains(q);
    }).toList();
  }
}
