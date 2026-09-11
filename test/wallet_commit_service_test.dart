import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override; // riverpod 3 把 Override 挪到了这个入口
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wallet/data/datasource/local/secure_wallet_storage.dart';
import 'package:wallet/domain/wallet.dart';
import 'package:wallet/providers/modules/wallet/wallet_provider.dart';
import 'package:wallet/providers/core/prefs_provider.dart';
import 'package:wallet/providers/core/service_provider.dart';
import 'package:wallet/services/wallet_commit_service.dart';
import 'package:wallet/services/wallet_registry.dart';

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

/// 内存版钱包列表 / 选中态，行为对齐 [WalletListNotifier] 与 [CurrentWalletIdNotifier]
/// （包括 remove 会连带清除敏感数据），并可注入元数据写入失败。
class _FakeWalletRegistry implements WalletRegistry {
  _FakeWalletRegistry(this._storage);

  final SecureWalletStorage _storage;
  final List<Wallet> wallets = [];
  String? selectedId;

  /// true 时 [add] 抛异常（模拟钱包元数据落盘失败）。
  bool throwOnAdd = false;

  /// true 时 [select] 抛异常一次（模拟选中态落盘失败）。
  /// 只抛一次：回滚时的恢复调用必须能正常执行，否则测不出「列表被摘掉」这一步。
  bool throwOnFirstSelect = false;

  /// false 模拟「钱包列表键不存在 / 已损坏」，即删 App 重装后的首次启动。
  bool listTrusted = true;

  @override
  String? get currentWalletId => selectedId;

  @override
  bool get walletListTrusted => listTrusted;

  @override
  bool contains(String walletId) => wallets.any((w) => w.id == walletId);

  @override
  Set<String> get knownWalletIds => wallets.map((w) => w.id).toSet();

  @override
  void add(Wallet wallet) {
    if (throwOnAdd) throw Exception('prefs write failed');
    wallets.add(wallet);
  }

  @override
  Future<void> remove(String walletId) async {
    wallets.removeWhere((w) => w.id == walletId);
    await _storage.deleteSecrets(walletId);
  }

  @override
  void select(String? walletId) {
    if (throwOnFirstSelect) {
      throwOnFirstSelect = false;
      throw Exception('prefs write failed');
    }
    selectedId = walletId;
  }
}

/// 元数据落盘失败：模拟钱包入列表这一步抛异常。（仅端到端组用）
class _ThrowingWalletListNotifier extends WalletListNotifier {
  @override
  void add(Wallet wallet) => throw Exception('prefs write failed');
}

Wallet _wallet(String id) => Wallet(id: id, name: 'W-$id', addresses: const {'evm': '0xabc'});

/// 组装被测 service：假安全存储 + 假钱包列表，不经过 Riverpod。
(WalletCommitService, _FakeWalletRegistry, _FakeSecureStoragePlatform) _build({
  Map<String, String> secrets = const {},
}) {
  final platform = _FakeSecureStoragePlatform(initial: secrets);
  FlutterSecureStoragePlatform.instance = platform;

  final storage = SecureWalletStorage(const FlutterSecureStorage());
  final registry = _FakeWalletRegistry(storage);
  return (WalletCommitService(registry, storage), registry, platform);
}

