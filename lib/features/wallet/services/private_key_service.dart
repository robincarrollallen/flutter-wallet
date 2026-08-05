import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:wallet/core/blockchain/chain_registry.dart';

import 'mnemonic_service.dart';

/// 自动判断出的私钥类型。
/// - [evmHex]：secp256k1 的 64 位十六进制（可带 0x），同一把私钥可还原全部 EVM 链 + Tron 地址。
/// - [solanaBase58]：Solana ed25519 私钥（base58，32 或 64 字节）。
/// - [suiBech32]：Sui 私钥（`suiprivkey1...` bech32）。
/// - [unknown]：无法识别。
enum PrivateKeyKind { evmHex, solanaBase58, suiBech32, unknown }

/// 私钥导入相关能力的统一封装：集中 blockchain_utils 调用，隔离第三方库细节，
/// 便于将来替换与单测。复用 [DerivedWallet] 作为派生结果。
///
/// 注意：Aptos 私钥同样是 64 位 hex（ed25519），与 EVM 的 secp256k1 hex 格式无法
/// 自动区分，故不纳入自动判断；Aptos 地址仅通过助记词派生。
class PrivateKeyService {
  const PrivateKeyService._();

  /// Sui 私钥 bech32 的 HRP 前缀。
  static const _suiHrp = 'suiprivkey';

  /// 规整输入：仅去首尾空白（私钥大小写敏感，不做 toLowerCase 折叠）。
  static String normalize(String input) => input.trim();

  /// 自动判断私钥类型；无法识别返回 [PrivateKeyKind.unknown]。
  static PrivateKeyKind detect(String input) {
    final s = normalize(input);
    if (s.isEmpty) return PrivateKeyKind.unknown;
    // 先判 Sui：有明确 HRP 前缀，最不易误判。
    if (s.toLowerCase().startsWith('${_suiHrp}1')) {
      return _isValidSui(s) ? PrivateKeyKind.suiBech32 : PrivateKeyKind.unknown;
    }
    // 再判 EVM hex：固定 64 位十六进制。
    if (_isEvmHex(s)) return PrivateKeyKind.evmHex;
    // 最后判 Solana base58（32 或 64 字节）。
    if (_isSolanaKey(s)) return PrivateKeyKind.solanaBase58;
    return PrivateKeyKind.unknown;
  }

  /// 按类型派生钱包。调用方应先用 [detect] 得到非 unknown 的类型。
  static DerivedWallet derive(PrivateKeyKind kind, String input) {
    final s = normalize(input);
    return switch (kind) {
      PrivateKeyKind.evmHex => _deriveEvm(s),
      PrivateKeyKind.solanaBase58 => _deriveSolana(s),
      PrivateKeyKind.suiBech32 => _deriveSui(s),
      PrivateKeyKind.unknown => throw ArgumentError('无法识别的私钥，无法派生'),
    };
  }

  // —— 各类型校验 —— //

  static bool _isEvmHex(String s) =>
      RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(_strip0x(s));

  static bool _isSolanaKey(String s) {
    try {
      final bytes = Base58Decoder.decode(s);
      return bytes.length == 32 || bytes.length == 64;
    } catch (_) {
      return false;
    }
  }

  static bool _isValidSui(String s) {
    try {
      _decodeSui(s);
      return true;
    } catch (_) {
      return false;
    }
  }

  // —— 各类型派生 —— //

  /// secp256k1 hex：同一把私钥还原全部 EVM 链（共用 0x 地址）+ Tron 地址。
  static DerivedWallet _deriveEvm(String s) {
    final hex = _strip0x(s);
    final priv = Secp256k1PrivateKey.fromBytes(BytesUtils.fromHexString(hex));
    final pub = priv.publicKey.compressed;
    final evmAddr = EthAddrEncoder().encodeKey(pub);
    final tronAddr = TrxAddrEncoder().encodeKey(pub);

    final addresses = <String, String>{};
    for (final chain in SupportedChains.all) {
      if (chain.kind == ChainKind.evm) {
        addresses[chain.id] = evmAddr;
      } else if (chain.kind == ChainKind.tron) {
        addresses[chain.id] = tronAddr;
      }
    }
    return DerivedWallet(
      addresses: addresses,
      primaryPrivateKey: '0x${hex.toLowerCase()}',
    );
  }

  /// Solana ed25519：base58 私钥（64 字节取前 32 为种子）。
  static DerivedWallet _deriveSolana(String s) {
    final bytes = Base58Decoder.decode(s);
    final seed = bytes.length == 64 ? bytes.sublist(0, 32) : bytes;
    final priv = Ed25519PrivateKey.fromBytes(seed);
    final addr = SolAddrEncoder().encodeKey(priv.publicKey.compressed);

    final chain = SupportedChains.all.firstWhere(
      (c) => c.kind == ChainKind.solana,
    );
    return DerivedWallet(
      addresses: {chain.id: addr},
      // 保存用户原始 base58 私钥，便于导出/签名时原样取回。
      primaryPrivateKey: s,
    );
  }

  /// Sui：bech32 解出 [1 字节方案标志 + 32 字节私钥]，按方案选曲线派生。
  static DerivedWallet _deriveSui(String s) {
    final (flag, key) = _decodeSui(s);
    final String addr;
    switch (flag) {
      case 0x00: // ed25519
        final priv = Ed25519PrivateKey.fromBytes(key);
        addr = SuiAddrEncoder().encodeKey(priv.publicKey.compressed);
      case 0x01: // secp256k1
        final priv = Secp256k1PrivateKey.fromBytes(key);
        addr = SuiSecp256k1AddrEncoder().encodeKey(priv.publicKey.compressed);
      default:
        throw FormatException('不支持的 Sui 私钥方案标志: $flag');
    }

    final chain = SupportedChains.all.firstWhere(
      (c) => c.kind == ChainKind.sui,
    );
    return DerivedWallet(addresses: {chain.id: addr}, primaryPrivateKey: s);
  }

  /// 解析 Sui `suiprivkey1...`：返回 (方案标志, 32 字节私钥)。
  static (int flag, List<int> key) _decodeSui(String s) {
    final data = Bech32Decoder.decode(_suiHrp, s.toLowerCase());
    if (data.length != 33) {
      throw FormatException('Sui 私钥长度异常: ${data.length}');
    }
    return (data[0], data.sublist(1));
  }

  static String _strip0x(String s) =>
      (s.startsWith('0x') || s.startsWith('0X')) ? s.substring(2) : s;
}

/// compute() 顶层入口：在后台 isolate 由私钥派生（避免阻塞 UI）。
/// 入参为 (类型, 原始私钥串)。
DerivedWallet deriveFromPrivateKeyInBackground((PrivateKeyKind, String) args) =>
    PrivateKeyService.derive(args.$1, args.$2);
