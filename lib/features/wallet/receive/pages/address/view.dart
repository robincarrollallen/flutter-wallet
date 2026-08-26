import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../../../core/responsive/screen_adapter.dart';
import '../../../../../providers/modules/wallet_provider.dart';
import '../../state.dart';
import '../../../../../widgets/asset_icon.dart';
import '../../../../../widgets/app_toast.dart';
import '../../../../../enums/toast_position.dart';

/// 收款地址子页：在接收弹窗内部滑入展示（嵌套 Navigator）。
/// 内容：资产标识 + 地址二维码 + 地址全文 + 复制按钮。
class ReceiveAddressPage extends ConsumerWidget {
  const ReceiveAddressPage({super.key, required this.asset, this.tokenLogoUrl, this.chainLogoUrl});

  final ReceiveAsset asset;

  /// 列表页已拿到的图标 URL，直接透传避免重复查询行情。
  final String? tokenLogoUrl;

  /// 所在链图标 URL：右下角徽标用，与列表行保持一致。
  final String? chainLogoUrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final wallet = ref.watch(activeWalletProvider);
    final address = wallet?.addressFor(asset.chain);

    return Material(
      color: Colors.transparent,
      child: Column(
        children: [
          // —— 顶部头部：返回箭头（嵌套 pop）+ 标题 —— //
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: '返回',
                // 嵌套 pop：回到弹窗内的资产列表页。
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              Expanded(
                child: Text(
                  '接收 ${asset.symbol}',
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              SizedBox(width: 48.s), // 平衡左侧返回按钮，让标题视觉居中。
            ],
          ),
          Expanded(
            child: address == null
                ? Center(
                    child: Text(
                      '当前钱包暂无 ${asset.chain.name} 地址',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  )
                : SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(24.s, 8.s, 24.s, 24.s),
                    child: Column(
                      children: [
                        // —— 资产标识：图标（右下角叠链徽标）+ 名称（含链名，防止转错网络） —— //
                        AssetIcon(
                          symbol: asset.symbol,
                          tokenLogoUrl: tokenLogoUrl,
                          chainSymbol: asset.chain.symbol,
                          chainLogoUrl: chainLogoUrl,
                          size: 48.s,
                        ),
                        SizedBox(height: 8.s),
                        Text(
                          '${asset.name} · ${asset.chain.name}',
                          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                        SizedBox(height: 20.s),
                        // —— 地址二维码：白底圆角卡片，深色模式下也可扫 —— //
                        Container(
                          padding: EdgeInsets.all(12.s),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16.s),
                            border: Border.all(color: theme.colorScheme.outlineVariant),
                          ),
                          child: QrImageView(data: address, size: 200.s, backgroundColor: Colors.white),
                        ),
                        SizedBox(height: 20.s),
                        // —— 地址全文：点击整块或复制按钮均可复制 —— //
                        InkWell(
                          borderRadius: BorderRadius.circular(12.s),
                          onTap: () => _copy(context, address),
                          child: Container(
                            width: double.infinity,
                            padding: EdgeInsets.all(12.s),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(12.s),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    address,
                                    style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                                  ),
                                ),
                                SizedBox(width: 8.s),
                                Icon(Icons.copy_rounded, size: 18.s, color: theme.colorScheme.primary),
                              ],
                            ),
                          ),
                        ),
                        SizedBox(height: 12.s),
                        // —— 提醒：仅限本链网络，转错链无法找回 —— //
                        Text(
                          '仅支持接收 ${asset.chain.name} 网络上的 ${asset.symbol}，'
                          '向该地址转入其他网络资产可能无法找回。',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  void _copy(BuildContext context, String address) {
    Clipboard.setData(ClipboardData(text: address));
    // 不用 SnackBar：SnackBar 挂在根 Scaffold 上, 会被本页<底部弹窗>整个盖住
    AppToast.show(context, '地址已复制', position: ToastPosition.center);
  }
}
