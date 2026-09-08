import '../enums/backup_method.dart';
import '../enums/wallet_source.dart';
import '../blockchain/chain_registry.dart';

export '../enums/backup_method.dart';
export '../enums/wallet_source.dart';

/// 【状态数据】应用内长期持有、驱动 UI 的钱包模型。
/// 只保存非敏感信息；助记词 / 私钥等敏感数据应存入 flutter_secure_storage，
/// 不要放进状态中。由 Riverpod 的 walletListProvider 管理。
class Wallet {
  const Wallet({
    required this.id,
    required this.name,
    this.source = WalletSource.mnemonic,
    this.addresses = const {},
    this.createdAt,
    this.icon = 'account_balance_wallet',
    this.backupMethods = const {},
  });

  final String id;
  final String name;
  final WalletSource source;

  /// 各链地址：chainId -> address。新建/导入时一次性派生写入。
  final Map<String, String> addresses;

  /// 创建时间；老数据可能缺失，故可空。
  final DateTime? createdAt;

  /// 头像图标名（映射到 Material 图标或品牌资产），默认钱包图标。
  final String icon;

  /// 已采用的备份方式集合（可同时多种）。
  /// 新建钱包默认空（需引导备份）；导入钱包视为已手动备份；各方式成功后并入对应值。
  final Set<BackupMethod> backupMethods;

  /// 是否已备份（任意一种方式即视为已备份）。
  bool get isBackedUp => backupMethods.isNotEmpty;

  /// 是否持有助记词（仅助记词新建/助记词导入的钱包有；私钥导入、硬件钱包没有）。
  bool get hasMnemonic => source == WalletSource.mnemonic || source == WalletSource.imported;

  /// 搜索等只需展示一条地址时用：优先 EVM 主链，否则取 map 中第一项。
  String? get previewAddress =>
      addresses[SupportedChains.ethereumSepolia.id] ?? (addresses.isEmpty ? null : addresses.values.first);

  /// 取某条链的地址。只认 [addresses]，老盘的单字段 `address` 在 [fromJson] 里迁进来。
  String? addressFor(Chain chain) => addresses[chain.id];

  /// 钱包实际拥有地址的链（按 SupportedChains.all 顺序），用于列表页过滤。
  List<Chain> get chainsWithAddress => SupportedChains.all.where((c) => addressFor(c) != null).toList();

  Wallet copyWith({String? name, String? icon, Set<BackupMethod>? backupMethods}) {
    return Wallet(
      id: id,
      name: name ?? this.name,
      source: source,
      addresses: addresses,
      createdAt: createdAt,
      icon: icon ?? this.icon,
      backupMethods: backupMethods ?? this.backupMethods,
    );
  }

  /// 序列化为可持久化的 JSON（仅非敏感元数据）。
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'source': source.name,
    'addresses': addresses,
    'createdAt': createdAt?.toIso8601String(),
    'icon': icon,
    'backupMethods': backupMethods.map((m) => m.name).toList(),
  };

  /// 从持久化的 JSON 还原；source 缺失或非法时回退到 mnemonic。
  /// 老字段 `address` 只在读盘时消费，不再写回。
  factory Wallet.fromJson(Map<String, dynamic> json) => Wallet(
    id: json['id'] as String,
    name: json['name'] as String,
    source: WalletSource.values.asNameMap()[json['source']] ?? WalletSource.mnemonic,
    addresses: _addressesFromJson(json),
    createdAt: json['createdAt'] is String ? DateTime.tryParse(json['createdAt'] as String) : null,
    icon: json['icon'] as String? ?? 'account_balance_wallet',
    backupMethods: _backupMethodsFromJson(json),
  );

  /// 已废弃的 chainId → 现用 chainId。
  ///
  /// 地址按 chainId 存盘，而 [addressFor] 只按 [Chain.id] 查、加载时不会重新派生，
  /// 所以换测试网若只改 id，老钱包的该链地址会直接消失（首页与发送列表都不再显示）。
  ///
  /// 值不用重算：Tron 地址只由 `Bip44Coins.tron` 派生，与网络无关，
  /// 同一个 T... 地址在 Shasta / Nile / 主网通用，搬键即可。
  static const _renamedChainIds = {'tron-shasta': 'tron-nile'};

  /// 还原地址表：先搬历史 chainId，再把老字段 `address` 补进空 map。
  ///
  /// 只在新键**尚不存在**时才搬 chainId，避免把已经派生好的新数据覆盖掉。
  /// 老 `address` 仅当 map 仍为空时才写入全部 EVM 链——map 非空时不回填，
  /// 避免把私钥钱包的非 EVM 地址误认成 EVM 链地址。
  static Map<String, String> _addressesFromJson(Map<String, dynamic> json) {
    final raw = (json['addresses'] as Map?)?.map((k, v) => MapEntry(k as String, v as String));
    final migrated = <String, String>{...?raw};

    for (final entry in _renamedChainIds.entries) {
      final legacy = migrated.remove(entry.key);
      if (legacy != null) migrated.putIfAbsent(entry.value, () => legacy);
    }

    if (migrated.isEmpty) {
      final legacyAddress = json['address'];
      if (legacyAddress is String && legacyAddress.isNotEmpty) {
        for (final chain in SupportedChains.all) {
          if (chain.kind == ChainKind.evm) {
            migrated[chain.id] = legacyAddress;
          }
        }
      }
    }

    return migrated.isEmpty ? const {} : migrated;
  }

  /// 解析备份方式集合；兼容旧字段 `backUp`(int 1)→ {manual}。
  static Set<BackupMethod> _backupMethodsFromJson(Map<String, dynamic> json) {
    final raw = json['backupMethods'];
    if (raw is List) {
      final byName = BackupMethod.values.asNameMap();
      return raw.whereType<String>().map((n) => byName[n]).whereType<BackupMethod>().toSet();
    }
    // 旧数据迁移：backUp==1 视为已手动备份。
    if ((json['backUp'] as num?)?.toInt() == 1) return {BackupMethod.manual};
    return const {};
  }
}
