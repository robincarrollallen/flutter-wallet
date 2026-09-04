import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override; // riverpod 3 把 Override 挪到了这个入口
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wallet/data/datasource/local/secure_wallet_storage.dart';
import 'package:wallet/domain/wallet.dart';
import 'package:wallet/providers/modules/wallet_provider.dart';
import 'package:wallet/providers/prefs_provider.dart';
import 'package:wallet/services/wallet_commit_service.dart';

/// 内存版安全存储：可注入「写入抛异常」与「写入静默丢弃」两种故障，
/// 用来覆盖 Keychain / Keystore 真实世界里的两类失败模式。
class _FakeSecureStoragePlatform extends FlutterSecureStoragePlatform with MockPlatformInterfaceMixin {
  _FakeSecureStoragePlatform({this.initial = const {}}) : store = {...initial};

  final Map<String, String> initial;
  final Map<String, String> store;

  /// true 时 write 抛异常（模拟存储不可用）。
  bool throwOnWrite = false;

  /// true 时 write 正常返回但不落数据（模拟 Keystore 静默失败）。
  bool silentlyDropWrites = false;

  /// true 时 read 抛异常（模拟设备锁定期间不可读）。
  bool throwOnRead = false;

  /// true 时 delete 抛异常（模拟回滚阶段自身再次失败）。
  bool throwOnDelete = false;

  /// true 时 readAll 抛异常（模拟启动对账时安全存储不可用）。
  bool throwOnReadAll = false;

  @override
  Future<void> write({required String key, required String value, required Map<String, String> options}) async {
    if (throwOnWrite) throw Exception('secure storage unavailable');
    if (silentlyDropWrites) return;
    store[key] = value;
  }

  @override
  Future<String?> read({required String key, required Map<String, String> options}) async {
    if (throwOnRead) throw Exception('secure storage locked');
    return store[key];
  }

  @override
  Future<bool> containsKey({required String key, required Map<String, String> options}) async =>
      store.containsKey(key);

  @override
  Future<void> delete({required String key, required Map<String, String> options}) async {
    if (throwOnDelete) throw Exception('secure storage delete failed');
    store.remove(key);
  }

  @override
  Future<Map<String, String>> readAll({required Map<String, String> options}) async {
    if (throwOnReadAll) throw Exception('secure storage unavailable');
    return {...store};
  }

  @override
  Future<void> deleteAll({required Map<String, String> options}) async => store.clear();
}

/// 元数据落盘失败：模拟钱包入列表这一步抛异常。
class _ThrowingWalletListNotifier extends WalletListNotifier {
  @override
  void add(Wallet wallet) => throw Exception('prefs write failed');
}

/// 选中态写入失败：模拟提交最后一步抛异常——此时钱包已入列表，回滚必须把它摘掉。
class _ThrowingCurrentWalletIdNotifier extends CurrentWalletIdNotifier {
  /// 回滚时的恢复调用不能也抛，否则测不出「列表被摘掉」这一步。
  bool _armed = true;

  @override
  void select(String? id) {
    if (_armed) {
      _armed = false;
      throw Exception('prefs write failed');
    }
    super.select(id);
  }
}

Wallet _wallet(String id) => Wallet(id: id, name: 'W-$id', address: '0xabc', addresses: const {'evm': '0xabc'});

