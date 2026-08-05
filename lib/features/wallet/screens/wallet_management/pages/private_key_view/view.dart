import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wallet/core/blockchain/chain_registry.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../../../../core/responsive/screen_adapter.dart';
import '../../../../domain/wallet.dart';
import '../../../../services/wallet_key_service.dart';
import '../../widgets/panel/view.dart';

/// 显示某条链的私钥：默认隐藏，点击「闭眼」区域后展示二维码与明文。
class PrivateKeyViewPage extends ConsumerStatefulWidget {
  const PrivateKeyViewPage({
    super.key,
    required this.wallet,
    required this.chain,
  });

  final Wallet wallet;
  final Chain chain;

  @override
  ConsumerState<PrivateKeyViewPage> createState() => _PrivateKeyViewPageState();
}

class _PrivateKeyViewPageState extends ConsumerState<PrivateKeyViewPage> {
  /// 已展示的私钥明文，仅在用户点击「展示」后按需读取，离开页面即清空。
  String? _privateKey;
  bool _loading = false;
  bool _failed = false;

  @override
  void dispose() {
    // 主动断开对私钥明文的引用，缩短其在内存中的存活时间。
    _privateKey = null;
    super.dispose();
  }

  /// 点击展示：按需取出当前链的私钥明文到本地状态（不进 Provider 缓存）。
  ///
  /// 取私钥的分支逻辑（助记词现场派生 / 读取已存）统一收敛在
  /// [WalletKeyService.resolveExportKey]，与将来的签名流程共用。
  Future<void> _reveal() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final pk = await ref
          .read(walletKeyServiceProvider)
          .resolveExportKey(widget.wallet, widget.chain);
      if (!mounted) return;
      setState(() {
        _privateKey = pk;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final privateKey = _privateKey;
    final revealed = privateKey != null && privateKey.isNotEmpty;

    return PanelPage(
      title: '查看私钥',
      showBack: true,
      child: ListView(
        padding: EdgeInsets.all(16.s),
        children: [
          // 风险提示。
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(12.s),
            decoration: BoxDecoration(
              color: theme.colorScheme.error.withValues(alpha: 0.06),
              border: Border.all(
                color: theme.colorScheme.error.withValues(alpha: 0.4),
              ),
              borderRadius: BorderRadius.circular(8.s),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 18.s,
                  color: theme.colorScheme.error,
                ),
                SizedBox(width: 8.s),
                Expanded(
                  child: Text(
                    '私钥即财产，任何人拿到都能转走你的资产，切勿泄露或截图。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 24.s),
          Text(
            widget.chain.name,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 16.s),
          if (_failed)
            const Center(child: Text('该钱包没有可导出的私钥或读取失败'))
          else if (revealed)
            _RevealedContent(privateKey: privateKey)
          else
            _HiddenPlaceholder(loading: _loading, onReveal: _reveal),
        ],
      ),
    );
  }
}

/// 二维码白色方框的整体边长：二维码本体 + 四周内边距，
/// 隐藏态占位方框与之保持一致，切换显示/隐藏时布局不跳动。
const double _qrBoxSize = 200 + 12 * 2;

/// 隐藏态：与二维码同尺寸的方框（闭眼图标 + 提示文本）+ 掩码明文栏。
class _HiddenPlaceholder extends StatelessWidget {
  const _HiddenPlaceholder({required this.onReveal, this.loading = false});

  final VoidCallback onReveal;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        // 与二维码等大的方框占位。
        Center(
          child: InkWell(
            onTap: loading ? null : onReveal,
            borderRadius: BorderRadius.circular(8.s),
            child: Container(
              width: _qrBoxSize.s,
              height: _qrBoxSize.s,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8.s),
              ),
              child: loading
                  ? const CircularProgressIndicator()
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.visibility_off_outlined,
                          size: 48.s,
                          color: theme.colorScheme.primary,
                        ),
                        SizedBox(height: 12.s),
                        Text(
                          '点击展示私钥二维码',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
        SizedBox(height: 24.s),
        // 掩码明文栏：与展示态明文栏同样式，保持高度一致。
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(12.s),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8.s),
          ),
          child: Text(
            '••••••••••••••••••••••••••••••••',
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: theme.textTheme.bodyMedium?.copyWith(
              letterSpacing: 2,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

/// 展示态：二维码 + 私钥明文栏 + 复制按钮。
class _RevealedContent extends StatelessWidget {
  const _RevealedContent({required this.privateKey});

  final String privateKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        // 二维码（白底方框，边长 _qrBoxSize）。
        Center(
          child: Container(
            padding: EdgeInsets.all(12.s),
            color: Colors.white,
            child: QrImageView(
              data: privateKey,
              version: QrVersions.auto,
              size: 200.s,
            ),
          ),
        ),
        SizedBox(height: 24.s),
        // 私钥明文栏。
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(12.s),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8.s),
          ),
          child: SelectableText(privateKey, style: theme.textTheme.bodyMedium),
        ),
        SizedBox(height: 16.s),
        // 复制按钮。
        OutlinedButton.icon(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: privateKey));
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('私钥已复制')));
          },
          icon: Icon(Icons.copy_rounded, size: 18.s),
          label: const Text('复制私钥'),
        ),
      ],
    );
  }
}
