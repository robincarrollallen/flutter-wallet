import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// App 级「安全密码（安全码）」的安全存储。
///
/// 与助记词 / 私钥一样，落在 flutter_secure_storage：
/// - iOS / macOS：Keychain
/// - Android：Keystore 派生密钥 + EncryptedSharedPreferences
///
/// 安全码是 App 全局唯一的，用于导出私钥 / 备份等敏感操作前的二次校验。
class SecurityPasswordStorage {
  SecurityPasswordStorage([FlutterSecureStorage? storage])
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
            iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
          );

  final FlutterSecureStorage _storage;

  static const _key = 'app.security_password';

  /// 是否已设置安全码。
  Future<bool> hasPassword() async {
    final value = await _storage.read(key: _key);
    return value != null && value.isNotEmpty;
  }

  /// 设置 / 重置安全码。
  Future<void> setPassword(String password) => _storage.write(key: _key, value: password);

  /// 校验输入的安全码是否正确。
  Future<bool> verify(String password) async {
    final value = await _storage.read(key: _key);
    return value != null && value == password;
  }
}

/// 全局单例 provider。
final securityPasswordStorageProvider = Provider<SecurityPasswordStorage>((ref) => SecurityPasswordStorage());

/// 是否已设置安全码（用于 UI 判断跳转设置页还是校验页）。
final securityPasswordSetProvider = FutureProvider<bool>((ref) {
  return ref.watch(securityPasswordStorageProvider).hasPassword();
});
