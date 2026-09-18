import 'package:blockchain_utils/blockchain_utils.dart';

import 'chain_registry.dart';

/// 收款地址的格式校验，按 [ChainKind] 分流。
///
/// **刻意放在 `blockchain/` 而不是 `features/`**：地址校验是安全关键逻辑，
/// 而 `lib/services/` 不允许 import `lib/features/`（见 tool/check_layers.sh）。
/// 早先它只存在于发送弹窗的 UI 逻辑里，于是绕过 UI 直接调
/// [WalletService.sendTransaction] 的调用方，收款地址不经任何格式校验就会进签名流程。
/// 放在这一层，UI 与 service 才能共用同一份判断——两边口径不一致比没有校验更危险。
class AddressValidation {
  const AddressValidation._();

  /// 校验收款地址是否符合 [chain] 的地址格式。合法返回 null，否则返回错误文案。
  ///
  /// switch **刻意不写 default 分支**：新增一条链时编译器会在这里报错，
  /// 逼着实现方补上该链的校验，而不是悄悄走进「未知链一律放行」。
  static String? validate(Chain chain, String input) {
    final addr = input.trim();
    if (addr.isEmpty) return '请输入收款地址';
    final valid = switch (chain.kind) {
      ChainKind.evm => _isValidEvm(addr),
      ChainKind.solana => _decodes(() => SolAddrDecoder().decodeAddr(addr)),
      ChainKind.tron => _decodes(() => TrxAddrDecoder().decodeAddr(addr)),
      ChainKind.bitcoin => _isValidBitcoinTestnet(addr),
      // 与签名层同一套解码器：宽松正则会放过签名时才会拒绝的截断地址。
      ChainKind.sui => _decodes(() => SuiAddrDecoder().decodeAddr(addr)),
      ChainKind.aptos => _decodes(() => AptosAddrDecoder().decodeAddr(addr)),
    };
    return valid ? null : '地址格式不正确，请检查是否为 ${chain.name} 地址';
  }

  /// EVM：0x + 40 位十六进制；混合大小写时额外校验 EIP-55 checksum。
  static bool _isValidEvm(String addr) {
    if (!RegExp(r'^0x[0-9a-fA-F]{40}$').hasMatch(addr)) return false;
    final hex = addr.substring(2);
    final mixedCase = hex.toLowerCase() != hex && hex.toUpperCase() != hex;
    if (!mixedCase) return true;
    return _decodes(() => EthAddrDecoder().decodeAddr(addr));
  }

  /// Bitcoin（项目为测试网）：收款方地址类型不受本钱包自身脚本类型限制，三种都放行——
  /// tb1q…（SegWit v0 / P2WPKH）、tb1p…（Taproot v1 / P2TR）、以及 legacy（m/n/2 开头）。
  static bool _isValidBitcoinTestnet(String addr) {
    if (addr.toLowerCase().startsWith('tb1')) {
      return _decodes(() => P2WPKHAddrDecoder().decodeAddr(addr, hrp: 'tb')) ||
          _decodes(() => P2TRAddrDecoder().decodeAddr(addr, hrp: 'tb'));
    }
    return RegExp(r'^[mn2][1-9A-HJ-NP-Za-km-z]{25,39}$').hasMatch(addr);
  }

  /// 解码不抛异常即视为合法。
  static bool _decodes(void Function() decode) {
    try {
      decode();
      return true;
    } catch (_) {
      return false;
    }
  }
}
