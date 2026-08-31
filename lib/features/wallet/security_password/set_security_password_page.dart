import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/responsive/screen_adapter.dart';
import '../../../data/datasource/local/security_password_storage.dart';
import '../wallet_management/widgets/panel/view.dart';

/// 设置安全码页面：输入并确认两次，一致后写入安全存储。
/// 成功后 pop(true)，方便调用方继续后续敏感操作。
class SetSecurityPasswordPage extends ConsumerStatefulWidget {
  const SetSecurityPasswordPage({super.key});

  @override
  ConsumerState<SetSecurityPasswordPage> createState() => _SetSecurityPasswordPageState();
}

class _SetSecurityPasswordPageState extends ConsumerState<SetSecurityPasswordPage> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  String? _error;
  bool _submitting = false;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final password = _passwordController.text.trim();
    final confirm = _confirmController.text.trim();

    if (password.length < 6) {
      setState(() => _error = '安全码至少 6 位');
      return;
    }
    if (password != confirm) {
      setState(() => _error = '两次输入不一致');
      return;
    }

    setState(() {
      _error = null;
      _submitting = true;
    });

    await ref.read(securityPasswordStorageProvider).setPassword(password);
    ref.invalidate(securityPasswordSetProvider);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('安全码设置成功')));
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PanelPage(
      title: '设置安全码',
      showBack: true,
      child: ListView(
        padding: EdgeInsets.all(16.s),
        children: [
          Text(
            '安全码用于导出私钥、备份等敏感操作的身份校验，请牢记。',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          SizedBox(height: 24.s),
          TextField(
            controller: _passwordController,
            obscureText: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '安全码', hintText: '请输入至少 6 位', border: OutlineInputBorder()),
          ),
          SizedBox(height: 16.s),
          TextField(
            controller: _confirmController,
            obscureText: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '确认安全码', hintText: '请再次输入', border: OutlineInputBorder()),
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null) ...[
            SizedBox(height: 12.s),
            Text(_error!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
          ],
          SizedBox(height: 24.s),
          FilledButton(onPressed: _submitting ? null : _submit, child: const Text('确认')),
        ],
      ),
    );
  }
}
