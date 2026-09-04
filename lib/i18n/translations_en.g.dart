///
/// Generated file. Do not edit.
///
// coverage:ignore-file
// ignore_for_file: type=lint, unused_import
// dart format off

part of 'translations.g.dart';

// Path: <root>
typedef TranslationsEn = Translations; // ignore: unused_element
class Translations with BaseTranslations<AppLocale, Translations> {
	/// Returns the current translations of the given [context].
	///
	/// Usage:
	/// final t = Translations.of(context);
	static Translations of(BuildContext context) => InheritedLocaleData.of<AppLocale, Translations>(context).translations;

	/// You can call this constructor and build your own translation instance of this locale.
	/// Constructing via the enum [AppLocale.build] is preferred.
	Translations({Map<String, Node>? overrides, PluralResolver? cardinalResolver, PluralResolver? ordinalResolver, TranslationMetadata<AppLocale, Translations>? meta})
		: assert(overrides == null, 'Set "translation_overrides: true" in order to enable this feature.'),
		  $meta = meta ?? TranslationMetadata(
		    locale: AppLocale.en,
		    overrides: overrides ?? {},
		    cardinalResolver: cardinalResolver,
		    ordinalResolver: ordinalResolver,
		  ) {
		$meta.setFlatMapFunction(_flatMapFunction);
	}

	/// Metadata for the translations of <en>.
	@override final TranslationMetadata<AppLocale, Translations> $meta;

	/// Access flat map
	dynamic operator[](String key) => $meta.getTranslation(key);

	late final Translations _root = this; // ignore: unused_field

	Translations $copyWith({TranslationMetadata<AppLocale, Translations>? meta}) => Translations(meta: meta ?? this.$meta);

	// Translations

	/// en: 'My Wallet'
	String get appTitle => 'My Wallet';

	late final Translations$tabs$en tabs = Translations$tabs$en.internal(_root);
	late final Translations$home$en home = Translations$home$en.internal(_root);
	late final Translations$manageTokens$en manageTokens = Translations$manageTokens$en.internal(_root);
	late final Translations$settings$en settings = Translations$settings$en.internal(_root);
	late final Translations$currency$en currency = Translations$currency$en.internal(_root);
	Map<String, String> get currencyNames => {
		'USD': 'United States Dollar',
		'EUR': 'Euro',
		'GBP': 'British Pound',
		'JPY': 'Japanese Yen',
		'CNY': 'Chinese Yuan',
		'HKD': 'Hong Kong Dollar',
		'TWD': 'New Taiwan Dollar',
		'KRW': 'South Korean Won',
		'AUD': 'Australian Dollar',
		'NZD': 'New Zealand Dollar',
		'CAD': 'Canadian Dollar',
		'SGD': 'Singapore Dollar',
		'PHP': 'Philippine Peso',
		'THB': 'Thai Baht',
		'VND': 'Vietnamese Dong',
		'INR': 'Indian Rupee',
		'IDR': 'Indonesian Rupiah',
		'MYR': 'Malaysian Ringgit',
		'BDT': 'Bangladeshi Taka',
		'PKR': 'Pakistani Rupee',
		'LKR': 'Sri Lankan Rupee',
		'MMK': 'Myanmar Kyat',
		'BRL': 'Brazilian Real',
		'MXN': 'Mexican Peso',
		'ARS': 'Argentine Peso',
		'CLP': 'Chilean Peso',
		'BMD': 'Bermudian Dollar',
		'VEF': 'Venezuelan Bolívar',
		'CHF': 'Swiss Franc',
		'SEK': 'Swedish Krona',
		'NOK': 'Norwegian Krone',
		'DKK': 'Danish Krone',
		'PLN': 'Polish Zloty',
		'CZK': 'Czech Koruna',
		'HUF': 'Hungarian Forint',
		'RUB': 'Russian Ruble',
		'UAH': 'Ukrainian Hryvnia',
		'GEL': 'Georgian Lari',
		'TRY': 'Turkish Lira',
		'ILS': 'Israeli New Shekel',
		'AED': 'UAE Dirham',
		'SAR': 'Saudi Riyal',
		'KWD': 'Kuwaiti Dinar',
		'BHD': 'Bahraini Dinar',
		'NGN': 'Nigerian Naira',
		'ZAR': 'South African Rand',
	};
	late final Translations$search$en search = Translations$search$en.internal(_root);
	late final Translations$scan$en scan = Translations$scan$en.internal(_root);
	late final Translations$balance$en balance = Translations$balance$en.internal(_root);
	late final Translations$create$en create = Translations$create$en.internal(_root);
	late final Translations$createWallet$en createWallet = Translations$createWallet$en.internal(_root);
	late final Translations$import$en import = Translations$import$en.internal(_root);
	late final Translations$placeholder$en placeholder = Translations$placeholder$en.internal(_root);
}

