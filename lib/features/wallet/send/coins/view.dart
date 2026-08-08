import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/format/amount_formatter.dart';
import '../../../../core/responsive/screen_adapter.dart';
import '../../../../widgets/amount_text.dart';
import '../../../../widgets/app_toast.dart';
import '../../../../widgets/asset_icon.dart';
import '../../../../providers/modules/balance_provider.dart';
import '../../../../providers/modules/chain_icon_provider.dart';
import '../../../../providers/modules/currency_provider.dart';
import '../../../../providers/modules/wallet_provider.dart';
import '../../../../blockchain/chain_registry.dart';
import 'logic.dart';
import '../recipient/view.dart';
import 'state.dart';

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
    final markets = ref.watch(marketsProvider).value ?? const {};
    final chainIcons = ref.watch(chainIconsProvider).value ?? const {};
    final wallet = ref.watch(activeWalletProvider);

    final assets = SendLogic.filter(SendLogic.assetsOf(null), _query);
    // 法币价值：无地址按 0（进折叠区）；余额加载中为 null（留在可发送区尾部）。
    double? fiatValueOf(SendAsset a) {
      final address = wallet?.addressFor(a.chain);
      if (address == null) return 0;
      final balance = ref.watch(balanceProvider((a.chain.id, address)));
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
                IconButton(icon: const Icon(Icons.close), tooltip: '关闭', onPressed: () => Navigator.of(context).pop()),
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
                      itemBuilder: (context, i) =>
                          _AssetTile(asset: sendable[i], markets: markets, chainIcons: chainIcons),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 单个资产行：图标 + 符号/链名 + 右侧持仓，点击进入收款地址子页。
class _AssetTile extends ConsumerWidget {
  const _AssetTile({required this.asset, required this.markets, required this.chainIcons});

  final SendAsset asset;
  final Markets markets;
  final ChainIcons chainIcons;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallet = ref.watch(activeWalletProvider);
    final tokenLogoUrl = markets[asset.coinGeckoId]?.logoUrl;
    final chainLogoUrl = chainIcons[asset.chain.coinGeckoPlatformId] ?? markets[asset.chain.coinGeckoId]?.logoUrl;
    return ListTile(
      leading: AssetIcon(
        symbol: asset.symbol,
        tokenLogoUrl: tokenLogoUrl,
        chainSymbol: asset.chain.symbol,
        chainLogoUrl: chainLogoUrl,
      ),
      title: Text(asset.symbol),
      // 链名必须保留：多条 EVM 链的 ETH 符号与图标都相同，链名是唯一的防错标识。
      subtitle: Text(_subtitle(ref)),
      // 右侧展示持仓「数量 + 折算价值」。
      trailing: _AssetAmount(asset: asset),
      onTap: () {
        // 无该链地址时无从发起转账，直接提示并拦截。
        if (wallet?.addressFor(asset.chain) == null) {
          AppToast.show(context, '当前钱包暂无 ${asset.chain.name} 地址');
          return;
        }
        // 转账目前仅接入 EVM 链，其余链在入口拦截。
        if (asset.chain.kind != ChainKind.evm) {
          AppToast.show(context, '${asset.chain.name} 转账暂未支持');
          return;
        }
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => SendRecipientPage(asset: asset, tokenLogoUrl: tokenLogoUrl, chainLogoUrl: chainLogoUrl),
          ),
        );
      },
    );
  }

  /// 副标题：「链名 · 当前单价」。
  ///
  /// 单价取自已注入的 [markets]，不额外发请求。行情加载中或拉取失败时
  /// （marketsProvider 失败即返回空 map）退回纯链名——不显示 $0.00，
  /// 免得用户误以为该币真的没价值。
  ///
  /// 刻意不用 AmountText：它会按 balanceHiddenProvider 打掩码，而掩码是为了藏
  /// 用户的持仓，单价是公开行情，与隐私无关，藏了既没意义又难看。
  String _subtitle(WidgetRef ref) {
    final price = markets[asset.coinGeckoId]?.price;
    if (price == null) return asset.chain.name;
    final symbol = ref.watch(currencySymbolProvider);
    return '${asset.chain.name} · ${formatAmount(price, symbol: symbol)}';
  }
}

/// 资产行右侧：当前钱包在该资产上的持仓「数量 + 折算价值」。
class _AssetAmount extends ConsumerWidget {
  const _AssetAmount({required this.asset});

  final SendAsset asset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallet = ref.watch(currentWalletProvider);
    final address = wallet?.addressFor(asset.chain);

    // 有地址：走实时余额查询；无地址按 0 展示。
    if (address != null) {
      final balance = ref.watch(balanceProvider((asset.chain.id, address)));
      return balance.when(
        loading: () => SizedBox(width: 14.s, height: 14.s, child: const CircularProgressIndicator(strokeWidth: 2)),
        error: (_, _) => _amount(context, '0', asset.symbol, 0),
        data: (b) => _amount(context, b.amount, b.symbol, b.fiatValue),
      );
    }
    return _amount(context, '0', asset.symbol, 0);
  }

  /// 两行：上为「数量 + 符号」，下为折算法币价值。
  Widget _amount(BuildContext context, String amount, String symbol, double fiatValue) {
    final theme = Theme.of(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        AmountText.raw('$amount $symbol', style: theme.textTheme.bodyMedium),
        AmountText(fiatValue, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }
}