/// 组装一个注入了假安全存储的容器。
Future<(ProviderContainer, _FakeSecureStoragePlatform)> _setUp({
  Map<String, Object> prefs = const {},
  Map<String, String> secrets = const {},
  List<Override> overrides = const [],
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final sharedPreferences = await SharedPreferences.getInstance();

  final platform = _FakeSecureStoragePlatform(initial: secrets);
  FlutterSecureStoragePlatform.instance = platform;

  final container = ProviderContainer(
    overrides: [
      sharedPrefsProvider.overrideWithValue(sharedPreferences),
      secureWalletStorageProvider.overrideWithValue(SecureWalletStorage(const FlutterSecureStorage())),
      ...overrides,
    ],
  );
  addTearDown(container.dispose);
  return (container, platform);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('commit', () {
    test('全部成功：钱包入列表、被选中、助记词可读回', () async {
      final (container, platform) = await _setUp();
      final wallet = _wallet('w1');

      await container.read(walletCommitServiceProvider).commit(wallet: wallet, mnemonic: 'abandon ability able');

      expect(container.read(walletListProvider).map((w) => w.id), ['w1']);
      expect(container.read(currentWalletIdProvider), 'w1');
      expect(platform.store['wallet.w1.mnemonic'], 'abandon ability able');
    });

    test('敏感数据写入抛异常：报 secretWriteFailed，且不留任何痕迹', () async {
      final (container, platform) = await _setUp();
      // 预置一个已有钱包并选中，验证回滚恢复的是「原选中项」而非 null。
      final existing = _wallet('old');
      container.read(walletListProvider.notifier).add(existing);
      container.read(currentWalletIdProvider.notifier).select('old');

      platform.throwOnWrite = true;

      await expectLater(
        container.read(walletCommitServiceProvider).commit(wallet: _wallet('w1'), mnemonic: 'seed'),
        throwsA(
          isA<WalletCommitException>().having((e) => e.reason, 'reason', WalletCommitFailure.secretWriteFailed),
        ),
      );

      expect(container.read(walletListProvider).map((w) => w.id), ['old']);
      expect(container.read(currentWalletIdProvider), 'old');
      expect(platform.store.keys.where((k) => k.contains('w1')), isEmpty);
    });

    test('写入静默失败：回读校验拦截，不产生砖块钱包', () async {
      final (container, platform) = await _setUp();
      platform.silentlyDropWrites = true;

      await expectLater(
        container.read(walletCommitServiceProvider).commit(wallet: _wallet('w1'), mnemonic: 'seed'),
        throwsA(
          isA<WalletCommitException>().having((e) => e.reason, 'reason', WalletCommitFailure.secretWriteFailed),
        ),
      );

      expect(container.read(walletListProvider), isEmpty);
      expect(container.read(currentWalletIdProvider), isNull);
    });

    test('私钥导入：只写私钥，不写助记词', () async {
      final (container, platform) = await _setUp();

      await container.read(walletCommitServiceProvider).commit(wallet: _wallet('w1'), privateKey: '0xdeadbeef');

      expect(platform.store['wallet.w1.pk'], '0xdeadbeef');
      expect(platform.store.containsKey('wallet.w1.mnemonic'), isFalse);
    });

    test('回读时安全存储不可读：同样归因 secretWriteFailed 并回滚', () async {
      final (container, platform) = await _setUp();
      platform.throwOnRead = true;

      await expectLater(
        container.read(walletCommitServiceProvider).commit(wallet: _wallet('w1'), mnemonic: 'seed'),
        throwsA(
          isA<WalletCommitException>().having((e) => e.reason, 'reason', WalletCommitFailure.secretWriteFailed),
        ),
      );
      expect(container.read(walletListProvider), isEmpty);
    });

    test('元数据落盘失败：报 persistFailed，且已写入的密钥被清掉', () async {
      final (container, platform) = await _setUp(
        overrides: [walletListProvider.overrideWith(_ThrowingWalletListNotifier.new)],
      );

      await expectLater(
        container.read(walletCommitServiceProvider).commit(wallet: _wallet('w1'), mnemonic: 'seed'),
        throwsA(isA<WalletCommitException>().having((e) => e.reason, 'reason', WalletCommitFailure.persistFailed)),
      );

      // 密钥已经写进去了，回滚必须把它删掉，否则就是孤儿。
      expect(platform.store, isEmpty);
      expect(container.read(walletListProvider), isEmpty);
      expect(container.read(currentWalletIdProvider), isNull);
    });

    test('选中态写入失败：已入列表的钱包被摘掉，密钥一并清除', () async {
      final (container, platform) = await _setUp(
        overrides: [currentWalletIdProvider.overrideWith(_ThrowingCurrentWalletIdNotifier.new)],
      );

      await expectLater(
        container.read(walletCommitServiceProvider).commit(wallet: _wallet('w1'), mnemonic: 'seed'),
        throwsA(isA<WalletCommitException>().having((e) => e.reason, 'reason', WalletCommitFailure.persistFailed)),
      );

      // 这是最容易漏的一条：失败发生在钱包已经进入列表之后。
      expect(container.read(walletListProvider), isEmpty);
      expect(platform.store, isEmpty);
    });

    test('回滚自身失败：仍抛出原始失败原因，不吞不挂', () async {
      final (container, platform) = await _setUp(
        overrides: [walletListProvider.overrideWith(_ThrowingWalletListNotifier.new)],
      );
      platform.throwOnDelete = true; // 回滚里的 deleteSecrets 也失败

      await expectLater(
        container.read(walletCommitServiceProvider).commit(wallet: _wallet('w1'), mnemonic: 'seed'),
        throwsA(isA<WalletCommitException>().having((e) => e.reason, 'reason', WalletCommitFailure.persistFailed)),
      );

      // 密钥删不掉是可接受的降级——它会在下次启动被对账清理。
      expect(platform.store.keys, ['wallet.w1.mnemonic']);
    });

    test('失败后可重试：第二次提交正常成功', () async {
      final (container, platform) = await _setUp();
      platform.throwOnWrite = true;

      await expectLater(
        container.read(walletCommitServiceProvider).commit(wallet: _wallet('w1'), mnemonic: 'seed'),
        throwsA(isA<WalletCommitException>()),
      );

      platform.throwOnWrite = false;
      await container.read(walletCommitServiceProvider).commit(wallet: _wallet('w1'), mnemonic: 'seed');

      expect(container.read(walletListProvider).map((w) => w.id), ['w1']);
      expect(platform.store['wallet.w1.mnemonic'], 'seed');
    });

    test('连续提交多个钱包：列表累积，选中项指向最后一个', () async {
      final (container, _) = await _setUp();
      final service = container.read(walletCommitServiceProvider);

      await service.commit(wallet: _wallet('w1'), mnemonic: 'seed1');
      await service.commit(wallet: _wallet('w2'), mnemonic: 'seed2');

      expect(container.read(walletListProvider).map((w) => w.id), ['w1', 'w2']);
      expect(container.read(currentWalletIdProvider), 'w2');
    });
  });

  group('purgeOrphanSecrets', () {
    test('删除无钱包引用的孤儿密钥', () async {
      final (container, platform) = await _setUp(
        secrets: {'wallet.ghost.mnemonic': 'orphan seed', 'wallet.ghost2.pk': '0xorphan'},
      );

      expect(await container.read(walletCommitServiceProvider).purgeOrphanSecrets(), 2);
      expect(platform.store, isEmpty);
    });

    test('保留在列表中的钱包的密钥，不误删', () async {
      final (container, platform) = await _setUp(
        secrets: {'wallet.keep.mnemonic': 'good seed', 'wallet.ghost.mnemonic': 'orphan seed'},
      );
      container.read(walletListProvider.notifier).add(_wallet('keep'));

      expect(await container.read(walletCommitServiceProvider).purgeOrphanSecrets(), 1);
      expect(platform.store, {'wallet.keep.mnemonic': 'good seed'});
    });

    test('不触碰不属于本类键格式的数据', () async {
      final (container, platform) = await _setUp(secrets: {'security.password': 'hash', 'unrelated': 'x'});

      expect(await container.read(walletCommitServiceProvider).purgeOrphanSecrets(), 0);
      expect(platform.store.length, 2);
    });

    test('walletId 含点号时仍能正确切分，不误删', () async {
      final (container, platform) = await _setUp(
        secrets: {'wallet.a.b.mnemonic': 'keep me', 'wallet.c.d.pk': 'orphan'},
      );
      container.read(walletListProvider.notifier).add(_wallet('a.b'));

      expect(await container.read(walletCommitServiceProvider).purgeOrphanSecrets(), 1);
      expect(platform.store.keys, ['wallet.a.b.mnemonic']);
    });

    test('同一钱包的助记词与私钥都是孤儿时，两条都删', () async {
      final (container, platform) = await _setUp(
        secrets: {'wallet.ghost.mnemonic': 'seed', 'wallet.ghost.pk': '0x1'},
      );

      expect(await container.read(walletCommitServiceProvider).purgeOrphanSecrets(), 2);
      expect(platform.store, isEmpty);
    });

    test('幂等：无孤儿时重复执行返回 0，不改动数据', () async {
      final (container, platform) = await _setUp(secrets: {'wallet.keep.mnemonic': 'seed'});
      container.read(walletListProvider.notifier).add(_wallet('keep'));
      final service = container.read(walletCommitServiceProvider);

      expect(await service.purgeOrphanSecrets(), 0);
      expect(await service.purgeOrphanSecrets(), 0);
      expect(platform.store, {'wallet.keep.mnemonic': 'seed'});
    });

    test('安全存储不可用时抛出，由 main 的 try/catch 兜底不阻塞启动', () async {
      final (container, platform) = await _setUp();
      platform.throwOnReadAll = true;

      await expectLater(container.read(walletCommitServiceProvider).purgeOrphanSecrets(), throwsException);
    });
  });

  group('崩溃残留场景（端到端）', () {
    test('密钥已写、元数据未落盘就被杀：重启后对账清掉孤儿助记词', () async {
      // 第一段生命周期：只让密钥落地，元数据写入失败（等价于写元数据前进程被杀）。
      final (crashed, platform) = await _setUp(
        overrides: [walletListProvider.overrideWith(_ThrowingWalletListNotifier.new)],
      );
      platform.throwOnDelete = true; // 连回滚也没机会执行，密钥就此残留
      await expectLater(
        crashed.read(walletCommitServiceProvider).commit(wallet: _wallet('w1'), mnemonic: 'lost seed'),
        throwsA(isA<WalletCommitException>()),
      );
      expect(platform.store['wallet.w1.mnemonic'], 'lost seed', reason: '前置条件：孤儿密钥确实残留了');

      // 第二段生命周期：新容器 + 空的钱包列表，等价于重启后的启动对账。
      platform.throwOnDelete = false;
      SharedPreferences.setMockInitialValues({});
      final restarted = ProviderContainer(
        overrides: [
          sharedPrefsProvider.overrideWithValue(await SharedPreferences.getInstance()),
          secureWalletStorageProvider.overrideWithValue(SecureWalletStorage(const FlutterSecureStorage())),
        ],
      );
      addTearDown(restarted.dispose);

      expect(await restarted.read(walletCommitServiceProvider).purgeOrphanSecrets(), 1);
      expect(platform.store, isEmpty, reason: '重启后孤儿助记词已被清理，敏感数据不留在设备上');
    });

    test('提交成功后重启：对账不会误删正常钱包的助记词', () async {
      final (first, platform) = await _setUp();
      await first.read(walletCommitServiceProvider).commit(wallet: _wallet('w1'), mnemonic: 'good seed');

      // 用第一段生命周期真实落盘的 prefs 重建容器，模拟重启。
      final persisted = first.read(sharedPrefsProvider);
      final restarted = ProviderContainer(
        overrides: [
          sharedPrefsProvider.overrideWithValue(persisted),
          secureWalletStorageProvider.overrideWithValue(SecureWalletStorage(const FlutterSecureStorage())),
        ],
      );
      addTearDown(restarted.dispose);

      expect(restarted.read(walletListProvider).map((w) => w.id), ['w1'], reason: '前置条件：钱包元数据确实恢复了');
      expect(await restarted.read(walletCommitServiceProvider).purgeOrphanSecrets(), 0);
      expect(platform.store['wallet.w1.mnemonic'], 'good seed');
    });
  });
}
