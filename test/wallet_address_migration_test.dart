import 'package:flutter_test/flutter_test.dart';
import 'package:wallet/blockchain/chain_registry.dart';
import 'package:wallet/domain/wallet.dart';

const _legacyAddress = '0x0000000000000000000000000000000000000001';
const _sepoliaAddress = '0x9858EfFD232B4033E47d90003D41EC34EcaEda94';

Iterable<Chain> get _evmChains => SupportedChains.all.where((c) => c.kind == ChainKind.evm);
Iterable<Chain> get _nonEvmChains => SupportedChains.all.where((c) => c.kind != ChainKind.evm);

void main() {
  group('老字段 address → addresses 迁移', () {
    test('只有老字段时写入全部 EVM 链，非 EVM 仍为空', () {
      final wallet = Wallet.fromJson({
        'id': 'w1',
        'name': '测试钱包',
        'address': _legacyAddress,
        'source': 'mnemonic',
      });

      for (final chain in _evmChains) {
        expect(wallet.addressFor(chain), _legacyAddress, reason: '${chain.id} 应拿到老主地址');
      }
      for (final chain in _nonEvmChains) {
        expect(wallet.addressFor(chain), isNull, reason: '${chain.id} 不应被老 0x 地址填上');
      }
    });

    test('addresses 非空时忽略老字段，不回填其它 EVM 链', () {
      final wallet = Wallet.fromJson({
        'id': 'w1',
        'name': '测试钱包',
        'address': _legacyAddress,
        'source': 'mnemonic',
        'addresses': {SupportedChains.ethereumSepolia.id: _sepoliaAddress},
      });

      expect(wallet.addressFor(SupportedChains.ethereumSepolia), _sepoliaAddress);
      expect(wallet.addressFor(SupportedChains.polygonAmoy), isNull);
      expect(wallet.addresses, hasLength(1));
    });

    test('新盘没有 address 键时照常加载', () {
      final wallet = Wallet.fromJson({
        'id': 'w1',
        'name': '测试钱包',
        'source': 'mnemonic',
        'addresses': {SupportedChains.ethereumSepolia.id: _sepoliaAddress},
      });

      expect(wallet.addressFor(SupportedChains.ethereumSepolia), _sepoliaAddress);
      expect(wallet.toJson().containsKey('address'), isFalse);
    });

    test('toJson 不再写出 address', () {
      final wallet = Wallet(
        id: 'w1',
        name: '测试钱包',
        addresses: {SupportedChains.ethereumSepolia.id: _sepoliaAddress},
      );

      expect(wallet.toJson().containsKey('address'), isFalse);
    });

    test('老 JSON 往返后 EVM 地址仍在，且不再依赖 address 键', () {
      final first = Wallet.fromJson({
        'id': 'w1',
        'name': '测试钱包',
        'address': _legacyAddress,
        'source': 'mnemonic',
      });
      final stored = first.toJson();
      expect(stored.containsKey('address'), isFalse);

      final second = Wallet.fromJson(stored);
      for (final chain in _evmChains) {
        expect(second.addressFor(chain), _legacyAddress, reason: '${chain.id} 往返后应仍在');
      }
    });

    test('空 address 或缺失时不编造地址', () {
      expect(Wallet.fromJson({'id': 'w1', 'name': 'W', 'addresses': const {}}).addresses, isEmpty);
      expect(Wallet.fromJson({'id': 'w1', 'name': 'W', 'address': ''}).addresses, isEmpty);
      expect(Wallet.fromJson({'id': 'w1', 'name': 'W'}).addresses, isEmpty);
    });

    test('chainId 改名先于老字段补洞：有 tron-shasta 时不拿 address 填 EVM', () {
      const tron = 'TYAYRLQjBst1fPc6nziUVCebt5vwXUeLqK';
      final wallet = Wallet.fromJson({
        'id': 'w1',
        'name': '测试钱包',
        'address': _legacyAddress,
        'source': 'mnemonic',
        'addresses': {'tron-shasta': tron},
      });

      expect(wallet.addressFor(SupportedChains.tronNile), tron);
      expect(wallet.addressFor(SupportedChains.ethereumSepolia), isNull);
    });
  });
}
