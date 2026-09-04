///
/// Generated file. Do not edit.
///
// coverage:ignore-file
// ignore_for_file: type=lint, unused_import
// dart format off

import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:slang/generated.dart';
import 'translations.g.dart';

// Path: <root>
class TranslationsZh extends Translations with BaseTranslations<AppLocale, Translations> {
	/// You can call this constructor and build your own translation instance of this locale.
	/// Constructing via the enum [AppLocale.build] is preferred.
	TranslationsZh({Map<String, Node>? overrides, PluralResolver? cardinalResolver, PluralResolver? ordinalResolver, TranslationMetadata<AppLocale, Translations>? meta})
		: assert(overrides == null, 'Set "translation_overrides: true" in order to enable this feature.'),
		  $meta = meta ?? TranslationMetadata(
		    locale: AppLocale.zh,
		    overrides: overrides ?? {},
		    cardinalResolver: cardinalResolver,
		    ordinalResolver: ordinalResolver,
		  ),
		  super(cardinalResolver: cardinalResolver, ordinalResolver: ordinalResolver) {
		super.$meta.setFlatMapFunction($meta.getTranslation); // copy base translations to super.$meta
		$meta.setFlatMapFunction(_flatMapFunction);
	}

	/// Metadata for the translations of <zh>.
	@override final TranslationMetadata<AppLocale, Translations> $meta;

	/// Access flat map
	@override dynamic operator[](String key) => $meta.getTranslation(key) ?? super.$meta.getTranslation(key);

	late final TranslationsZh _root = this; // ignore: unused_field

	@override 
	TranslationsZh $copyWith({TranslationMetadata<AppLocale, Translations>? meta}) => TranslationsZh(meta: meta ?? this.$meta);

	// Translations
	@override String get appTitle => '我的钱包';
	@override late final _Translations$tabs$zh tabs = _Translations$tabs$zh._(_root);
	@override late final _Translations$home$zh home = _Translations$home$zh._(_root);
	@override late final _Translations$manageTokens$zh manageTokens = _Translations$manageTokens$zh._(_root);
	@override late final _Translations$settings$zh settings = _Translations$settings$zh._(_root);
	@override late final _Translations$currency$zh currency = _Translations$currency$zh._(_root);
	@override Map<String, String> get currencyNames => {
		'USD': '美元',
		'EUR': '欧元',
		'GBP': '英镑',
		'JPY': '日元',
		'CNY': '人民币',
		'HKD': '港币',
		'TWD': '新台币',
		'KRW': '韩元',
		'AUD': '澳元',
		'NZD': '新西兰元',
		'CAD': '加元',
		'SGD': '新加坡元',
		'PHP': '菲律宾比索',
		'THB': '泰铢',
		'VND': '越南盾',
		'INR': '印度卢比',
		'IDR': '印尼盾',
		'MYR': '马来西亚林吉特',
		'BDT': '孟加拉塔卡',
		'PKR': '巴基斯坦卢比',
		'LKR': '斯里兰卡卢比',
		'MMK': '缅甸元',
		'BRL': '巴西雷亚尔',
		'MXN': '墨西哥比索',
		'ARS': '阿根廷比索',
		'CLP': '智利比索',
		'BMD': '百慕大元',
		'VEF': '委内瑞拉玻利瓦尔',
		'CHF': '瑞士法郎',
		'SEK': '瑞典克朗',
		'NOK': '挪威克朗',
		'DKK': '丹麦克朗',
		'PLN': '波兰兹罗提',
		'CZK': '捷克克朗',
		'HUF': '匈牙利福林',
		'RUB': '俄罗斯卢布',
		'UAH': '乌克兰格里夫纳',
		'GEL': '格鲁吉亚拉里',
		'TRY': '土耳其里拉',
		'ILS': '以色列新谢克尔',
		'AED': '阿联酋迪拉姆',
		'SAR': '沙特里亚尔',
		'KWD': '科威特第纳尔',
		'BHD': '巴林第纳尔',
		'NGN': '尼日利亚奈拉',
		'ZAR': '南非兰特',
	};
	@override late final _Translations$search$zh search = _Translations$search$zh._(_root);
	@override late final _Translations$scan$zh scan = _Translations$scan$zh._(_root);
	@override late final _Translations$balance$zh balance = _Translations$balance$zh._(_root);
	@override late final _Translations$create$zh create = _Translations$create$zh._(_root);
	@override late final _Translations$createWallet$zh createWallet = _Translations$createWallet$zh._(_root);
	@override late final _Translations$import$zh import = _Translations$import$zh._(_root);
	@override late final _Translations$placeholder$zh placeholder = _Translations$placeholder$zh._(_root);
}

