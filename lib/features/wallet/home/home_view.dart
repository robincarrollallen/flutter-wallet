import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/responsive/screen_adapter.dart';
import '../../../i18n/translations.g.dart';
import '../../../providers/modules/wallet_panel_progress_provider.dart';
import '../../search/search_view.dart';
import '../../search/modules/pill/view.dart';
import '../../scan/scan_view.dart';
import '../../settings/settings_panel.dart';
import 'modules/wallet_list.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  /// 搜索页用淡入淡出路由：背景（首页）淡出，Hero 让搜索栏单独移动 / 放大到输入框。
  void _openSearch(BuildContext context) {
    Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 400),
        reverseTransitionDuration: const Duration(milliseconds: 400),
        pageBuilder: (_, _, _) => const SearchScreen(),
        transitionsBuilder: (_, anim, _, child) => FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  void _openScan(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ScanScreen()));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 空状态由 RootShell 的引导页处理，这里只会在已有钱包时渲染。
    // 钱包管理面板弹出时，首页随进度缩小 + 加圆角，形成卡片层叠效果。
    final progress = ref.watch(walletPanelProgressProvider);

    // 向下位移距离 = 顶部安全区高度（状态栏/刘海）。
    final topPadding = MediaQuery.of(context).padding.top;

    return ValueListenableBuilder<double>(
      valueListenable: progress,
      builder: (context, t, child) {
        return Transform(
          alignment: Alignment.topCenter, // 横向缩放以顶部中心为锚点
          transform: Matrix4.identity()
            ..translate(0.0, topPadding * t) // 向下平移，最大 = 安全区高度
            ..scale(1 - 0.08 * t, 1.0), // 仅 X 收窄，纵向不缩放
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16.s * t), // 0 → 16
            child: child,
          ),
        );
      },
      child: _walletHome(context),
    );
  }

  /// 已有钱包：自定义头部（设置 / 搜索栏 / 扫码）+ 全屏左侧抽屉。
  Widget _walletHome(BuildContext context) {
    final theme = Theme.of(context);
    final t = context.t;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: theme.colorScheme.inversePrimary,
        // 左侧：设置按钮，从顶部下滑出全屏毛玻璃设置面板（盖住底部导航栏）。
        leading: IconButton(
          icon: const Icon(Icons.settings_outlined),
          tooltip: t.home.settings,
          onPressed: () => Navigator.of(context, rootNavigator: true).push(SettingsPanel.route()),
        ),
        // 中间：搜索栏，点击后 Hero 变形放大到搜索页输入框，其余淡出。
        title: GestureDetector(
          onTap: () => _openSearch(context),
          child: SearchPillHero(
            child: Text(
              t.home.searchHint,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ),
        titleSpacing: 0,
        // 右侧：扫码按钮（与搜索栏拉开一点间距）。
        actions: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 8.s),
            child: IconButton(
              icon: const Icon(Icons.qr_code_scanner),
              tooltip: t.home.scan,
              onPressed: () => _openScan(context),
            ),
          ),
        ],
      ),
      body: const WalletList(),
    );
  }
}
