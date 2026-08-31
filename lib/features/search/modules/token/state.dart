import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../blockchain/chain_registry.dart';
import '../../../../blockchain/token.dart';
import '../../../../providers/modules/wallet_provider.dart';
import '../../../../providers/token_catalog_provider.dart';
import '../../../../domain/wallet.dart';
import '../pill/logic.dart';
import '../pill/state.dart';
import 'logic.dart';

/// 代币 Tab 的检索结果（不可变）。
class TokenResults {
  const TokenResults({required this.query, required this.chains, required this.tokens, required this.wallets});

  final String query;
  final List<Chain> chains;

  /// 匹配到的代币及其所在链（同名代币逐链展开，如多链 USDC）。
  final List<(Chain, Token)> tokens;
  final List<Wallet> wallets;

  bool get isEmptyQuery => query.isEmpty;
  bool get hasResult => chains.isNotEmpty || tokens.isNotEmpty || wallets.isNotEmpty;
}

/// 由当前关键词 + 钱包列表派生代币检索结果。
final tokenResultsProvider = Provider.autoDispose<TokenResults>((ref) {
  final q = normalizeQuery(ref.watch(searchQueryProvider));
  final wallets = ref.watch(walletListProvider);
  final catalog = ref.watch(tokenCatalogProvider);
  return TokenResults(
    query: q,
    chains: TokenSearchLogic.matchChains(q),
    tokens: TokenSearchLogic.matchTokens(q, catalog),
    wallets: TokenSearchLogic.matchWallets(q, wallets),
  );
});
