import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../blockchain/listed_asset.dart';
import '../../../core/responsive/screen_adapter.dart';
import '../../../i18n/translations.g.dart';
import '../../../providers/modules/balance_provider.dart';
import '../../../providers/modules/chain_icon_provider.dart';
import '../../../providers/token_catalog_provider.dart';
import '../../../widgets/asset_icon.dart';
import 'logic.dart';
import 'state.dart';

/// 管理代币：列出全量资产，用开关控制它在首页 / 接收页是否展示。
///
/// 开关即写即存（[hiddenAssetsProvider] 自带持久化），没有保存按钮。
class ManageTokensScreen extends ConsumerStatefulWidget {
  const ManageTokensScreen({super.key});

  static Route<void> route() => MaterialPageRoute(builder: (_) => const ManageTokensScreen());

  @override
  ConsumerState<ManageTokensScreen> createState() => _ManageTokensScreenState();
}

class _ManageTokensScreenState extends ConsumerState<ManageTokensScreen> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final assets = ManageTokensLogic.filter(ref.watch(manageTokenListProvider), _query);
    final hidden = ref.watch(hiddenAssetsProvider);
    final markets = ref.watch(marketsProvider).value ?? const {};
    final chainIcons = ref.watch(chainIconsProvider).icons;

    return Scaffold(
      appBar: AppBar(title: Text(t.manageTokens.title)),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16.s, 8.s, 16.s, 0),
            child: TextField(
              controller: _controller,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: t.manageTokens.searchHint,
                prefixIcon: Icon(Icons.search, size: 20.s),
                isDense: true,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          SizedBox(height: 8.s),
          Expanded(
            child: assets.isEmpty
                ? Center(
                    child: Text(
                      t.manageTokens.empty,
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  )
                : ListView.builder(
                    padding: EdgeInsets.only(bottom: 24.s),
                    itemCount: assets.length,
                    itemBuilder: (context, i) => _ManageTile(
                      asset: assets[i],
                      visible: !hidden.contains(assets[i].key),
                      markets: markets,
                      chainIcons: chainIcons,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// 单行：图标 + 符号/名称 + 右侧显示开关。
///
/// 不复用 [AssetTile]：那一行的尾部固定是持仓金额，这里要放开关。
class _ManageTile extends ConsumerWidget {
  const _ManageTile({required this.asset, required this.visible, required this.markets, required this.chainIcons});

  final ListedAsset asset;
  final bool visible;
  final Markets markets;
  final ChainIcons chainIcons;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return ListTile(
      leading: AssetIcon(
        symbol: asset.symbol,
        tokenLogoUrl: markets[asset.coinGeckoId]?.logoUrl,
        chainSymbol: asset.chain.symbol,
        chainLogoUrl: chainIcons[asset.chain.coinGeckoPlatformId] ?? markets[asset.chain.coinGeckoId]?.logoUrl,
      ),
      title: Text(asset.symbol),
      subtitle: Text(
        asset.name == asset.chain.name ? asset.chain.name : '${asset.name} · ${asset.chain.name}',
        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Switch(
        value: visible,
        onChanged: (_) => ref.read(hiddenAssetsProvider.notifier).toggle(asset.key),
      ),
      onTap: () => ref.read(hiddenAssetsProvider.notifier).toggle(asset.key),
    );
  }
}
