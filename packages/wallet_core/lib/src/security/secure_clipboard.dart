import 'dart:async';

import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:flutter/services.dart';

/// 敏感文本（私钥 / 助记词）复制到剪贴板后的自动清除时长。
///
/// 取 60 秒：够用户切到密码管理器或便签粘贴一次，又不至于让密钥在一个
/// 跨应用共享的缓冲区里长期驻留。
const Duration kSensitiveClipboardLifetime = Duration(seconds: 60);

/// 尚未触发的清除任务。同一时刻只保留一个——后一次复制会取消前一次的计时，
/// 否则先前的计时器会把新复制的内容提前清掉。
Timer? _pendingClear;

/// 把敏感文本放进剪贴板，并在 [lifetime] 之后自动清除。
///
/// 系统剪贴板是**跨应用共享**的：Android 上其他应用可读、输入法通常还带剪贴板
/// 历史；iOS 的通用剪贴板会同步到同一 Apple 账号的其他设备。私钥躺在那里的每一秒
/// 都是暴露窗口，所以复制之后必须有一个自动兜底，不能指望用户自己去清。
///
/// 清除前会**先比对剪贴板当前内容**：用户若在这期间复制了别的东西，那是他自己的
/// 数据，我们没有理由清掉。比对走摘要而不是明文，避免计时器闭包把密钥钉在
/// 进程全局根上整整 [lifetime]。代价是 iOS 14+ 读剪贴板会弹一次「App 已粘贴」
/// 提示——一次一分钟后的提示，换不误删用户数据，这笔交换是划算的。
Future<void> copySensitiveToClipboard(String text, {Duration lifetime = kSensitiveClipboardLifetime}) async {
  await Clipboard.setData(ClipboardData(text: text));

  final digest = _digestOf(text);
  _pendingClear?.cancel();
  _pendingClear = Timer(lifetime, () async {
    _pendingClear = null;
    final current = await Clipboard.getData(Clipboard.kTextPlain);
    final currentText = current?.text;
    if (currentText != null && _digestOf(currentText) == digest) {
      await Clipboard.setData(const ClipboardData(text: ''));
    }
  });
}

String _digestOf(String text) => BytesUtils.toHexString(QuickCrypto.sha256Hash(StringUtils.encode(text)));

/// 立即取消待执行的清除任务。仅供测试使用，避免计时器跨用例泄漏。
void cancelPendingSensitiveClipboardClear() {
  _pendingClear?.cancel();
  _pendingClear = null;
}
