import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/responsive/screen_adapter.dart';
import '../../../providers/modules/balance_provider.dart';
import '../../../providers/modules/chain_icon_provider.dart';
import '../../../blockchain/chain_registry.dart';
import '../../../widgets/token_icon.dart';
import '../../../domain/wallet.dart';

/// 地址管理页：列出当前钱包在各条链上的地址，支持复制与查看二维码。
class AddressManagementScreen extends ConsumerWidget {
  const AddressManagementScreen({super.key, required this.wallet});

  final Wallet wallet;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    // 在此一次性取表再逐行分发，避免每个 tile 各自 watch 造成 N 次重建。
    // 首帧未就绪时取空表，图标自然回退，就绪后整页重建。
    final chainIcons = ref.watch(chainIconsProvider).value ?? const {};
    final markets = ref.watch(marketsProvider).value ?? const {};

    return Scaffold(
      appBar: AppBar(backgroundColor: theme.colorScheme.inversePrimary, title: const Text('地址管理')),
      body: ListView.separated(
        padding: EdgeInsets.all(16.s),
        itemCount: wallet.chainsWithAddress.length,
        separatorBuilder: (_, _) => SizedBox(height: 8.s),
        itemBuilder: (context, index) {
          final chain = wallet.chainsWithAddress[index];
          return _AddressTile(
            chain: chain,
            address: wallet.addressFor(chain),
            // 三级降级：链图标 -> 币图标（Bitcoin 无平台 id 走这层）-> 首字母圆底。
            logoUrl: chainIcons[chain.coinGeckoPlatformId] ?? markets[chain.coinGeckoId]?.logoUrl,
          );
        },
      ),
    );
  }
}

/// 单链地址卡片：链名 + 地址 + 复制 + 二维码。
class _AddressTile extends StatelessWidget {
  const _AddressTile({required this.chain, required this.address, this.logoUrl});

  final Chain chain;
  final String? address;

  /// 链图标地址；为空时 [TokenIcon] 自动回退为 symbol 首字母圆底。
  final String? logoUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasAddress = address != null && address!.isNotEmpty;

    return Card(
      child: Padding(
        padding: EdgeInsets.all(16.s),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                TokenIcon(symbol: chain.symbol, logoUrl: logoUrl, size: 28.s),
                SizedBox(width: 8.s),
                Expanded(
                  child: Text(chain.name, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                ),
                Text(
                  chain.symbol,
                  style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
            SizedBox(height: 8.s),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: SelectableText(
                    hasAddress ? address! : '（未派生地址）',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: hasAddress ? null : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (hasAddress) ...[
                  SizedBox(width: 8.s),
                  InkWell(
                    onTap: () => _copy(context, address!),
                    child: Icon(Icons.copy_rounded, size: 18.s),
                  ),
                  SizedBox(width: 12.s),
                  InkWell(
                    onTap: () => _showQr(context),
                    child: Icon(Icons.qr_code, size: 18.s),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _copy(BuildContext context, String value) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制')));
  }

  void _showQr(BuildContext context) {
    final theme = Theme.of(context);
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(chain.name),
        content: SizedBox(
          width: 240.s,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: EdgeInsets.all(12.s),
                color: Colors.white,
                child: QrImageView(data: address!, version: QrVersions.auto, size: 200.s),
              ),
              SizedBox(height: 12.s),
              SelectableText(address!, textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => _copy(context, address!), child: const Text('复制')),
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('关闭')),
        ],
      ),
    );
  }
}
