import 'dart:typed_data';

import 'package:blockchain_utils/blockchain_utils.dart';
import '../blockchain/chain_registry.dart';

/// 助记词相关能力的统一封装: 集中 blockchain_utils 的调用, 隔离第三方库细节,便于将来替换与单测
class MnemonicService {
  const MnemonicService._();

  /// BIP39 英文词表 (用于前缀匹配候选与无效单词校验)
  static final List<String> englishWordlist = Bip39Languages.english.wordList;

  /// 校验助记词 (词表 + 校验), 通过返回 true
  static bool validate(String mnemonic) => Bip39MnemonicValidator().isValid(mnemonic);

  /// 生成新助记词, 默认 12 词
  static String generate() => Bip39MnemonicGenerator().fromWordsNumber(Bip39WordsNum.wordsNum12).toStr();

  /// 一次性派生「全部受支持链」的地址, 种子只从助记词推导一次
  static DerivedWallet deriveWallet(String mnemonic) {
    final seed = _seedFromMnemonic(mnemonic); // 根据助记词推导出二进制种子
    final addressByScheme = <DerivationScheme, String>{}; // 缓存地址容器

    // 遍历所有支持的派生方案(distinctDerivations 已去重)，派生地址
    for (final scheme in SupportedChains.distinctDerivations) {
      final acct = _derive(seed, scheme); // 根据种子和派生方案派生出账户(含地址)
      addressByScheme[scheme] = acct.publicKey.toAddress; // 缓存地址
    }

    // 映射成 chainId -> address（多条链可能共用同一派生方案, 所以对外用 chainId 索引）
    final addresses = <String, String>{
      for (final chain in SupportedChains.all) chain.id: addressByScheme[chain.derivation]!,
    };

    return DerivedWallet(addresses: addresses);
  }

  /// 助记词 → 某链私钥的**原始 32 字节**，供签名直接使用。
  ///
  /// 与 [derivePrivateKey] 走同一条派生（同一个 [_derive]），区别只在**不编码**：
  /// 那个方法是给「用户查看 / 导入别的钱包」用的可移植字符串，签名不该绕这一趟——
  /// Sui 的 bech32 首字节是曲线方案标志、BTC 的 WIF 夹着网络字节，
  /// 每多一次编解码就多一处能签错的地方；而且 Dart 的 String 不可变、无法清零，
  /// 私钥明文会一直留在内存里等 GC，字节数组则可以用完覆写。
  ///
  /// 各链一律返回 32 字节：Solana 的导出串虽是 64 字节（私钥 + 公钥），
  /// 但签名只需要前 32 字节的私钥本身，也就是这里的 [Bip44Base.privateKey] `.raw`。
  /// 返回的是**可写副本**，调用方用完应 [wipeKey] 清零。两个原因缺一不可：
  /// blockchain_utils 各曲线的 `.raw` 实现不一致——secp256k1 返回新数组，
  /// 而 ed25519 直接把内部列表交出来，就地清零会把密钥对象本身弄坏。
  static List<int> derivePrivateKeyBytes(String mnemonic, Chain chain) =>
      Uint8List.fromList(_derive(_seedFromMnemonic(mnemonic), chain.derivation).privateKey.raw);

  /// 助记词 → 某链私钥<按 [Chain.kind] 分别编码>(EVM 的 0x hex 可直接用于交易签名): 签名与导出场景共用
  /// - EVM / Tron：`0x` + secp256k1 十六进制；
  /// - Solana：base58（64 字节 = 32 字节私钥 + 32 字节公钥，兼容 Phantom 等）；
  /// - Sui：`suiprivkey1…` bech32（首字节 0x00 = ed25519 方案，与导入解码对称）；
  /// - Bitcoin：WIF（testnet 版本字节由币种配置自动带上）；
  /// - Aptos：`0x` + ed25519 十六进制。
  static String derivePrivateKey(String mnemonic, Chain chain) {
    final seed = _seedFromMnemonic(mnemonic); // 根据助记词推导出二进制种子词
    final acct = _derive(seed, chain.derivation); // 根据种子词 + 链的派生方案派生出账户
    final raw = acct.privateKey.raw; // 原始私钥的字节数组

    return switch (chain.kind) {
      ChainKind.evm || ChainKind.tron => _formatPrivateKey(raw),
      ChainKind.aptos => _formatPrivateKey(raw),
      ChainKind.solana => Base58Encoder.encode([...raw, ...acct.publicKey.compressed.sublist(1)]),
      ChainKind.sui => Bech32Encoder.encode('suiprivkey', [0x00, ...raw]),
      ChainKind.bitcoin => acct.privateKey.toWif(),
    };
  }

