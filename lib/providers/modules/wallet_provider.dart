import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/wallet/domain/wallet.dart';
import '../../features/wallet/services/secure_wallet_storage.dart';
import '../persistent_notifier.dart';

/// 钱包列表的状态管理。
/// 元数据（id/name/address/source）持久化到 SharedPreferences；
/// 助记词 / 私钥等敏感数据存于 [SecureWalletStorage]，不在这里。
class WalletListNotifier extends Notifier<List<Wallet>>
    with PersistentNotifier<List<Wallet>> {
  @override
  List<Wallet> build() => restore(const []);

  @override
  String get persistKey => 'wallet.list';

  @override
  Map<String, dynamic> toJson(List<Wallet> state) =>
      {'wallets': state.map((w) => w.toJson()).toList()};

  @override
  List<Wallet> fromJson(Map<String, dynamic> json, List<Wallet> fallback) {
    final raw = json['wallets'];
    if (raw is! List) return fallback;
    return raw
        .whereType<Map<String, dynamic>>()
        .map(Wallet.fromJson)
        .toList(growable: false);
  }

  void add(Wallet wallet) {
    state = [...state, wallet];
  }

  /// 给指定钱包改名。空白名称将被忽略；前后空格会被裁掉。
  void rename(String id, String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    state = [
      for (final w in state)
        if (w.id == id) w.copyWith(name: trimmed) else w,
    ];
  }

  /// 更新指定钱包的头像图标 key。
  void setIcon(String id, String icon) {
    state = [
      for (final w in state)
        if (w.id == id) w.copyWith(icon: icon) else w,
    ];
  }

  /// 为指定钱包追加一种备份方式（并入集合），持久化生效。
  void addBackupMethod(String id, BackupMethod method) {
    state = [
      for (final w in state)
        if (w.id == id)
          w.copyWith(backupMethods: {...w.backupMethods, method})
        else
          w,
    ];
  }

  void remove(String id) {
    state = state.where((w) => w.id != id).toList();
    // 同步清除该钱包的助记词 / 私钥，避免敏感数据残留。
    ref.read(secureWalletStorageProvider).deleteSecrets(id);
  }
}

/// 所有钱包。
final walletListProvider =
    NotifierProvider<WalletListNotifier, List<Wallet>>(
  WalletListNotifier.new,
);

/// 当前选中钱包的 id。
class CurrentWalletIdNotifier extends Notifier<String?>
    with PersistentNotifier<String?> {
  @override
  String? build() => restore(null);

  @override
  String get persistKey => 'wallet.currentId';

  @override
  Map<String, dynamic> toJson(String? state) => {'id': state};

  @override
  String? fromJson(Map<String, dynamic> json, String? fallback) =>
      json['id'] as String? ?? fallback;

  void select(String? id) => state = id;
}

final currentWalletIdProvider =
    NotifierProvider<CurrentWalletIdNotifier, String?>(
  CurrentWalletIdNotifier.new,
);

/// 当前选中的钱包（派生自上面两个 provider）。
final currentWalletProvider = Provider<Wallet?>((ref) {
  final id = ref.watch(currentWalletIdProvider);
  final wallets = ref.watch(walletListProvider);
  if (id == null) return null;
  for (final w in wallets) {
    if (w.id == id) return w;
  }
  return null;
});

/// 首页展示用「有效选中钱包」：无显式选中（或选中项已删除）时回退到列表首个，
/// 避免首页空白。
final activeWalletProvider = Provider<Wallet?>((ref) {
  final current = ref.watch(currentWalletProvider);
  if (current != null) return current;
  final wallets = ref.watch(walletListProvider);
  return wallets.isEmpty ? null : wallets.first;
});

/// 是否已有任意钱包 —— 首页用它决定显示空状态还是钱包列表。
final hasWalletProvider = Provider<bool>((ref) {
  return ref.watch(walletListProvider).isNotEmpty;
});
