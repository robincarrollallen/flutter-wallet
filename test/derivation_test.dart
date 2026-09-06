import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:on_chain/tron/tron.dart';
import 'package:wallet/blockchain/chain_registry.dart';
import 'package:wallet/features/wallet/send/coins/logic.dart';
import 'package:wallet/services/mnemonic_service.dart';
import 'package:wallet/services/private_key_service.dart';
import 'package:wallet/services/wallet_key_service.dart';

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

  // 这条锁死一个很容易踩的坑：Tron 走 coin_type 195，EVM 走 60，两者私钥不同。
  // 若签名时误用 EVM 私钥，签出的地址与钱包展示的 Tron 地址对不上，转账会被拦下。
  test('Tron 私钥派生出的地址与钱包里的 Tron 地址一致，且与 EVM 私钥不同', () {
    final wallet = MnemonicService.deriveWallet(vector);
    final tron = SupportedChains.tronShasta;

    final tronKey = MnemonicService.derivePrivateKey(vector, tron);
    final evmKey = MnemonicService.derivePrivateKey(vector, SupportedChains.ethereumSepolia);
    expect(tronKey, isNot(evmKey));

    final derived = TronPrivateKey(tronKey.substring(2)).publicKey().toAddress().toAddress();
    expect(derived, wallet.addresses[tron.id]);
  });

  // 原始字节派生与编码导出必须同源：一旦漂移，就会出现「导出的私钥导进别的钱包，
  // 地址跟 App 里显示的不一样」——这类问题极难查，所以在这里钉死。
  test('derivePrivateKeyBytes 与 derivePrivateKey 同源，且各链都是 32 字节', () {
    for (final chain in SupportedChains.all) {
      final bytes = MnemonicService.derivePrivateKeyBytes(vector, chain);
      expect(bytes, hasLength(32), reason: chain.id);

      // hex 编码的三类链可以直接比对，其余链编码里还夹着公钥/标志位，不适合直接比。
      if (chain.kind == ChainKind.evm || chain.kind == ChainKind.tron || chain.kind == ChainKind.aptos) {
        final encoded = MnemonicService.derivePrivateKey(vector, chain);
        expect('0x${BytesUtils.toHexString(bytes)}', encoded, reason: chain.id);
      }
    }
  });

  // 私钥导入的钱包没有助记词，签名要靠把存下的字符串解回字节。
  test('PrivateKeyService.decodeToBytes 能把导出串解回原始字节', () {
    for (final chain in [SupportedChains.ethereumSepolia, SupportedChains.solanaDevnet, SupportedChains.suiTestnet]) {
      final bytes = MnemonicService.derivePrivateKeyBytes(vector, chain);
      final exported = MnemonicService.derivePrivateKey(vector, chain);
      expect(PrivateKeyService.decodeToBytes(exported), bytes, reason: chain.id);
    }
  });

  // wipeKey 吞异常，清不掉也不会报错——所以必须单独验证缓冲区确实可写，
  // 否则清零会静默变成空操作，而我们还以为清过了。
  test('派生出的私钥缓冲区可写，且清零不影响后续派生', () {
    for (final chain in [SupportedChains.ethereumSepolia, SupportedChains.solanaDevnet, SupportedChains.tronShasta]) {
      final bytes = MnemonicService.derivePrivateKeyBytes(vector, chain);
      wipeKey(bytes);
      expect(bytes.every((b) => b == 0), isTrue, reason: '${chain.id} 未被清零');

      // 清的必须是我们自己的副本：再派生一次应拿到完好的私钥，
      // 若清到了 blockchain_utils 的内部状态，这里就会拿到一串 0。
      expect(MnemonicService.derivePrivateKeyBytes(vector, chain).any((b) => b != 0), isTrue, reason: chain.id);
    }
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
