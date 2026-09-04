/// SharedPreferences 的全局键清单。
///
/// 所有 [PersistentNotifier] 的存储键都必须来自这里：
/// - 键是**跨文件共享的命名空间**，集中声明才能一眼看出有没有撞键（撞键会静默互相覆盖）。
/// - [value] 是真正落盘的字符串，与枚举项名解耦——重命名枚举项不会改变磁盘格式，
///   老用户的数据依然读得出来。**改 [value] 等于丢数据，不要改。**
enum PrefsKey {
  /// 外观：主题 + 明暗模式
  appearance('appearance'),

  /// 应用语言
  locale('app_locale'),

  /// 是否隐藏余额
  balanceHidden('balance_hidden'),

  /// 计价法币
  fiatCurrency('fiat_currency'),

  /// 钱包列表
  walletList('wallet.list'),

  /// 当前选中钱包 id
  walletCurrentId('wallet.currentId'),

  /// 转账最近使用地址
  recentAddresses('send.recentAddresses'),

  /// 搜索历史
  searchHistory('search.history'),

  /// 用户自定义代币
  customTokens('token.custom'),

  /// 用户手动隐藏的资产（原生币 / 代币）
  hiddenAssets('asset.hidden'),

  /// 行情缓存（按币种分槽，含写入时刻与请求过的 coinGeckoId）
  markets('markets_cache'),

  /// 链图标缓存（含写入时刻与请求过的平台 id）
  chainIcons('chain_icons_cache'),

  /// 远程代币目录缓存（含写入时刻）
  tokenCatalog('token_catalog_cache'),

  /// EVM 费率基准缓存（每链一份 baseFee + 各档小费 + 抓取时刻，另存收款方 gasLimit）
  evmGasBasis('evm_gas_basis_cache'),

  /// 本机广播过的 BTC 交易 id（txid -> 广播时刻）
  btcBroadcasts('btc.broadcasts');

  /// 给上面这个字段赋值的构造函数(使 PrefsKey.locale.value 能生效)
  const PrefsKey(this.value);

  /// 每个枚举实例上的字段(例如 PrefsKey.locale.value 就是 'app_locale', 枚举项名获取依旧使用 PrefsKey.locale.name)
  final String value;
}
