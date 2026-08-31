import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 钱包敏感数据（助记词 / 私钥）的安全存储。
///
/// 底层使用 flutter_secure_storage：
/// - iOS / macOS：Keychain（本机加密，受设备解锁保护）
/// - Android：Keystore 派生密钥 + EncryptedSharedPreferences
///
/// 这些数据**绝不能**进入 Riverpod 状态、日志或 SharedPreferences。
/// 仅在签名、备份等必要场景按钱包 id 临时读取。
class SecureWalletStorage {
  SecureWalletStorage([FlutterSecureStorage? storage])
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
            iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
          );

  final FlutterSecureStorage _storage;

  static String _mnemonicKey(String walletId) => 'wallet.$walletId.mnemonic';
  static String _privateKeyKey(String walletId) => 'wallet.$walletId.pk';

  /// 保存某个钱包的私钥；助记词可选（私钥导入的钱包没有助记词，传 null 即不写入）。
  Future<void> saveSecrets({required String walletId, String? privateKey, String? mnemonic}) async {
    if (mnemonic != null) {
      await _storage.write(key: _mnemonicKey(walletId), value: mnemonic);
    }
    // 助记词钱包不存私钥（签名/导出按需现场派生），仅私钥导入钱包写入。
    if (privateKey != null) {
      await _storage.write(key: _privateKeyKey(walletId), value: privateKey);
    }
  }

  /// 读取助记词（用于备份 / 展示），不存在返回 null。
  Future<String?> readMnemonic(String walletId) => _storage.read(key: _mnemonicKey(walletId));

  /// 读取私钥（用于交易签名 / 导出），不存在返回 null。
  Future<String?> readPrivateKey(String walletId) => _storage.read(key: _privateKeyKey(walletId));

  /// 删除某个钱包的全部敏感数据（删除钱包时调用）。
  Future<void> deleteSecrets(String walletId) async {
    await _storage.delete(key: _mnemonicKey(walletId));
    await _storage.delete(key: _privateKeyKey(walletId));
  }
}

/// 全局单例 provider，供创建 / 导入 / 签名流程注入使用。
final secureWalletStorageProvider = Provider<SecureWalletStorage>((ref) => SecureWalletStorage());
