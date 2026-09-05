import 'package:flutter/material.dart';

import '../blockchain/units.dart';
import '../core/format/token_amount_formatter.dart';
import '../core/responsive/screen_adapter.dart';
import '../domain/evm_fee.dart';
import '../enums/fee_speed.dart';

/// 预估网络费选择器：一行按钮，展示当前档位与该档位的预计费用，
/// 点击弹出底部弹窗切换 快速 / 普通 / 缓慢。
///
/// 只负责展示与选择，报价来源与选中值都由外部持有：
/// [quotes] 是各档位的链上报价，行内展示 [EvmFeeQuote.expectedFee]（预计实付），
/// 弹窗里补充 [EvmFeeQuote.maxFee]（出价上限，baseFee 涨到顶格时的最坏情况）。
/// [quotes] 为 null（没有缓存、首次查询还没回来）时费用位显示 `--`；
/// [stale] 为 true 表示展示的是落盘的旧报价，追加「更新中」提示——
/// baseFee 每 12 秒一变，旧数字必须让用户看得出是旧的。
/// 估费失败不阻塞发送，最终以链上实际扣费为准。
class NetworkFeeSelector extends StatelessWidget {
  const NetworkFeeSelector({
    super.key,
    required this.quotes,
    this.stale = false,
    required this.speed,
    required this.onSpeedChanged,
    required this.decimals,
    required this.symbol,
    this.fiatPrice = 0,
    this.currencySymbol = '',
    this.label = '预估网络费',
    this.enabled = true,
  });

  /// 各档位报价；null 表示还没有任何可展示的数据。
  final Map<FeeSpeed, EvmFeeQuote>? quotes;

  /// 报价是否已过新鲜期（展示的是落盘旧值，后台正在刷新）。
  final bool stale;
  final FeeSpeed speed;
  final ValueChanged<FeeSpeed> onSpeedChanged;

  /// 费用计价币种（原生币）的精度与符号。
  final int decimals;
  final String symbol;

  /// 原生币单价与法币符号，均可缺省：缺省时只展示币本位金额。
  final double fiatPrice;
  final String currencySymbol;

  final String label;
  final bool enabled;

  /// 金额文案：`0.00021 ETH（$0.52）`，价格缺失时省略法币部分。
  String _format(BigInt fee) {
    final exact = formatUnits(fee, decimals);
    // 法币折算用精确值算，只有展示的币本位数字被截短。
    final shown = formatTokenAmount(exact);
    if (fiatPrice <= 0) return '$shown $symbol';
    final fiat = (double.tryParse(exact) ?? 0) * fiatPrice;
    return '$shown $symbol（$currencySymbol${fiat.toStringAsFixed(2)}）';
  }

  /// 某档位的预计实付文案。没有数据时给占位。
  String _expectedTextOf(FeeSpeed target) {
    final quote = quotes?[target];
    return quote == null ? '--' : '≈ ${_format(quote.expectedFee)}';
  }

  Future<void> _pickSpeed(BuildContext context) async {
    final picked = await showModalBottomSheet<FeeSpeed>(
      context: context,
      showDragHandle: true, // 与创建钱包等弹窗保持一致：顶部给一条可拖拽下滑关闭的标识。
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.s)),
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                // 顶部留 0：拖拽标识自带上下留白，再加 16 会把标题推得离手柄太远。
                padding: EdgeInsets.fromLTRB(16.s, 0, 16.s, 8.s),
                child: Text(label, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              ),
              for (final option in FeeSpeed.values)
                ListTile(
                  onTap: () => Navigator.of(sheetContext).pop(option),
                  title: Text('${option.label}    ${_expectedTextOf(option)}'),
                  subtitle: Text([option.description, _capNoteOf(option)].nonNulls.join('\n')),
                  isThreeLine: true,
                  trailing: option == speed ? Icon(Icons.check, color: theme.colorScheme.primary) : null,
                ),
              SizedBox(height: 8.s),
            ],
          ),
        );
      },
    );
    if (picked != null && picked != speed) onSpeedChanged(picked);
  }

  /// 出价上限说明：链上按 baseFee + 小费实扣，上限只在 baseFee 暴涨时才会用满。
  String? _capNoteOf(FeeSpeed target) {
    final quote = quotes?[target];
    return quote == null ? null : '上限 ${_format(quote.maxFee)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: enabled ? () => _pickSpeed(context) : null,
      borderRadius: BorderRadius.circular(8.s),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 4.s),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            SizedBox(width: 16.s),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(stale ? '${speed.label}（更新中…）' : speed.label, style: theme.textTheme.bodyMedium),
                  Text(
                    _expectedTextOf(speed),
                    textAlign: TextAlign.right,
                    style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                  ),
                ],
              ),
            ),
            Icon(Icons.keyboard_arrow_right, size: 20.s, color: theme.colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
