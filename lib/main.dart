import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'features/shell/view.dart';
import 'providers/modules/locale_provider.dart';
import 'providers/modules/theme_provider.dart';
import 'core/responsive/screen_adapter.dart';
import 'providers/prefs_provider.dart';
import 'services/wallet_commit_service.dart';
import 'i18n/translations.g.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized(); // 手动把 Flutter 引擎与 Dart 层之间的绑定初始化好
  final sharedPreferences = await SharedPreferences.getInstance(); // 同步拿到 prefs 实例，注入到 provider，供各 Notifier 的 build() 同步读取。

  // 显式持有容器：runApp 之前就要用它做启动对账，之后再交给 UncontrolledProviderScope。
  final container = ProviderContainer(
    overrides: [sharedPrefsProvider.overrideWithValue(sharedPreferences)], // 覆写原来的 Provider，注入真实的实例
  );

  // 启动对账：清理上次被中断的创建 / 导入在安全存储里留下的、无钱包引用的助记词与私钥。
  // 放在 runApp 前是为了排除与首帧内用户操作的竞争；耗时只是一次 Keychain 全量读，毫秒级。
  try {
    await container.read(walletCommitServiceProvider).purgeOrphanSecrets();
  } catch (_) {
    // 对账只是清理残留，失败不应阻塞启动。
  }

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: TranslationProvider(
        child: const MyApp(),
      ), // TranslationProvider 让 context.t / Translations.of(context) 可用，并在切换语言时重建界面。
    ),
  );
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    ref.watch(localeProvider); // 确保启动时恢复已保存的语言（其 build 会同步给 slang）。
    final appearance = ref.watch(appearanceProvider);

    return MaterialApp(
      title: t.appTitle,
      locale: TranslationProvider.of(context).flutterLocale,
      supportedLocales: AppLocaleUtils.supportedLocales,
      localizationsDelegates: const [
        ...GlobalMaterialLocalizations.delegates,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      themeMode: appearance.themeMode,
      // 按选中的主题名生成整套配色：切主题即换 seedColor，theme/darkTheme 随之重建。
      theme: appearance.themeName.lightTheme,
      darkTheme: appearance.themeName.darkTheme,
      builder: (context, child) {
        // 用最新 MediaQuery 刷新缩放比；不锁死 textScaler，保留系统字体大小。
        ScreenAdapter.init(context);
        return child!;
      },
      home: const RootShell(),
    );
  }
}
