import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/responsive/screen_adapter.dart';
import '../../../../widgets/amount_text.dart';
import '../../../../providers/modules/balance_provider.dart';
import '../../../../providers/modules/wallet_provider.dart';
import '../coins/logic.dart';
import '../../../../blockchain/listed_asset.dart';
import '../confirm/view.dart';

/// 金额输入子页：展示可用余额，支持 MAX 一键填入与法币折算。
class SendAmountPage extends ConsumerStatefulWidget {
  const SendAmountPage({super.key, required this.asset, required this.toAddress, this.tokenLogoUrl, this.chainLogoUrl});

  final ListedAsset asset;
  final String toAddress;
  final String? tokenLogoUrl;
  final String? chainLogoUrl;

  @override
  ConsumerState<SendAmountPage> createState() => _SendAmountPageState();
}

class _SendAmountPageState extends ConsumerState<SendAmountPage> {
  final _controller = TextEditingController();
  String? _error;

  /// 当前输入是否由「最大」按钮填入（= 全额余额，网络费用留到确认页扣减）。
  /// 只有它为 true 时，才允许链上从转出额里扣费；用户一旦手动改动输入即失效。
  bool _isMax = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next(String balance) {
    final input = _controller.text.trim();
    final error = SendLogic.validateAmount(input, balance, decimals: widget.asset.decimals);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SendConfirmPage(
          asset: widget.asset,
          toAddress: widget.toAddress,
          amount: input,
          isMaxAmount: _isMax,
          tokenLogoUrl: widget.tokenLogoUrl,
          chainLogoUrl: widget.chainLogoUrl,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final asset = widget.asset;
    final wallet = ref.watch(activeWalletProvider);
    final address = wallet?.addressFor(asset.chain);
    // 进入本页前列表已拦截无地址场景，这里的 address 正常不为空；兜底按 0 处理。
    final balanceAsync = address == null ? null : ref.watch(balanceProvider((asset.chain.id, address, asset.token?.identifier)));
    final balance = balanceAsync?.value?.amount ?? '0';
    // 法币折算：余额查询里已带实时单价。
    final price = balanceAsync?.value?.price ?? 0;
    final inputValue = double.tryParse(_controller.text.trim()) ?? 0;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // —— 顶部头部：返回箭头 + 标题 —— //
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  tooltip: '返回',
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
                Expanded(
                  child: Text(
                    '发送 ${asset.symbol}',
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                SizedBox(width: 48.s),
              ],
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(24.s, 8.s, 24.s, 24.s),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('金额', style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    SizedBox(height: 8.s),
                    TextField(
                      controller: _controller,
                      autofocus: true,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: theme.textTheme.headlineSmall,
                      // 手动改动即不再是 MAX，后续不允许链上自动扣费。
                      onChanged: (_) => setState(() {
                        _error = null;
                        _isMax = false;
                      }),
                      decoration: InputDecoration(
                        hintText: '0',
                        errorText: _error,
                        suffixText: asset.symbol,
                        filled: true,
                        fillColor: theme.colorScheme.surfaceContainerHighest,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12.s),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    SizedBox(height: 8.s),
                    // —— 输入金额的法币折算 —— //
                    AmountText(
                      inputValue * price,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    SizedBox(height: 16.s),
                    // —— 可用余额 + MAX —— //
                    Row(
                      children: [
                        Expanded(
                          child: balanceAsync == null
                              ? Text('可用余额：0 ${asset.symbol}', style: theme.textTheme.bodyMedium)
                              : balanceAsync.when(
                                  loading: () => Text(
                                    '可用余额查询中…',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  error: (_, _) => Text('可用余额：0 ${asset.symbol}', style: theme.textTheme.bodyMedium),
                                  // 刻意不走 formatTokenAmount：这里是用户决定转多少的依据，
                                  // 截断会让人对着一个比实际略小的数做判断。列表页求整齐，
                                  // 这一处求准确。
                                  data: (b) => Text('可用余额：${b.amount} ${b.symbol}', style: theme.textTheme.bodyMedium),
                                ),
                        ),
                        TextButton(
                          // 填满全部余额并标记为「全额转出」，网络费用在确认页按实时费率扣减展示。
                          onPressed: () => setState(() {
                            _controller.text = balance;
                            _isMax = true;
                            _error = null;
                          }),
                          child: const Text('最大'),
                        ),
                      ],
                    ),
                    SizedBox(height: 24.s),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(onPressed: () => _next(balance), child: const Text('下一步')),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