// Path: tabs
class _Translations$tabs$zh extends Translations$tabs$en {
	_Translations$tabs$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override String get home => '首页';
	@override String get market => '市场';
	@override String get exchange => '兑换';
	@override String get contract => '合约';
	@override String get discover => '发现';
}

// Path: home
class _Translations$home$zh extends Translations$home$en {
	_Translations$home$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override String get noWalletTitle => '还没有钱包';
	@override String get noWalletSubtitle => '创建或导入一个钱包开始使用';
	@override String get createWallet => '创建钱包';
	@override String get totalAssets => '总资产';
	@override String get assetsScanning => '正在扫描链上资产…';
	@override String get partialAssets => '部分链数据获取失败';
	@override String get searchHint => '搜索代币、地址或交易';
	@override String get settings => '设置';
	@override String get scan => '扫一扫';
	@override String get tokens => '代币';
	@override String get manageTokens => '管理代币';
}

// Path: manageTokens
class _Translations$manageTokens$zh extends Translations$manageTokens$en {
	_Translations$manageTokens$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override String get title => '管理代币';
	@override String get searchHint => '搜索代币或公链';
	@override String get empty => '未找到相关资产';
}

// Path: settings
class _Translations$settings$zh extends Translations$settings$en {
	_Translations$settings$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override String get title => '设置';
	@override String get general => '通用';
	@override String get security => '安全';
	@override String get about => '关于';
}

// Path: currency
class _Translations$currency$zh extends Translations$currency$en {
	_Translations$currency$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override String get title => '计价货币';
	@override String get searchHint => '搜索币种';
}

// Path: search
class _Translations$search$zh extends Translations$search$en {
	_Translations$search$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override String get title => '搜索';
	@override String get hint => '搜索代币、地址或交易';
	@override String get empty => '输入关键词开始搜索';
	@override String get noResult => '没有找到相关结果';
	@override late final _Translations$search$tabs$zh tabs = _Translations$search$tabs$zh._(_root);
	@override String get history => '搜索历史';
	@override String get clearHistory => '清空';
	@override String get hot => '热门搜索';
}

// Path: scan
class _Translations$scan$zh extends Translations$scan$en {
	_Translations$scan$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override String get title => '扫一扫';
	@override String get hint => '将二维码放入框内即可自动扫描';
}

// Path: balance
class _Translations$balance$zh extends Translations$balance$en {
	_Translations$balance$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override String get unavailable => '--';
	@override String get pending => '待确认';
}

// Path: create
class _Translations$create$zh extends Translations$create$en {
	_Translations$create$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override String get generatingTitle => '正在创建你的专属钱包';
	@override String get generatingHint => '正在生成助记词并派生地址，请勿离开页面';
	@override String get successTitle => '钱包创建成功';
	@override String get successSubtitle => '你的全新钱包已就绪，快开始使用吧';
	@override String get start => '开始使用新钱包';
	@override String get walletName => '我的钱包';
	@override String get failed => '创建失败，请重试';
	@override String get retry => '重试';
}

// Path: createWallet
class _Translations$createWallet$zh extends Translations$createWallet$en {
	_Translations$createWallet$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override String get title => '创建钱包';
	@override late final _Translations$createWallet$create$zh create = _Translations$createWallet$create$zh._(_root);
	@override late final _Translations$createWallet$import$zh import = _Translations$createWallet$import$zh._(_root);
	@override late final _Translations$createWallet$hardware$zh hardware = _Translations$createWallet$hardware$zh._(_root);
}

// Path: import
class _Translations$import$zh extends Translations$import$en {
	_Translations$import$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override String get selectTitle => '选择导入钱包';
	@override String get software => '助记词或私钥';
	@override String get hardware => '硬件钱包';
	@override late final _Translations$import$mnemonic$zh mnemonic = _Translations$import$mnemonic$zh._(_root);
}

// Path: placeholder
class _Translations$placeholder$zh extends Translations$placeholder$en {
	_Translations$placeholder$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override String get wip => '功能开发中';
}

// Path: search.tabs
class _Translations$search$tabs$zh extends Translations$search$tabs$en {
	_Translations$search$tabs$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override String get token => '代币';
	@override String get contract => '合约';
	@override String get dapp => 'Dapp';
}

// Path: createWallet.create
class _Translations$createWallet$create$zh extends Translations$createWallet$create$en {
	_Translations$createWallet$create$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override String get title => '新建助记词钱包';
	@override String get subtitle => '生成一组全新的助记词并创建钱包';
}

// Path: createWallet.import
class _Translations$createWallet$import$zh extends Translations$createWallet$import$en {
	_Translations$createWallet$import$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override String get title => '导入已有钱包';
	@override String get subtitle => '通过助记词或私钥恢复已有钱包';
}

