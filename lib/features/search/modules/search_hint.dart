import 'package:flutter/material.dart';

/// 各结果 Tab 共享的居中提示（空态 / 无结果）。
class SearchHint extends StatelessWidget {
  const SearchHint({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Text(text, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
    );
  }
}
