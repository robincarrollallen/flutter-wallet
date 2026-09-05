import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/scan/scan_view.dart';
import '../features/search/search_view.dart';
import '../features/settings/appearance_view.dart';
import '../features/settings/currency/view.dart';
import '../features/settings/settings_panel.dart';
import '../features/settings/theme_colors_view.dart';
import '../features/shell/view.dart';
import '../features/wallet/address_management/address_management_view.dart';
import '../features/wallet/create_wallet/create_wallet_view.dart';
import '../features/wallet/import_mnemonic/import_mnemonic_view.dart';
import '../features/wallet/import_wallet/import_wallet_view.dart';
import '../features/wallet/manage_tokens/view.dart';
import '../features/wallet/onboarding/onboarding_view.dart';
import '../features/wallet/send/amount/view.dart';
import '../features/wallet/send/coins/view.dart';
import '../features/wallet/send/confirm/view.dart';
import '../features/wallet/send/recipient/view.dart';
import '../features/wallet/send/result/view.dart';
import '../features/wallet/wallet_management/view.dart';
import '../providers/modules/wallet_provider.dart';
import '../widgets/placeholder_screen.dart';
import 'route_args.dart';
import 'routes.dart';

/// 全应用唯一的路由表。
///
/// 用 Provider 暴露而非全局 final，是为了 [GoRouter.redirect] 能读到钱包状态
/// （无钱包时强制停留引导页），同时让 router 的生命周期跟随 ProviderContainer。
final appRouterProvider = Provider<GoRouter>((ref) {
  final walletGate = _WalletGateNotifier(ref);
  ref.onDispose(walletGate.dispose);

  return GoRouter(
    initialLocation: AppRoute.root,
    // 钱包从无到有（或被删光）时重新跑一遍 redirect，把用户带到该去的页面。
    refreshListenable: walletGate,
    redirect: (context, state) => _walletGateRedirect(ref, state),
    routes: [
      GoRoute(
        path: AppRoute.root,
        // 首页是 IndexedStack 承载的 tab 容器，切 tab 是纯状态，不参与路由；
        // 它是根页面，没有进入转场。
        pageBuilder: (_, state) => NoTransitionPage(key: state.pageKey, child: const RootShell()),
      ),
      GoRoute(
        path: AppRoute.onboarding,
        pageBuilder: (_, state) => NoTransitionPage(key: state.pageKey, child: const OnboardingScreen()),
      ),

      // —— 首页入口 —— //
      GoRoute(
        path: AppRoute.search,
        // 淡入淡出：背景（首页）淡出，Hero 让搜索栏单独移动 / 放大到输入框。
        pageBuilder: (_, state) => CustomTransitionPage<void>(
          key: state.pageKey,
          transitionDuration: const Duration(milliseconds: 400),
          reverseTransitionDuration: const Duration(milliseconds: 400),
          transitionsBuilder: (_, animation, _, child) => FadeTransition(opacity: animation, child: child),
          child: const SearchScreen(),
        ),
      ),
      GoRoute(path: AppRoute.scan, builder: (_, _) => const ScanScreen()),
      GoRoute(path: AppRoute.manageTokens, builder: (_, _) => const ManageTokensScreen()),
      GoRoute(
        path: AppRoute.addressManagement,
        redirect: _requireArgs<AddressManagementArgs>,
        builder: (_, state) => AddressManagementScreen(wallet: (state.extra! as AddressManagementArgs).wallet),
      ),
      GoRoute(
        path: AppRoute.walletPanel,
        // 从底部向上滑入的透明覆盖层：下层首页保持渲染并随进度缩放。
        pageBuilder: (_, state) => CustomTransitionPage<void>(
          key: state.pageKey,
          opaque: false,
          barrierColor: Colors.transparent,
          transitionDuration: const Duration(milliseconds: 300),
          reverseTransitionDuration: const Duration(milliseconds: 250),
          transitionsBuilder: (_, animation, _, child) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            );
            return SlideTransition(
              position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero).animate(curved),
              child: child,
            );
          },
          child: const WalletManagementScreen(),
        ),
      ),

      // —— 设置面板：从顶部下滑的全屏毛玻璃覆盖层，盖住悬浮导航栏 —— //
      GoRoute(
        path: AppRoute.settings,
        pageBuilder: (_, state) => CustomTransitionPage<void>(
          key: state.pageKey,
          opaque: false,
          barrierColor: Colors.transparent,
          transitionDuration: const Duration(milliseconds: 300),
          reverseTransitionDuration: const Duration(milliseconds: 300),
          transitionsBuilder: (_, animation, _, child) => SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, -1),
              end: Offset.zero,
            ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
            child: child,
          ),
          child: const SettingsPanel(),
        ),
        routes: [
          GoRoute(path: AppRoute.settingsAppearanceSegment, builder: (_, _) => const AppearanceScreen()),
          GoRoute(path: AppRoute.settingsCurrencySegment, builder: (_, _) => const CurrencyScreen()),
          GoRoute(path: AppRoute.settingsThemeColorsSegment, builder: (_, _) => const ThemeColorsScreen()),
        ],
      ),

      // —— 发送流程：逐级嵌套，返回天然回到上一步 —— //
      GoRoute(
        path: AppRoute.send,
        // 全屏模态：从底部滑入。
        pageBuilder: (_, state) => CustomTransitionPage<void>(
          key: state.pageKey,
          fullscreenDialog: true,
          transitionsBuilder: (_, animation, _, child) => SlideTransition(
            position: animation.drive(
              Tween(begin: const Offset(0, 1), end: Offset.zero).chain(CurveTween(curve: Curves.easeOutCubic)),
            ),
            child: child,
          ),
          child: const SendScreen(),
        ),
        routes: [
          GoRoute(
            path: AppRoute.sendRecipientSegment,
            redirect: _requireArgs<SendRecipientArgs>,
            builder: (_, state) {
              final args = state.extra! as SendRecipientArgs;
              return SendRecipientPage(
                asset: args.asset,
                tokenLogoUrl: args.tokenLogoUrl,
                chainLogoUrl: args.chainLogoUrl,
              );
            },
            routes: [
              GoRoute(
                path: AppRoute.sendAmountSegment,
                redirect: _requireArgs<SendAmountArgs>,
                builder: (_, state) {
                  final args = state.extra! as SendAmountArgs;
                  return SendAmountPage(
                    asset: args.asset,
                    toAddress: args.toAddress,
                    tokenLogoUrl: args.tokenLogoUrl,
                    chainLogoUrl: args.chainLogoUrl,
                  );
                },
                routes: [
                  GoRoute(
                    path: AppRoute.sendConfirmSegment,
                    redirect: _requireArgs<SendConfirmArgs>,
                    builder: (_, state) {
                      final args = state.extra! as SendConfirmArgs;
                      return SendConfirmPage(
                        asset: args.asset,
                        toAddress: args.toAddress,
                        amount: args.amount,
                        isMaxAmount: args.isMaxAmount,
                        tokenLogoUrl: args.tokenLogoUrl,
                        chainLogoUrl: args.chainLogoUrl,
                      );
                    },
                    routes: [
                      GoRoute(
                        path: AppRoute.sendResultSegment,
                        redirect: _requireArgs<SendResultArgs>,
                        builder: (_, state) {
                          final args = state.extra! as SendResultArgs;
                          return SendResultPage(
                            asset: args.asset,
                            toAddress: args.toAddress,
                            amount: args.amount,
                            txHash: args.txHash,
                            status: args.status,
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
      ),

      // —— 创建 / 导入钱包：见 [_walletGateRedirect] 的豁免说明 —— //
      GoRoute(path: AppRoute.createWallet, builder: (_, _) => const CreateWalletView()),
      GoRoute(
        path: AppRoute.importWallet,
        builder: (_, _) => const ImportWalletScreen(),
        routes: [GoRoute(path: AppRoute.importMnemonicSegment, builder: (_, _) => const ImportMnemonicView())],
      ),
      GoRoute(
        path: AppRoute.placeholder,
        redirect: _requireArgs<PlaceholderArgs>,
        builder: (_, state) => PlaceholderScreen(title: (state.extra! as PlaceholderArgs).title),
      ),
    ],
  );
});

/// 带参路由的兜底：`extra` 不是期望类型（热重载丢失、或被直接以路径跳转）时回首页，
/// 而不是在 builder 里强转崩溃。
String? _requireArgs<T>(BuildContext context, GoRouterState state) => state.extra is T ? null : AppRoute.root;

/// 无钱包门禁：没有任何钱包时只允许停留在引导页与创建 / 导入流程。
///
/// 创建 / 导入流程必须豁免——流程进行到一半 `hasWallet` 就会翻转为 true，
/// 若不豁免，用户会在看到成功页之前被 redirect 直接弹走。
String? _walletGateRedirect(Ref ref, GoRouterState state) {
  const exemptPrefixes = [AppRoute.createWallet, AppRoute.importWallet, AppRoute.placeholder];
  final location = state.matchedLocation;
  if (exemptPrefixes.any(location.startsWith)) return null;

  final hasWallet = ref.read(hasWalletProvider);
  if (!hasWallet) return location == AppRoute.onboarding ? null : AppRoute.onboarding;
  return location == AppRoute.onboarding ? AppRoute.root : null;
}

/// 把 [hasWalletProvider] 的变化桥接成 [Listenable]，供 go_router 触发重定向。
class _WalletGateNotifier extends ChangeNotifier {
  _WalletGateNotifier(Ref ref) {
    _subscription = ref.listen<bool>(hasWalletProvider, (_, _) => notifyListeners());
  }

  late final ProviderSubscription<bool> _subscription;

  @override
  void dispose() {
    _subscription.close();
    super.dispose();
  }
}
