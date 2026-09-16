import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_core/wallet_core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 内存版剪贴板：拦下平台通道，记录 setData / getData。
  String? clipboard;
  late List<String> calls;

  setUp(() {
    clipboard = null;
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        calls.add(call.method);
        switch (call.method) {
          case 'Clipboard.setData':
            clipboard = (call.arguments as Map)['text'] as String?;
            return null;
          case 'Clipboard.getData':
            return clipboard == null ? null : <String, dynamic>{'text': clipboard};
          default:
            return null;
        }
      },
    );
  });

  tearDown(() {
    cancelPendingSensitiveClipboardClear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
  });

  group('copySensitiveToClipboard', () {
    testWidgets('复制后到期自动清空', (tester) async {
      await copySensitiveToClipboard('私钥明文', lifetime: const Duration(seconds: 30));
      expect(clipboard, '私钥明文');

      // 到期前仍在——不能刚复制就清掉，用户还没来得及粘贴。
      await tester.pump(const Duration(seconds: 29));
      expect(clipboard, '私钥明文');

      await tester.pump(const Duration(seconds: 2));
      await tester.pump(); // 让清除里的两次异步通道调用落地
      expect(clipboard, '');
    });

    testWidgets('期间用户复制了别的内容，则不动它', (tester) async {
      await copySensitiveToClipboard('私钥明文', lifetime: const Duration(seconds: 30));

      // 用户自己复制了一段无关文本。
      clipboard = '购物清单';

      await tester.pump(const Duration(seconds: 31));
      await tester.pump();
      // 清掉用户自己的数据是另一种伤害，宁可让密钥早已被覆盖这件事自然发生。
      expect(clipboard, '购物清单');
    });

    testWidgets('连续两次复制，前一次的计时不会提前清掉后一次', (tester) async {
      await copySensitiveToClipboard('第一次', lifetime: const Duration(seconds: 30));
      await tester.pump(const Duration(seconds: 20));

      await copySensitiveToClipboard('第二次', lifetime: const Duration(seconds: 30));
      // 距第一次已 31 秒，若旧计时器还活着，这里就会把「第二次」清掉。
      await tester.pump(const Duration(seconds: 11));
      await tester.pump();
      expect(clipboard, '第二次');

      await tester.pump(const Duration(seconds: 20));
      await tester.pump();
      expect(clipboard, '');
    });
  });
}
