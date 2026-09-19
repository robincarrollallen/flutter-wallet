import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// App 级「安全密码（安全码）」的安全存储。
///
/// 与助记词 / 私钥一样，落在 flutter_secure_storage：
/// - iOS / macOS：Keychain
/// - Android：Keystore 保管密钥（RSA-OAEP 包装）+ AES/GCM 加密数据
///
/// 安全码是 App 全局唯一的，用于导出私钥 / 备份等敏感操作前的二次校验。
///
/// **这一层只负责存取一个字符串，不认识它的格式，也不做任何校验。**
/// 编码格式（salt + PBKDF2 摘要）与比对逻辑都在 [SecurityPasswordService]——
/// 存储层做密码学判断，既没法单测，也会让「怎么存」和「怎么验」散在两处。
class SecurityPasswordStorage {
  /// 不传 `aOptions` 的理由同 [SecureWalletStorage]：默认值即强加密，
  /// 而 `encryptedSharedPreferences` 已被上游弃用且会被忽略。
  SecurityPasswordStorage([FlutterSecureStorage? storage]) : _storage = storage ?? const FlutterSecureStorage(iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device));

  final FlutterSecureStorage _storage;

  static const _key = 'app.security_password';

  /// 读出已存的记录；从未设置过则为 null。
  Future<String?> read() => _storage.read(key: _key);

  /// 写入记录。内容格式由 [SecurityPasswordService] 决定。
  Future<void> write(String record) => _storage.write(key: _key, value: record);
}
