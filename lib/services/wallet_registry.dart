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

  /// 钱包列表的持久化数据是否可信。
  ///
  /// false 表示存储键根本不存在或内容已损坏——**这不等于「用户没有钱包」**。
  /// iOS 删除 App 会清掉 SharedPreferences 而 Keychain 属于 access group 会保留，
  /// 重装后首次启动正是这个状态：[knownWalletIds] 返回空集是「不知道」而非
  /// 「确实没有」，任何以它为依据的删除动作都必须停手。
  bool get walletListTrusted;

  /// 钱包入列表。
  void add(Wallet wallet);

  /// 移出列表；实现方需一并清除该钱包的敏感数据。
  ///
  /// 返回 Future 是为了让调用方能等到密钥真的删完：清密钥要走 Keychain / Keystore，
  /// 丢掉这个 Future 的话，删除失败会变成没人收得到的异步异常，
  /// 连回滚里的 try/catch 都拦不住。
  Future<void> remove(String walletId);

  /// 设置选中项，传 null 表示不选中任何钱包。
  void select(String? walletId);
}
