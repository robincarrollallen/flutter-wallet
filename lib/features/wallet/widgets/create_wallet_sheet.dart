import 'package:flutter/material.dart';

import '../../../core/responsive/screen_adapter.dart';
import '../import_wallet/import_wallet_view.dart';
import '../create_wallet/create_wallet_view.dart';
import '../../../widgets/placeholder_screen.dart';
import '../../../i18n/translations.g.dart';

class CreateWalletSheet extends StatelessWidget {
  const CreateWalletSheet({super.key});

  void _openFlow(BuildContext context, String title) {
    Navigator.pop(context);
    Navigator.push(context, MaterialPageRoute(builder: (context) => PlaceholderScreen(title: title)));
  }

  void _openImport(BuildContext context) {
    Navigator.pop(context);
    Navigator.push(context, MaterialPageRoute(builder: (context) => const ImportWalletScreen()));
  }

  void _openCreate(BuildContext context) {
    Navigator.pop(context);
    Navigator.push(context, MaterialPageRoute(builder: (context) => const CreateWalletView()));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = context.t;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(20.s, 4.s, 20.s, 12.s),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(t.createWallet.title, style: theme.textTheme.titleLarge),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.add_circle_outline),
            title: Text(t.createWallet.create.title),
            subtitle: Text(t.createWallet.create.subtitle),
            onTap: () => _openCreate(context),
          ),
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: Text(t.createWallet.import.title),
            subtitle: Text(t.createWallet.import.subtitle),
            onTap: () => _openImport(context),
          ),
          ListTile(
            leading: const Icon(Icons.usb_outlined),
            title: Text(t.createWallet.hardware.title),
            subtitle: Text(t.createWallet.hardware.subtitle),
            onTap: () => _openFlow(context, t.createWallet.hardware.title),
          ),
          SizedBox(height: 8.s),
        ],
      ),
    );
  }
}