// Path: tabs
class Translations$tabs$en {
	Translations$tabs$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Home'
	String get home => 'Home';

	/// en: 'Market'
	String get market => 'Market';

	/// en: 'Exchange'
	String get exchange => 'Exchange';

	/// en: 'Contract'
	String get contract => 'Contract';

	/// en: 'Discover'
	String get discover => 'Discover';
}

// Path: home
class Translations$home$en {
	Translations$home$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'No wallet yet'
	String get noWalletTitle => 'No wallet yet';

	/// en: 'Create or import a wallet to get started'
	String get noWalletSubtitle => 'Create or import a wallet to get started';

	/// en: 'Create Wallet'
	String get createWallet => 'Create Wallet';

	/// en: 'Total Assets'
	String get totalAssets => 'Total Assets';

	/// en: 'Scanning on-chain assets…'
	String get assetsScanning => 'Scanning on-chain assets…';

	/// en: 'Some chains failed to load'
	String get partialAssets => 'Some chains failed to load';

	/// en: 'Search tokens, addresses or transactions'
	String get searchHint => 'Search tokens, addresses or transactions';

	/// en: 'Settings'
	String get settings => 'Settings';

	/// en: 'Scan'
	String get scan => 'Scan';

	/// en: 'Tokens'
	String get tokens => 'Tokens';

	/// en: 'Manage tokens'
	String get manageTokens => 'Manage tokens';
}

// Path: manageTokens
class Translations$manageTokens$en {
	Translations$manageTokens$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Manage tokens'
	String get title => 'Manage tokens';

	/// en: 'Search tokens or chains'
	String get searchHint => 'Search tokens or chains';

	/// en: 'No matching assets'
	String get empty => 'No matching assets';
}

// Path: settings
class Translations$settings$en {
	Translations$settings$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Settings'
	String get title => 'Settings';

	/// en: 'General'
	String get general => 'General';

	/// en: 'Security'
	String get security => 'Security';

	/// en: 'About'
	String get about => 'About';
}

// Path: currency
class Translations$currency$en {
	Translations$currency$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Currency'
	String get title => 'Currency';

	/// en: 'Search currency'
	String get searchHint => 'Search currency';
}

// Path: search
class Translations$search$en {
	Translations$search$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Search'
	String get title => 'Search';

	/// en: 'Search tokens, addresses or transactions'
	String get hint => 'Search tokens, addresses or transactions';

	/// en: 'Type a keyword to start searching'
	String get empty => 'Type a keyword to start searching';

	/// en: 'No matching results'
	String get noResult => 'No matching results';

	late final Translations$search$tabs$en tabs = Translations$search$tabs$en.internal(_root);

	/// en: 'Search history'
	String get history => 'Search history';

	/// en: 'Clear'
	String get clearHistory => 'Clear';

	/// en: 'Trending'
	String get hot => 'Trending';
}

// Path: scan
class Translations$scan$en {
	Translations$scan$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Scan'
	String get title => 'Scan';

	/// en: 'Place the QR code inside the frame to scan automatically'
	String get hint => 'Place the QR code inside the frame to scan automatically';
}

// Path: balance
class Translations$balance$en {
	Translations$balance$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: '--'
	String get unavailable => '--';

	/// en: 'Pending'
	String get pending => 'Pending';
}

// Path: create
class Translations$create$en {
	Translations$create$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Creating your wallet'
	String get generatingTitle => 'Creating your wallet';

	/// en: 'Generating the mnemonic and deriving the address — please stay on this page'
	String get generatingHint => 'Generating the mnemonic and deriving the address — please stay on this page';

	/// en: 'Wallet created'
	String get successTitle => 'Wallet created';

	/// en: 'Your brand-new wallet is ready to go'
	String get successSubtitle => 'Your brand-new wallet is ready to go';

