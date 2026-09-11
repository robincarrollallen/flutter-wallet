import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../blockchain/chain_registry.dart';
import '../../../core/format/token_amount_formatter.dart';
import '../../../core/responsive/screen_adapter.dart';
import '../../../domain/transaction_record.dart';
import '../../../i18n/translations.g.dart';
import '../../../providers/modules/asset/chain_icon_provider.dart';
import '../../../providers/modules/market/markets_provider.dart';
import '../../../router/route_args.dart';
import '../../../router/routes.dart';
import '../../../widgets/token_icon.dart';
import 'logic.dart';
import 'state.dart';

/// 交易历史：按日分组展示当前钱包发起过的交易，可按链筛选。
///
/// 数据来自本地记录（发送成功时写入），下拉刷新会回填仍在确认中的交易状态；
/// 接入区块浏览器后，收款方向的记录会合并进同一个列表，本页无需改动。
class TransactionHistoryScreen extends ConsumerStatefulWidget {
  const TransactionHistoryScreen({super.key});

  @override
  ConsumerState<TransactionHistoryScreen> createState() => _TransactionHistoryScreenState();
}

class _TransactionHistoryScreenState extends ConsumerState<TransactionHistoryScreen> {
  @override
  void initState() {
    super.initState();
    // 进页面先回填一次 pending：用户多半就是回来看那笔交易确认了没有。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(transactionHistoryRefresherProvider).refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final records = ref.watch(filteredTransactionHistoryProvider);
    final grouped = groupByDay(records);

    return Scaffold(
      appBar: AppBar(title: Text(t.transactionHistory.title), actions: const [_ChainFilterAction()]),
      body: RefreshIndicator(
        onRefresh: () => ref.read(transactionHistoryRefresherProvider).refresh(),
        child: records.isEmpty
            // 空态也要能下拉：首次进来没记录时，用户下拉是想触发同步。
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(height: 120.s),
                  const _EmptyState(),
                ],
              )
            : ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.only(bottom: 24.s),
                itemCount: grouped.length,
                itemBuilder: (_, index) {
                  final day = grouped.keys.elementAt(index);
                  return _DaySection(day: day, records: grouped[day]!);
                },
              ),
      ),
    );
  }
}

/// 导航栏右侧的链选择入口：只显示当前筛选链的图标，「全部链」显示地球图标。
///
/// 常驻显示，历史为空时也在——它是入口，不是数据的附属物。
class _ChainFilterAction extends ConsumerWidget {
  const _ChainFilterAction();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final selectedChainId = ref.watch(transactionHistoryFilterProvider).chainId;
    final chainIds = ref.watch(selectableChainsProvider);
    final selectedChain = selectedChainId == null ? null : _chainOf(selectedChainId);

    final theme = Theme.of(context);
    final radius = BorderRadius.circular(999.s);

