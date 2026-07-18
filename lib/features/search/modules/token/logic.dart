import '../../../wallet/domain/chain.dart';
import '../../../wallet/domain/wallet.dart';

/// 代币 Tab 的纯匹配逻辑：与状态/UI 无关，便于单测与复用。
/// 入参 [q] 应为已规整（小写、去空白）的关键词。
class TokenSearchLogic {
  const TokenSearchLogic._();

  /// 热门代币（空词时展示）：当前用全部受支持链占位。
  static List<Chain> hotChains() => SupportedChains.all;

  /// 按名称 / 符号匹配受支持链。
  static List<Chain> matchChains(String q) {
    if (q.isEmpty) return const [];
    return SupportedChains.all
        .where((c) =>
            c.name.toLowerCase().contains(q) ||
            c.symbol.toLowerCase().contains(q))
        .toList(growable: false);
  }

  /// 按名称 / 任一地址匹配钱包。
  static List<Wallet> matchWallets(String q, List<Wallet> wallets) {
    if (q.isEmpty) return const [];
    return wallets.where((w) {
      if (w.name.toLowerCase().contains(q)) return true;
      if (w.address.toLowerCase().contains(q)) return true;
      return w.addresses.values.any((a) => a.toLowerCase().contains(q));
    }).toList(growable: false);
  }
}