// Path: createWallet.hardware
class _Translations$createWallet$hardware$zh extends Translations$createWallet$hardware$en {
	_Translations$createWallet$hardware$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override String get title => '连接硬件钱包';
	@override String get subtitle => '连接 Ledger、Trezor 等硬件设备';
}

// Path: import.mnemonic
class _Translations$import$mnemonic$zh extends Translations$import$mnemonic$en {
	_Translations$import$mnemonic$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override String get title => '导入助记词或私钥';
	@override String get hint => '请输入助记词（单词以空格分隔），或直接粘贴私钥';
	@override String get helper => '自动识别助记词或私钥；输入助记词时键盘上方会提示 BIP39 候选单词';
	@override String get warning => '请勿在不信任的环境下输入助记词或私钥，任何人获取后都能掌控你的资产。';
	@override String get submit => '导入';
	@override String wordCount({required Object n}) => '${n} 个单词';
	@override String get walletName => '导入钱包';
	@override String get deriveFailed => '地址派生失败';
	@override String get saveFailed => '钱包保存失败，请重试';
	@override late final _Translations$import$mnemonic$errors$zh errors = _Translations$import$mnemonic$errors$zh._(_root);
}

// Path: import.mnemonic.errors
class _Translations$import$mnemonic$errors$zh extends Translations$import$mnemonic$errors$en {
	_Translations$import$mnemonic$errors$zh._(TranslationsZh root) : this._root = root, super.internal(root);

	final TranslationsZh _root; // ignore: unused_field

	// Translations
	@override String get empty => '请输入助记词';
	@override String get nonEnglish => '助记词只能包含英文单词';
	@override String wordCount({required Object count}) => '助记词应为 12 / 15 / 18 / 21 / 24 个单词，当前 ${count} 个';
	@override String invalidWords({required Object words}) => '存在无效单词：${words}';
	@override String get checksum => '助记词校验失败，请检查顺序或拼写';
	@override String get invalidPrivateKey => '私钥格式无效，请检查是否为完整的 EVM / Solana / Sui 私钥';
}

