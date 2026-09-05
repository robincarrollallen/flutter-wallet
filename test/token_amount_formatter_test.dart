import 'package:flutter_test/flutter_test.dart';
import 'package:wallet/blockchain/units.dart';
import 'package:wallet/core/format/token_amount_formatter.dart';

void main() {
  group('formatTokenAmount 按数量级分档', () {
    test('>= 1000 保留两位', () {
      expect(formatTokenAmount('1234.56789'), '1,234.56');
      expect(formatTokenAmount('1000000.999'), '1,000,000.99');
    });

    test('1 ~ 999 保留四位', () {
      expect(formatTokenAmount('1.23456789'), '1.2345');
      expect(formatTokenAmount('999.9999999'), '999.9999');
    });

    test('0.001 ~ 1 保留六位', () {
      expect(formatTokenAmount('0.049939577316748207'), '0.049939');
      expect(formatTokenAmount('0.001234567'), '0.001234');
    });

    test('< 0.001 保留八位', () {
      expect(formatTokenAmount('0.000023208702657'), '0.0000232'); // 截到八位后尾零去掉
      expect(formatTokenAmount('0.000123456789'), '0.00012345');
    });
  });

  group('截断而非四舍五入', () {
    // 这是本模块存在的理由：舍入成更大的数会让「最大」按钮和手输金额撞上余额不足。
    test('永远向下取整，不进位', () {
      expect(formatTokenAmount('0.049939577316748207'), '0.049939'); // 非 0.049940
      expect(formatTokenAmount('1.99999999'), '1.9999'); // 非 2.0
      expect(formatTokenAmount('9999.999'), '9,999.99'); // 非 10,000.00
    });

    test('展示值恒不大于精确值', () {
      const exact = '0.049939577316748207';
      final shown = formatTokenAmount(exact);
      expect(parseUnits(shown, 18) <= parseUnits(exact, 18), isTrue);
    });
  });

  group('边界', () {
    test('整数去掉小数部分', () {
      expect(formatTokenAmount('0'), '0');
      expect(formatTokenAmount('42'), '42');
      expect(formatTokenAmount('1.0000'), '1');
    });

    test('去尾零', () {
      expect(formatTokenAmount('0.050000'), '0.05');
      expect(formatTokenAmount('10.5000'), '10.5');
    });

    test('小到当前档位表示不出来时，不显示成 0', () {
      expect(formatTokenAmount('0.00000000004'), '<0.00000001');
    });

    test('真正的 0 就显示 0，不加小于号', () {
      expect(formatTokenAmount('0.000000000000'), '0');
    });

    test('maxDecimals 可显式覆盖分档', () {
      expect(formatTokenAmount('0.049939577316748207', maxDecimals: 2), '0.04');
    });

    test('非十进制字面量原样返回', () {
      expect(formatTokenAmount('--'), '--');
      expect(formatTokenAmount(''), '');
    });
  });

  test('与 formatUnits 衔接：wei 级余额直接可读', () {
    final readable = formatUnits(BigInt.parse('49939577316748207'), 18);
    expect(readable, '0.049939577316748207');
    expect(formatTokenAmount(readable), '0.049939');
  });
}
