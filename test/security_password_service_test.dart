import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:wallet/data/datasource/local/security_password_storage.dart';
import 'package:wallet/services/security_password_service.dart';

/// 内存版安全存储平台层，只需支持读写。
class _FakePlatform extends FlutterSecureStoragePlatform with MockPlatformInterfaceMixin {
  _FakePlatform({Map<String, String>? initial}) : store = {...?initial};

  final Map<String, String> store;

  @override
  Future<void> write({required String key, required String value, required Map<String, String> options}) async {
    store[key] = value;
  }

  @override
  Future<String?> read({required String key, required Map<String, String> options}) async => store[key];

  @override
  Future<bool> containsKey({required String key, required Map<String, String> options}) async => store.containsKey(key);

  @override
  Future<void> delete({required String key, required Map<String, String> options}) async => store.remove(key);

  @override
  Future<Map<String, String>> readAll({required Map<String, String> options}) async => {...store};

  @override
  Future<void> deleteAll({required Map<String, String> options}) async => store.clear();
}

/// 安全码在 Keychain 里的键名，与 [SecurityPasswordStorage] 内部一致。
const _key = 'app.security_password';

({SecurityPasswordService service, _FakePlatform platform}) _build({Map<String, String>? initial}) {
  final platform = _FakePlatform(initial: initial);
  FlutterSecureStoragePlatform.instance = platform;
  return (service: SecurityPasswordService(SecurityPasswordStorage(const FlutterSecureStorage())), platform: platform);
}

void main() {
  group('SecurityPasswordService', () {
    test('未设置过时，校验一律不通过', () async {
      final (:service, :platform) = _build();
      expect(await service.hasPassword(), isFalse);
      expect(await service.verify('123456'), isFalse);
    });

    test('落盘的是摘要，不是明文', () async {
      final (:service, :platform) = _build();
      await service.setPassword('123456');

      final record = platform.store[_key]!;
      // 最要紧的一条：口令本身不该以任何形式出现在存储里。
      expect(record, isNot(contains('123456')));
      expect(record, startsWith(r'v1$'));
      expect(await service.verify('123456'), isTrue);
      expect(await service.verify('123457'), isFalse);
    });

    test('每次设置都换新 salt，相同口令存出不同记录', () async {
      final (service: first, platform: p1) = _build();
      await first.setPassword('123456');
      final a = p1.store[_key]!;

      final (service: second, platform: p2) = _build();
      await second.setPassword('123456');
      final b = p2.store[_key]!;

      // salt 复用会让两个用同一口令的用户拥有相同摘要，也让彩虹表重新变得可用。
      expect(a, isNot(b));
    });

    test('迭代次数写在记录里，据此重算而不是读当前常量', () async {
      final (:service, :platform) = _build();
      await service.setPassword('123456');

      final parts = platform.store[_key]!.split(r'$');
      expect(parts, hasLength(4));
      expect(int.parse(parts[1]), greaterThan(0));

      // 把记录里的迭代次数改掉，摘要就对不上了——证明校验用的确实是记录里那个值，
      // 而不是服务里的常量。少了这个性质，以后调高迭代次数会锁死全部老用户。
      platform.store[_key] = [parts[0], '${int.parse(parts[1]) + 1}', parts[2], parts[3]].join(r'$');
      expect(await service.verify('123456'), isFalse);
    });

    group('旧明文记录的迁移', () {
      test('明文记录仍能验通，并就地升级为 v1', () async {
        // 本次改造之前写下的记录就是这个样子：口令明文直接躺在 Keychain 里。
        final (:service, :platform) = _build(initial: {_key: '123456'});

        expect(await service.verify('123456'), isTrue);

        final record = platform.store[_key]!;
        expect(record, startsWith(r'v1$'), reason: '验通之后应当就地升级');
        expect(record, isNot(contains('123456')));
      });

      test('升级之后仍然验得通，且错误口令仍被拒', () async {
        final (:service, :platform) = _build(initial: {_key: '123456'});
        await service.verify('123456'); // 触发升级

        expect(await service.verify('123456'), isTrue);
        expect(await service.verify('000000'), isFalse);
      });

      test('明文记录下口令错误时不升级，也不放行', () async {
        final (:service, :platform) = _build(initial: {_key: '123456'});

        expect(await service.verify('999999'), isFalse);
        // 没验通就改写记录，等于让攻击者用任意输入覆盖掉真正的安全码。
        expect(platform.store[_key], '123456');
      });
    });

    group('损坏的记录', () {
      test('字段数不对一律拒绝，不去猜它想表达什么', () async {
        final (:service, :platform) = _build(initial: {_key: r'v1$deadbeef'});
        expect(await service.verify('123456'), isFalse);
      });

      test('salt / 摘要不是合法 base64 时拒绝而不是抛异常', () async {
        final (:service, :platform) = _build(initial: {_key: r'v1$200000$!!!$???'});
        expect(await service.verify('123456'), isFalse);
      });

      test('迭代次数不是正整数时拒绝', () async {
        final (:service, :platform) = _build(initial: {_key: r'v1$0$AAAA$AAAA'});
        expect(await service.verify('123456'), isFalse);
      });
    });
  });
}
