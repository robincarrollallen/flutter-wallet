import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wallet/domain/wallet.dart';
import 'package:wallet/providers/core/prefs_provider.dart';
import 'package:wallet/providers/modules/wallet/wallet_provider.dart';

class _FakeStore extends FlutterSecureStoragePlatform with MockPlatformInterfaceMixin {
  final Map<String, String> store = {};

  /// true 时 delete 抛异常（模拟设备锁定 / 存储不可用）。
  bool throwOnDelete = false;
  @override
  Future<void> write({required String key, required String value, required Map<String, String> options}) async =>
      store[key] = value;
  @override
  Future<String?> read({required String key, required Map<String, String> options}) async => store[key];
  @override
  Future<bool> containsKey({required String key, required Map<String, String> options}) async =>
      store.containsKey(key);
  @override
  Future<void> delete({required String key, required Map<String, String> options}) async {
    if (throwOnDelete) throw Exception('secure storage delete failed');
    store.remove(key);
  }
  @override
  Future<Map<String, String>> readAll({required Map<String, String> options}) async => {...store};
  @override
  Future<void> deleteAll({required Map<String, String> options}) async => store.clear();
}

Wallet _w(String id) => Wallet(id: id, name: 'W-$id', addresses: const {'evm': '0xabc'});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeStore secureStore;

  Future<ProviderContainer> build() async {
    SharedPreferences.setMockInitialValues({});
    secureStore = _FakeStore();
    FlutterSecureStoragePlatform.instance = secureStore;
    final c = ProviderContainer(
      overrides: [sharedPrefsProvider.overrideWithValue(await SharedPreferences.getInstance())],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('adapter 的每个方法都真的落到 notifier 上', () async {
    final c = await build();
    final registry = c.read(walletRegistryProvider);

    expect(registry.currentWalletId, isNull);
    expect(registry.knownWalletIds, isEmpty);
    expect(registry.contains('w1'), isFalse);

    registry.add(_w('w1'));
    registry.add(_w('w2'));
    expect(c.read(walletListProvider).map((w) => w.id), ['w1', 'w2']);
    expect(registry.knownWalletIds, {'w1', 'w2'});
    expect(registry.contains('w1'), isTrue);

    registry.select('w1');
    expect(c.read(currentWalletIdProvider), 'w1');
    expect(registry.currentWalletId, 'w1');

    await registry.remove('w1');
    expect(c.read(walletListProvider).map((w) => w.id), ['w2']);
    expect(registry.contains('w1'), isFalse);

    registry.select(null);
    expect(registry.currentWalletId, isNull);
  });

  test('registry 不因钱包列表变化而重建（否则 commitService 会跟着churn）', () async {
    final c = await build();
    final first = c.read(walletRegistryProvider);
    first.add(_w('w1'));
    first.select('w1');
    expect(identical(c.read(walletRegistryProvider), first), isTrue);
  });

  // remove 里删密钥这一步曾经是 fire-and-forget：失败会变成没人接得住的异步异常，
  // 连 WalletCommitService._rollback 外面那层 try/catch 都拦不住。
  test('删密钥失败时，错误由 remove 的 Future 带出来，而不是变成未捕获异常', () async {
    final c = await build();
    final registry = c.read(walletRegistryProvider);
    registry.add(_w('w1'));

    secureStore.throwOnDelete = true;

    await expectLater(registry.remove('w1'), throwsException);
    expect(c.read(walletListProvider), isEmpty, reason: '列表照样要摘干净，残留密钥交给启动对账');
  });
}
