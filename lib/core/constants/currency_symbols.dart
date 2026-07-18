/// 法币代码 -> 货币符号的内置默认表。
/// 仅作兜底：优先用后端 API 返回的符号，API 未覆盖时回退到这里。
const Map<String, String> defaultCurrencySymbols = {
  'USD': '\$', // 美元 - United States Dollar
  'EUR': '€', // 欧元 - Eurozone
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
  'BRL': 'R\$', // 巴西雷亚尔 - Brazilian Real
  'MXN': 'Mex\$', // 墨西哥比索 - Mexican Peso
  'CHF': 'CHF', // 瑞士法郎 - Swiss Franc
  'SEK': 'kr', // 瑞典克朗 - Swedish Krona
  'NOK': 'kr', // 挪威克朗 - Norwegian Krone
  'DKK': 'kr', // 丹麦克朗 - Danish Krone
  'RUB': '₽', // 俄罗斯卢布 - Russian Ruble
  'TRY': '₺', // 土耳其里拉 - Turkish Lira
  'AED': 'د.إ', // 阿联酋迪拉姆 - UAE Dirham
  'SAR': '﷼', // 沙特里亚尔 - Saudi Riyal
  'QAR': '﷼', // 卡塔尔里亚尔 - Qatari Riyal
  'KWD': 'KD', // 科威特第纳尔 - Kuwaiti Dinar
  'EGP': '£', // 埃及镑 - Egyptian Pound
};

/// 取货币符号：[remote] 为后端返回的符号表（可空），优先使用；
/// 未覆盖时回退内置默认；再没有则回退代码本身（如 'BTC' -> 'BTC'）。
String currencySymbolOf(String code, {Map<String, String>? remote}) {
  final c = code.toUpperCase();
  return remote?[c] ?? defaultCurrencySymbols[c] ?? c;
}
