import 'package:flutter_test/flutter_test.dart';
import 'package:wallet/blockchain/chain_registry.dart';
import 'package:wallet/services/private_key_service.dart';

void main() {
  // secp256k1 私钥 = 1 的知名测试向量。
  const evmHex = '0000000000000000000000000000000000000000000000000000000000000001';
  const evmAddr = '0x7E5F4552091A69125d5DfCb7b8C2659029395Bdf';
  const tronAddr = 'TMVQGm1qAQYVdetCeGRRkTWYYrLXuHK2HC';

  // Solana：32 字节全 0x11 的种子。
  const solBase58 = '29d2S7vB453rNYFdR5Ycwt7y9haRT5fwVwL9zTmBhfV2';
  const solAddr = 'F25s3DdjXdCxYBhh2z8FBusVEMT4b9bGNFVKJi3wFoF4';

  // Sui ed25519：flag 0x00 + 32 字节全 0x22。
  const suiBech = 'suiprivkey1qq3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyqz52s0';
  const suiAddr = '0x48936240c871663e6ba416724158736101ccab29436f72ae3ae4c8fa1ce7e45f';

  group('PrivateKeyService.detect', () {
    test('EVM hex（带/不带 0x）', () {
      expect(PrivateKeyService.detect(evmHex), PrivateKeyKind.evmHex);
      expect(PrivateKeyService.detect('0x$evmHex'), PrivateKeyKind.evmHex);
    });
    test('Solana base58', () {
      expect(PrivateKeyService.detect(solBase58), PrivateKeyKind.solanaBase58);
    });
    test('Sui bech32', () {
      expect(PrivateKeyService.detect(suiBech), PrivateKeyKind.suiBech32);
    });
    test('助记词词组 / 乱码 / 空 → unknown', () {
      expect(PrivateKeyService.detect('abandon ability able'), PrivateKeyKind.unknown);
      expect(PrivateKeyService.detect('not-a-key!!!'), PrivateKeyKind.unknown);
      expect(PrivateKeyService.detect('   '), PrivateKeyKind.unknown);
    });
    test('长度不足的 hex 不识别为 EVM', () {
      expect(PrivateKeyService.detect('0x1234'), PrivateKeyKind.unknown);
    });
  });

  group('PrivateKeyService.derive EVM hex', () {
    test('还原 EVM 地址并覆盖所有 EVM 链', () {
      final w = PrivateKeyService.derive(PrivateKeyKind.evmHex, '0x$evmHex');
      expect(w.primaryAddress, evmAddr);
      expect(w.primaryPrivateKey, '0x$evmHex');
      for (final c in SupportedChains.all.where((c) => c.kind == ChainKind.evm)) {
        expect(w.addresses[c.id], evmAddr);
      }
    });
    test('同一把私钥同时还原 Tron 地址', () {
      final w = PrivateKeyService.derive(PrivateKeyKind.evmHex, evmHex);
      final tron = SupportedChains.all.firstWhere((c) => c.kind == ChainKind.tron);
      expect(w.addresses[tron.id], tronAddr);
    });
  });

  group('PrivateKeyService.derive Solana', () {
    test('还原 Solana 地址', () {
      final w = PrivateKeyService.derive(PrivateKeyKind.solanaBase58, solBase58);
      final sol = SupportedChains.all.firstWhere((c) => c.kind == ChainKind.solana);
      expect(w.primaryAddress, solAddr);
      expect(w.addresses[sol.id], solAddr);
    });
  });

  group('PrivateKeyService.derive Sui', () {
    test('还原 Sui 地址', () {
      final w = PrivateKeyService.derive(PrivateKeyKind.suiBech32, suiBech);
      final sui = SupportedChains.all.firstWhere((c) => c.kind == ChainKind.sui);
      expect(w.primaryAddress, suiAddr);
      expect(w.addresses[sui.id], suiAddr);
    });
  });

  test('derive(unknown) 抛错', () {
    expect(() => PrivateKeyService.derive(PrivateKeyKind.unknown, 'x'), throwsArgumentError);
  });
}
