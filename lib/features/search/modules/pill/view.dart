import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/responsive/screen_adapter.dart';
import '../../../../i18n/translations.g.dart';
import '../history/state.dart';
import 'logic.dart';
import 'state.dart';

/// 共享的胶囊样式搜索框外壳：首页放静态提示文案，搜索页放可编辑 TextField，
/// 两端样式完全一致，Hero 在它们之间平滑移动 / 放大。
class SearchPill extends StatelessWidget {
  const SearchPill({super.key, required this.child, this.trailing});

  /// 中间内容：首页为 Text 提示，搜索页为 TextField。
  final Widget child;

  /// 右侧可选控件（如清空按钮）。
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 40.s,
      padding: EdgeInsets.symmetric(horizontal: 12.s),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(20.s),
      ),
      child: Row(
        children: [
          Icon(Icons.search, size: 20.s, color: theme.colorScheme.onSurfaceVariant),
          SizedBox(width: 8.s),
          Expanded(child: child),
          ?trailing,
        ],
      ),
    );
  }
}

/// 把胶囊包进 Hero。飞行途中用静态提示版本，避免 TextField 在 Overlay 中无 Material 报错。
class SearchPillHero extends StatelessWidget {
  const SearchPillHero({super.key, required this.child, this.trailing});

  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Hero(
      tag: kSearchHeroTag,
      // 飞行过程中显示静态胶囊（带提示文案），保证两端一致、无焦点抖动。
      flightShuttleBuilder: (_, _, _, _, _) => Material(
        type: MaterialType.transparency,
        child: SearchPill(
          child: Text(
            context.t.home.searchHint,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: SearchPill(trailing: trailing, child: child),
      ),
    );
  }
}

/// 搜索页输入胶囊：内部维护输入框控制器，并把关键词写入 [searchQueryProvider]。
class SearchInputPill extends ConsumerStatefulWidget {
  const SearchInputPill({super.key});

  @override
  ConsumerState<SearchInputPill> createState() => _SearchInputPillState();
}

class _SearchInputPillState extends ConsumerState<SearchInputPill> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = context.t;
    final query = ref.watch(searchQueryProvider);

    return SearchPillHero(
      trailing: query.isEmpty
          ? null
          : GestureDetector(
              onTap: () {
                _controller.clear();
                ref.read(searchQueryProvider.notifier).clear();
              },
              child: Icon(Icons.clear, size: 18.s, color: theme.colorScheme.onSurfaceVariant),
            ),
      child: TextField(
        controller: _controller,
        autofocus: true,
        textInputAction: TextInputAction.search,
        style: theme.textTheme.bodyMedium,
        decoration: InputDecoration(
          hintText: t.search.hint,
          border: InputBorder.none,
          isCollapsed: true,
          hintStyle: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        onChanged: (v) => ref.read(searchQueryProvider.notifier).update(v),
        // 键盘「搜索」时把关键词记入历史。
        onSubmitted: (v) => ref.read(searchHistoryProvider.notifier).add(v),
      ),
    );
  }
}
