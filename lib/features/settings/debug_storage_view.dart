import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/responsive/screen_adapter.dart';
import '../../providers/modules/wallet_provider.dart';
import '../wallet/domain/wallet.dart';
import '../wallet/services/secure_wallet_storage.dart';

/// 【调试页】把已持久化的全部钱包原始数据展示出来：
/// - 非敏感元数据（id / name / source / 各链地址）来自 SharedPreferences。
/// - 敏感数据（助记词 / 私钥）按钱包 id 从安全存储（Keychain / Keystore）读取。
///
/// ⚠️ 仅供开发调试 / 备份验证使用，正式发布版不应暴露私钥到 UI。
class DebugStorageScreen extends ConsumerWidget {
  const DebugStorageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallets = ref.watch(walletListProvider);
    final currentId = ref.watch(currentWalletIdProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('存储数据（调试）')),
      body: wallets.isEmpty
          ? const Center(child: Text('暂无已保存的钱包'))
          : ListView(
              padding: EdgeInsets.all(16.s),
              children: [
                Text('当前选中 id：${currentId ?? "(无)"}'),
                SizedBox(height: 8.s),
                Text('共 ${wallets.length} 个钱包',
                    style: Theme.of(context).textTheme.titleMedium),
                SizedBox(height: 12.s),
                for (final w in wallets)
                  _WalletCard(wallet: w, isCurrent: w.id == currentId),
              ],
            ),
    );
  }
}

class _WalletCard extends ConsumerWidget {
  const _WalletCard({required this.wallet, required this.isCurrent});

  final Wallet wallet;
  final bool isCurrent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Card(
      margin: EdgeInsets.only(bottom: 12.s),
      child: Padding(
        padding: EdgeInsets.all(12.s),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(wallet.name,
                      style: theme.textTheme.titleMedium),
                ),
                if (isCurrent)
                  Container(
                    padding:
                        EdgeInsets.symmetric(horizontal: 8.s, vertical: 2.s),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8.s),
                    ),
                    child: Text('当前',
                        style: theme.textTheme.labelSmall),
                  ),
              ],
            ),
            const Divider(),
            _row('name（名称）', wallet.name),
            _row('id', wallet.id),
            _row('source', wallet.source.name),
            _row('address', wallet.address),
            SizedBox(height: 4.s),
            Text('addresses（各链）：', style: theme.textTheme.labelLarge),
            if (wallet.addresses.isEmpty)
              const Text('  (空)')
            else
              for (final e in wallet.addresses.entries)
                _row('  ${e.key}', e.value),
            const Divider(),
            Text('敏感数据（来自安全存储）',
                style: theme.textTheme.labelLarge
                    ?.copyWith(color: theme.colorScheme.error)),
            // ⚠️ 临时调试：每次构建时一次性读取，不进 Provider 缓存。
            FutureBuilder<WalletSecrets>(
              future:
                  ref.read(secureWalletStorageProvider).readSecrets(wallet.id),
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.all(8),
                    child: Text('读取中…'),
                  );
                }
                if (snapshot.hasError) {
                  return Text('读取失败：${snapshot.error}');
                }
                final s = snapshot.data!;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _row('mnemonic', s.mnemonic ?? '(无)'),
                    _row('privateKey', s.privateKey ?? '(无)'),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$label：',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          SelectableText(value),
        ],
      ),
    );
  }
}
