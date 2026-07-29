import 'package:flutter_test/flutter_test.dart';
import 'package:wallet/core/constants/currency_symbols.dart';
import 'package:wallet/features/settings/currency/logic.dart';
import 'package:wallet/i18n/translations.g.dart';
import 'package:wallet/providers/modules/currency_provider.dart';

void main() {
  final en = AppLocale.en.buildSync(); // base locale，非 deferred，可同步构建
  final codes = supportedCurrencyCodes;

  // zh 是 deferred library，必须先异步加载才能构建。
  late Translations zh;
  setUpAll(() async => zh = await AppLocale.zh.build());

  group('币种表', () {
    test('每个可选币种都有符号、名称与国旗', () {
      for (final code in codes) {
        expect(defaultCurrencySymbols[code], isNotNull, reason: code);
        expect(en.currencyNames[code], isNotNull, reason: code);
        expect(zh.currencyNames[code], isNotNull, reason: code);
        // 两位区域指示符 = 2 个 code point，各占 2 个 UTF-16 单元。
        expect(currencyFlagOf(code).length, 4, reason: code);
      }
    });

    test('EUR 特例为欧盟旗', () {
      expect(currencyFlagOf('EUR'), '🇪🇺');
    });

    test('非法代码回退白旗', () {
      expect(currencyFlagOf('1'), '🏳️');
    });
  });

  group('filter', () {
    test('空关键词返回全部', () {
      expect(CurrencyLogic.filter(codes, '   ', en), hasLength(codes.length));
    });

    test('按代码匹配', () {
      expect(CurrencyLogic.filter(codes, 'usd', en), ['USD']);
    });

    test('按当前语言名称匹配', () {
      expect(CurrencyLogic.filter(codes, '美元', zh), contains('USD'));
      expect(CurrencyLogic.filter(codes, 'yen', en), contains('JPY'));
    });

    test('中文界面下英文名兜底仍生效', () {
      expect(CurrencyLogic.filter(codes, 'yen', zh), contains('JPY'));
      expect(
        CurrencyLogic.filter(codes, 'dollar', zh),
        containsAll(['USD', 'AUD', 'CAD', 'HKD', 'NZD', 'SGD', 'BMD']),
      );
    });

    test('无匹配返回空', () {
      expect(CurrencyLogic.filter(codes, 'zzzz', en), isEmpty);
    });
  });

  group('nameOf', () {
    test('缺译回退代码本身', () {
      expect(CurrencyLogic.nameOf(en, 'XYZ'), 'XYZ');
    });
  });
}