  /// 格式化私钥为 0x 前缀的十六进制字符串(EVM/TRON/APTOS)。
  static String _formatPrivateKey(List<int> raw) => '0x${BytesUtils.toHexString(raw)}';

  /// 统一助记词 -> seed 二进制种子词推导入口，避免多处重复，后续支持 passphrase 时只改一处。
  static List<int> _seedFromMnemonic(String mnemonic) => Bip39SeedGenerator(Mnemonic.fromString(mnemonic)).generate();

  /// 种子 + 派生方案 -> 该方案默认路径的账户, 全部地址派生统一入口, BTC 按脚本类型分流到 BIP44/84/86, 其余链一律走 BIP44 默认路径
  static Bip44Base<dynamic> _derive(List<int> seed, DerivationScheme scheme) => switch (scheme.btcScriptType) {
    null || BtcScriptType.p2pkh => Bip44.fromSeed(seed, scheme.coin).deriveDefaultPath,
    BtcScriptType.p2wpkh => Bip84.fromSeed(seed, _bip84Coin(scheme.coin)).deriveDefaultPath,
    BtcScriptType.p2tr => Bip86.fromSeed(seed, _bip86Coin(scheme.coin)).deriveDefaultPath,
  };

  /// BIP44 币种 -> BIP84 币种（仅 BTC 主网/测试网两种，其余为配置错误）。
  static Bip84Coins _bip84Coin(Bip44Coins coin) => switch (coin) {
    Bip44Coins.bitcoin => Bip84Coins.bitcoin,
    Bip44Coins.bitcoinTestnet => Bip84Coins.bitcoinTestnet,
    _ => throw ArgumentError('BIP84 仅支持 Bitcoin，收到 $coin'),
  };

  /// BIP44 币种 -> BIP86 币种（同上，Taproot 目前也只对 BTC 开放）。
  static Bip86Coins _bip86Coin(Bip44Coins coin) => switch (coin) {
    Bip44Coins.bitcoin => Bip86Coins.bitcoin,
    Bip44Coins.bitcoinTestnet => Bip86Coins.bitcoinTestnet,
    _ => throw ArgumentError('BIP86 仅支持 Bitcoin，收到 $coin'),
  };
}

/// 多链派生结果：各链地址 + 私钥导入场景的主私钥
class DerivedWallet {
  const DerivedWallet({required this.addresses, this.primaryPrivateKey});

  /// chainId -> 该链地址
  final Map<String, String> addresses;
  /// 主私钥，仅私钥导入钱包需要（无助记词，签名/导出只能靠已存私钥; 助记词派生（deriveWallet）为 null——私钥一律按需现场重派生，不预存。
  final String? primaryPrivateKey;

  /// 主地址(私钥导入钱包): 优先取 EVM 主链地址; 非 EVM 私钥导入时 map 只有该链一项, 取其唯一地址
  String get primaryAddress => addresses[SupportedChains.ethereumSepolia.id] ?? addresses.values.first;
}

/// 在后台 isolate 派生全部链地址（compute 顶层入口）
DerivedWallet deriveWalletInBackground(String mnemonic) => MnemonicService.deriveWallet(mnemonic);

/// 由助记词派生某条链的私钥<签名/导出共用>（compute 顶层入口）
/// 入参为 (助记词, chainId)：不把 [Chain] 整份塞进 isolate，到对端再 [SupportedChains.byId] 还原。
String derivePrivateKeyInBackground((String, String) args) =>
    MnemonicService.derivePrivateKey(args.$1, SupportedChains.byId(args.$2));

/// 由助记词派生某条链的**原始 32 字节**私钥<仅签名用>（compute 顶层入口）
/// 入参同上：(助记词, chainId)。
List<int> derivePrivateKeyBytesInBackground((String, String) args) =>
    MnemonicService.derivePrivateKeyBytes(args.$1, SupportedChains.byId(args.$2));
