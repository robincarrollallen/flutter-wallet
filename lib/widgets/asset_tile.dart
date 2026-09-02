import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../blockchain/listed_asset.dart';
import '../core/format/amount_formatter.dart';
import '../core/responsive/screen_adapter.dart';
import '../providers/modules/balance_provider.dart';
import '../providers/modules/chain_icon_provider.dart';
import '../providers/modules/currency_provider.dart';
import '../providers/modules/wallet_provider.dart';
import 'amount_text.dart';
import 'asset_icon.dart';

/// 资产行：图标 + 符号/全名 + 副标题链名单价 + 右侧持仓。
///
/// 首页代币列表与接收页共用。点击由 [onTap] 决定；为空则不可点。
class AssetTile extends ConsumerWidget {
  const AssetTile({
    super.key,
    required this.asset,
    required this.showChainName,
    required this.markets,
    required this.chainIcons,
    this.onTap,
  });

  final ListedAsset asset;
  final bool showChainName;
  final Markets markets;
  final ChainIcons chainIcons;

  /// 列表页已解析好的图标 URL 一并回传，避免子页再查行情。
  final void Function(String? tokenLogoUrl, String? chainLogoUrl)? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokenLogoUrl = markets[asset.coinGeckoId]?.logoUrl;
    final chainLogoUrl = chainIcons[asset.chain.coinGeckoPlatformId] ?? markets[asset.chain.coinGeckoId]?.logoUrl;
    final subtitle = _subtitle(ref);
    return ListTile(
      leading: AssetIcon(
        symbol: asset.symbol,
        tokenLogoUrl: tokenLogoUrl,
        chainSymbol: asset.chain.symbol,
        chainLogoUrl: chainLogoUrl,
      ),
      title: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(asset.symbol),
          SizedBox(width: 6.s),
          Flexible(
            child: Text(
              asset.name,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      subtitle: subtitle.isEmpty ? null : Text(subtitle),
      trailing: _AssetAmount(asset: asset),
      onTap: onTap == null ? null : () => onTap!(tokenLogoUrl, chainLogoUrl),
    );
  }

  /// 副标题：「链名 · 当前单价」。全名已挪到主标题右侧，此处不再重复。
  ///
  /// 「全部」页附带链名，便于区分同名代币归属；原生币的名称本身就是链名，
  /// 不再写第二遍。单价取自已注入的 [markets]，不额外发请求。行情加载中
  /// 或拉取失败时不显示 $0.00，免得用户误以为该币真的没价值。
  ///
  /// 刻意不用 AmountText：掩码是为了藏持仓，单价是公开行情，与隐私无关。
  String _subtitle(WidgetRef ref) {
    final price = markets[asset.coinGeckoId]?.price;
    final priceText = price == null ? null : formatAmount(price, symbol: ref.watch(currencySymbolProvider));
    if (showChainName && asset.name != asset.chain.name) {
      return priceText == null ? asset.chain.name : '${asset.chain.name} · $priceText';
    }
    return priceText ?? '';
  }
}

/// 资产行右侧：当前钱包在该资产上的持仓「数量 + 折算价值」。
///
/// 原生币与代币走同一个 [balanceProvider]（键里带上代币 identifier），
/// 无地址（该钱包未派生出这条链的地址）才按 0 展示。
class _AssetAmount extends ConsumerWidget {
  const _AssetAmount({required this.asset});

  final ListedAsset asset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallet = ref.watch(currentWalletProvider);
    final address = wallet?.addressFor(asset.chain);

    // 无地址：没有可查的对象，按 0 展示。
    if (address == null) return _amount(context, '0', asset.symbol, 0);

    final balance = ref.watch(balanceProvider((asset.chain.id, address, asset.token?.identifier)));
    return balance.when(
      loading: () => SizedBox(width: 14.s, height: 14.s, child: const CircularProgressIndicator(strokeWidth: 2)),
      error: (_, _) => _amount(context, '0', asset.symbol, 0),
      data: (b) => _amount(context, b.amount, b.symbol, b.fiatValue),
    );
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
