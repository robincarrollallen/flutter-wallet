import 'package:blockchain_utils/blockchain_utils.dart';
import '../blockchain/chain_registry.dart';

/// 助记词相关能力的统一封装：集中 blockchain_utils 的调用，
/// 隔离第三方库细节，便于将来替换与单测。
class MnemonicService {
  const MnemonicService._();

  /// BIP39 英文词表（用于前缀匹配候选与无效单词校验），仅取一次后缓存。
  static final List<String> englishWordlist = Bip39Languages.english.wordList;

  /// 校验助记词（词表 + 校验和），通过返回 true。
  static bool validate(String mnemonic) => Bip39MnemonicValidator().isValid(mnemonic);

  /// 生成新助记词，默认 12 词。
  static String generate() => Bip39MnemonicGenerator().fromWordsNumber(Bip39WordsNum.wordsNum12).toStr();

  /// 由助记词派生以太坊首地址（BIP44 默认路径 m/44'/60'/0'/0/0），返回 0x… 字符串。
  static String deriveEthAddress(String mnemonic) => _deriveDefault(mnemonic).publicKey.toAddress;

  /// 一次性派生「全部受支持链」的地址，种子只从助记词推导一次。
  static DerivedWallet deriveWallet(String mnemonic) {
    final seed = _seedFromMnemonic(mnemonic); // 根据助记词推导出二进制种子

    final addressByCoin = <Bip44Coins, String>{}; // 缓存地址容器
    // 遍历所有支持的币种(distinctCoins已去重)，派生地址
    for (final coin in SupportedChains.distinctCoins) {
      final acct = _derive(seed, coin); // 根据种子和币种派生出账户
      addressByCoin[coin] = acct.publicKey.toAddress; // 缓存地址
    }

    // 映射成 chainId -> address（coin币种有相同值，所以使用chainId映射）
    final addresses = <String, String>{for (final chain in SupportedChains.all) chain.id: addressByCoin[chain.coin]!};

    return DerivedWallet(addresses: addresses);
  }

  /// 助记词 → 某链私钥<按 [Chain.kind] 分别编码>(EVM 的 0x hex 可直接用于交易签名): 签名与导出场景共用
  /// - EVM / Tron：`0x` + secp256k1 十六进制；
  /// - Solana：base58（64 字节 = 32 字节私钥 + 32 字节公钥，兼容 Phantom 等）；
  /// - Sui：`suiprivkey1…` bech32（首字节 0x00 = ed25519 方案，与导入解码对称）；
  /// - Bitcoin：WIF（testnet 版本字节由币种配置自动带上）；
  /// - Aptos：`0x` + ed25519 十六进制。
  static String derivePrivateKey(String mnemonic, Chain chain) {
    final seed = _seedFromMnemonic(mnemonic); // 根据助记词推导出二进制种子词
    final acct = _derive(seed, chain.coin); // 根据种子词 + 链原生币标识派生出BIP44 账户
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

  /// 种子 + 链原生币标识 -> 该币种默认路径的 BIP44 账户，全部地址派生统一入口。
  static Bip44 _derive(List<int> seed, Bip44Coins coin) => Bip44.fromSeed(seed, coin).deriveDefaultPath;

  /// 助记词 -> 以太坊默认账户（EVM 快捷入口）。
  static Bip44 _deriveDefault(String mnemonic) {
    final seed = _seedFromMnemonic(mnemonic); // 根据助记词推导出二进制种子
    return _derive(seed, Bip44Coins.ethereum);
  }
}

/// 多链派生结果：各链地址（+ 私钥导入场景的主私钥）。
class DerivedWallet {
  const DerivedWallet({required this.addresses, this.primaryPrivateKey});

  final Map<String, String> addresses; // chainId -> 该链地址。
  final String? primaryPrivateKey; // 主私钥，仅私钥导入钱包需要（无助记词，签名/导出只能靠已存私钥; 助记词派生（deriveWallet）为 null——私钥一律按需现场重派生，不预存。

  /// 主地址（私钥导入钱包）：优先取 EVM 主链地址；
  /// 非 EVM 私钥导入时 map 只有该链一项，取其唯一地址。
  String get primaryAddress => addresses[SupportedChains.ethereumSepolia.id] ?? addresses.values.first;
}

/// 在后台 isolate 派生全部链地址（compute 顶层入口）
DerivedWallet deriveWalletInBackground(String mnemonic) => MnemonicService.deriveWallet(mnemonic);

/// 由助记词派生某条链的私钥<签名/导出共用>（compute 顶层入口）
/// 入参为 (助记词, chainId)：不把 [Chain] 整份塞进 isolate，到对端再 [SupportedChains.byId] 还原。
String derivePrivateKeyInBackground((String, String) args) =>
    MnemonicService.derivePrivateKey(args.$1, SupportedChains.byId(args.$2));
