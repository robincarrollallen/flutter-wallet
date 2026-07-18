import 'package:blockchain_utils/blockchain_utils.dart';

import '../domain/chain.dart';

/// 助记词相关能力的统一封装：集中 blockchain_utils 的调用，
/// 隔离第三方库细节，便于将来替换与单测。
class MnemonicService {
  const MnemonicService._();

  /// BIP39 英文词表（用于前缀匹配候选与无效单词校验），仅取一次后缓存。
  static final List<String> englishWordlist = Bip39Languages.english.wordList;

  /// 校验助记词（词表 + 校验和），通过返回 true。
  static bool validate(String mnemonic) =>
      Bip39MnemonicValidator().isValid(mnemonic);

  /// 生成新助记词，默认 12 词。
  static String generate() =>
      Bip39MnemonicGenerator()
          .fromWordsNumber(Bip39WordsNum.wordsNum12)
          .toStr();

  /// 由助记词派生以太坊首地址（BIP44 默认路径 m/44'/60'/0'/0/0），返回 0x… 字符串。
  static String deriveEthAddress(String mnemonic) =>
      _deriveDefault(mnemonic).publicKey.toAddress;

  /// 由助记词派生以太坊首账户的私钥（BIP44 默认路径），返回 0x 前缀的十六进制字符串。
  /// 注意：私钥为高度敏感数据，仅可写入安全存储，切勿放入状态或日志。
  static String derivePrivateKey(String mnemonic) =>
      _formatPrivateKey(_deriveDefault(mnemonic).privateKey.raw);

  /// 一次性派生地址 + 私钥（只跑一次重运算，避免重复推导种子）。
  static DerivedAccount deriveAccount(String mnemonic) {
    final account = _deriveDefault(mnemonic);
    return DerivedAccount(
      address: account.publicKey.toAddress,
      privateKey: _formatPrivateKey(account.privateKey.raw),
    );
  }

  /// 一次性派生「全部受支持链」的地址 + 以太坊主私钥。
  /// 种子只从助记词推导一次，再按各币种派生，避免重复重运算。
  static DerivedWallet deriveWallet(String mnemonic) {
    final seed = Bip39SeedGenerator(Mnemonic.fromString(mnemonic)).generate();

    // 先按去重后的币种各派生一次（EVM 多链共用同一地址）。
    final addressByCoin = <Bip44Coins, String>{};
    final pkByCoin = <Bip44Coins, String>{};
    for (final coin in SupportedChains.distinctCoins) {
      final acct = Bip44.fromSeed(seed, coin).deriveDefaultPath;
      addressByCoin[coin] = acct.publicKey.toAddress;
      pkByCoin[coin] = _formatPrivateKey(acct.privateKey.raw);
    }

    // 映射成 chainId -> address。
    final addresses = <String, String>{
      for (final chain in SupportedChains.all)
        chain.id: addressByCoin[chain.coin]!,
    };

    final eth = SupportedChains.ethereumSepolia.coin;
    return DerivedWallet(
      addresses: addresses,
      primaryAddress: addressByCoin[eth]!,
      primaryPrivateKey: pkByCoin[eth]!,
    );
  }

  /// 由助记词按某条链的币种现场派生「可导出/可回导」的私钥字符串。
  ///
  /// 不同链私钥的规范可移植格式不同，按 [Chain.kind] 分别编码：
  /// - EVM / Tron：`0x` + secp256k1 十六进制；
  /// - Solana：base58（64 字节 = 32 字节私钥 + 32 字节公钥，兼容 Phantom 等）；
  /// - Sui：`suiprivkey1…` bech32（首字节 0x00 = ed25519 方案，与导入解码对称）；
  /// - Bitcoin：WIF（testnet 版本字节由币种配置自动带上）；
  /// - Aptos：`0x` + ed25519 十六进制。
  ///
  /// 仅在导出场景按需调用，结果为敏感明文，切勿写入状态 / 日志 / 持久化。
  static String deriveExportKey(String mnemonic, Chain chain) {
    final seed = Bip39SeedGenerator(Mnemonic.fromString(mnemonic)).generate();
    final acct = Bip44.fromSeed(seed, chain.coin).deriveDefaultPath;
    final raw = acct.privateKey.raw;

    return switch (chain.kind) {
      ChainKind.evm || ChainKind.tron => _formatPrivateKey(raw),
      ChainKind.aptos => _formatPrivateKey(raw),
      // 公钥 compressed 首字节为 0x00 前缀，去掉得纯 32 字节公钥。
      ChainKind.solana => Base58Encoder.encode(
          [...raw, ...acct.publicKey.compressed.sublist(1)],
        ),
      ChainKind.sui => Bech32Encoder.encode('suiprivkey', [0x00, ...raw]),
      ChainKind.bitcoin => acct.privateKey.toWif(),
    };
  }

  static String _formatPrivateKey(List<int> raw) =>
      '0x${BytesUtils.toHexString(raw)}';

  static Bip44 _deriveDefault(String mnemonic) {
    final seed = Bip39SeedGenerator(Mnemonic.fromString(mnemonic)).generate();
    return Bip44.fromSeed(seed, Bip44Coins.ethereum).deriveDefaultPath;
  }
}

/// 多链派生结果：各链地址 + 以太坊主账户私钥（用于安全存储）。
class DerivedWallet {
  const DerivedWallet({
    required this.addresses,
    required this.primaryAddress,
    required this.primaryPrivateKey,
  });

  /// chainId -> 该链地址。
  final Map<String, String> addresses;
  final String primaryAddress;
  final String primaryPrivateKey;
}

/// compute() 顶层入口：在后台 isolate 派生全部链地址。
DerivedWallet deriveWalletInBackground(String mnemonic) =>
    MnemonicService.deriveWallet(mnemonic);

/// compute() 顶层入口：在后台 isolate 由助记词派生某条链的可导出私钥。
///
/// 入参为 (助记词, chainId)：避免把含 Token 列表的 [Chain] 跨 isolate 传输，
/// 在 isolate 内经 [SupportedChains.byId] 还原为 Chain。
String deriveExportKeyInBackground((String, String) args) =>
    MnemonicService.deriveExportKey(args.$1, SupportedChains.byId(args.$2));

/// 派生结果：以太坊首账户的地址与私钥。
class DerivedAccount {
  const DerivedAccount({required this.address, required this.privateKey});

  final String address;
  final String privateKey;
}

/// compute() 的顶层入口：在后台 isolate 执行重运算（PBKDF2 种子推导 + BIP44 派生），
/// 避免阻塞 UI 线程。必须是顶层/静态函数才能被 compute 调用。
DerivedAccount deriveAccountInBackground(String mnemonic) =>
    MnemonicService.deriveAccount(mnemonic);
