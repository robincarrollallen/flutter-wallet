import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/responsive/screen_adapter.dart';
import '../../../../../widgets/app_toast.dart';
import '../../../../../providers/modules/wallet_provider.dart';
import '../../../../../domain/wallet.dart';
import '../../widgets/panel/view.dart';

/// 备份步骤二之校验：把助记词打乱后让用户按原顺序依次点击，
/// 顺序全部正确才能点击「完成」。
class VerifyMnemonicPage extends ConsumerStatefulWidget {
  const VerifyMnemonicPage({super.key, required this.wallet, required this.mnemonic});

  final Wallet wallet;
  final String mnemonic;

  @override
  ConsumerState<VerifyMnemonicPage> createState() => _VerifyMnemonicPageState();
}

class _VerifyMnemonicPageState extends ConsumerState<VerifyMnemonicPage> {
  /// 正确顺序的助记词。
  late final List<String> _words = widget.mnemonic.trim().split(RegExp(r'\s+'));

  /// 打乱后的待选词池（固定顺序，不随选择变化）。
  late final List<String> _pool = [..._words]..shuffle();

  /// 已选词在词池中的下标，按点击先后顺序排列。
  final List<int> _picked = [];

  bool get _completed => _picked.length == _words.length;

  /// 当前已选序列是否与正确顺序逐位一致（用于即时标红与启用「完成」）。
  bool get _correct {
    for (var i = 0; i < _picked.length; i++) {
      if (_pool[_picked[i]] != _words[i]) return false;
    }
    return true;
  }

  void _pick(int poolIndex) {
    if (_picked.contains(poolIndex)) return;
    setState(() => _picked.add(poolIndex));
  }

  /// 撤销最后一次选择。
  void _undo() {
    if (_picked.isEmpty) return;
    setState(() => _picked.removeLast());
  }

  void _onConfirm() {
    // 校验通过：标记该钱包已完成手动备份并持久化。
    ref.read(walletListProvider.notifier).addBackupMethod(widget.wallet.id, BackupMethod.manual);
    // 回退两页：弹出本页与手动备份页，回到「选择备份方式」页。
    var popCount = 0;
    Navigator.of(context).popUntil((_) => popCount++ >= 2);
    AppToast.show(context, '助记词校验通过，备份完成');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 已全部选完但顺序错误：整体标红提示重选。
    final hasError = _completed && !_correct;

    return PanelPage(
      title: '校验助记词',
      showBack: true,
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: EdgeInsets.all(16.s),
              children: [
                Text(
                  '请按抄写的顺序依次点击下方助记词，验证你已正确备份。',
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                SizedBox(height: 16.s),
                _AnswerArea(
                  picked: [for (final i in _picked) _pool[i]],
                  total: _words.length,
                  hasError: hasError,
                  onUndo: _picked.isEmpty ? null : _undo,
                ),
                if (hasError) ...[
                  SizedBox(height: 12.s),
                  Text(
                    '顺序不正确，请点击右上角撤销后重新选择。',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                  ),
                ],
                SizedBox(height: 24.s),
                _WordPool(pool: _pool, pickedIndexes: _picked.toSet(), onPick: _pick),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(16.s, 8.s, 16.s, 12.s),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(padding: EdgeInsets.symmetric(vertical: 14.s)),
                  // 全部选完且顺序正确才可点击。
                  onPressed: (_completed && _correct) ? _onConfirm : null,
                  child: const Text('完成'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 已选答案区：按序展示已点选的词；右上角提供撤销。
class _AnswerArea extends StatelessWidget {
  const _AnswerArea({required this.picked, required this.total, required this.hasError, required this.onUndo});

  final List<String> picked;
  final int total;
  final bool hasError;
  final VoidCallback? onUndo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderColor = hasError ? theme.colorScheme.error : theme.colorScheme.outlineVariant;
    return Container(
      width: double.infinity,
      constraints: BoxConstraints(minHeight: 120.s),
      padding: EdgeInsets.all(12.s),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8.s),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '已选 ${picked.length}/$total',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const Spacer(),
              if (onUndo != null)
                InkWell(
                  onTap: onUndo,
                  borderRadius: BorderRadius.circular(6.s),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6.s, vertical: 2.s),
                    child: Row(
                      children: [
                        Icon(Icons.undo, size: 16.s, color: theme.colorScheme.primary),
                        SizedBox(width: 4.s),
                        Text('撤销', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(height: 10.s),
          Wrap(
            spacing: 8.s,
            runSpacing: 8.s,
            children: [
              for (var i = 0; i < picked.length; i++)
                _WordChip(index: i + 1, word: picked[i], filled: true, highlightError: hasError),
            ],
          ),
        ],
      ),
    );
  }
}

/// 待选词池：点选后变灰禁用。
class _WordPool extends StatelessWidget {
  const _WordPool({required this.pool, required this.pickedIndexes, required this.onPick});

  final List<String> pool;
  final Set<int> pickedIndexes;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10.s,
      runSpacing: 10.s,
      children: [
        for (var i = 0; i < pool.length; i++)
          if (pickedIndexes.contains(i))
            _WordChip(word: pool[i], used: true)
          else
            InkWell(
              onTap: () => onPick(i),
              borderRadius: BorderRadius.circular(8.s),
              child: _WordChip(word: pool[i]),
            ),
      ],
    );
  }
}

/// 助记词小卡片：词池态 / 已用态 / 答案态（可选序号、可标红）。
class _WordChip extends StatelessWidget {
  const _WordChip({
    required this.word,
    this.index,
    this.used = false,
    this.filled = false,
    this.highlightError = false,
  });

  final String word;
  final int? index;
  final bool used;
  final bool filled;
  final bool highlightError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final Color bg;
    final Color fg;
    if (used) {
      // 词池中已被选用：灰底淡字。
      bg = theme.colorScheme.surfaceContainerHighest;
      fg = theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5);
    } else if (filled) {
      bg = highlightError ? theme.colorScheme.errorContainer : theme.colorScheme.primaryContainer;
      fg = highlightError ? theme.colorScheme.onErrorContainer : theme.colorScheme.onPrimaryContainer;
    } else {
      bg = theme.colorScheme.surface;
      fg = theme.colorScheme.onSurface;
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.s, vertical: 8.s),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8.s),
        border: filled ? null : Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (index != null) ...[
            Text('$index', style: theme.textTheme.bodySmall?.copyWith(color: fg.withValues(alpha: 0.7))),
            SizedBox(width: 6.s),
          ],
          Text(
            word,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: fg,
              fontWeight: FontWeight.w600,
              decoration: used ? TextDecoration.lineThrough : null,
            ),
          ),
        ],
      ),
    );
  }
}
