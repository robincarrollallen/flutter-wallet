import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/responsive/screen_adapter.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../providers/modules/wallet_provider.dart';
import '../../../../../domain/wallet.dart';
import '../../widgets/panel/view.dart';
import '../../../../../core/navigation/panel_routes.dart';
import '../cloud_backup/view.dart';
import '../manual_backup/view.dart';
import 'logic.dart';
import '../../../../../enums/backup_choice.dart';

/// 备份步骤一：选择备份方式（手动备份 / 云备份），并显示各方式的备份状态。
class BackupMethodPage extends ConsumerWidget {
  const BackupMethodPage({super.key, required this.wallet});

  final Wallet wallet;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 监听列表拿最新备份状态，备份完成返回本页时实时刷新。
    final wallets = ref.watch(walletListProvider);
    final current = wallets.firstWhere((w) => w.id == wallet.id, orElse: () => wallet);
    final methods = current.backupMethods;

    return PanelPage(
      title: '选择备份方式',
      showBack: true,
      child: ListView(
        padding: EdgeInsets.all(16.s),
        children: [
          _MethodCard(
            icon: Icons.edit_note,
            title: '手动备份',
            subtitle: '抄写助记词并离线保存，安全性最高',
            backedUp: methods.contains(BackupMethod.manual),
            onTap: () => _onSelect(context, BackupChoice.manual),
          ),
          _MethodCard(
            icon: Icons.cloud_upload_outlined,
            title: '云备份',
            subtitle: BackupMethodLogic.cloudSubtitle(),
            backedUp: methods.contains(BackupMethodLogic.cloudMethod()),
            onTap: () => _onSelect(context, BackupChoice.cloud),
          ),
        ],
      ),
    );
  }

  /// 选择备份方式后进入步骤二：手动备份需先弹出「备份需知」警告确认。
  Future<void> _onSelect(BuildContext context, BackupChoice choice) async {
    if (choice == BackupChoice.manual) {
      final confirmed = await _showManualBackupNotice(context);
      if (confirmed != true || !context.mounted) return;
    }
    final Widget page = switch (choice) {
      BackupChoice.manual => ManualBackupPage(wallet: wallet),
      BackupChoice.cloud => CloudBackupPage(wallet: wallet),
    };
    Navigator.of(context).push(panelSlideRoute(page));
  }

  /// 底部弹窗：手动备份前的「备份需知」红色高醒警告，确认后返回 true。
  Future<bool?> _showManualBackupNotice(BuildContext context) {
    return showModalBottomSheet<bool>(
      context: context,
      builder: (sheetContext) => const _ManualBackupNoticeSheet(),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.s), // 设置圆角大大小
      ),
    );
  }
}

/// 「备份需知」警告弹窗：红色标题 + 每条须知为带勾选框的卡片，
/// 全部勾选后底部「立即备份」按钮才可点击。
class _ManualBackupNoticeSheet extends StatefulWidget {
  const _ManualBackupNoticeSheet();

  @override
  State<_ManualBackupNoticeSheet> createState() => _ManualBackupNoticeSheetState();
}

class _ManualBackupNoticeSheetState extends State<_ManualBackupNoticeSheet> {
  static const _notices = ['App 卸载后，助记词将被删除', '助记词一旦丢失无法找回'];

  // 每条须知的勾选状态，与 _notices 一一对应。
  final List<bool> _checked = List<bool>.filled(_notices.length, false);

  bool get _allChecked => _checked.every((c) => c);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.all(16.s),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.warning_amber_rounded, size: 22.s, color: theme.colorScheme.error),
                SizedBox(width: 8.s),
                Text(
                  '备份需知',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
            ),
            SizedBox(height: 16.s),
            for (var i = 0; i < _notices.length; i++)
              _NoticeCard(
                text: _notices[i],
                checked: _checked[i],
                onTap: () => setState(() => _checked[i] = !_checked[i]),
              ),
            SizedBox(height: 8.s),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  padding: EdgeInsets.symmetric(vertical: 14.s),
                  disabledBackgroundColor: theme.colorScheme.surfaceContainerHighest, // 未全部勾选时为禁用态，背景与未选中勾选框同色。
                  disabledForegroundColor: theme.colorScheme.onSurfaceVariant,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12.s), // 设置圆角大小(12.s 与卡片圆角保持一致)
                  ),
                ),
                onPressed: _allChecked ? () => Navigator.of(context).pop(true) : null,
                child: const Text('立即备份'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 单条须知卡片：左侧文案 + 右侧勾选框；未选中时勾选框背景与卡片同色系。
class _NoticeCard extends StatelessWidget {
  const _NoticeCard({required this.text, required this.checked, required this.onTap});

  final String text;
  final bool checked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.only(bottom: 12.s),
      color: theme.colorScheme.surfaceContainerHighest,
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(16.s),
          child: Row(
            children: [
              Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
              SizedBox(width: 12.s),
              Container(
                width: 22.s,
                height: 22.s,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  // 选中：主色；未选中：与卡片同色（视觉上「融入」背景）。
                  color: checked ? theme.colorScheme.primary : theme.colorScheme.surfaceContainerHighest,
                  border: Border.all(
                    color: checked ? theme.colorScheme.primary : theme.colorScheme.outline,
                    width: 1.5.s,
                  ),
                ),
                child: checked ? Icon(Icons.check, size: 14.s, color: theme.colorScheme.onPrimary) : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 备份方式卡片：左侧图标 + 标题（主）/ 说明（副）+ 备份状态文本 + 右侧箭头。
class _MethodCard extends StatelessWidget {
  const _MethodCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.backedUp,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  /// 该方式是否已完成备份：已备份显示绿色「已备份」，否则红色「未备份」。
  final bool backedUp;
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
              Container(
                width: 40.s,
                height: 40.s,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: theme.colorScheme.primaryContainer, shape: BoxShape.circle),
                child: Icon(icon, size: 22.s, color: theme.colorScheme.onPrimaryContainer),
              ),
              SizedBox(width: 12.s),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                    SizedBox(height: 2.s),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 8.s),
              Text(
                backedUp ? '已备份' : '未备份',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: backedUp ? context.appColors.success : theme.colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(width: 4.s),
              Icon(Icons.chevron_right, size: 20.s, color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
