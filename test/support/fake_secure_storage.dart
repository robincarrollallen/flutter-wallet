import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// 内存版安全存储：可注入「写入抛异常」与「写入静默丢弃」两种故障，
/// 用来覆盖 Keychain / Keystore 真实世界里的两类失败模式。
class FakeSecureStoragePlatform extends FlutterSecureStoragePlatform with MockPlatformInterfaceMixin {
  FakeSecureStoragePlatform({this.initial = const {}}) : store = {...initial};

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
  Future<bool> containsKey({required String key, required Map<String, String> options}) async => store.containsKey(key);

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
