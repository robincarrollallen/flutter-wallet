import 'package:flutter_test/flutter_test.dart';
import 'package:wallet/blockchain/chain_registry.dart';
import 'package:wallet/services/mnemonic_service.dart';
import 'package:wallet/services/private_key_service.dart';

void main() {
  // BIP39 标准测试向量（全 abandon + about）。
  const validMnemonic = 'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';

  group('MnemonicService.englishWordlist', () {
    test('为标准 2048 词英文词表', () {
      expect(MnemonicService.englishWordlist.length, 2048);
      expect(MnemonicService.englishWordlist.first, 'abandon');
      expect(MnemonicService.englishWordlist.last, 'zoo');
    });
  });

  group('MnemonicService.validate', () {
    test('合法助记词通过', () {
      expect(MnemonicService.validate(validMnemonic), isTrue);
    });

    test('校验和错误的助记词不通过', () {
      // 末词换成另一个合法词，破坏校验和。
      const bad = 'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon';
      expect(MnemonicService.validate(bad), isFalse);
    });
  });

  group('MnemonicService.generate', () {
    test('生成 12 词且自身可通过校验', () {
      final m = MnemonicService.generate();
      expect(m.split(' ').length, 12);
      expect(MnemonicService.validate(m), isTrue);
    });
  });

  group('MnemonicService.deriveEthAddress', () {
    test('派生出标准 BIP44 以太坊首地址', () {
      expect(MnemonicService.deriveEthAddress(validMnemonic), '0x9858EfFD232B4033E47d90003D41EC34EcaEda94');
    });

    test('同一助记词派生结果稳定', () {
      expect(MnemonicService.deriveEthAddress(validMnemonic), MnemonicService.deriveEthAddress(validMnemonic));
    });
  });

  group('MnemonicService.deriveWallet 多链', () {
    test('新增链（Tron/Sui/Aptos）均派生出非空且稳定的地址', () {
      final a = MnemonicService.deriveWallet(validMnemonic);
      final b = MnemonicService.deriveWallet(validMnemonic);
      for (final kind in [ChainKind.tron, ChainKind.sui, ChainKind.aptos]) {
        final chain = SupportedChains.all.firstWhere((c) => c.kind == kind);
        expect(a.addresses[chain.id], isNotEmpty, reason: '${chain.id} 应派生出地址');
        expect(a.addresses[chain.id], b.addresses[chain.id], reason: '${chain.id} 派生应稳定');
      }
    });
  });

  group('MnemonicService.derivePrivateKey 导出私钥', () {
    test('同一助记词按链导出稳定', () {
      final chain = SupportedChains.solanaDevnet;
      expect(
        MnemonicService.derivePrivateKey(validMnemonic, chain),
        MnemonicService.derivePrivateKey(validMnemonic, chain),
      );
    });

    test('EVM 各链导出同一把 0x hex 私钥', () {
      final eth = MnemonicService.derivePrivateKey(validMnemonic, SupportedChains.ethereumSepolia);
      final poly = MnemonicService.derivePrivateKey(validMnemonic, SupportedChains.polygonAmoy);
      expect(eth, startsWith('0x'));
      expect(eth.length, 66); // 0x + 64 hex
      expect(eth, poly, reason: 'EVM 多链共用同一私钥');
    });

    test('Sui 导出为 suiprivkey bech32，Bitcoin 为 WIF', () {
      expect(MnemonicService.derivePrivateKey(validMnemonic, SupportedChains.suiTestnet), startsWith('suiprivkey1'));
      // testnet WIF 以 'c' 或 '9' 开头（0xEF 版本字节）。
      final wif = MnemonicService.derivePrivateKey(validMnemonic, SupportedChains.bitcoinTestnet);
      expect(wif, isNotEmpty);
      expect(wif.startsWith('c') || wif.startsWith('9'), isTrue);
    });

    // 自洽回导：导出串经 PrivateKeyService 还原的地址应等于 deriveWallet 派生地址。
    test('EVM/Solana/Sui 导出私钥可回导且地址一致', () {
      final wallet = MnemonicService.deriveWallet(validMnemonic);
      for (final chain in [SupportedChains.ethereumSepolia, SupportedChains.solanaDevnet, SupportedChains.suiTestnet]) {
        final exported = MnemonicService.derivePrivateKey(validMnemonic, chain);
        final kind = PrivateKeyService.detect(exported);
        expect(kind, isNot(PrivateKeyKind.unknown), reason: '${chain.id} 导出串应可被识别');
        final reimported = PrivateKeyService.derive(kind, exported);
        expect(reimported.primaryAddress, wallet.addresses[chain.id], reason: '${chain.id} 回导地址应与派生地址一致');
      }
    });
  });
}
