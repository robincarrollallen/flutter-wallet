import '../domain/wallet.dart';

/// 钱包列表与选中态的读写端口。
///
/// services 层需要读写这两份状态，但状态本身归 providers 层管。让下层定义端口、
/// 上层提供实现（依赖倒置），services 就不必反过来 import providers，
/// 同时调用方从构造签名上一眼看清依赖，测试里换个假实现即可。
abstract interface class WalletRegistry {
  /// 当前选中钱包的 id，未选中时为 null。
  String? get currentWalletId;

  /// 列表中是否存在该 id 的钱包。
  bool contains(String walletId);

  /// 列表中所有钱包的 id，用于与安全存储对账。
  Set<String> get knownWalletIds;

  /// 钱包入列表。
  void add(Wallet wallet);

  /// 移出列表；实现方需一并清除该钱包的敏感数据。
  void remove(String walletId);

  /// 设置选中项，传 null 表示不选中任何钱包。
  void select(String? walletId);
}