/// The flat map containing all translations for locale <zh>.
/// Only for edge cases! For simple maps, use the map function of this library.
///
/// The Dart AOT compiler has issues with very large switch statements,
/// so the map is split into smaller functions (512 entries each).
extension on TranslationsZh {
	dynamic _flatMapFunction(String path) {
		return switch (path) {
			'appTitle' => '我的钱包',
			'tabs.home' => '首页',
			'tabs.market' => '市场',
			'tabs.exchange' => '兑换',
			'tabs.contract' => '合约',
			'tabs.discover' => '发现',
			'home.noWalletTitle' => '还没有钱包',
			'home.noWalletSubtitle' => '创建或导入一个钱包开始使用',
			'home.createWallet' => '创建钱包',
			'home.totalAssets' => '总资产',
			'home.assetsScanning' => '正在扫描链上资产…',
			'home.partialAssets' => '部分链数据获取失败',
			'home.searchHint' => '搜索代币、地址或交易',
			'home.settings' => '设置',
			'home.scan' => '扫一扫',
			'home.tokens' => '代币',
			'home.manageTokens' => '管理代币',
			'manageTokens.title' => '管理代币',
			'manageTokens.searchHint' => '搜索代币或公链',
			'manageTokens.empty' => '未找到相关资产',
			'settings.title' => '设置',
			'settings.general' => '通用',
			'settings.security' => '安全',
			'settings.about' => '关于',
			'currency.title' => '计价货币',
			'currency.searchHint' => '搜索币种',
			'currencyNames.USD' => '美元',
			'currencyNames.EUR' => '欧元',
			'currencyNames.GBP' => '英镑',
			'currencyNames.JPY' => '日元',
			'currencyNames.CNY' => '人民币',
			'currencyNames.HKD' => '港币',
			'currencyNames.TWD' => '新台币',
			'currencyNames.KRW' => '韩元',
			'currencyNames.AUD' => '澳元',
			'currencyNames.NZD' => '新西兰元',
			'currencyNames.CAD' => '加元',
			'currencyNames.SGD' => '新加坡元',
			'currencyNames.PHP' => '菲律宾比索',
			'currencyNames.THB' => '泰铢',
			'currencyNames.VND' => '越南盾',
			'currencyNames.INR' => '印度卢比',
			'currencyNames.IDR' => '印尼盾',
			'currencyNames.MYR' => '马来西亚林吉特',
			'currencyNames.BDT' => '孟加拉塔卡',
			'currencyNames.PKR' => '巴基斯坦卢比',
			'currencyNames.LKR' => '斯里兰卡卢比',
			'currencyNames.MMK' => '缅甸元',
			'currencyNames.BRL' => '巴西雷亚尔',
			'currencyNames.MXN' => '墨西哥比索',
			'currencyNames.ARS' => '阿根廷比索',
			'currencyNames.CLP' => '智利比索',
			'currencyNames.BMD' => '百慕大元',
			'currencyNames.VEF' => '委内瑞拉玻利瓦尔',
			'currencyNames.CHF' => '瑞士法郎',
			'currencyNames.SEK' => '瑞典克朗',
			'currencyNames.NOK' => '挪威克朗',
			'currencyNames.DKK' => '丹麦克朗',
			'currencyNames.PLN' => '波兰兹罗提',
			'currencyNames.CZK' => '捷克克朗',
			'currencyNames.HUF' => '匈牙利福林',
			'currencyNames.RUB' => '俄罗斯卢布',
			'currencyNames.UAH' => '乌克兰格里夫纳',
			'currencyNames.GEL' => '格鲁吉亚拉里',
			'currencyNames.TRY' => '土耳其里拉',
			'currencyNames.ILS' => '以色列新谢克尔',
			'currencyNames.AED' => '阿联酋迪拉姆',
			'currencyNames.SAR' => '沙特里亚尔',
			'currencyNames.KWD' => '科威特第纳尔',
			'currencyNames.BHD' => '巴林第纳尔',
			'currencyNames.NGN' => '尼日利亚奈拉',
			'currencyNames.ZAR' => '南非兰特',
			'search.title' => '搜索',
			'search.hint' => '搜索代币、地址或交易',
			'search.empty' => '输入关键词开始搜索',
			'search.noResult' => '没有找到相关结果',
			'search.tabs.token' => '代币',
			'search.tabs.contract' => '合约',
			'search.tabs.dapp' => 'Dapp',
			'search.history' => '搜索历史',
			'search.clearHistory' => '清空',
			'search.hot' => '热门搜索',
			'scan.title' => '扫一扫',
			'scan.hint' => '将二维码放入框内即可自动扫描',
			'balance.unavailable' => '--',
			'balance.pending' => '待确认',
			'create.generatingTitle' => '正在创建你的专属钱包',
			'create.generatingHint' => '正在生成助记词并派生地址，请勿离开页面',
			'create.successTitle' => '钱包创建成功',
			'create.successSubtitle' => '你的全新钱包已就绪，快开始使用吧',
			'create.start' => '开始使用新钱包',
			'create.walletName' => '我的钱包',
			'create.failed' => '创建失败，请重试',
			'create.retry' => '重试',
			'createWallet.title' => '创建钱包',
			'createWallet.create.title' => '新建助记词钱包',
			'createWallet.create.subtitle' => '生成一组全新的助记词并创建钱包',
			'createWallet.import.title' => '导入已有钱包',
			'createWallet.import.subtitle' => '通过助记词或私钥恢复已有钱包',
			'createWallet.hardware.title' => '连接硬件钱包',
			'createWallet.hardware.subtitle' => '连接 Ledger、Trezor 等硬件设备',
			'import.selectTitle' => '选择导入钱包',
			'import.software' => '助记词或私钥',
			'import.hardware' => '硬件钱包',
			'import.mnemonic.title' => '导入助记词或私钥',
			'import.mnemonic.hint' => '请输入助记词（单词以空格分隔），或直接粘贴私钥',
			'import.mnemonic.helper' => '自动识别助记词或私钥；输入助记词时键盘上方会提示 BIP39 候选单词',
			'import.mnemonic.warning' => '请勿在不信任的环境下输入助记词或私钥，任何人获取后都能掌控你的资产。',
			'import.mnemonic.submit' => '导入',
			'import.mnemonic.wordCount' => ({required Object n}) => '${n} 个单词',
			'import.mnemonic.walletName' => '导入钱包',
			'import.mnemonic.deriveFailed' => '地址派生失败',
			'import.mnemonic.saveFailed' => '钱包保存失败，请重试',
			'import.mnemonic.errors.empty' => '请输入助记词',
			'import.mnemonic.errors.nonEnglish' => '助记词只能包含英文单词',
			'import.mnemonic.errors.wordCount' => ({required Object count}) => '助记词应为 12 / 15 / 18 / 21 / 24 个单词，当前 ${count} 个',
			'import.mnemonic.errors.invalidWords' => ({required Object words}) => '存在无效单词：${words}',
			'import.mnemonic.errors.checksum' => '助记词校验失败，请检查顺序或拼写',
			'import.mnemonic.errors.invalidPrivateKey' => '私钥格式无效，请检查是否为完整的 EVM / Solana / Sui 私钥',
			'placeholder.wip' => '功能开发中',
			_ => null,
		};
	}
}