/// 端到端场景专用：走真实 notifier + SharedPreferences 的容器。
Future<(ProviderContainer, _FakeSecureStoragePlatform)> _setUpContainer({
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
      final (service, registry, platform) = _build();
      final wallet = _wallet('w1');

      await service.commit(wallet: wallet, mnemonic: 'abandon ability able');

      expect(registry.wallets.map((w) => w.id), ['w1']);
      expect(registry.selectedId, 'w1');
      expect(platform.store['wallet.w1.mnemonic'], 'abandon ability able');
    });

    test('敏感数据写入抛异常：报 secretWriteFailed，且不留任何痕迹', () async {
      final (service, registry, platform) = _build();
      // 预置一个已有钱包并选中，验证回滚恢复的是「原选中项」而非 null。
      registry.add(_wallet('old'));
      registry.select('old');

      platform.throwOnWrite = true;

      await expectLater(
        service.commit(wallet: _wallet('w1'), mnemonic: 'seed'),
        throwsA(
          isA<WalletCommitException>().having((e) => e.reason, 'reason', WalletCommitFailure.secretWriteFailed),
        ),
      );

      expect(registry.wallets.map((w) => w.id), ['old']);
      expect(registry.selectedId, 'old');
      expect(platform.store.keys.where((k) => k.contains('w1')), isEmpty);
    });

    test('写入静默失败：回读校验拦截，不产生砖块钱包', () async {
      final (service, registry, platform) = _build();
      platform.silentlyDropWrites = true;

      await expectLater(
        service.commit(wallet: _wallet('w1'), mnemonic: 'seed'),
        throwsA(
          isA<WalletCommitException>().having((e) => e.reason, 'reason', WalletCommitFailure.secretWriteFailed),
        ),
      );

      expect(registry.wallets, isEmpty);
      expect(registry.selectedId, isNull);
    });

    test('私钥导入：只写私钥，不写助记词', () async {
      final (service, _, platform) = _build();

      await service.commit(wallet: _wallet('w1'), privateKey: '0xdeadbeef');

      expect(platform.store['wallet.w1.pk'], '0xdeadbeef');
      expect(platform.store.containsKey('wallet.w1.mnemonic'), isFalse);
    });

    test('回读时安全存储不可读：同样归因 secretWriteFailed 并回滚', () async {
      final (service, registry, platform) = _build();
      platform.throwOnRead = true;

      await expectLater(
        service.commit(wallet: _wallet('w1'), mnemonic: 'seed'),
        throwsA(
          isA<WalletCommitException>().having((e) => e.reason, 'reason', WalletCommitFailure.secretWriteFailed),
        ),
      );
      expect(registry.wallets, isEmpty);
    });

    test('元数据落盘失败：报 persistFailed，且已写入的密钥被清掉', () async {
      final (service, registry, platform) = _build();
      registry.throwOnAdd = true;

      await expectLater(
        service.commit(wallet: _wallet('w1'), mnemonic: 'seed'),
        throwsA(isA<WalletCommitException>().having((e) => e.reason, 'reason', WalletCommitFailure.persistFailed)),
      );

      // 密钥已经写进去了，回滚必须把它删掉，否则就是孤儿。
      expect(platform.store, isEmpty);
      expect(registry.wallets, isEmpty);
      expect(registry.selectedId, isNull);
    });

    test('选中态写入失败：已入列表的钱包被摘掉，密钥一并清除', () async {
      final (service, registry, platform) = _build();
      registry.throwOnFirstSelect = true;

      await expectLater(
        service.commit(wallet: _wallet('w1'), mnemonic: 'seed'),
        throwsA(isA<WalletCommitException>().having((e) => e.reason, 'reason', WalletCommitFailure.persistFailed)),
      );

      // 这是最容易漏的一条：失败发生在钱包已经进入列表之后。
      expect(registry.wallets, isEmpty);
      expect(platform.store, isEmpty);
    });

    test('回滚自身失败：仍抛出原始失败原因，不吞不挂', () async {
      final (service, registry, platform) = _build();
      registry.throwOnAdd = true;
      platform.throwOnDelete = true; // 回滚里的 deleteSecrets 也失败

      await expectLater(
        service.commit(wallet: _wallet('w1'), mnemonic: 'seed'),
        throwsA(isA<WalletCommitException>().having((e) => e.reason, 'reason', WalletCommitFailure.persistFailed)),
      );

      // 密钥删不掉是可接受的降级——它连同提交标记一起留下，下次启动的对账认标记清理。
      expect(platform.store.keys, containsAll(['wallet.w1.mnemonic', 'wallet.w1.pending']));
    });

    test('提交成功后撤下提交标记：这份密钥从此不再具备被对账删除的资格', () async {
      final (service, _, platform) = _build();

      await service.commit(wallet: _wallet('w1'), mnemonic: 'seed');

      expect(platform.store.containsKey('wallet.w1.pending'), isFalse);
      expect(platform.store['wallet.w1.mnemonic'], 'seed');
    });

    test('提交标记写不上时直接失败，绝不继续写密钥', () async {
      final (service, registry, platform) = _build();
      platform.throwOnWrite = true;

      await expectLater(
        service.commit(wallet: _wallet('w1'), mnemonic: 'seed'),
        throwsA(
          isA<WalletCommitException>().having((e) => e.reason, 'reason', WalletCommitFailure.secretWriteFailed),
        ),
      );

      // 没有标记的密钥永远清不掉，所以宁可整笔提交失败，也不能留下这种残留。
      expect(platform.store, isEmpty);
      expect(registry.wallets, isEmpty);
    });

    test('撤标记失败不影响提交结果，遗留标记由对账自愈', () async {
      final (service, registry, platform) = _build();
      platform.throwOnDelete = true;

      await service.commit(wallet: _wallet('w1'), mnemonic: 'seed');

      expect(registry.wallets.map((w) => w.id), ['w1'], reason: '元数据已生效，用户视角就是成功了');
      expect(platform.store['wallet.w1.pending'], isNotNull, reason: '标记残留');

      // 下一次对账：钱包在列表里，只清标记、不碰密钥。
      platform.throwOnDelete = false;
      expect(await service.purgeOrphanSecrets(), 0);
      expect(platform.store, {'wallet.w1.mnemonic': 'seed'});
    });

    test('失败后可重试：第二次提交正常成功', () async {
      final (service, registry, platform) = _build();
      platform.throwOnWrite = true;

      await expectLater(
        service.commit(wallet: _wallet('w1'), mnemonic: 'seed'),
        throwsA(isA<WalletCommitException>()),
      );

      platform.throwOnWrite = false;
      await service.commit(wallet: _wallet('w1'), mnemonic: 'seed');

      expect(registry.wallets.map((w) => w.id), ['w1']);
      expect(platform.store['wallet.w1.mnemonic'], 'seed');
    });

    test('连续提交多个钱包：列表累积，选中项指向最后一个', () async {
      final (service, registry, _) = _build();

      await service.commit(wallet: _wallet('w1'), mnemonic: 'seed1');
      await service.commit(wallet: _wallet('w2'), mnemonic: 'seed2');

      expect(registry.wallets.map((w) => w.id), ['w1', 'w2']);
      expect(registry.selectedId, 'w2');
    });
  });

  group('purgeOrphanSecrets', () {
    test('删除带提交标记、且无钱包引用的孤儿密钥', () async {
      final (service, _, platform) = _build(
        secrets: {
          'wallet.ghost.mnemonic': 'orphan seed',
          'wallet.ghost.pending': 'at',
          'wallet.ghost2.pk': '0xorphan',
          'wallet.ghost2.pending': 'at',
        },
      );

      expect(await service.purgeOrphanSecrets(), 2, reason: '返回值只计密钥，不含标记');
      expect(platform.store, isEmpty, reason: '标记也一并清掉，不留垃圾');
    });

    // 本次修复的核心：判据是「带标记」而不是「不在列表里」。没有标记的密钥可能是
    // 删 App 重装后幸存下来的真钱包，删掉就等于销毁用户最后的恢复路径。
    test('无提交标记的密钥一律不删，哪怕不在钱包列表里', () async {
      final (service, _, platform) = _build(
        secrets: {'wallet.survivor.mnemonic': 'real money seed', 'wallet.survivor2.pk': '0xreal'},
      );

      expect(await service.purgeOrphanSecrets(), 0);
      expect(platform.store, {'wallet.survivor.mnemonic': 'real money seed', 'wallet.survivor2.pk': '0xreal'});
    });

    test('保留在列表中的钱包的密钥，不误删', () async {
      final (service, registry, platform) = _build(
        secrets: {
          'wallet.keep.mnemonic': 'good seed',
          'wallet.ghost.mnemonic': 'orphan seed',
          'wallet.ghost.pending': 'at',
        },
      );
      registry.add(_wallet('keep'));

      expect(await service.purgeOrphanSecrets(), 1);
      expect(platform.store, {'wallet.keep.mnemonic': 'good seed'});
    });

    // 撤标记那一步失败留下的陈旧标记：钱包已在列表里，说明提交其实成功了。
    test('标记残留但钱包在列表里：只清标记，密钥保留', () async {
      final (service, registry, platform) = _build(
        secrets: {'wallet.keep.mnemonic': 'good seed', 'wallet.keep.pending': 'at'},
      );
      registry.add(_wallet('keep'));

      expect(await service.purgeOrphanSecrets(), 0);
      expect(platform.store, {'wallet.keep.mnemonic': 'good seed'});
    });

    // 打完标记、密钥还没写就被杀：标记要能自己收敛掉，否则会越积越多。
    test('只有裸标记没有密钥：标记被清掉，返回 0', () async {
      final (service, _, platform) = _build(secrets: {'wallet.ghost.pending': 'at'});

      expect(await service.purgeOrphanSecrets(), 0);
      expect(platform.store, isEmpty);
    });

    test('钱包列表不可信时（删 App 重装）一条都不删', () async {
      final (service, registry, platform) = _build(
        secrets: {'wallet.ghost.mnemonic': 'orphan seed', 'wallet.ghost.pending': 'at'},
      );
      registry.listTrusted = false;

      expect(await service.purgeOrphanSecrets(), 0);
      expect(
        platform.store,
        {'wallet.ghost.mnemonic': 'orphan seed', 'wallet.ghost.pending': 'at'},
        reason: '空列表此时是「不知道」而非「确实没有」，连标记都不该动',
      );
    });

    test('不触碰不属于本类键格式的数据', () async {
      final (service, _, platform) = _build(secrets: {'security.password': 'hash', 'unrelated': 'x'});

      expect(await service.purgeOrphanSecrets(), 0);
      expect(platform.store.length, 2);
    });

    test('walletId 含点号时仍能正确切分，不误删', () async {
      final (service, registry, platform) = _build(
        secrets: {
          'wallet.a.b.mnemonic': 'keep me',
          'wallet.a.b.pending': 'at',
          'wallet.c.d.pk': 'orphan',
          'wallet.c.d.pending': 'at',
        },
      );
      registry.add(_wallet('a.b'));

      expect(await service.purgeOrphanSecrets(), 1);
      expect(platform.store.keys, ['wallet.a.b.mnemonic'], reason: 'a.b 的陈旧标记被清，密钥留下');
    });

    test('同一钱包的助记词与私钥都是孤儿时，两条都删', () async {
      final (service, _, platform) = _build(
        secrets: {'wallet.ghost.mnemonic': 'seed', 'wallet.ghost.pk': '0x1', 'wallet.ghost.pending': 'at'},
      );

      expect(await service.purgeOrphanSecrets(), 2);
      expect(platform.store, isEmpty);
    });

    // 标记的后缀与密钥键互斥，不能让它混进密钥的读取或统计里。
    test('提交标记不会被当成密钥读取', () async {
      _build(secrets: {'wallet.w1.pending': 'at'});
      final storage = SecureWalletStorage(const FlutterSecureStorage());

      expect(await storage.readMnemonic('w1'), isNull);
      expect(await storage.readPrivateKey('w1'), isNull);
      expect(await storage.hasSecrets('w1'), isFalse);
      expect(await storage.hasPendingCommit('w1'), isTrue);
    });

    test('幂等：无孤儿时重复执行返回 0，不改动数据', () async {
      final (service, registry, platform) = _build(secrets: {'wallet.keep.mnemonic': 'seed'});
      registry.add(_wallet('keep'));

      expect(await service.purgeOrphanSecrets(), 0);
      expect(await service.purgeOrphanSecrets(), 0);
      expect(platform.store, {'wallet.keep.mnemonic': 'seed'});
    });

    test('安全存储不可用时抛出，由 main 的 try/catch 兜底不阻塞启动', () async {
      final (service, _, platform) = _build();
      platform.throwOnReadAll = true;

      await expectLater(service.purgeOrphanSecrets(), throwsException);
    });
  });

  // 这一组刻意走完整的 Riverpod 装配（walletRegistryProvider → 真实 notifier →
  // SharedPreferences），因为要验的正是「跨进程重启后元数据是否真的还在」，
  // 换成假 registry 就测不到持久化那一段了。
  group('崩溃残留场景（端到端）', () {
    test('密钥已写、元数据未落盘就被杀：重启后对账清掉孤儿助记词', () async {
      // 第一段生命周期：只让密钥落地，元数据写入失败（等价于写元数据前进程被杀）。
      final (crashed, platform) = await _setUpContainer(
        overrides: [walletListProvider.overrideWith(_ThrowingWalletListNotifier.new)],
      );
      platform.throwOnDelete = true; // 连回滚也没机会执行，密钥就此残留
      await expectLater(
        crashed.read(walletCommitServiceProvider).commit(wallet: _wallet('w1'), mnemonic: 'lost seed'),
        throwsA(isA<WalletCommitException>()),
      );
      expect(platform.store['wallet.w1.mnemonic'], 'lost seed', reason: '前置条件：孤儿密钥确实残留了');
      expect(platform.store['wallet.w1.pending'], isNotNull, reason: '前置条件：提交标记也残留了，这是可清理的凭据');

      // 第二段生命周期：新容器 + 一份**确实是空的**钱包列表（键在、内容为空），
      // 等价于「用户手上真没有钱包」的重启，此时列表可信，对账照常进行。
      platform.throwOnDelete = false;
      SharedPreferences.setMockInitialValues({'flutter.wallet.list': '{"wallets":[]}'});
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

    // 本次修复的核心回归：删 App 会带走 SharedPreferences，却带不走 Keychain。
    // 此时钱包列表为空不代表用户没钱包，对账必须停手。
    test('删 App 重装（prefs 整体消失）：对账一条都不删，保住 Keychain 里的恢复路径', () async {
      final (first, platform) = await _setUpContainer();
      await first.read(walletCommitServiceProvider).commit(wallet: _wallet('w1'), mnemonic: 'real money seed');
      expect(platform.store.containsKey('wallet.w1.pending'), isFalse, reason: '前置条件：提交成功已撤下标记');

      // 第二段生命周期：prefs 容器被清空（键根本不存在），Keychain 原样保留。
      SharedPreferences.setMockInitialValues({});
      final reinstalled = ProviderContainer(
        overrides: [
          sharedPrefsProvider.overrideWithValue(await SharedPreferences.getInstance()),
          secureWalletStorageProvider.overrideWithValue(SecureWalletStorage(const FlutterSecureStorage())),
        ],
      );
      addTearDown(reinstalled.dispose);

      expect(reinstalled.read(walletListProvider), isEmpty, reason: '前置条件：钱包列表确实恢复成空');
      expect(await reinstalled.read(walletCommitServiceProvider).purgeOrphanSecrets(), 0);
      expect(
        platform.store['wallet.w1.mnemonic'],
        'real money seed',
        reason: '助记词必须活着——这是用户找回资产的唯一凭据',
      );
    });

    // 两道防线各挡一种失败：标记因撤除失败而残留时，列表不可信这一层仍要拦住删除。
    test('陈旧标记 + prefs 整体消失：列表可信度门闩仍然拦住删除', () async {
      final (first, platform) = await _setUpContainer();
      platform.throwOnDelete = true; // 撤标记失败，标记就此残留
      await first.read(walletCommitServiceProvider).commit(wallet: _wallet('w1'), mnemonic: 'real money seed');
      expect(platform.store['wallet.w1.pending'], isNotNull, reason: '前置条件：陈旧标记残留了');

      platform.throwOnDelete = false;
      SharedPreferences.setMockInitialValues({});
      final reinstalled = ProviderContainer(
        overrides: [
          sharedPrefsProvider.overrideWithValue(await SharedPreferences.getInstance()),
          secureWalletStorageProvider.overrideWithValue(SecureWalletStorage(const FlutterSecureStorage())),
        ],
      );
      addTearDown(reinstalled.dispose);

      expect(await reinstalled.read(walletCommitServiceProvider).purgeOrphanSecrets(), 0);
      expect(platform.store['wallet.w1.mnemonic'], 'real money seed');
    });

    test('提交成功后重启：对账不会误删正常钱包的助记词', () async {
      final (first, platform) = await _setUpContainer();
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