	/// en: 'Start using my new wallet'
	String get start => 'Start using my new wallet';

	/// en: 'My wallet'
	String get walletName => 'My wallet';

	/// en: 'Creation failed, please try again'
	String get failed => 'Creation failed, please try again';

	/// en: 'Retry'
	String get retry => 'Retry';
}

// Path: createWallet
class Translations$createWallet$en {
	Translations$createWallet$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Create Wallet'
	String get title => 'Create Wallet';

	late final Translations$createWallet$create$en create = Translations$createWallet$create$en.internal(_root);
	late final Translations$createWallet$import$en import = Translations$createWallet$import$en.internal(_root);
	late final Translations$createWallet$hardware$en hardware = Translations$createWallet$hardware$en.internal(_root);
}

// Path: import
class Translations$import$en {
	Translations$import$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Import Wallet'
	String get selectTitle => 'Import Wallet';

	/// en: 'Mnemonic or private key'
	String get software => 'Mnemonic or private key';

	/// en: 'Hardware wallet'
	String get hardware => 'Hardware wallet';

	late final Translations$import$mnemonic$en mnemonic = Translations$import$mnemonic$en.internal(_root);
}

// Path: placeholder
class Translations$placeholder$en {
	Translations$placeholder$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Feature under development'
	String get wip => 'Feature under development';
}

// Path: search.tabs
class Translations$search$tabs$en {
	Translations$search$tabs$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Token'
	String get token => 'Token';

	/// en: 'Contract'
	String get contract => 'Contract';

	/// en: 'Dapp'
	String get dapp => 'Dapp';
}

// Path: createWallet.create
class Translations$createWallet$create$en {
	Translations$createWallet$create$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'New mnemonic wallet'
	String get title => 'New mnemonic wallet';

	/// en: 'Generate a brand-new mnemonic phrase and create a wallet'
	String get subtitle => 'Generate a brand-new mnemonic phrase and create a wallet';
}

// Path: createWallet.import
class Translations$createWallet$import$en {
	Translations$createWallet$import$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Import existing wallet'
	String get title => 'Import existing wallet';

	/// en: 'Recover an existing wallet via mnemonic or private key'
	String get subtitle => 'Recover an existing wallet via mnemonic or private key';
}

// Path: createWallet.hardware
class Translations$createWallet$hardware$en {
	Translations$createWallet$hardware$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Connect hardware wallet'
	String get title => 'Connect hardware wallet';

	/// en: 'Connect Ledger, Trezor and other hardware devices'
	String get subtitle => 'Connect Ledger, Trezor and other hardware devices';
}

// Path: import.mnemonic
class Translations$import$mnemonic$en {
	Translations$import$mnemonic$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Import mnemonic or private key'
	String get title => 'Import mnemonic or private key';

	/// en: 'Enter your mnemonic (space-separated) or paste a private key'
	String get hint => 'Enter your mnemonic (space-separated) or paste a private key';

	/// en: 'Mnemonic or private key is auto-detected; BIP39 suggestions appear above the keyboard while typing a mnemonic'
	String get helper => 'Mnemonic or private key is auto-detected; BIP39 suggestions appear above the keyboard while typing a mnemonic';

	/// en: 'Never enter your mnemonic in an untrusted environment — anyone who obtains it can control your assets.'
	String get warning => 'Never enter your mnemonic in an untrusted environment — anyone who obtains it can control your assets.';

	/// en: 'Import'
	String get submit => 'Import';

	/// en: '{n} words'
	String wordCount({required Object n}) => '${n} words';

	/// en: 'Imported wallet'
	String get walletName => 'Imported wallet';

	/// en: 'Failed to derive address'
	String get deriveFailed => 'Failed to derive address';

	/// en: 'Failed to save wallet, please try again'
	String get saveFailed => 'Failed to save wallet, please try again';

	late final Translations$import$mnemonic$errors$en errors = Translations$import$mnemonic$errors$en.internal(_root);
}

// Path: import.mnemonic.errors
class Translations$import$mnemonic$errors$en {
	Translations$import$mnemonic$errors$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Please enter your mnemonic'
	String get empty => 'Please enter your mnemonic';

	/// en: 'Mnemonic may only contain English words'
	String get nonEnglish => 'Mnemonic may only contain English words';

