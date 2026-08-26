import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/responsive/screen_adapter.dart';
import '../../../i18n/translations.g.dart';
import 'import_mnemonic_logic.dart';
import 'import_mnemonic_state.dart';
import '../../../enums/secret_type.dart';

/// 把校验错误类型映射为当前语言的文案。
String _errorText(Translations t, MnemonicError error) {
  final m = t.import.mnemonic.errors;
  switch (error.kind) {
    case MnemonicErrorKind.empty:
      return m.empty;
    case MnemonicErrorKind.nonEnglish:
      return m.nonEnglish;
    case MnemonicErrorKind.wordCount:
      return m.wordCount(count: error.count ?? 0);
    case MnemonicErrorKind.invalidWords:
      return m.invalidWords(words: (error.words ?? const []).join('、'));
    case MnemonicErrorKind.checksum:
      return m.checksum;
    case MnemonicErrorKind.invalidPrivateKey:
      return m.invalidPrivateKey;
    case MnemonicErrorKind.deriveFailed:
      return t.import.mnemonic.deriveFailed;
  }
}

class ImportMnemonicView extends ConsumerStatefulWidget {
  const ImportMnemonicView({super.key});

  @override
  ConsumerState<ImportMnemonicView> createState() => _ImportMnemonicViewState();
}

class _ImportMnemonicViewState extends ConsumerState<ImportMnemonicView> {
  late final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// 点击候选词：替换末尾正在敲的单词为完整词，光标移到末尾，保持键盘不收起。
  void _applySuggestion(String word) {
    final notifier = ref.read(importMnemonicProvider.notifier);
    final text = ImportMnemonicLogic.applySuggestion(_controller.text, word);
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    notifier.onMnemonicChanged(text);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(importMnemonicProvider);
    final notifier = ref.read(importMnemonicProvider.notifier);
    final theme = Theme.of(context);
    final t = context.t;

    Future<void> onImport() async {
      final ok = await notifier.submit();
      if (ok && context.mounted) {
        // 导入成功后清空导入相关路由（助记词页 + 选择页），回到首页。
        Navigator.popUntil(context, (route) => route.isFirst);
      }
    }

    return Scaffold(
      appBar: AppBar(title: Text(t.import.mnemonic.title)),
      // body 底部的候选栏会随键盘上移（resizeToAvoidBottomInset 默认开启）。
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(16.s),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    onChanged: notifier.onMnemonicChanged,
                    autofocus: true,
                    maxLines: 5,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      hintText: t.import.mnemonic.hint,
                      helperText: t.import.mnemonic.helper,
                      errorText: state.error == null ? null : _errorText(t, state.error!),
                      counterText: state.wordCount > 0 ? t.import.mnemonic.wordCount(n: state.wordCount) : null,
                    ),
                  ),
                  SizedBox(height: 12.s),
                  Row(
                    children: [
                      Icon(Icons.info_outline, size: 16.s, color: theme.colorScheme.onSurfaceVariant),
                      SizedBox(width: 6.s),
                      Expanded(
                        child: Text(
                          t.import.mnemonic.warning,
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 24.s),
                  FilledButton(
                    onPressed: state.canSubmit ? onImport : null,
                    child: state.submitting
                        ? SizedBox(width: 18.s, height: 18.s, child: const CircularProgressIndicator(strokeWidth: 2))
                        : Text(t.import.mnemonic.submit),
                  ),
                ],
              ),
            ),
          ),
          _SuggestionBar(suggestions: state.suggestions, onTap: _applySuggestion),
        ],
      ),
    );
  }
}

/// 键盘上方的横向候选词栏：有候选时显示，点击补全。
class _SuggestionBar extends StatelessWidget {
  const _SuggestionBar({required this.suggestions, required this.onTap});

  final List<String> suggestions;
  final void Function(String word) onTap;

  @override
  Widget build(BuildContext context) {
    if (suggestions.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);

    return Material(
      elevation: 8,
      color: theme.colorScheme.surfaceContainerHighest,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 48.s,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: 12.s, vertical: 6.s),
            itemCount: suggestions.length,
            separatorBuilder: (_, _) => SizedBox(width: 8.s),
            itemBuilder: (context, index) {
              final word = suggestions[index];
              return ActionChip(label: Text(word), onPressed: () => onTap(word));
            },
          ),
        ),
      ),
    );
  }
}
