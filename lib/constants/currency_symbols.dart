/// 计价法币的默认值（ISO 4217 大写代码）。CoinGecko 的 `vs_currency` 取其小写形式。
const String defaultCurrencyCode = 'USD';

/// 法币代码 -> 货币符号的内置默认表。
/// 兼两职：既是符号来源（API 未返回符号时兜底），也是**受支持币种的唯一真源**
/// （supportedCurrencyCodes 由其 keys 派生，保证每个可选币种都显示得出符号）。
///
/// 不变式：**本表必须是 CoinGecko `/simple/supported_vs_currencies` 的法币子集**。
/// 该接口不支持的代码传进 vs_currency 会返回空数组，等同一次静默的行情失败。
/// 下列 46 项即该接口全部法币（已排除 btc/eth/sol/sats/bits 等加密计价单位
/// 与 xag/xau/xdr 这类非法币单位）。新增币种前请先核对该接口。
///
/// 顺序即选择页的展示顺序：主流币种在前，其余按地区归并。
const Map<String, String> defaultCurrencySymbols = {
  'USD': '\$', // 美元 - United States Dollar
  'EUR': '€', // 欧元 - Euro
  'GBP': '£', // 英镑 - British Pound
  'JPY': '¥', // 日元 - Japanese Yen
  'CNY': '¥', // 人民币 - Chinese Yuan
  'HKD': 'HK\$', // 港币 - Hong Kong Dollar
  'TWD': 'NT\$', // 新台币 - New Taiwan Dollar
  'KRW': '₩', // 韩元 - South Korean Won
  'AUD': 'A\$', // 澳元 - Australian Dollar
  'NZD': 'NZ\$', // 新西兰元 - New Zealand Dollar
  'CAD': 'C\$', // 加元 - Canadian Dollar
  'SGD': 'S\$', // 新加坡元 - Singapore Dollar
  'PHP': '₱', // 菲律宾比索 - Philippine Peso
  'THB': '฿', // 泰铢 - Thai Baht
  'VND': '₫', // 越南盾 - Vietnamese Dong
  'INR': '₹', // 印度卢比 - Indian Rupee
  'IDR': 'Rp', // 印尼盾 - Indonesian Rupiah
  'MYR': 'RM', // 马来西亚林吉特 - Malaysian Ringgit
  'BDT': '৳', // 孟加拉塔卡 - Bangladeshi Taka
  'PKR': '₨', // 巴基斯坦卢比 - Pakistani Rupee
  'LKR': 'Rs', // 斯里兰卡卢比 - Sri Lankan Rupee
  'MMK': 'K', // 缅甸元 - Myanmar Kyat
  'BRL': 'R\$', // 巴西雷亚尔 - Brazilian Real
  'MXN': 'Mex\$', // 墨西哥比索 - Mexican Peso
  'ARS': 'AR\$', // 阿根廷比索 - Argentine Peso
  'CLP': 'CL\$', // 智利比索 - Chilean Peso
  'BMD': 'BD\$', // 百慕大元 - Bermudian Dollar
  'VEF': 'Bs', // 委内瑞拉玻利瓦尔 - Venezuelan Bolívar
  'CHF': 'CHF', // 瑞士法郎 - Swiss Franc
  'SEK': 'kr', // 瑞典克朗 - Swedish Krona
  'NOK': 'kr', // 挪威克朗 - Norwegian Krone
  'DKK': 'kr', // 丹麦克朗 - Danish Krone
  'PLN': 'zł', // 波兰兹罗提 - Polish Złoty
  'CZK': 'Kč', // 捷克克朗 - Czech Koruna
  'HUF': 'Ft', // 匈牙利福林 - Hungarian Forint
  'RUB': '₽', // 俄罗斯卢布 - Russian Ruble
  'UAH': '₴', // 乌克兰格里夫纳 - Ukrainian Hryvnia
  'GEL': '₾', // 格鲁吉亚拉里 - Georgian Lari
  'TRY': '₺', // 土耳其里拉 - Turkish Lira
  'ILS': '₪', // 以色列新谢克尔 - Israeli New Shekel
  'AED': 'د.إ', // 阿联酋迪拉姆 - UAE Dirham
  'SAR': '﷼', // 沙特里亚尔 - Saudi Riyal
  'KWD': 'KD', // 科威特第纳尔 - Kuwaiti Dinar
  'BHD': 'BD', // 巴林第纳尔 - Bahraini Dinar
  'NGN': '₦', // 尼日利亚奈拉 - Nigerian Naira
  'ZAR': 'R', // 南非兰特 - South African Rand
};

/// 取货币符号：[remote] 为后端返回的符号表（可空），优先使用；
/// 未覆盖时回退内置默认；再没有则回退代码本身（如 'BTC' -> 'BTC'）。
String currencySymbolOf(String code, {Map<String, String>? remote}) {
  final c = code.toUpperCase();
  return remote?[c] ?? defaultCurrencySymbols[c] ?? c;
}

/// 取国旗 emoji：ISO 4217 代码前两位即 ISO 3166 国家码，
/// 逐位映射到区域指示符（U+1F1E6 起）拼成国旗，无需任何图片资源。
///
/// EUR 不对应单一国家，特例返回欧盟旗；代码不合法时回退白旗。
String currencyFlagOf(String code) {
  const base = 0x1F1E6; // 🇦：区域指示符 A
  const fallback = '🏳️';
  final c = code.toUpperCase();
  if (c == 'EUR') return '🇪🇺';
  if (c.length < 2) return fallback;
  final first = c.codeUnitAt(0);
  final second = c.codeUnitAt(1);
  const a = 0x41, z = 0x5A; // 'A' / 'Z'
  if (first < a || first > z || second < a || second > z) return fallback;
  return String.fromCharCodes([base + first - a, base + second - a]);
}
