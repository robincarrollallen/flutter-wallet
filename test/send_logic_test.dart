import 'package:flutter_test/flutter_test.dart';
import 'package:wallet/blockchain/chain_registry.dart';
import 'package:wallet/blockchain/units.dart';
import 'package:wallet/features/wallet/send/coins/logic.dart';
import 'package:wallet/features/wallet/send/coins/state.dart';

void main() {
  group('SendLogic.assetsOf', () {
    test('仅返回原生币（不含代币）', () {
      final all = SendLogic.assetsOf(null);
      expect(all.length, SupportedChains.all.length);
    });

    test('指定链时只返回该链原生币', () {
      final assets = SendLogic.assetsOf(SupportedChains.ethereumSepolia);
      expect(assets.length, 1);
      expect(assets.single.symbol, 'ETH');
    });
  });

  group('SendLogic.filter', () {
    test('按符号/名称过滤，忽略大小写', () {
      final assets = SendLogic.assetsOf(null);
      expect(SendLogic.filter(assets, 'sol').single.symbol, 'SOL');
      expect(SendLogic.filter(assets, 'BITCOIN').single.symbol, 'BTC');
      expect(SendLogic.filter(assets, ''), assets);
    });
  });

  group('SendLogic.partition', () {
    final assets = SendLogic.assetsOf(null);

    test('价值降序，零值进 rest 并保持原顺序', () {
      final values = {'ethereum-sepolia': 10.0, 'solana-devnet': 30.0, 'bsc-testnet': 20.0};
      final (sendable, rest) = SendLogic.partition(assets, (a) => values[a.chain.id] ?? 0);
      expect(sendable.map((a) => a.chain.id).toList(), ['solana-devnet', 'bsc-testnet', 'ethereum-sepolia']);
      expect(rest.length, assets.length - 3);
      // rest 保持链默认顺序。
      expect(
        rest.map((a) => a.chain.id).toList(),
        assets.where((a) => !values.containsKey(a.chain.id)).map((a) => a.chain.id).toList(),
      );
    });

    test('加载中（null）留在 sendable 尾部', () {
      final (sendable, rest) = SendLogic.partition(assets, (a) => a.symbol == 'SOL' ? 5.0 : null);
      expect(rest, isEmpty);
      expect(sendable.first.symbol, 'SOL');
      expect(sendable.length, assets.length);
    });

    test('空列表', () {
      final (sendable, rest) = SendLogic.partition(const [], (_) => 0);
      expect(sendable, isEmpty);
      expect(rest, isEmpty);
    });
  });

  group('SendLogic.validateAddress', () {
    const evm = SupportedChains.ethereumSepolia;

    test('EVM：合法全小写地址', () {
      expect(SendLogic.validateAddress(evm, '0x52908400098527886e0f7030069857d2e4169ee7'), isNull);
    });

    test('EVM：合法 EIP-55 checksum 地址', () {
      expect(SendLogic.validateAddress(evm, '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed'), isNull);
    });

    test('EVM：错误 checksum 被拒绝', () {
      expect(SendLogic.validateAddress(evm, '0x5aaeb6053F3E94C9b9A09f33669435E7Ef1BeAed'), isNotNull);
    });

    test('EVM：长度/前缀非法被拒绝', () {
      expect(SendLogic.validateAddress(evm, '0x1234'), isNotNull);
      expect(SendLogic.validateAddress(evm, ''), isNotNull);
    });

    test('Solana：合法 base58 地址', () {
      expect(
        SendLogic.validateAddress(SupportedChains.solanaDevnet, '4Nd1mBQtrMJVYVfKf2PJy9NZUZdTAsp7D4xWLs4gDB4T'),
        isNull,
      );
    });

    test('Solana：EVM 地址被拒绝（错链粘贴）', () {
      expect(
        SendLogic.validateAddress(SupportedChains.solanaDevnet, '0x52908400098527886e0f7030069857d2e4169ee7'),
        isNotNull,
      );
    });

    test('Tron：合法 T 开头 base58check 地址', () {
      expect(SendLogic.validateAddress(SupportedChains.tronShasta, 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t'), isNull);
    });

    test('Bitcoin testnet：合法 tb1 bech32 地址', () {
      expect(
        SendLogic.validateAddress(SupportedChains.bitcoinTestnet, 'tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx'),
        isNull,
      );
    });

    test('Bitcoin testnet：主网 bc1 地址被拒绝', () {
      expect(
        SendLogic.validateAddress(SupportedChains.bitcoinTestnet, 'bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4'),
        isNotNull,
      );
    });

    test('Sui/Aptos：32 字节十六进制', () {
      expect(SendLogic.validateAddress(SupportedChains.suiTestnet, '0x2'), isNull);
      expect(SendLogic.validateAddress(SupportedChains.aptosTestnet, '0x'), isNotNull);
    });
  });

  group('SendLogic.validateAmount', () {
    test('合法金额', () {
      expect(SendLogic.validateAmount('0.5', '1.0'), isNull);
      expect(SendLogic.validateAmount('1.0', '1.0'), isNull);
    });

    test('非法输入', () {
      expect(SendLogic.validateAmount('', '1.0'), isNotNull);
      expect(SendLogic.validateAmount('abc', '1.0'), isNotNull);
      expect(SendLogic.validateAmount('0', '1.0'), isNotNull);
      expect(SendLogic.validateAmount('-1', '1.0'), isNotNull);
    });

    test('余额不足', () {
      expect(SendLogic.validateAmount('2', '1.0'), '余额不足');
    });
  });

  test('SendAsset 展示字段取自链本身', () {
    const asset = SendAsset(chain: SupportedChains.solanaDevnet);
    expect(asset.symbol, 'SOL');
    expect(asset.name, 'Solana Devnet');
    expect(asset.coinGeckoId, 'solana');
  });

  group('parseUnits', () {
    test('整数金额', () {
      expect(parseUnits('1', 18), BigInt.parse('1000000000000000000'));
      expect(parseUnits('0', 18), BigInt.zero);
    });

    test('小数金额不丢精度', () {
      expect(parseUnits('1.234567890123456789', 18), BigInt.parse('1234567890123456789'));
      expect(parseUnits('0.5', 6), BigInt.from(500000));
    });

    test('decimals 为 0', () {
      expect(parseUnits('42', 0), BigInt.from(42));
    });

    test('小数位超过精度上限抛异常', () {
      expect(() => parseUnits('0.1234567', 6), throwsFormatException);
    });

    test('非法格式抛异常', () {
      expect(() => parseUnits('', 18), throwsFormatException);
      expect(() => parseUnits('abc', 18), throwsFormatException);
      expect(() => parseUnits('-1', 18), throwsFormatException);
      expect(() => parseUnits('1.', 18), throwsFormatException);
    });
  });

  group('formatUnits', () {
    test('整数与零', () {
      expect(formatUnits(BigInt.parse('1000000000000000000'), 18), '1');
      expect(formatUnits(BigInt.zero, 18), '0');
      expect(formatUnits(BigInt.from(42), 0), '42');
    });

    test('小数去尾零', () {
      expect(formatUnits(BigInt.from(500000), 6), '0.5');
      expect(formatUnits(BigInt.parse('1234567890123456789'), 18), '1.234567890123456789');
    });

    test('与 parseUnits 互逆', () {
      for (final s in ['1', '0.5', '123.456', '0.000001']) {
        expect(formatUnits(parseUnits(s, 18), 18), s);
      }
    });
  });
}
