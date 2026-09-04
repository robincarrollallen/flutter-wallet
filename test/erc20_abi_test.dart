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

  group('encodeTransfer', () {
    const to = '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed';

    test('选择器 + 收款地址 + 金额，各补零到 32 字节', () {
      // 1 USDC（decimals 6）= 1000000 = 0xf4240
      final data = encodeTransfer(to: to, amount: BigInt.from(1000000));

      expect(data.length, 2 + 8 + 64 + 64, reason: '0x + 4 字节选择器 + 两个 32 字节参数');
      expect(
        data,
        '0xa9059cbb'
        '0000000000000000000000005aaeb6053f3e94c9b9a09f33669435e7ef1beaed'
        '00000000000000000000000000000000000000000000000000000000000f4240',
      );
    });

    test('大小写与 0x 前缀不影响结果', () {
      final amount = BigInt.from(42);
      expect(encodeTransfer(to: to, amount: amount), encodeTransfer(to: to.toLowerCase(), amount: amount));
      expect(encodeTransfer(to: to, amount: amount), encodeTransfer(to: to.substring(2), amount: amount));
    });

    test('超出 double 精度的大额不失真', () {
      final amount = BigInt.parse('123456789012345678901234567890');
      final data = encodeTransfer(to: to, amount: amount);
      expect(decodeUint256('0x${data.substring(data.length - 64)}'), amount);
    });

    test('uint256 边界值可编码', () {
      final max = (BigInt.one << 256) - BigInt.one;
      expect(encodeTransfer(to: to, amount: max).endsWith('f' * 64), isTrue);
      expect(encodeTransfer(to: to, amount: BigInt.zero).endsWith('0' * 64), isTrue);
    });

    // calldata 编错等于把钱打给一个陌生地址 / 转出一个陌生金额，必须报错。
    test('地址非法或金额越界即抛错', () {
      expect(() => encodeTransfer(to: '0x1234', amount: BigInt.one), throwsArgumentError);
      expect(() => encodeTransfer(to: to, amount: -BigInt.one), throwsArgumentError);
      expect(() => encodeTransfer(to: to, amount: BigInt.one << 256), throwsArgumentError);
    });
  });

  group('encodeAddressArgument', () {
    test('20 字节右对齐补零成 64 位十六进制，不带 0x', () {
      final arg = encodeAddressArgument(List.filled(20, 0xab));

      expect(arg.length, 64);
      expect(arg.startsWith('0' * 24), isTrue, reason: '前 12 字节应当是补的零');
      expect(arg.substring(24), 'ab' * 20);
    });

    test('小于 0x10 的字节保留前导零，不塌成单字符', () {
      final arg = encodeAddressArgument([1, ...List.filled(19, 0)]);

      expect(arg.length, 64);
      expect(arg.substring(24), '01${'00' * 19}');
    });

    // TRC-20 复用这段编码，长度错了会查到一个陌生地址的 0。
    test('长度不是 20 字节即抛错', () {
      expect(() => encodeAddressArgument(List.filled(19, 0)), throwsArgumentError);
      expect(() => encodeAddressArgument(List.filled(21, 0)), throwsArgumentError);
      expect(() => encodeAddressArgument(const []), throwsArgumentError);
    });

    test('与 encodeBalanceOf 共用同一份编码', () {
      const owner = '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed';
      final bytes = [
        for (var i = 2; i < owner.length; i += 2) int.parse(owner.substring(i, i + 2), radix: 16),
      ];

      expect(encodeBalanceOf(owner), '0x70a08231${encodeAddressArgument(bytes)}');
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
