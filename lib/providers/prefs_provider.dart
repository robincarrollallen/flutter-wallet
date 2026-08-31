import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences 实例的全局入口。
///
/// SharedPreferences 是异步获取的，但各 Notifier 的 build() 需要同步初值，
/// 所以在 main() 里先 `await SharedPreferences.getInstance()`，
/// 再通过 ProviderScope(overrides:) 注入这里。未 override 直接使用会抛错，
final sharedPrefsProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('在 main() 中用 overrideWithValue 注入'),
);
