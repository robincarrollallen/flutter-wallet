import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wallet/blockchain/chain_registry.dart';
import 'package:wallet/providers/modules/transaction/evm_fee_provider.dart';
import 'package:wallet/providers/core/prefs_provider.dart';
import 'package:wallet/providers/core/service_provider.dart';
import 'package:wallet/services/evm_transaction_service.dart';

const _chain = SupportedChains.ethereumSepolia;
const _from = '0x1111111111111111111111111111111111111111';

/// 假节点：baseFee / 小费固定，gasLimit 可逐次改，并能整体切到「网络故障」。
class _FakeNode {
  _FakeNode({this.gasEstimate = '0xfde8'});

  String gasEstimate;

  /// true 时所有 RPC 抛异常，模拟网络抖动。
  bool down = false;

  Future<Object?> call(String url, String method, List<Object?> params) async {
    if (down) throw Exception('network down');
    return switch (method) {
      'eth_getBlockByNumber' => {'baseFeePerGas': '0x3b9aca00'}, // 1 gwei
      'eth_feeHistory' => {
        'reward': [
          ['0x3b9aca00', '0x3b9aca00', '0x3b9aca00'],
        ],
      },
      'eth_getCode' => '0x', // 收款方是 EOA，走固定 21000
      'eth_estimateGas' => gasEstimate,
      _ => throw StateError('未预期的 RPC 方法：$method'),
    };
  }
}

EvmFeeKey _key(String to, {String? token}) => (chainId: _chain.id, from: _from, to: to, tokenIdentifier: token);

/// 收款地址由序号生成，用来把 gasLimit 缓存填满。
String _address(int index) => '0x${index.toRadixString(16).padLeft(40, '0')}';

Future<ProviderContainer> _setUp(_FakeNode node) async {
  SharedPreferences.setMockInitialValues({});
  final container = ProviderContainer(
    overrides: [
      sharedPrefsProvider.overrideWithValue(await SharedPreferences.getInstance()),
      // 正是这次解耦留出的注入点：换掉链上读写，不碰真实节点。
      evmTransactionServiceProvider.overrideWithValue(EvmTransactionService(call: node.call)),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('refresh 成功：写入该链的费率基准与该收款方的 gasLimit', () async {
    final node = _FakeNode();
    final container = await _setUp(node);
    final key = _key(_address(1));

    await container.read(evmGasBasisProvider.notifier).refresh(key);

    final cache = container.read(evmGasBasisProvider);
    expect(cache.basis.containsKey(_chain.id), isTrue);
    expect(cache.gasLimits[EvmGasBasisNotifier.gasLimitKey(key)], BigInt.from(21000));
  });

  test('网络故障：保留上一次的报价，不清空成 `--`', () async {
    final node = _FakeNode();
    final container = await _setUp(node);
    final key = _key(_address(1));

    await container.read(evmGasBasisProvider.notifier).refresh(key);
    final before = container.read(evmGasBasisProvider);

    node.down = true;
    await container.read(evmGasBasisProvider.notifier).refresh(key);

    final after = container.read(evmGasBasisProvider);
    expect(after.basis[_chain.id], before.basis[_chain.id]);
    expect(after.gasLimits, before.gasLimits);
  });

  test('gasLimit 缓存超出上限：淘汰最久没用到的那条', () async {
    final node = _FakeNode();
    final container = await _setUp(node);
    final notifier = container.read(evmGasBasisProvider.notifier);

    // 填满 30 条，再多刷一条，最早的 #0 应被挤出去。
    for (var i = 0; i < 31; i++) {
      await notifier.refresh(_key(_address(i)));
    }

    final gasLimits = container.read(evmGasBasisProvider).gasLimits;
    expect(gasLimits.length, 30);
    expect(gasLimits.containsKey(EvmGasBasisNotifier.gasLimitKey(_key(_address(0)))), isFalse);
    expect(gasLimits.containsKey(EvmGasBasisNotifier.gasLimitKey(_key(_address(30)))), isTrue);
  });

  test('重新用到的条目排回队尾，淘汰的是真正最久没用的那条', () async {
    final node = _FakeNode();
    final container = await _setUp(node);
    final notifier = container.read(evmGasBasisProvider.notifier);

    for (var i = 0; i < 30; i++) {
      await notifier.refresh(_key(_address(i)));
    }
    await notifier.refresh(_key(_address(0))); // #0 重新用到
    await notifier.refresh(_key(_address(99))); // 触发一次淘汰

    final gasLimits = container.read(evmGasBasisProvider).gasLimits;
    expect(gasLimits.containsKey(EvmGasBasisNotifier.gasLimitKey(_key(_address(0)))), isTrue);
    expect(gasLimits.containsKey(EvmGasBasisNotifier.gasLimitKey(_key(_address(1)))), isFalse, reason: '#1 才是最久没用的');
  });
}
