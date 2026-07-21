import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../../core/responsive/screen_adapter.dart';
import '../../../../../../core/theme/app_colors.dart';
import '../../../../../../core/widgets/amount_text.dart';
import '../../../../../../providers/modules/balance_provider.dart';
import '../../../../../../providers/modules/wallet_provider.dart';
import '../../../../domain/wallet.dart';
import '../backup_method/view.dart';
import '../export_private_key/view.dart';
import '../../../../domain/wallet_avatar.dart';
import '../../widgets/panel/view.dart';
import '../../../../../../core/navigation/panel_routes.dart';

/// 钱包详情：展示名称 / 创建方式 / 创建时间 / 主地址，并可编辑头像。
class WalletDetailPage extends ConsumerWidget {
  const WalletDetailPage({super.key, required this.wallet});

  final Wallet wallet;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    // 监听列表，拿到最新钱包（改头像后实时刷新）；被删除则回退到传入值。
    final wallets = ref.watch(walletListProvider);
    final current = wallets.firstWhere(
      (w) => w.id == wallet.id,
      orElse: () => wallet,
    );

    return PanelPage(
      title: '钱包详情',
      showBack: true,
      child: Column(
        children: [
          Expanded( // 可滚动内容区：占据除底部按钮外的全部空间。
            child: ListView(
              padding: EdgeInsets.all(16.s),
              children: [
                Center( // 头像 + 名称区域
                  child: Column(
                    children: [
                      // 头像：点击可编辑，右下角悬浮编辑标记。
                      GestureDetector(
                        onTap: () => _showAvatarPicker(context, ref, current),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceContainerHighest,
                                shape: BoxShape.circle,
                              ),
                              child: WalletAvatar(iconName: current.icon, size: 72.s),
                            ),
                            Positioned(
                              right: 2.s,
                              bottom: 2.s,
                              child: Container(
                                padding: EdgeInsets.all(2.s),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.edit_note,
                                  size: 12.s,
                                  color: theme.colorScheme.onPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: 6.s),
                      // 钱包名称 + 右侧编辑按钮：点击可修改名称。
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            current.name,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              fontSize: 18.s
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.border_color_outlined, size: 18.s),
                            tooltip: '修改名称',
                            onPressed: () => _showRenameDialog(context, ref, current),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 24.s),
                Card(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16.s, vertical: 4.s),
                    child: Column(
                      children: [
                        _DetailRow(
                          label: '余额',
                          valueWidget: ref
                              .watch(walletTotalProvider(current.id))
                              .when(
                                loading: () => const Text(
                                  '加载中…',
                                  textAlign: TextAlign.right,
                                ),
                                error: (_, _) => const Text(
                                  '获取失败',
                                  textAlign: TextAlign.right,
                                ),
                                data: (v) => AmountText(
                                  v,
                                  textAlign: TextAlign.right,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                        ),
                        Divider(height: 1.s),
                        _DetailRow(
                          label: '创建方式',
                          value: walletSourceLabel(current.source),
                        ),
                        Divider(height: 1.s),
                        _DetailRow(
                          label: '创建时间',
                          value: _formatCreatedAt(current.createdAt),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: 16.s),
                Card( // 可跳转的操作列表：右侧带箭头表示进入下级页面。
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16.s, vertical: 4.s),
                    child: Column(
                      children: [
                        // 私钥导入/硬件钱包没有助记词，不显示助记词备份入口。
                        if (current.hasMnemonic) ...[
                          _NavRow(
                            label: '备份',
                            hint: current.isBackedUp ? '已备份' : '未备份',
                            hintColor: current.isBackedUp
                                ? context.appColors.success
                                : theme.colorScheme.error,
                            onTap: () => _onBackup(context, current),
                          ),
                          Divider(height: 1.s),
                        ],
                        _NavRow(
                          label: '导出私钥',
                          onTap: () => _onExportPrivateKey(context, current),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          SafeArea( // 固定在底部的删除按钮：不随上方内容滚动，且不与之重叠
            top: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(16.s, 8.s, 16.s, 12.s),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.colorScheme.error,
                    foregroundColor: theme.colorScheme.onError,
                    padding: EdgeInsets.symmetric(vertical: 14.s),
                  ),
                  onPressed: () => _onDelete(context, ref, current),
                  icon: Icon(Icons.delete_outline, size: 20.s),
                  label: const Text('删除钱包'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 删除钱包：二次确认后移除并退出详情页。
  Future<void> _onDelete(
    BuildContext context,
    WidgetRef ref,
    Wallet current,
  ) async {
    // 删除后关闭整个钱包管理面板（pop 根 Navigator），而非仅返回上一页。
    final rootNavigator = Navigator.of(context, rootNavigator: true);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除钱包'),
        content: Text('确定要删除「${current.name}」吗？\n请确保已备份助记词，删除后将无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    ref.read(walletListProvider.notifier).remove(current.id);
    rootNavigator.pop();
  }

  /// 进入备份流程：步骤一选择备份方式。
  void _onBackup(BuildContext context, Wallet current) {
    Navigator.of(context).push(
      panelSlideRoute(BackupMethodPage(wallet: current)),
    );
  }

  /// 进入导出私钥流程：列出钱包支持的所有链。
  void _onExportPrivateKey(BuildContext context, Wallet current) {
    Navigator.of(context).push(
      panelSlideRoute(ExportPrivateKeyPage(wallet: current)),
    );
  }

  /// 底部弹窗：网格列出全部头像选项，点击即保存并关闭。
  void _showAvatarPicker(BuildContext context, WidgetRef ref, Wallet current) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);

        return SafeArea(
          child: Padding(
            padding: EdgeInsets.all(16.s),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '选择头像',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 12.s),
                Wrap(
                  spacing: 16.s,
                  runSpacing: 16.s,
                  children: [
                    for (final option in WalletAvatarCatalog.all)
                      GestureDetector(
                        onTap: () {
                          ref
                              .read(walletListProvider.notifier)
                              .setIcon(current.id, option.key);
                          Navigator.of(sheetContext).pop();
                        },
                        child: Container(
                          width: 48.s,
                          height: 48.s,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest,
                            shape: BoxShape.circle,
                            border: option.key == current.icon
                                ? Border.all(
                                    color: theme.colorScheme.primary,
                                    width: 2.s,
                                  )
                                : null,
                          ),
                          child: WalletAvatar(
                            iconName: option.key,
                            size: 32.s,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 弹出改名对话框，确认后写入并持久化。
  Future<void> _showRenameDialog(
    BuildContext context,
    WidgetRef ref,
    Wallet current,
  ) async {
    final newName = await showDialog<String>(
      context: context,
      builder: (_) => _RenameDialog(initialName: current.name),
    );
    if (newName != null && newName.trim().isNotEmpty) {
      ref.read(walletListProvider.notifier).rename(current.id, newName);
    }
  }

  /// 格式化创建时间；为空显示「未知」。
  String _formatCreatedAt(DateTime? dt) {
    if (dt == null) return '未知';
    final local = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}

/// 改名对话框：自持有 TextEditingController，在 dispose 中释放，
/// 避免在对话框退场动画期间被提前释放导致 `_dependents.isEmpty` 断言。
class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initialName});

  final String initialName;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialName);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('修改钱包名称'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 30,
        decoration: const InputDecoration(hintText: '输入新的名称'),
        onSubmitted: (v) => Navigator.of(context).pop(v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('保存'),
        ),
      ],
    );
  }
}

/// 详情页一行「左标签 + 右值」，用于卡片内的基础信息列表。
class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    this.value,
    this.valueWidget,
    this.selectable = false,
  }) : assert(value != null || valueWidget != null);

  final String label;
  final String? value;

  /// 自定义右值组件（提供时优先于 [value]，如金额 AmountText）。
  final Widget? valueWidget;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 12.s),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          SizedBox(width: 16.s),
          Expanded(
            child:
                valueWidget ??
                (selectable
                    ? SelectableText(
                        value!,
                        textAlign: TextAlign.right,
                        style: theme.textTheme.bodyMedium,
                      )
                    : Text(
                        value!,
                        textAlign: TextAlign.right,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      )),
          ),
        ],
      ),
    );
  }
}

/// 可点击跳转的一行：左标签 +（可选）右侧提示 + 箭头。
class _NavRow extends StatelessWidget {
  const _NavRow({
    required this.label,
    required this.onTap,
    this.hint,
    this.hintColor,
  });

  final String label;
  final VoidCallback onTap;
  final String? hint;
  final Color? hintColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 12.s),
        child: Row(
          children: [
            Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            if (hint != null)
              Text(
                hint!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: hintColor ?? theme.colorScheme.onSurfaceVariant,
                ),
              ),
            SizedBox(width: 4.s),
            Icon(
              Icons.chevron_right,
              size: 20.s,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}
