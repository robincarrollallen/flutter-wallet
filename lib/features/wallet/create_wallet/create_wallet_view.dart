import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/responsive/screen_adapter.dart';
import '../../../i18n/translations.g.dart';
import '../../../widgets/confetti_overlay.dart';
import 'create_wallet_state.dart';

/// 新建助记词钱包流程页：
/// 进入即开始创建（生成助记词 + 派生地址），全程播放过渡动画并屏蔽返回；
/// 成功后切换为带礼花的静态成功页，仅提供「开始使用新钱包」一个出口。
class CreateWalletView extends ConsumerStatefulWidget {
  const CreateWalletView({super.key});

  @override
  ConsumerState<CreateWalletView> createState() => _CreateWalletViewState();
}

class _CreateWalletViewState extends ConsumerState<CreateWalletView> {
  @override
  void initState() {
    super.initState();
    // 进入页面即触发真正的创建逻辑。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(createWalletProvider.notifier).create();
    });
  }

  /// 回到首页：清空创建流程相关路由，回到根（首页）。
  /// 首页会据钱包列表自动扫描资产并展示总资产价值。
  void _goHome() {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(createWalletProvider);
    final generating = state.phase == CreatePhase.generating;

    // 生成阶段禁止返回，避免中途产生半成品钱包；成功/失败阶段放开。
    return PopScope(
      canPop: !generating,
      child: Scaffold(
        body: switch (state.phase) {
          CreatePhase.generating => const _GeneratingView(),
          CreatePhase.success => _SuccessView(onStart: _goHome),
          CreatePhase.failed => _FailedView(
            onRetry: () => ref.read(createWalletProvider.notifier).create(),
            onBack: () => Navigator.of(context).maybePop(),
          ),
        },
      ),
    );
  }
}

/// 生成中的过渡动画：旋转 + 呼吸缩放的钱包图标，配文案。
class _GeneratingView extends StatefulWidget {
  const _GeneratingView();

  @override
  State<_GeneratingView> createState() => _GeneratingViewState();
}

class _GeneratingViewState extends State<_GeneratingView> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = context.t;
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 32.s),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                // 呼吸缩放 + 缓慢旋转，营造「正在生成」的过渡感。
                final scale = 1 + 0.12 * (0.5 - (_controller.value - 0.5).abs());
                return Transform.rotate(
                  angle: _controller.value * 6.2831853,
                  child: Transform.scale(scale: scale, child: child),
                );
              },
              child: Container(
                width: 104.s,
                height: 104.s,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(colors: [theme.colorScheme.primary, theme.colorScheme.tertiary]),
                ),
                child: Icon(Icons.account_balance_wallet, size: 52.s, color: theme.colorScheme.onPrimary),
              ),
            ),
            SizedBox(height: 32.s),
            Text(t.create.generatingTitle, style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
            SizedBox(height: 12.s),
            Text(
              t.create.generatingHint,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 28.s),
            SizedBox(width: 160.s, child: const LinearProgressIndicator()),
          ],
        ),
      ),
    );
  }
}

/// 创建成功的静态页：纯静态插画 + 礼花动画 + 单一行动按钮。
class _SuccessView extends StatelessWidget {
  const _SuccessView({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = context.t;
    return Stack(
      children: [
        // —— 静态成功内容 —— //
        SafeArea(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 32.s),
            child: Column(
              children: [
                const Spacer(),
                _SuccessBadge(),
                SizedBox(height: 32.s),
                Text(
                  t.create.successTitle,
                  style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 12.s),
                Text(
                  t.create.successSubtitle,
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: onStart,
                    style: FilledButton.styleFrom(padding: EdgeInsets.symmetric(vertical: 16.s)),
                    child: Text(t.create.start),
                  ),
                ),
                SizedBox(height: 24.s),
              ],
            ),
          ),
        ),
        // —— 覆盖在内容之上的礼花动画 —— //
        const Positioned.fill(child: ConfettiOverlay()),
      ],
    );
  }
}

/// 静态成功徽标：分层圆形 + 对勾。纯静态、无动画。
class _SuccessBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 132.s,
      height: 132.s,
      decoration: BoxDecoration(shape: BoxShape.circle, color: theme.colorScheme.primaryContainer),
      alignment: Alignment.center,
      child: Container(
        width: 92.s,
        height: 92.s,
        decoration: BoxDecoration(shape: BoxShape.circle, color: theme.colorScheme.primary),
        child: Icon(Icons.check_rounded, size: 56.s, color: theme.colorScheme.onPrimary),
      ),
    );
  }
}

/// 创建失败：提供重试与返回。
class _FailedView extends StatelessWidget {
  const _FailedView({required this.onRetry, required this.onBack});

  final VoidCallback onRetry;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = context.t;
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 32.s),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 72.s, color: theme.colorScheme.error),
            SizedBox(height: 16.s),
            Text(t.create.failed, style: theme.textTheme.titleMedium),
            SizedBox(height: 24.s),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton(onPressed: onBack, child: Text(MaterialLocalizations.of(context).backButtonTooltip)),
                SizedBox(width: 12.s),
                FilledButton(onPressed: onRetry, child: Text(t.create.retry)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
