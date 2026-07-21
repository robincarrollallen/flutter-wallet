import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../../core/responsive/screen_adapter.dart';
import '../../../../domain/wallet.dart';
import '../../../../services/secure_wallet_storage.dart';
import '../../widgets/panel/view.dart';
import '../../../../../../core/navigation/panel_routes.dart';
import '../verify_mnemonic/view.dart';

/// 备份步骤二（手动备份）：默认隐藏助记词，点击展示后抄写，再「下一步」校验。
class ManualBackupPage extends ConsumerStatefulWidget {
  const ManualBackupPage({super.key, required this.wallet});

  final Wallet wallet;

  @override
  ConsumerState<ManualBackupPage> createState() => _ManualBackupPageState();
}

class _ManualBackupPageState extends ConsumerState<ManualBackupPage> {
  /// 已展示的助记词，仅在用户点击「展示」后按需读取，离开页面即清空。
  String? _mnemonic;
  bool _loading = false;
  bool _failed = false;

  @override
  void dispose() {
    // 主动断开对助记词明文的引用，缩短其在内存中的存活时间。
    _mnemonic = null;
    super.dispose();
  }

  /// 点击展示：从安全存储一次性读取助记词到本地状态（不进 Provider 缓存）。
  Future<void> _reveal() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final mnemonic = await ref
          .read(secureWalletStorageProvider)
          .readMnemonic(widget.wallet.id);
      if (!mounted) return;
      setState(() {
        _mnemonic = mnemonic;
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

  /// 下一步：进入校验助记词页面。
  void _onNext() {
    final mnemonic = _mnemonic;
    if (mnemonic == null || mnemonic.isEmpty) return;
    Navigator.of(context).push(
      panelSlideRoute(
        VerifyMnemonicPage(wallet: widget.wallet, mnemonic: mnemonic),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mnemonic = _mnemonic;
    final revealed = mnemonic != null && mnemonic.isNotEmpty;

    return PanelPage(
      title: '手动备份',
      showBack: true,
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: EdgeInsets.all(12.s),
              children: [
                Container(
                  padding: EdgeInsets.all(12.s),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(12.s),
                  ),
                  child: Row(
                    spacing: 6.s,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 20.s,
                        color: theme.colorScheme.onErrorContainer,
                      ),
                      Expanded(
                        child: Text(
                          '请在无人窥视的环境下抄写助记词，并离线妥善保管。'
                          '任何人获取助记词都可转移你的资产，切勿截图或联网传输。',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 24.s),
                if (_failed)
                  const Center(child: Text('该钱包没有可备份的助记词或读取失败'))
                else if (revealed)
                  _MnemonicGrid(mnemonic: mnemonic)
                else
                  _HiddenPlaceholder(loading: _loading, onReveal: _reveal),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(16.s, 8.s, 16.s, 12.s),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    padding: EdgeInsets.symmetric(vertical: 14.s),
                  ),
                  onPressed: revealed ? _onNext : null,
                  child: const Text('下一步'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

BoxDecoration _revealBoxDecoration(ThemeData theme) => BoxDecoration(
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8.s),
    );

/// 隐藏态：闭眼图标 + 「点击展示助记词」提示，点击触发读取。
class _HiddenPlaceholder extends StatelessWidget {
  const _HiddenPlaceholder({required this.onReveal, this.loading = false});

  final VoidCallback onReveal;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: InkWell(
        onTap: loading ? null : onReveal,
        borderRadius: BorderRadius.circular(8.s),
        child: Container(
          width: double.infinity,
          alignment: Alignment.center,
          padding: EdgeInsets.symmetric(vertical: 46.s),
          decoration: _revealBoxDecoration(theme),
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
                      '点击展示助记词',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// 展示态：与隐藏态同样式（同背景色、同最小高度）的方框内，按序号网格列出助记词。
/// 复用 [_revealBoxDecoration] / [_revealBoxMinHeight] 让显示/隐藏切换不突兀。
class _MnemonicGrid extends StatelessWidget {
  const _MnemonicGrid({required this.mnemonic});

  final String mnemonic;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final words = mnemonic.trim().split(RegExp(r'\s+'));
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(10.s),
      decoration: _revealBoxDecoration(theme),
      child: Wrap(
        spacing: 10.s,
        runSpacing: 10.s,
        children: [
          for (var i = 0; i < words.length; i++)
            Container(
              width: (100.sw - 24.s - 20.s - 20.s) / 3, // 一行三列：方框内宽(屏宽 - 页面内边距10×2 - 方框内边距12×2) - 两个间距(10×2)。
              padding: EdgeInsets.symmetric(horizontal: 8.s, vertical: 6.s),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface, // 比外层方框更浅的底色，让单词从背景中凸显。
                borderRadius: BorderRadius.circular(8.s),
              ),
              child: Row(
                spacing: 4.s,
                children: [
                  Container(
                    constraints: BoxConstraints(minWidth: 15.s), // 最小宽度
                    child: Text(
                      '${i + 1}',
                      style: theme.textTheme.bodySmall?.copyWith(),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      words[i],
                      style: theme.textTheme.labelLarge?.copyWith()
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
