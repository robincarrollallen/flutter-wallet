import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/responsive/screen_adapter.dart';
import '../../../router/route_args.dart';
import '../../../router/routes.dart';
import '../../../i18n/translations.g.dart';

class CreateWalletSheet extends StatelessWidget {
  const CreateWalletSheet({super.key});

  /// 关掉弹窗后跳到目标流程。
  ///
  /// router 必须在 pop 之前取好：pop 之后本 sheet 的 context 已从树上摘除，
  /// 再用它查 GoRouter 会失败。
  void _closeSheetAndGo(BuildContext context, String route, {Object? extra}) {
    final router = GoRouter.of(context);
    Navigator.pop(context);
    router.push(route, extra: extra);
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
            onTap: () => _closeSheetAndGo(context, AppRoute.createWallet),
          ),
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: Text(t.createWallet.import.title),
            subtitle: Text(t.createWallet.import.subtitle),
            onTap: () => _closeSheetAndGo(context, AppRoute.importWallet),
          ),
          ListTile(
            leading: const Icon(Icons.usb_outlined),
            title: Text(t.createWallet.hardware.title),
            subtitle: Text(t.createWallet.hardware.subtitle),
            onTap: () => _closeSheetAndGo(
              context,
              AppRoute.placeholder,
              extra: PlaceholderArgs(title: t.createWallet.hardware.title),
            ),
          ),
          SizedBox(height: 8.s),
        ],
      ),
    );
  }
}
