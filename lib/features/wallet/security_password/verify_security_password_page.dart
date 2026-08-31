import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/responsive/screen_adapter.dart';
import '../../../data/datasource/local/security_password_storage.dart';
import '../wallet_management/widgets/panel/view.dart';

/// 校验安全码页面：输入正确后 pop(true)，否则提示错误。
class VerifySecurityPasswordPage extends ConsumerStatefulWidget {
  const VerifySecurityPasswordPage({super.key, this.title = '输入安全码'});

  final String title;

  @override
  ConsumerState<VerifySecurityPasswordPage> createState() => _VerifySecurityPasswordPageState();
}

class _VerifySecurityPasswordPageState extends ConsumerState<VerifySecurityPasswordPage> {
  final _controller = TextEditingController();
  String? _error;
  bool _submitting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final password = _controller.text.trim();
    if (password.isEmpty) {
      setState(() => _error = '请输入安全码');
      return;
    }

    setState(() {
      _error = null;
      _submitting = true;
    });

    final ok = await ref.read(securityPasswordStorageProvider).verify(password);

    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _error = '安全码错误';
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PanelPage(
      title: widget.title,
      showBack: true,
      child: ListView(
        padding: EdgeInsets.all(16.s),
        children: [
          Text('请输入安全码以继续。', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          SizedBox(height: 24.s),
          TextField(
            controller: _controller,
            obscureText: true,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '安全码', border: OutlineInputBorder()),
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
