import 'package:flutter/material.dart';

import '../../core/responsive/screen_adapter.dart';
import '../../i18n/translations.g.dart';

/// 扫码页占位：相机扫码需接入插件（如 mobile_scanner），此处先给出页面骨架。
class ScanScreen extends StatelessWidget {
  const ScanScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = context.t;
    return Scaffold(
      appBar: AppBar(title: Text(t.scan.title)),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 220.s,
              height: 220.s,
              decoration: BoxDecoration(
                border: Border.all(color: theme.colorScheme.primary, width: 2),
                borderRadius: BorderRadius.circular(16.s),
              ),
              child: Icon(
                Icons.qr_code_scanner,
                size: 96.s,
                color: theme.colorScheme.primary,
              ),
            ),
            SizedBox(height: 24.s),
            Text(
              t.scan.hint,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
