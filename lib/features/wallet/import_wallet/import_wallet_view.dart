import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/responsive/screen_adapter.dart';
import '../../../i18n/translations.g.dart';
import '../../../router/route_args.dart';
import '../../../router/routes.dart';
import 'import_wallet_logic.dart';
import 'import_wallet_state.dart';
import '../../../enums/import_kind.dart';

class ImportWalletScreen extends ConsumerWidget {
  const ImportWalletScreen({super.key});

  /// 入口标题：按导入方式取当前语言文案。
  String _title(Translations t, ImportKind kind) => switch (kind) {
    ImportKind.software => t.import.software,
    ImportKind.hardware => t.import.hardware,
  };

  /// 点击入口的跳转目标：软件钱包进入助记词导入，硬件钱包暂为占位页。
  void _open(BuildContext context, Translations t, ImportKind kind) {
    switch (kind) {
      case ImportKind.software:
        context.push(AppRoute.importMnemonic);
      case ImportKind.hardware:
        context.push(AppRoute.placeholder, extra: PlaceholderArgs(title: t.createWallet.hardware.title));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final options = ref.watch(importWalletStateProvider).options;
    return Scaffold(
      appBar: AppBar(title: Text(t.import.selectTitle)),
      body: ListView.separated(
        padding: EdgeInsets.all(16.s),
        itemCount: options.length,
        separatorBuilder: (_, _) => SizedBox(height: 12.s),
        itemBuilder: (context, index) {
          final option = options[index];
          return _ImportOptionCard(
            title: _title(t, option.kind),
            brands: option.brands,
            onTap: () => _open(context, t, option.kind),
          );
        },
      ),
    );
  }
}

class _ImportOptionCard extends StatelessWidget {
  const _ImportOptionCard({required this.title, required this.brands, required this.onTap});

  final String title;
  final List<WalletBrand> brands;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.s, vertical: 16.s),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleMedium),
                    SizedBox(height: 10.s),
                    Wrap(
                      spacing: 8.s,
                      runSpacing: 8.s,
                      children: [for (final brand in brands) _WalletLogo(brand: brand)],
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

/// 钱包品牌徽章：优先显示真实 logo 图片；若图片资源缺失，
/// 自动降级为带首字母的彩色徽章，保证界面不会破图。
class _WalletLogo extends StatelessWidget {
  const _WalletLogo({required this.brand});

  final WalletBrand brand;

  static const double _size = 28;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8.s),
      child: Image.asset(
        brand.asset,
        width: _size.s,
        height: _size.s,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _fallback(),
      ),
    );
  }

  Widget _fallback() {
    return Container(
      width: _size.s,
      height: _size.s,
      color: brand.fallbackColor,
      alignment: Alignment.center,
      child: Text(
        brand.fallbackLabel,
        style: TextStyle(color: Colors.white, fontSize: 14.s, fontWeight: FontWeight.bold),
      ),
    );
  }
}
