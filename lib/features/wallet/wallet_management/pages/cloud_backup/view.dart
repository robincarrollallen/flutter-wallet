import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/responsive/screen_adapter.dart';
import '../../../../../domain/wallet.dart';
import '../../widgets/panel/view.dart';
import '../backup_method/logic.dart';

/// 备份步骤二（云备份）：按平台备份到 iCloud（iOS）或 Google 云端硬盘（Android）。
class CloudBackupPage extends ConsumerWidget {
  const CloudBackupPage({super.key, required this.wallet});

  final Wallet wallet;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final service = BackupMethodLogic.cloudServiceName();
    return PanelPage(
      title: '云备份',
      showBack: true,
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: EdgeInsets.all(16.s),
              children: [
                Center(
                  child: Column(
                    children: [
                      SizedBox(height: 24.s),
                      Icon(Icons.cloud_upload_outlined, size: 64.s, color: theme.colorScheme.primary),
                      SizedBox(height: 16.s),
                      Text('备份到 $service', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                      SizedBox(height: 8.s),
                      Text(
                        '助记词将加密后上传到你的 $service 账户，'
                        '更换设备时可使用同一账户快速恢复钱包。',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
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
                  style: FilledButton.styleFrom(padding: EdgeInsets.symmetric(vertical: 14.s)),
                  onPressed: () => _onBackup(context, service),
                  child: Text('备份到 $service'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 执行云备份（待实现：登录云账户并上传加密助记词）。
  void _onBackup(BuildContext context, String service) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$service 备份功能开发中')));
  }
}
