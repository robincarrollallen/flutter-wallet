import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/currency_symbols.dart';
import '../../../core/responsive/screen_adapter.dart';
import '../../../i18n/translations.g.dart';
import '../../../providers/modules/currency_provider.dart';
import 'logic.dart';

/// 计价货币选择页：搜索 + 单选列表，选中即时生效并持久化。
///
/// 选中后 [marketsProvider] 会按新币种向 CoinGecko 重取行情（接口原生计价，
/// 非本地汇率换算），全应用的金额与货币符号随之刷新。
class CurrencyScreen extends ConsumerStatefulWidget {
  const CurrencyScreen({super.key});

  @override
  ConsumerState<CurrencyScreen> createState() => _CurrencyScreenState();
}

class _CurrencyScreenState extends ConsumerState<CurrencyScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = context.t;
    final current = ref.watch(currencyProvider);
    final codes = CurrencyLogic.filter(supportedCurrencyCodes, _query, t);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: theme.colorScheme.inversePrimary,
        title: Text(t.currency.title),
      ),
      body: Column(
        children: [
          // —— 搜索框：币种代码 / 本地化名称 / 英文名 任一命中 —— //
          Padding(
            padding: EdgeInsets.fromLTRB(16.s, 8.s, 16.s, 8.s),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _query = v),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: t.currency.searchHint,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                      ),
                isDense: true,
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16.s),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: codes.isEmpty
                ? Center(
                    child: Text(
                      t.search.noResult,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: codes.length,
                    itemBuilder: (context, index) {
                      final code = codes[index];
                      return _CurrencyTile(
                        code: code,
                        name: CurrencyLogic.nameOf(t, code),
                        selected: code == current,
                        onTap: () =>
                            ref.read(currencyProvider.notifier).set(code),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// 单个币种行：国旗 + 代码（大标题）+ 名称（小标题），选中时右侧打勾。
class _CurrencyTile extends StatelessWidget {
  const _CurrencyTile({
    required this.code,
    required this.name,
    required this.selected,
    required this.onTap,
  });

  final String code;
  final String name;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      // 国旗 emoji 由代码算出，无需图片资源；定宽保证各行文案左对齐。
      leading: SizedBox(
        width: 32.s,
        child: Center(
          child: Text(
            currencyFlagOf(code),
            style: TextStyle(fontSize: 24.s),
          ),
        ),
      ),
      title: Text(code, style: theme.textTheme.titleMedium),
      subtitle: Text(
        name,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: selected
          ? Icon(Icons.check, color: theme.colorScheme.primary)
          : null,
      onTap: onTap,
    );
  }
}
