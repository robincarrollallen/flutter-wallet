import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/responsive/screen_adapter.dart';
import '../../../i18n/translations.g.dart';
import '../widgets/create_wallet_sheet.dart';

/// 还没有创建/导入钱包时的引导页。
/// 与底部导航栏同级：此时不显示导航栏，整屏只有引导内容。
class OnboardingScreen extends ConsumerWidget {
  const OnboardingScreen({super.key});

  void _showCreateWalletSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20.s))),
      builder: (context) => const CreateWalletSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final t = context.t;
    return Scaffold(
      appBar: AppBar(backgroundColor: theme.colorScheme.inversePrimary, title: Text(t.appTitle)),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.account_balance_wallet_outlined, size: 88.s, color: theme.colorScheme.primary),
            SizedBox(height: 16.s),
            Text(t.home.noWalletTitle, style: theme.textTheme.titleLarge),
            SizedBox(height: 8.s),
            Text(
              t.home.noWalletSubtitle,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            SizedBox(height: 32.s),
            FilledButton.icon(
              onPressed: () => _showCreateWalletSheet(context),
              icon: const Icon(Icons.add),
              label: Text(t.home.createWallet),
            ),
          ],
        ),
      ),
    );
  }
}
