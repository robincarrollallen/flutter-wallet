import 'package:flutter_test/flutter_test.dart';
import 'package:wallet/core/format/amount_formatter.dart';

void main() {
  group('formatFiatFee 小额边界', () {
    test('大于 0 但四舍五入后为 0 时给 `<\$0.01`，不显示会被误解的 `\$0.00`', () {
      // Solana 一笔转账的实际手续费：0.000005 SOL × $101.89 ≈ $0.0005。
      expect(formatFiatFee(0.00050945), r'<$0.01');
      // 紧贴阈值下方：0.004 四舍五入是 0.00，仍要加 `<`。
      expect(formatFiatFee(0.004), r'<$0.01');
      expect(formatFiatFee(0.0049999), r'<$0.01');
    });

    test('四舍五入后有得显示时照常显示，不加 `<`', () {
      // 0.005 进位成 0.01——这一档已经显示得出来了，再加 `<` 反而把它说小了。
      expect(formatFiatFee(0.005), r'$0.01');
      expect(formatFiatFee(0.01), r'$0.01');
      expect(formatFiatFee(1.5), r'$1.50');
      expect(formatFiatFee(4321.5), r'$4,321.50');
    });

    test('真正的 0 照实显示，不谎称有费用', () {
      // 调用方拿不到单价时应当整段省略法币部分，不该传 0 进来；
      // 真传了也只能说「0」，绝不能变成 `<$0.01`。
      expect(formatFiatFee(0), r'$0.00');
    });

    test('沿用传入的货币符号', () {
      expect(formatFiatFee(0.0005, symbol: '¥'), '<¥0.01');
      expect(formatFiatFee(12.3, symbol: '¥'), '¥12.30');
    });

    test('小数位可调，阈值随之变化', () {
      // 保留 4 位时阈值降到 0.00005：低于它才加 `<`。
      expect(formatFiatFee(0.00004, decimals: 4), r'<$0.0001');
      // 正好在阈值上则进位成 0.0001，显示得出来，不加 `<`。
      expect(formatFiatFee(0.00005, decimals: 4), r'$0.0001');
      expect(formatFiatFee(0.0005, decimals: 4), r'$0.0005');
    });
  });

  group('formatAmount', () {
    test('千分位与符号', () {
      expect(formatAmount(4321.5), r'$4,321.50');
      expect(formatAmount(4321.5, symbol: '¥'), '¥4,321.50');
      expect(formatAmount(4321.5, showSymbol: false, decimals: 0), '4,322');
    });

    test('负数把符号放在货币符号之前', () {
      expect(formatAmount(-12.3), r'-$12.30');
    });
  });
}
