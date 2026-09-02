import 'package:flutter_test/flutter_test.dart';
import 'package:wallet/core/utils/erc20_abi.dart';

void main() {
  group('encodeBalanceOf', () {
    const owner = '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed';

    test('选择器 + 地址右对齐补零到 32 字节', () {
      final data = encodeBalanceOf(owner);

      expect(data.length, 2 + 8 + 64, reason: '0x + 4 字节选择器 + 32 字节参数');
      expect(data.startsWith('0x70a08231'), isTrue);
      expect(
        data,
        '0x70a08231'
        '0000000000000000000000005aaeb6053f3e94c9b9a09f33669435e7ef1beaed',
      );
    });

    test('大小写与 0x 前缀不影响结果', () {
      expect(encodeBalanceOf(owner), encodeBalanceOf(owner.toLowerCase()));
      expect(encodeBalanceOf(owner), encodeBalanceOf(owner.substring(2)));
    });

    // 地址错了就查不到余额；静默补零只会得到一个陌生地址的 0，比报错危险得多。
    test('长度不对或含非十六进制字符即抛错，不静默补零', () {
      expect(() => encodeBalanceOf('0x1234'), throwsArgumentError);
      expect(() => encodeBalanceOf('0x${'z' * 40}'), throwsArgumentError);
      expect(() => encodeBalanceOf(''), throwsArgumentError);
    });
  });

  group('decodeUint256', () {
    test('解析 32 字节返回值', () {
      expect(decodeUint256('0x${'0' * 62}ff'), BigInt.from(255));
      expect(decodeUint256('0x${'0' * 64}'), BigInt.zero);
    });

    test('超出 double 精度的大额不失真', () {
      final raw = BigInt.parse('123456789012345678901234567890');
      expect(decodeUint256('0x${raw.toRadixString(16).padLeft(64, '0')}'), raw);
    });

    // 空返回意味着目标地址上没有合约代码（合约填错 / 链选错），
    // 当成 0 就是在告诉用户「你没有这个币」。
    test('空返回抛错而非当作 0', () {
      expect(() => decodeUint256('0x'), throwsFormatException);
      expect(() => decodeUint256(''), throwsFormatException);
    });
  });
}
