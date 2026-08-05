import '../../../core/enums/backup_method.dart';
import '../../../core/enums/wallet_source.dart';
import '../../../core/blockchain/chain_registry.dart';

export '../../../core/enums/backup_method.dart';
export '../../../core/enums/wallet_source.dart';

/// 【状态数据】应用内长期持有、驱动 UI 的钱包模型。
/// 只保存非敏感信息；助记词 / 私钥等敏感数据应存入 flutter_secure_storage，
/// 不要放进状态中。由 Riverpod 的 walletListProvider 管理。
class Wallet {
  const Wallet({
    required this.id,
    required this.name,
    required this.address,
    this.source = WalletSource.mnemonic,
    this.addresses = const {},
    this.createdAt,
    this.icon = 'account_balance_wallet',
    this.backupMethods = const {},
  });

  final String id;
  final String name;

  /// 主地址（以太坊 0x 地址），用于兼容旧逻辑。
  final String address;
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
  bool get hasMnemonic =>
      source == WalletSource.mnemonic || source == WalletSource.imported;

  /// 取某条链的地址；缺失时仅为兼容老数据（addresses 为空但有主 0x 地址）回退到 EVM 主地址。
  /// 注意：map 非空时不回退，避免把私钥钱包的非 EVM 主地址误认成 EVM 链地址。
  String? addressFor(Chain chain) {
    final a = addresses[chain.id];
    if (a != null) return a;
    if (addresses.isEmpty &&
        chain.kind == ChainKind.evm &&
        address.isNotEmpty) {
      return address;
    }
    return null;
  }

  /// 钱包实际拥有地址的链（按 SupportedChains.all 顺序），用于列表页过滤。
  List<Chain> get chainsWithAddress =>
      SupportedChains.all.where((c) => addressFor(c) != null).toList();

  Wallet copyWith({
    String? name,
    String? icon,
    Set<BackupMethod>? backupMethods,
  }) {
    return Wallet(
      id: id,
      name: name ?? this.name,
      address: address,
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
    'address': address,
    'source': source.name,
    'addresses': addresses,
    'createdAt': createdAt?.toIso8601String(),
    'icon': icon,
    'backupMethods': backupMethods.map((m) => m.name).toList(),
  };

  /// 从持久化的 JSON 还原；source 缺失或非法时回退到 mnemonic。
  factory Wallet.fromJson(Map<String, dynamic> json) => Wallet(
    id: json['id'] as String,
    name: json['name'] as String,
    address: json['address'] as String,
    source:
        WalletSource.values.asNameMap()[json['source']] ??
        WalletSource.mnemonic,
    addresses:
        (json['addresses'] as Map?)?.map(
          (k, v) => MapEntry(k as String, v as String),
        ) ??
        const {},
    createdAt: json['createdAt'] is String
        ? DateTime.tryParse(json['createdAt'] as String)
        : null,
    icon: json['icon'] as String? ?? 'account_balance_wallet',
    backupMethods: _backupMethodsFromJson(json),
  );

  /// 解析备份方式集合；兼容旧字段 `backUp`(int 1)→ {manual}。
  static Set<BackupMethod> _backupMethodsFromJson(Map<String, dynamic> json) {
    final raw = json['backupMethods'];
    if (raw is List) {
      final byName = BackupMethod.values.asNameMap();
      return raw
          .whereType<String>()
          .map((n) => byName[n])
          .whereType<BackupMethod>()
          .toSet();
    }
    // 旧数据迁移：backUp==1 视为已手动备份。
    if ((json['backUp'] as num?)?.toInt() == 1) return {BackupMethod.manual};
    return const {};
  }
}
