import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'features/shell/view.dart';
import 'providers/modules/locale_provider.dart';
import 'providers/modules/theme_provider.dart';
import 'core/responsive/screen_adapter.dart';
import 'core/theme/app_colors.dart';
import 'providers/prefs_provider.dart';
import 'i18n/translations.g.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final sharedPreferences = await SharedPreferences.getInstance(); // 同步拿到 prefs 实例，注入到 provider，供各 Notifier 的 build() 同步读取。

  runApp(
    ProviderScope(
      overrides: [sharedPrefsProvider.overrideWithValue(sharedPreferences)],  // 覆写原来的 Provider，注入真实的实例
      child: TranslationProvider(child: const MyApp()), // TranslationProvider 让 context.t / Translations.of(context) 可用，并在切换语言时重建界面。
    ),
  );
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    ref.watch(localeProvider); // 确保启动时恢复已保存的语言（其 build 会同步给 slang）。
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      title: t.appTitle,
      locale: TranslationProvider.of(context).flutterLocale,
      supportedLocales: AppLocaleUtils.supportedLocales,
      localizationsDelegates: const [
        ...GlobalMaterialLocalizations.delegates,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      themeMode: themeMode,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        extensions: const [AppColors.light],
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        extensions: const [AppColors.dark],
      ),
      builder: (context, child) {
        // 用最新 MediaQuery 刷新缩放比；不锁死 textScaler，保留系统字体大小。
        ScreenAdapter.init(context);
        return child!;
      },
      home: const RootShell(),
    );
  }
}
