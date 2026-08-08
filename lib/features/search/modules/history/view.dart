import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/responsive/screen_adapter.dart';
import '../../../../i18n/translations.g.dart';
import '../pill/state.dart';
import 'state.dart';

/// 搜索历史模块：标题 + 清空按钮 + 历史词 chips。无历史时整体隐藏。
class SearchHistoryModule extends ConsumerWidget {
  const SearchHistoryModule({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final t = context.t;
    final history = ref.watch(searchHistoryProvider);

    if (history.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.fromLTRB(16.s, 12.s, 16.s, 4.s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(t.search.history, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
              ),
              GestureDetector(
                onTap: () => ref.read(searchHistoryProvider.notifier).clear(),
                child: Text(
                  t.search.clearHistory,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
          SizedBox(height: 8.s),
          Wrap(
            spacing: 8.s,
            runSpacing: 4.s,
            children: [
              for (final term in history)
                InputChip(
                  label: Text(term),
                  onPressed: () => ref.read(searchQueryProvider.notifier).update(term),
                  onDeleted: () => ref.read(searchHistoryProvider.notifier).remove(term),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