    return Tooltip(
      message: selectedChain?.name ?? t.transactionHistory.filterAllChains,
      child: Padding(
        padding: EdgeInsets.only(right: 12.s),
        child: Material(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: radius,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _ChainPickerSheet.show(context, chainIds: chainIds, selectedChainId: selectedChainId),
            child: Padding(
              padding: EdgeInsets.fromLTRB(8.s, 4.s, 4.s, 4.s),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (selectedChain == null)
                    Icon(Icons.language, size: 22.s, color: theme.colorScheme.onSurfaceVariant)
                  else
                    _ChainAvatar(chain: selectedChain, size: 22.s),
                  Icon(Icons.arrow_drop_down_rounded, size: 22.s, color: theme.colorScheme.onSurfaceVariant),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 链图标。三级降级：链图标 → 币图标（Bitcoin 这类无平台 id 的走这层）→ 首字母圆底，
/// 与地址管理页同一套取法。
class _ChainAvatar extends ConsumerWidget {
  const _ChainAvatar({required this.chain, required this.size});

  final Chain chain;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logoUrl =
        ref.watch(chainIconsProvider).icons[chain.coinGeckoPlatformId] ??
        ref.watch(marketsProvider).markets[chain.coinGeckoId]?.logoUrl;
    return TokenIcon(symbol: chain.symbol, logoUrl: logoUrl, size: size);
  }
}

/// 链选择弹窗：「全部链」+ 当前钱包的链，当前选中项打勾。选项来源见 [selectableChainsProvider]。
class _ChainPickerSheet extends ConsumerWidget {
  const _ChainPickerSheet({required this.chainIds, required this.selectedChainId});

  final List<String> chainIds;
  final String? selectedChainId;

  /// 全屏弹窗：链最多十来条但每条都要看清图标，占满一屏比半截弹层好读。
  ///
  /// 走 [showModalBottomSheet] 而不是注册路由：它是当前页的一次性选择，不是可返回、
  /// 可深链的目的地，没必要进全局路由表。
  static void show(BuildContext context, {required List<String> chainIds, required String? selectedChainId}) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      // 不避让安全区：弹层要盖住状态栏，顶部留白交给里面 Scaffold 的 AppBar 自己加。
      useSafeArea: false,
      constraints: const BoxConstraints.expand(),
      // 占满整屏就不该再有圆角——默认的顶部圆角会把 AppBar 两角削掉。
      shape: const RoundedRectangleBorder(),
      builder: (_) => _ChainPickerSheet(chainIds: chainIds, selectedChainId: selectedChainId),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;

    void select(String? chainId) {
      ref.read(transactionHistoryFilterProvider.notifier).selectChain(chainId);
      Navigator.of(context).pop();
    }

    // 弹层要铺满整屏（含状态栏），但内容必须避开——关闭按钮压在状态栏下时，
    // 点击会被系统吃掉，按钮等于是死的。
    //
    // `useSafeArea: false` 会让 [showModalBottomSheet] 抹掉 MediaQuery 的顶部 padding，
    // AppBar 于是不再避让。直接从窗口取真实安全区还回去，绕开路由链上的任何改写。
    final windowPadding = MediaQueryData.fromView(View.of(context)).viewPadding;

    return MediaQuery(
      data: MediaQuery.of(context).copyWith(padding: windowPadding, viewPadding: windowPadding),
      child: Scaffold(
        appBar: AppBar(
          // 全屏弹层没有返回语义，左上角给关闭而不是返回箭头。
          leading: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.of(context).pop()),
          title: Text(t.transactionHistory.selectChain),
        ),
        body: ListView(
          children: [
            _ChainOption(
              label: t.transactionHistory.filterAllChains,
              icon: Icon(Icons.language, size: 28.s),
              selected: selectedChainId == null,
              onTap: () => select(null),
            ),
            for (final chainId in chainIds)
              _ChainOption(
                label: _chainNameOf(chainId),
                icon: switch (_chainOf(chainId)) {
                  final chain? => _ChainAvatar(chain: chain, size: 28.s),
                  // 链已下线：没有图标可取，留空位保持各行对齐。
                  null => SizedBox(width: 28.s),
                },
                selected: selectedChainId == chainId,
                onTap: () => select(chainId),
              ),
          ],
        ),
      ),
    );
  }
}

class _ChainOption extends StatelessWidget {
  const _ChainOption({required this.label, required this.icon, required this.selected, required this.onTap});

  final String label;
  final Widget icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      onTap: onTap,
      leading: icon,
      title: Text(label),
      trailing: selected ? Icon(Icons.check_rounded, size: 20.s, color: theme.colorScheme.primary) : null,
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    return Column(
      children: [
        Icon(Icons.receipt_long_outlined, size: 48.s, color: theme.colorScheme.onSurfaceVariant),
        SizedBox(height: 12.s),
        Text(t.transactionHistory.empty, style: theme.textTheme.titleMedium),
        SizedBox(height: 4.s),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 48.s),
          child: Text(
            t.transactionHistory.emptyHint,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

/// 一天的分组：日期标题 + 当天的交易行。
class _DaySection extends StatelessWidget {
  const _DaySection({required this.day, required this.records});

  final DateTime day;
  final List<TransactionRecord> records;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(16.s, 16.s, 16.s, 8.s),
          child: Text(
            _dayLabel(context, day),
            style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
        for (final record in records) _TransactionRow(record: record),
      ],
    );
  }
}

class _TransactionRow extends StatelessWidget {
  const _TransactionRow({required this.record});

  final TransactionRecord record;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final isOutgoing = record.direction == TransactionDirection.outgoing;
    final counterparty = isOutgoing ? record.toAddress : record.fromAddress;
    final (statusLabel, statusColor) = statusAppearance(context, record.status);

    return ListTile(
      onTap: () => context.push(AppRoute.transactionDetail, extra: TransactionDetailArgs(record: record)),
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
        child: Icon(
          isOutgoing ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
          size: 20.s,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      title: Text(
        '${isOutgoing ? t.transactionHistory.directionOutgoing : t.transactionHistory.directionIncoming} ${record.symbol}',
      ),
      subtitle: Text(
        '${shortenAddress(counterparty)} · ${_chainNameOf(record.chainId)}',
        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '${isOutgoing ? '-' : '+'}${formatTokenAmount(record.amount)}',
            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          SizedBox(height: 2.s),
          Text(statusLabel, style: theme.textTheme.bodySmall?.copyWith(color: statusColor)),
        ],
      ),
    );
  }
}

/// 状态的展示文案与配色。列表与详情共用，两处必须一致。
(String, Color) statusAppearance(BuildContext context, TransactionStatus status) {
  final t = context.t;
  final scheme = Theme.of(context).colorScheme;
  return switch (status) {
    TransactionStatus.confirmed => (t.transactionHistory.statusConfirmed, scheme.primary),
    TransactionStatus.failed => (t.transactionHistory.statusFailed, scheme.error),
    TransactionStatus.pending => (t.transactionHistory.statusPending, scheme.tertiary),
  };
}

/// 链 id → 链配置。历史记录可能引用已下线的链，用不抛的方式查。
Chain? _chainOf(String chainId) => SupportedChains.all.where((candidate) => candidate.id == chainId).firstOrNull;

/// 链 id → 展示名。链已下线时退回 id 本身，总比显示空白强。
String _chainNameOf(String chainId) => _chainOf(chainId)?.name ?? chainId;

/// 分组标题：今天 / 昨天 / `2026-09-11`。
String _dayLabel(BuildContext context, DateTime day) {
  final t = context.t;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final difference = today.difference(day).inDays;
  if (difference == 0) return t.transactionHistory.today;
  if (difference == 1) return t.transactionHistory.yesterday;
  return '${day.year}-${_twoDigits(day.month)}-${_twoDigits(day.day)}';
}

String _twoDigits(int value) => value.toString().padLeft(2, '0');
