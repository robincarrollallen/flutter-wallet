import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wallet/enums/prefs_key.dart';
import 'package:wallet/providers/core/persistent_notifier.dart';
import 'package:wallet/providers/core/prefs_provider.dart';

/// 借一个真实的 PrefsKey 建最小 Notifier：只验恢复态的诊断信号，不关心业务字段。
class _ProbeNotifier extends Notifier<List<String>> with PersistentNotifier<List<String>> {
  @override
  List<String> build() => restore(const []);

  @override
  PrefsKey get persistKey => PrefsKey.walletList;

  @override
  Map<String, dynamic> toJson(List<String> state) => {'items': state};

  @override
  List<String> fromJson(Map<String, dynamic> json, List<String> fallback) {
    final raw = json['items'];
    if (raw is! List) return fallback;
    return raw.whereType<String>().toList(growable: false);
  }
}

final _probeProvider = NotifierProvider<_ProbeNotifier, List<String>>(_ProbeNotifier.new);

/// 建容器并完成一次 restore，返回 notifier 供检查恢复态。
Future<_ProbeNotifier> _restoreWith(Map<String, Object> prefs) async {
  SharedPreferences.setMockInitialValues(prefs);
  final container = ProviderContainer(
    overrides: [sharedPrefsProvider.overrideWithValue(await SharedPreferences.getInstance())],
  );
  addTearDown(container.dispose);
  container.read(_probeProvider); // 触发 build → restore
  return container.read(_probeProvider.notifier);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 这三种情况恢复结果都是默认值，但对「能不能据此删数据」的调用方含义完全不同。
  group('恢复态诊断', () {
    test('键不存在：hasPersistedValue 为 false，未损坏', () async {
      final notifier = await _restoreWith(const {});

      expect(notifier.hasPersistedValue, isFalse);
      expect(notifier.persistedValueCorrupted, isFalse);
    });

    test('值损坏（不是 JSON）：键存在，且标记为损坏', () async {
      final notifier = await _restoreWith(const {'flutter.wallet.list': 'not json'});

      expect(notifier.hasPersistedValue, isTrue);
      expect(notifier.persistedValueCorrupted, isTrue);
    });

    test('值是 JSON 但不是对象：同样算损坏', () async {
      final notifier = await _restoreWith(const {'flutter.wallet.list': '[1,2,3]'});

      expect(notifier.hasPersistedValue, isTrue);
      expect(notifier.persistedValueCorrupted, isTrue);
    });

    test('确实存了一份空值：键存在且未损坏——这才是「真的是空的」', () async {
      final notifier = await _restoreWith(const {'flutter.wallet.list': '{"items":[]}'});

      expect(notifier.hasPersistedValue, isTrue);
      expect(notifier.persistedValueCorrupted, isFalse);
      expect(notifier.state, isEmpty);
    });

    test('正常恢复：数据还原，且未损坏', () async {
      final notifier = await _restoreWith(const {'flutter.wallet.list': '{"items":["a","b"]}'});

      expect(notifier.state, ['a', 'b']);
      expect(notifier.hasPersistedValue, isTrue);
      expect(notifier.persistedValueCorrupted, isFalse);
    });

    // 自动写回会在 build 后立刻把键建出来，现读 containsKey 永远是 true。
    test('hasPersistedValue 取的是 restore 当时的快照，不受自动写回影响', () async {
      final notifier = await _restoreWith(const {});
      notifier.state = ['written'];

      expect(notifier.hasPersistedValue, isFalse, reason: '写回之后仍要答得出「原本没有」');
    });
  });
}
