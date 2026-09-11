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
  static String _pendingKey(String walletId) => 'wallet.$walletId.pending';

  /// 匹配本类写入的敏感数据键，并捕获其中的 walletId（用于孤儿对账）。
  /// walletId 用非贪婪匹配 + 锚定的后缀，避免 id 里含 `.` 时切错。
  static final RegExp _secretKeyPattern = RegExp(r'^wallet\.(.+?)\.(?:mnemonic|pk)$');

  /// 匹配提交意图标记，并捕获其中的 walletId。后缀与 [_secretKeyPattern] 互斥，
  /// 标记自身不会被当成敏感数据读取或统计。
  static final RegExp _pendingKeyPattern = RegExp(r'^wallet\.(.+?)\.pending$');

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

  /// 落下「本钱包正在提交」的意图标记。
  ///
  /// **必须在写入任何敏感数据之前调用，且失败要向外抛**：只有带着这个标记的敏感数据
  /// 才有资格被 [purgeOrphanSecrets] 当作中断残留清掉。顺序反过来（先写密钥后打标记）
  /// 会留下一个时间窗，窗内产生的残留永远无法被识别、也就永远清不掉。
  ///
  /// 值存写入时刻，当前逻辑不读它，留给日后排查「这个标记为什么还在」。
  Future<void> markPendingCommit(String walletId) =>
      _storage.write(key: _pendingKey(walletId), value: DateTime.now().toUtc().toIso8601String());

  /// 撤下提交意图标记。**必须在钱包元数据全部生效之后调用**——标记一撤，这份敏感数据
  /// 就永久失去被对账删除的资格，早撤一步就等于重新打开了误删的口子。
  ///
  /// 这一步失败不影响提交结果：遗留的标记会被 [purgeOrphanSecrets] 识别为陈旧并清掉。
  Future<void> clearPendingCommit(String walletId) => _storage.delete(key: _pendingKey(walletId));

  /// 该钱包是否带着未完成的提交标记（诊断与测试用）。
  Future<bool> hasPendingCommit(String walletId) async => await _storage.read(key: _pendingKey(walletId)) != null;

  /// 清理「提交中断残留」的敏感数据，返回删除的敏感数据条数（不含标记本身）。
  ///
  /// 创建 / 导入钱包时敏感数据先于元数据落盘，若进程在两者之间被杀，Keychain 里就会
  /// 留下一份永远无人引用的助记词或私钥——[deleteSecrets] 按 walletId 触发，这份数据
  /// 再也不会被清掉。启动时对账一次即可收敛。
  ///
  /// 判据是「**带着提交意图标记**，且钱包列表确实不认识它」，而不是「不在列表里」：
  /// 列表可能整体丢失（iOS 删除 App 会清掉 SharedPreferences，而 Keychain 属于
  /// access group 会保留），按「不在列表里」删，等于在用户还能靠 Keychain 里的助记词
  /// 找回资产时，抢先把这条唯一的恢复路径销毁掉。没有标记的敏感数据一律不动。
  ///
  /// [registryTrusted] 为 false（列表键不存在 / 已损坏）时直接返回 0：此时
  /// [knownWalletIds] 为空是「不知道」而非「确实没有」，不足以支撑任何删除。
  Future<int> purgeOrphanSecrets({required Set<String> knownWalletIds, required bool registryTrusted}) async {
    if (!registryTrusted) return 0;

    final all = await _storage.readAll();

    final pendingIds = {
      for (final key in all.keys)
        if (_pendingKeyPattern.firstMatch(key) case final match?) match.group(1)!,
    };

    final orphanIds = pendingIds.difference(knownWalletIds); // 确证的半成品
    // 陈旧标记：钱包已在列表里，说明提交其实成功了，只是撤标记那一步没做成。
    final staleIds = pendingIds.intersection(knownWalletIds);

    final orphanSecretKeys = [
      for (final key in all.keys)
        if (_secretKeyPattern.firstMatch(key) case final match?)
          if (orphanIds.contains(match.group(1))) key,
    ];

    for (final key in orphanSecretKeys) {
      await _storage.delete(key: key);
    }
    for (final walletId in [...orphanIds, ...staleIds]) {
      await _storage.delete(key: _pendingKey(walletId));
    }
    return orphanSecretKeys.length;
  }

  /// 删除某个钱包的全部敏感数据（删除钱包时调用），连同可能残留的提交标记。
  Future<void> deleteSecrets(String walletId) async {
    await _storage.delete(key: _mnemonicKey(walletId));
    await _storage.delete(key: _privateKeyKey(walletId));
    await _storage.delete(key: _pendingKey(walletId));
  }
}

/// 全局单例 provider，供创建 / 导入 / 签名流程注入使用。
final secureWalletStorageProvider = Provider<SecureWalletStorage>((ref) => SecureWalletStorage());
