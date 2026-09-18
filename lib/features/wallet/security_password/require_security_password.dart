import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/navigation/panel_routes.dart';
import '../../../providers/core/service_provider.dart';
import 'set_security_password_page.dart';
import 'verify_security_password_page.dart';

/// 敏感操作前的二次确认：未设置则先设置，已设置则校验。
///
/// 用户取消或校验失败返回 false，调用方不得继续读密钥。
Future<bool> confirmSecurityPassword({required BuildContext context, required WidgetRef ref}) async {
  final hasPassword = await ref.read(securityPasswordServiceProvider).hasPassword();
  if (!context.mounted) return false;
  final confirmed = await Navigator.of(context).push<bool>(panelSlideRoute(hasPassword ? const VerifySecurityPasswordPage() : const SetSecurityPasswordPage()));
  return confirmed == true;
}
