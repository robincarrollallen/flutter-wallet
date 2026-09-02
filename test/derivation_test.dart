import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallet/blockchain/chain_registry.dart';
import 'package:wallet/features/wallet/send/coins/logic.dart';
import 'package:wallet/services/mnemonic_service.dart';

const vector = 'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';

void main() {
  test('BIP84/BIP86 主网首地址匹配官方 test vector', () {
    final seed = Bip39SeedGenerator(Mnemonic.fromString(vector)).generate();
    expect(
      Bip84.fromSeed(seed, Bip84Coins.bitcoin).deriveDefaultPath.publicKey.toAddress,
      'bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu',
    );
    expect(
      Bip86.fromSeed(seed, Bip86Coins.bitcoin).deriveDefaultPath.publicKey.toAddress,
      'bc1p5cyxnuxmeuwuvkwfem96lqzszd02n6xdcjrs20cac6yqjjwudpxqkedrcr',
    );
  });

  test('钱包派生的 BTC 测试网地址为 tb1q（P2WPKH）', () {
    final wallet = MnemonicService.deriveWallet(vector);
    final btc = wallet.addresses[SupportedChains.bitcoinTestnet.id]!;
    expect(btc.startsWith('tb1q'), isTrue, reason: btc);
  });

  test('其余链地址不受 BTC 派生方案影响', () {
    final wallet = MnemonicService.deriveWallet(vector);
    expect(wallet.addresses[SupportedChains.ethereumSepolia.id], '0x9858EfFD232B4033E47d90003D41EC34EcaEda94');
    expect(wallet.addresses.length, SupportedChains.all.length);
  });

  test('BTC 收款地址校验放行 P2WPKH / P2TR / legacy', () {
    final btc = SupportedChains.bitcoinTestnet;
    for (final addr in [
      'tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx', // v0 P2WPKH
      'tb1pqqqqp399et2xygdj5xreqhjjvcmzhxw4aywxecjdzew6hylgvsesf3hn0c', // v1 P2TR
      'mipcBbFg9gMiCh81Kj8tqqdgoZub1ZJRfn', // legacy P2PKH
    ]) {
      expect(SendLogic.validateAddress(btc, addr), isNull, reason: addr);
    }
    expect(SendLogic.validateAddress(btc, 'tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsy'), isNotNull); // 校验和错误
  });
}
