/// SharedPreferences 的全局键清单。
///
/// 所有 [PersistentNotifier] 的存储键都必须来自这里：
/// - 键是**跨文件共享的命名空间**，集中声明才能一眼看出有没有撞键（撞键会静默互相覆盖）。
/// - [value] 是真正落盘的字符串，与枚举项名解耦——重命名枚举项不会改变磁盘格式，
///   老用户的数据依然读得出来。**改 [value] 等于丢数据，不要改。**
enum PrefsKey {
  appearance('appearance'), // 外观：主题 + 明暗模式
  locale('app_locale'), // 应用语言
  balanceHidden('balance_hidden'), // 是否隐藏余额
  fiatCurrency('fiat_currency'), // 计价法币
  walletList('wallet.list'), // 钱包列表
  walletCurrentId('wallet.currentId'), // 当前选中钱包 id
  recentAddresses('send.recentAddresses'), // 转账最近使用地址
  searchHistory('search.history'), // 搜索历史
  customTokens('token.custom'); // 用户自定义代币

  const PrefsKey(this.value);

  /// 落盘用的实际键名。
  final String value;
}
