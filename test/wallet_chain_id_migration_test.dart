import 'package:flutter_test/flutter_test.dart';
import 'package:wallet/blockchain/chain_registry.dart';
import 'package:wallet/domain/wallet.dart';

/// 地址按 chainId 存盘，而 `addressFor` 只按 [Chain.id] 查、加载时不会重新派生。
/// 所以换测试网时若只改 id 不迁移老数据，用户钱包里该链的地址会**直接消失**——
/// 首页和发送列表都不再显示，且没有任何报错。这组用例就是钉住这件事。
Wallet _fromStored(Map<String, String> addresses) => Wallet.fromJson({
  'id': 'w1',
  'name': '测试钱包',
  'source': 'mnemonic',
  'addresses': addresses,
});

const _tronAddress = 'TYAYRLQjBst1fPc6nziUVCebt5vwXUeLqK';

void main() {
  group('chainId 迁移（tron-shasta → tron-nile）', () {
    test('老数据的 Tron 地址迁移到新 chainId 后仍能查到', () {
      final wallet = _fromStored({'tron-shasta': _tronAddress});

      // 地址值不变：Tron 地址与网络无关，同一个 T... 在 Shasta / Nile / 主网通用。
      expect(wallet.addressFor(SupportedChains.tronNile), _tronAddress);
      expect(wallet.addresses['tron-nile'], _tronAddress);
    });

    test('旧键迁移后不再保留，避免两份并存各自漂移', () {
      final wallet = _fromStored({'tron-shasta': _tronAddress});
      expect(wallet.addresses.containsKey('tron-shasta'), isFalse);
    });

    test('新键已存在时不被旧键覆盖', () {
      const fresh = 'TKEm4LHnRUtssmwXYSYaUGxND1PyXfo9UF';
      final wallet = _fromStored({'tron-shasta': _tronAddress, 'tron-nile': fresh});
      expect(wallet.addressFor(SupportedChains.tronNile), fresh);
    });

    test('其余链的地址不受影响', () {
      const evm = '0x9858EfFD232B4033E47d90003D41EC34EcaEda94';
      final wallet = _fromStored({'tron-shasta': _tronAddress, 'ethereum-sepolia': evm});

      expect(wallet.addressFor(SupportedChains.ethereumSepolia), evm);
      expect(wallet.addressFor(SupportedChains.tronNile), _tronAddress);
      expect(wallet.addresses, hasLength(2));
    });

    test('没有老数据时照常工作', () {
      expect(_fromStored(const {}).addresses, isEmpty);
      final onlyNew = _fromStored({'tron-nile': _tronAddress});
      expect(onlyNew.addressFor(SupportedChains.tronNile), _tronAddress);
    });

    // 新建钱包走的是派生而非迁移，这条确认注册表里已经没有 shasta 的痕迹。
    test('链注册表里不再有 tron-shasta', () {
      expect(SupportedChains.all.where((c) => c.id == 'tron-shasta'), isEmpty);
      expect(SupportedChains.byId('tron-nile').endpoint, 'https://nile.trongrid.io');
    });
  });
}
