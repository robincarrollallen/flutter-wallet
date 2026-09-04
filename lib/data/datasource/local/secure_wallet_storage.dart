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

  /// 匹配本类写入的敏感数据键，并捕获其中的 walletId（用于孤儿对账）。
  /// walletId 用非贪婪匹配 + 锚定的后缀，避免 id 里含 `.` 时切错。
  static final RegExp _secretKeyPattern = RegExp(r'^wallet\.(.+?)\.(?:mnemonic|pk)$');

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

  /// 该钱包是否已存在可用的敏感数据（助记词或私钥任一非空）。
  ///
  /// 提交流程用它做「写完立刻回读」的校验：底层 [FlutterSecureStorage.write] 不抛异常
  /// 并不等于真的写进去了（Android Keystore 在密钥轮换、存储空间不足时可能静默失败），
  /// 回读一次才算确认，否则会留下「列表里有钱包但签不了名」的砖块钱包。
  Future<bool> hasSecrets(String walletId) async {
    final mnemonic = await readMnemonic(walletId);
    if (mnemonic != null && mnemonic.isNotEmpty) return true;
    final privateKey = await readPrivateKey(walletId);
    return privateKey != null && privateKey.isNotEmpty;
  }

  /// 清理「无钱包引用」的敏感数据，返回删除条数。
  ///
  /// 创建 / 导入钱包时敏感数据先于元数据落盘，若进程在两者之间被杀，
  /// Keychain 里就会留下一份永远无人引用的助记词或私钥——[deleteSecrets] 按 walletId
  /// 触发，这份数据再也不会被清掉。启动时全量对账一次即可收敛，
  /// 且能连带清除历史版本遗留的孤儿。
  ///
  /// [knownWalletIds] 是当前钱包列表中的全部 id；只处理匹配
  /// [_secretKeyPattern] 的键，不会碰到其他 Keychain 数据。
  Future<int> purgeOrphanSecrets(Set<String> knownWalletIds) async {
    final all = await _storage.readAll();

    final orphanKeys = [
      for (final key in all.keys)
        if (_secretKeyPattern.firstMatch(key) case final match?)
          if (!knownWalletIds.contains(match.group(1))) key,
    ];

    for (final key in orphanKeys) {
      await _storage.delete(key: key);
    }
    return orphanKeys.length;
  }

  /// 删除某个钱包的全部敏感数据（删除钱包时调用）。
  Future<void> deleteSecrets(String walletId) async {
    await _storage.delete(key: _mnemonicKey(walletId));
    await _storage.delete(key: _privateKeyKey(walletId));
  }
}

/// 全局单例 provider，供创建 / 导入 / 签名流程注入使用。
final secureWalletStorageProvider = Provider<SecureWalletStorage>((ref) => SecureWalletStorage());