	/// en: 'Mnemonic must be 12 / 15 / 18 / 21 / 24 words, currently {count}'
	String wordCount({required Object count}) => 'Mnemonic must be 12 / 15 / 18 / 21 / 24 words, currently ${count}';

	/// en: 'Invalid words: {words}'
	String invalidWords({required Object words}) => 'Invalid words: ${words}';

	/// en: 'Mnemonic checksum failed, please check the order or spelling'
	String get checksum => 'Mnemonic checksum failed, please check the order or spelling';

	/// en: 'Invalid private key format. Please check it is a complete EVM / Solana / Sui private key'
	String get invalidPrivateKey => 'Invalid private key format. Please check it is a complete EVM / Solana / Sui private key';
}

/// The flat map containing all translations for locale <en>.
/// Only for edge cases! For simple maps, use the map function of this library.
///
/// The Dart AOT compiler has issues with very large switch statements,
/// so the map is split into smaller functions (512 entries each).
extension on Translations {
	dynamic _flatMapFunction(String path) {
		return switch (path) {
			'appTitle' => 'My Wallet',
			'tabs.home' => 'Home',
			'tabs.market' => 'Market',
			'tabs.exchange' => 'Exchange',
			'tabs.contract' => 'Contract',
			'tabs.discover' => 'Discover',
			'home.noWalletTitle' => 'No wallet yet',
			'home.noWalletSubtitle' => 'Create or import a wallet to get started',
			'home.createWallet' => 'Create Wallet',
			'home.totalAssets' => 'Total Assets',
			'home.assetsScanning' => 'Scanning on-chain assets…',
			'home.partialAssets' => 'Some chains failed to load',
			'home.searchHint' => 'Search tokens, addresses or transactions',
			'home.settings' => 'Settings',
			'home.scan' => 'Scan',
			'home.tokens' => 'Tokens',
			'home.manageTokens' => 'Manage tokens',
			'manageTokens.title' => 'Manage tokens',
			'manageTokens.searchHint' => 'Search tokens or chains',
			'manageTokens.empty' => 'No matching assets',
			'settings.title' => 'Settings',
			'settings.general' => 'General',
			'settings.security' => 'Security',
			'settings.about' => 'About',
			'currency.title' => 'Currency',
			'currency.searchHint' => 'Search currency',
			'currencyNames.USD' => 'United States Dollar',
			'currencyNames.EUR' => 'Euro',
			'currencyNames.GBP' => 'British Pound',
			'currencyNames.JPY' => 'Japanese Yen',
			'currencyNames.CNY' => 'Chinese Yuan',
			'currencyNames.HKD' => 'Hong Kong Dollar',
			'currencyNames.TWD' => 'New Taiwan Dollar',
			'currencyNames.KRW' => 'South Korean Won',
			'currencyNames.AUD' => 'Australian Dollar',
			'currencyNames.NZD' => 'New Zealand Dollar',
			'currencyNames.CAD' => 'Canadian Dollar',
			'currencyNames.SGD' => 'Singapore Dollar',
			'currencyNames.PHP' => 'Philippine Peso',
			'currencyNames.THB' => 'Thai Baht',
			'currencyNames.VND' => 'Vietnamese Dong',
			'currencyNames.INR' => 'Indian Rupee',
			'currencyNames.IDR' => 'Indonesian Rupiah',
			'currencyNames.MYR' => 'Malaysian Ringgit',
			'currencyNames.BDT' => 'Bangladeshi Taka',
			'currencyNames.PKR' => 'Pakistani Rupee',
			'currencyNames.LKR' => 'Sri Lankan Rupee',
			'currencyNames.MMK' => 'Myanmar Kyat',
			'currencyNames.BRL' => 'Brazilian Real',
			'currencyNames.MXN' => 'Mexican Peso',
			'currencyNames.ARS' => 'Argentine Peso',
			'currencyNames.CLP' => 'Chilean Peso',
			'currencyNames.BMD' => 'Bermudian Dollar',
			'currencyNames.VEF' => 'Venezuelan Bolívar',
			'currencyNames.CHF' => 'Swiss Franc',
			'currencyNames.SEK' => 'Swedish Krona',
			'currencyNames.NOK' => 'Norwegian Krone',
			'currencyNames.DKK' => 'Danish Krone',
			'currencyNames.PLN' => 'Polish Zloty',
			'currencyNames.CZK' => 'Czech Koruna',
			'currencyNames.HUF' => 'Hungarian Forint',
			'currencyNames.RUB' => 'Russian Ruble',
			'currencyNames.UAH' => 'Ukrainian Hryvnia',
			'currencyNames.GEL' => 'Georgian Lari',
			'currencyNames.TRY' => 'Turkish Lira',
			'currencyNames.ILS' => 'Israeli New Shekel',
			'currencyNames.AED' => 'UAE Dirham',
			'currencyNames.SAR' => 'Saudi Riyal',
			'currencyNames.KWD' => 'Kuwaiti Dinar',
			'currencyNames.BHD' => 'Bahraini Dinar',
			'currencyNames.NGN' => 'Nigerian Naira',
			'currencyNames.ZAR' => 'South African Rand',
			'search.title' => 'Search',
			'search.hint' => 'Search tokens, addresses or transactions',
			'search.empty' => 'Type a keyword to start searching',
			'search.noResult' => 'No matching results',
			'search.tabs.token' => 'Token',
			'search.tabs.contract' => 'Contract',
			'search.tabs.dapp' => 'Dapp',
			'search.history' => 'Search history',
			'search.clearHistory' => 'Clear',
			'search.hot' => 'Trending',
			'scan.title' => 'Scan',
			'scan.hint' => 'Place the QR code inside the frame to scan automatically',
			'balance.unavailable' => '--',
			'balance.pending' => 'Pending',
			'create.generatingTitle' => 'Creating your wallet',
			'create.generatingHint' => 'Generating the mnemonic and deriving the address — please stay on this page',
			'create.successTitle' => 'Wallet created',
			'create.successSubtitle' => 'Your brand-new wallet is ready to go',
			'create.start' => 'Start using my new wallet',
			'create.walletName' => 'My wallet',
			'create.failed' => 'Creation failed, please try again',
			'create.retry' => 'Retry',
			'createWallet.title' => 'Create Wallet',
			'createWallet.create.title' => 'New mnemonic wallet',
			'createWallet.create.subtitle' => 'Generate a brand-new mnemonic phrase and create a wallet',
			'createWallet.import.title' => 'Import existing wallet',
			'createWallet.import.subtitle' => 'Recover an existing wallet via mnemonic or private key',
			'createWallet.hardware.title' => 'Connect hardware wallet',
			'createWallet.hardware.subtitle' => 'Connect Ledger, Trezor and other hardware devices',
			'import.selectTitle' => 'Import Wallet',
			'import.software' => 'Mnemonic or private key',
			'import.hardware' => 'Hardware wallet',
			'import.mnemonic.title' => 'Import mnemonic or private key',
			'import.mnemonic.hint' => 'Enter your mnemonic (space-separated) or paste a private key',
			'import.mnemonic.helper' => 'Mnemonic or private key is auto-detected; BIP39 suggestions appear above the keyboard while typing a mnemonic',
			'import.mnemonic.warning' => 'Never enter your mnemonic in an untrusted environment — anyone who obtains it can control your assets.',
			'import.mnemonic.submit' => 'Import',
			'import.mnemonic.wordCount' => ({required Object n}) => '${n} words',
			'import.mnemonic.walletName' => 'Imported wallet',
			'import.mnemonic.deriveFailed' => 'Failed to derive address',
			'import.mnemonic.saveFailed' => 'Failed to save wallet, please try again',
			'import.mnemonic.errors.empty' => 'Please enter your mnemonic',
			'import.mnemonic.errors.nonEnglish' => 'Mnemonic may only contain English words',
			'import.mnemonic.errors.wordCount' => ({required Object count}) => 'Mnemonic must be 12 / 15 / 18 / 21 / 24 words, currently ${count}',
			'import.mnemonic.errors.invalidWords' => ({required Object words}) => 'Invalid words: ${words}',
			'import.mnemonic.errors.checksum' => 'Mnemonic checksum failed, please check the order or spelling',
			'import.mnemonic.errors.invalidPrivateKey' => 'Invalid private key format. Please check it is a complete EVM / Solana / Sui private key',
			'placeholder.wip' => 'Feature under development',
			_ => null,
		};
	}
}
