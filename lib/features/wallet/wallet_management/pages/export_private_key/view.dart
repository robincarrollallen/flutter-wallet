import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../blockchain/chain_registry.dart';

import '../../../../../core/responsive/screen_adapter.dart';
import '../../../../../domain/wallet.dart';
import '../../widgets/panel/view.dart';
import '../../../../../core/navigation/panel_routes.dart';
import '../private_key_view/view.dart';

/// 导出私钥：列出钱包支持的所有链，每条链一张卡片，点击进入对应链的导出流程。
class ExportPrivateKeyPage extends ConsumerWidget {
  const ExportPrivateKeyPage({super.key, required this.wallet});

  final Wallet wallet;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PanelPage(
      title: '导出私钥',
      showBack: true,
      child: ListView(
        padding: EdgeInsets.all(16.s),
        children: [
          for (final chain in wallet.chainsWithAddress)
            _ChainCard(
              chain: chain,
              address: wallet.addressFor(chain),
              onTap: () => _onSelectChain(context, ref, chain),
            ),
        ],
      ),
    );
  }

  /// 导出某条链私钥：直接展示私钥页面。
  // TODO: 安全码（设置 / 校验）功能暂时移除，后续补回后在此恢复校验逻辑。
  void _onSelectChain(BuildContext context, WidgetRef ref, Chain chain) {
    Navigator.of(context).push(panelSlideRoute(PrivateKeyViewPage(wallet: wallet, chain: chain)));
  }
}

/// 单条链卡片：左侧图标 + 链名（主标题）/ 地址（副标题）+ 右侧箭头。
class _ChainCard extends StatelessWidget {
  const _ChainCard({required this.chain, required this.address, required this.onTap});

  final Chain chain;
  final String? address;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.only(bottom: 12.s),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12.s),
        child: Padding(
          padding: EdgeInsets.all(16.s),
          child: Row(
            children: [
              _ChainIcon(chain: chain),
              SizedBox(width: 12.s),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(chain.name, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                    SizedBox(height: 2.s),
                    Text(
                      address ?? '（未派生地址）',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 8.s),
              Icon(Icons.chevron_right, size: 20.s, color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

/// 链图标：以链币种符号首字母生成的圆形占位图标。
class _ChainIcon extends StatelessWidget {
  const _ChainIcon({required this.chain});

  final Chain chain;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 40.s,
      height: 40.s,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: theme.colorScheme.primaryContainer, shape: BoxShape.circle),
      child: Text(
        chain.symbol.characters.first,
        style: theme.textTheme.titleMedium?.copyWith(
          color: theme.colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
