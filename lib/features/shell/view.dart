import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/responsive/screen_adapter.dart';
import '../../providers/modules/wallet_provider.dart';
import '../contract/view.dart';
import '../discover/view.dart';
import '../exchange/view.dart';
import '../market/view.dart';
import '../wallet/home/home_view.dart';
import '../wallet/onboarding/onboarding_view.dart';
import 'state.dart';
import 'widgets/glass_nav_bar.dart';

/// 应用根容器：IndexedStack 承载五个一级 tab（保留各自状态），
/// 顶部叠加悬浮的毛玻璃导航栏。
class RootShell extends ConsumerWidget {
  const RootShell({super.key});

  static const List<Widget> _pages = [
    HomeScreen(),
    MarketScreen(),
    ExchangeScreen(),
    ContractScreen(),
    DiscoverScreen(),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 还没有钱包时：只展示引导页，不显示底部导航栏。
    // 引导页与导航栏同级，创建/导入钱包后 hasWalletProvider 变 true，自动切到 shell。
    if (!ref.watch(hasWalletProvider)) {
      return const OnboardingScreen();
    }

    final index = ref.watch(tabIndexProvider);
    return Scaffold(
      body: Stack(
        // 延伸到底部，让内容透过悬浮导航栏的毛玻璃可见。
        children: [
          IndexedStack(index: index, children: _pages),
          Positioned(
            left: 16.s,
            right: 16.s,
            bottom: MediaQuery.of(context).viewPadding.bottom, // 让导航栏整体悬浮在底部安全区之上。
            child: const GlassNavBar(),
          ),
        ],
      ),
    );
  }
}
