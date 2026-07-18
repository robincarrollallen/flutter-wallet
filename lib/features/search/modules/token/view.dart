import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/responsive/screen_adapter.dart';
import '../../../../i18n/translations.g.dart';
import '../../../../providers/modules/balance_provider.dart';
import '../../../wallet/domain/token_icon.dart';
import '../pill/state.dart';
import '../search_hint.dart';
import 'logic.dart';
import 'state.dart';

/// 代币 Tab：空词展示热门链，输入关键词后在钱包与受支持链中检索。
class TokenTabView extends ConsumerWidget {
  const TokenTabView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final results = ref.watch(tokenResultsProvider);

    // 复用余额页已缓存的行情结果，不产生额外请求；
    // 首帧未就绪时取空表，图标自然回退首字母，就绪后自动重建。
    final markets = ref.watch(marketsProvider).value ?? const {};

    // 空词：展示热门链，点击即以其名称发起搜索。
    if (results.isEmptyQuery) {
      return ListView(
        padding: EdgeInsets.all(8.s),
        children: [
          for (final c in TokenSearchLogic.hotChains())
            ListTile(
              leading: TokenIcon(
                symbol: c.symbol,
                logoUrl: markets[c.coinGeckoId]?.logoUrl,
              ),
              title: Text(c.name),
              subtitle: Text(c.symbol),
              onTap: () =>
                  ref.read(searchQueryProvider.notifier).update(c.name),
            ),
        ],
      );
    }

    if (!results.hasResult) return SearchHint(text: t.search.noResult);

    return ListView(
      padding: EdgeInsets.all(8.s),
      children: [
        for (final w in results.wallets)
          ListTile(
            leading: const Icon(Icons.account_balance_wallet),
            title: Text(w.name),
            subtitle: Text(
              w.address,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        for (final c in results.chains)
          ListTile(
            leading: TokenIcon(
              symbol: c.symbol,
              logoUrl: markets[c.coinGeckoId]?.logoUrl,
            ),
            title: Text(c.name),
            subtitle: Text(c.symbol),
          ),
      ],
    );
  }
}
