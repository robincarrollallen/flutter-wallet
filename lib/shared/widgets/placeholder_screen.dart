import 'package:flutter/material.dart';

import '../../core/responsive/screen_adapter.dart';
import '../../i18n/translations.g.dart';

class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.construction_outlined,
              size: 72.s,
              color: theme.colorScheme.primary,
            ),
            SizedBox(height: 16.s),
            Text(context.t.placeholder.wip, style: theme.textTheme.titleMedium),
          ],
        ),
      ),
    );
  }
}
