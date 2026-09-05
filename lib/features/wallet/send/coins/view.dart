import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/responsive/screen_adapter.dart';
import '../../../../widgets/app_toast.dart';
import '../../../../widgets/asset_tile.dart';
import '../../../../providers/modules/balance_provider.dart';
import '../../../../providers/modules/chain_icon_provider.dart';
import '../../../../providers/modules/wallet_provider.dart';
import '../../../../providers/token_catalog_provider.dart';
import '../../../../blockchain/chain_registry.dart';
import '../../../../blockchain/listed_asset.dart';
import '../../../../router/route_args.dart';
import '../../../../router/routes.dart';
import 'logic.dart';

/// 发送页面：普通全屏页面。根页为按余额法币价值降序的持仓列表
/// （零余额/无地址的链不展示），点击资产后以普通路由依次进入
/// 「收款地址 → 金额 → 确认 → 结果」页面。
class SendScreen extends ConsumerStatefulWidget {
  const SendScreen({super.key});

  @override
  ConsumerState<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends ConsumerState<SendScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final markets = ref.watch(marketsProvider).markets;
    final chainIcons = ref.watch(chainIconsProvider).icons;
    final wallet = ref.watch(activeWalletProvider);

    final assets = SendLogic.filter(SendLogic.assetsOf(null, ref.watch(tokenCatalogProvider)), _query);
    // 法币价值：无地址按 0（进折叠区）；余额加载中为 null（留在可发送区尾部）。
    double? fiatValueOf(ListedAsset a) {
      final address = wallet?.addressFor(a.chain);
      if (address == null) return 0;
      final balance = ref.watch(balanceProvider((a.chain.id, address, a.token?.identifier)));
      return balance.when(loading: () => null, error: (_, _) => 0.0, data: (b) => b.fiatValue);
    }

    final (sendable, _) = SendLogic.partition(assets, fiatValueOf);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // —— 0. 顶部标题栏：关闭按钮 + 标题 —— //
            Row(
              children: [
                IconButton(icon: const Icon(Icons.close), tooltip: '关闭', onPressed: () => context.pop()),
                Expanded(
                  child: Text('发送', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                ),
                SizedBox(width: 48.s), // 平衡左侧关闭按钮，让标题视觉居中。
              ],
            ),
            // —— 1. 顶部搜索栏 —— //
            Padding(
              padding: EdgeInsets.fromLTRB(16.s, 0, 16.s, 8.s),
              child: TextField(
                controller: _searchController,
                onChanged: (v) => setState(() => _query = v),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: '搜索代币',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                        ),
                  isDense: true,
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16.s), borderSide: BorderSide.none),
                  contentPadding: EdgeInsets.symmetric(vertical: 12.s),
                ),
              ),
            ),
            const Divider(height: 1),
            // —— 2. 持仓列表：可发送资产按价值降序 —— //
            Expanded(
              child: assets.isEmpty
                  ? Center(
                      child: Text(
                        '未找到相关资产',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                    )
                  : sendable.isEmpty
                  ? Center(
                      child: Text(
                        '暂无可发送的资产，先通过「接收」充值吧',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.symmetric(vertical: 8.s),
                      itemCount: sendable.length,
                      itemBuilder: (context, i) => AssetTile(
                        asset: sendable[i],
                        // 恒为 true：多条 EVM 链的 ETH 符号与图标都相同，
                        // 链名是唯一的防错标识，不能省。
                        showChainName: true,
                        markets: markets,
                        chainIcons: chainIcons,
                        onTap: (tokenLogoUrl, chainLogoUrl) =>
                            _open(sendable[i], tokenLogoUrl, chainLogoUrl, wallet?.addressFor(sendable[i].chain)),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// 进入收款地址子页。图标 URL 由列表行解析后回传，避免子页再查一次行情。
  ///
  /// [address] 为当前钱包在该链上的地址，为空说明无从发起转账，直接拦下。
  void _open(ListedAsset asset, String? tokenLogoUrl, String? chainLogoUrl, String? address) {
    if (address == null) {
      AppToast.show(context, '当前钱包暂无 ${asset.chain.name} 地址');
      return;
    }
    // 转账目前仅接入 EVM 链，其余链在入口拦截。
    if (asset.chain.kind != ChainKind.evm) {
      AppToast.show(context, '${asset.chain.name} 转账暂未支持');
      return;
    }
    context.push(
      AppRoute.sendRecipient,
      extra: SendRecipientArgs(asset: asset, tokenLogoUrl: tokenLogoUrl, chainLogoUrl: chainLogoUrl),
    );
  }
}
