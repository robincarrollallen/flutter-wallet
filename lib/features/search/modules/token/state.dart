import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../providers/modules/wallet_provider.dart';
import '../../../wallet/domain/chain.dart';
import '../../../wallet/domain/wallet.dart';
import '../pill/logic.dart';
import '../pill/state.dart';
import 'logic.dart';

/// 代币 Tab 的检索结果（不可变）。
class TokenResults {
  const TokenResults({
    required this.query,
    required this.chains,
    required this.wallets,
  });

  final String query;
  final List<Chain> chains;
  final List<Wallet> wallets;

  bool get isEmptyQuery => query.isEmpty;
  bool get hasResult => chains.isNotEmpty || wallets.isNotEmpty;
}

/// 由当前关键词 + 钱包列表派生代币检索结果。
final tokenResultsProvider = Provider.autoDispose<TokenResults>((ref) {
  final q = normalizeQuery(ref.watch(searchQueryProvider));
  final wallets = ref.watch(walletListProvider);
  return TokenResults(
    query: q,
    chains: TokenSearchLogic.matchChains(q),
    wallets: TokenSearchLogic.matchWallets(q, wallets),
  );
});
