import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/responsive/screen_adapter.dart';
import '../../../../widgets/app_toast.dart';
import '../../../../providers/modules/recent_address_provider.dart';
import '../../../../providers/modules/wallet_provider.dart';
import '../../../../domain/wallet_avatar.dart';
import '../coins/logic.dart';
import '../coins/state.dart';
import '../amount/view.dart';

/// 收款地址页：发送流程第二步，普通路由进入。
/// 结构：多行地址输入框（带清除）→ 扫码/粘贴按钮行 →
/// 剩余高度为地址来源 Tabs（最近使用 / 我的钱包 / 地址簿）→ 底部下一步。
class SendRecipientPage extends ConsumerStatefulWidget {
  const SendRecipientPage({super.key, required this.asset, this.tokenLogoUrl, this.chainLogoUrl});

  final SendAsset asset;

  /// 列表页已拿到的图标 URL，直接透传避免重复查询行情。
  final String? tokenLogoUrl;

  /// 所在链图标 URL：确认页徽标用，与列表行保持一致。
  final String? chainLogoUrl;

  @override
  ConsumerState<SendRecipientPage> createState() => _SendRecipientPageState();
}

class _SendRecipientPageState extends ConsumerState<SendRecipientPage> {
  final _controller = TextEditingController();

  /// 校验错误文案；仅在点过「下一步」或选择/粘贴后变化时展示。
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 用给定地址填充输入框并即时校验（粘贴 / 列表选择共用）。
  void _fill(String address) {
    setState(() {
      _controller.text = address;
      _error = SendLogic.validateAddress(widget.asset.chain, address);
    });
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) return;
    _fill(text);
  }

  void _next() {
    final address = _controller.text.trim();
    final error = SendLogic.validateAddress(widget.asset.chain, address);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SendAmountPage(
          asset: widget.asset,
          toAddress: address,
          tokenLogoUrl: widget.tokenLogoUrl,
          chainLogoUrl: widget.chainLogoUrl,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final asset = widget.asset;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // —— 顶部头部：返回箭头 + 标题 —— //
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  tooltip: '返回',
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
                Expanded(
                  child: Text(
                    '发送 ${asset.symbol}',
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                SizedBox(width: 48.s), // 平衡左侧返回按钮，让标题视觉居中。
              ],
            ),
            // —— 内容区：统一整页水平边距 —— //
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.s),
                child: Column(
                  children: [
                    // —— 多行地址输入框（固定 4 行高，清除按钮悬于右下角） —— //
                    Padding(
                      padding: EdgeInsets.only(top: 8.s),
                      child: Stack(
                        children: [
                          TextField(
                            controller: _controller,
                            minLines: 4,
                            maxLines: 4,
                            style: theme.textTheme.bodyMedium?.copyWith(fontFamily: 'monospace'),
                            onChanged: (v) => setState(() {
                              // 实时校验：空输入不报错（下一步按钮本就隐藏）；
                              // setState 同时驱动清除按钮与下一步的显隐/禁用。
                              final text = v.trim();
                              _error = text.isEmpty ? null : SendLogic.validateAddress(widget.asset.chain, text);
                            }),
                            decoration: InputDecoration(
                              hintText: '输入或粘贴 ${asset.chain.name} 地址',
                              errorText: _error,
                              filled: true,
                              fillColor: theme.colorScheme.surfaceContainerHighest,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12.s),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                          if (_controller.text.isNotEmpty)
                            Positioned(
                              right: 4.s,
                              // 有错误提示时输入框下方多出 errorText 高度，
                              // 按钮锚定到框体右下而非整个 Stack 底部。
                              bottom: _error == null ? 4.s : 28.s,
                              child: IconButton(
                                icon: const Icon(Icons.delete_outline),
                                iconSize: 20.s,
                                tooltip: '清除',
                                color: theme.colorScheme.onSurfaceVariant,
                                onPressed: () => setState(() {
                                  _controller.clear();
                                  _error = null;
                                }),
                              ),
                            ),
                        ],
                      ),
                    ),
                    // —— 扫码 / 粘贴按钮：输入框底部横向排列 —— //
                    Padding(
                      padding: EdgeInsets.fromLTRB(0, 12.s, 0, 4.s),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              // 扫码页尚为占位（未接相机插件），先提示。
                              onPressed: () => AppToast.show(context, '扫码功能暂未接入'),
                              icon: const Icon(Icons.qr_code_scanner_rounded),
                              label: const Text('扫码'),
                            ),
                          ),
                          SizedBox(width: 12.s),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _paste,
                              icon: const Icon(Icons.content_paste_rounded),
                              label: const Text('粘贴'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // —— 剩余高度：地址来源 Tabs —— //
                    Expanded(
                      child: DefaultTabController(
                        length: 3,
                        child: Column(
                          children: [
                            TabBar(
                              // 左对齐 + 去下划线：仅靠文字颜色区分选中态。
                              // 首个 Tab 去掉默认左侧留白，与输入框左缘对齐。
                              isScrollable: true,
                              tabAlignment: TabAlignment.start,
                              padding: EdgeInsets.zero,
                              labelPadding: EdgeInsets.only(right: 24.s),
                              dividerColor: Colors.transparent,
                              labelColor: theme.colorScheme.primary,
                              unselectedLabelColor: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                              indicator: const BoxDecoration(),
                              tabs: const [
                                Tab(text: '最近使用'),
                                Tab(text: '我的钱包'),
                                Tab(text: '地址簿'),
                              ],
                            ),
                            Expanded(
                              child: TabBarView(
                                children: [
                                  _RecentList(asset: asset, onSelect: _fill),
                                  _MyWalletsList(asset: asset, onSelect: _fill),
                                  const _AddressBookList(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // —— 底部下一步：无输入时隐藏（onChanged 的 setState 驱动显隐） —— //
                    if (_controller.text.trim().isNotEmpty)
                      Padding(
                        padding: EdgeInsets.fromLTRB(0, 8.s, 0, 16.s),
                        child: SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            // 地址非法时禁用（灰色不可点）。
                            onPressed: _error == null ? _next : null,
                            child: const Text('下一步'),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 「最近使用」Tab：当前链下发送成功过的地址，最新在前。
class _RecentList extends ConsumerWidget {
  const _RecentList({required this.asset, required this.onSelect});

  final SendAsset asset;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final addresses = ref.watch(recentAddressesOfChainProvider(asset.chain.id));
    if (addresses.isEmpty) {
      return const _EmptyHint('暂无最近使用的地址');
    }
    return ListView.builder(
      padding: EdgeInsets.symmetric(vertical: 8.s),
      itemCount: addresses.length,
      itemBuilder: (context, i) =>
          _AddressTile(icon: Icons.history_rounded, title: addresses[i], onTap: () => onSelect(addresses[i])),
    );
  }
}

/// 「我的钱包」Tab：本机**其他**钱包在当前链上的地址。
/// 发送方即当前钱包（activeWallet），自转无意义，故排除自身。
class _MyWalletsList extends ConsumerWidget {
  const _MyWalletsList({required this.asset, required this.onSelect});

  final SendAsset asset;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallets = ref.watch(walletListProvider);
    final active = ref.watch(activeWalletProvider);
    final entries = [
      for (final w in wallets)
        if (w.id != active?.id)
          if (w.addressFor(asset.chain) case final address?) (w, address),
    ];
    if (entries.isEmpty) {
      return _EmptyHint('暂无其他钱包持有 ${asset.chain.name} 地址');
    }
    return ListView.builder(
      padding: EdgeInsets.symmetric(vertical: 8.s),
      itemCount: entries.length,
      itemBuilder: (context, i) {
        final (wallet, address) = entries[i];
        return _AddressTile(
          leading: WalletAvatar(iconName: wallet.icon, size: 32.s),
          title: wallet.name,
          subtitle: address,
          onTap: () => onSelect(address),
        );
      },
    );
  }
}

/// 「地址簿」Tab：地址簿功能尚未接入，先给空态占位。
class _AddressBookList extends StatelessWidget {
  const _AddressBookList();

  @override
  Widget build(BuildContext context) {
    return const _EmptyHint('暂无地址簿联系人');
  }
}

/// 通用地址行：图标/头像 + 标题（+ 地址副标题），点击回填输入框。
class _AddressTile extends StatelessWidget {
  const _AddressTile({this.icon, this.leading, required this.title, this.subtitle, required this.onTap});

  final IconData? icon;
  final Widget? leading;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mono = theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace');
    return ListTile(
      // 外层已有统一页面边距，行内不再叠加默认的 16 水平内边距。
      contentPadding: EdgeInsets.zero,
      leading: leading ?? Icon(icon, size: 22.s, color: theme.colorScheme.onSurfaceVariant),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        // 无副标题时标题本身就是地址，用等宽字体。
        style: subtitle == null ? mono : theme.textTheme.bodyMedium,
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: mono?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
      onTap: onTap,
    );
  }
}

/// 空态提示：居中灰色文案。
class _EmptyHint extends StatelessWidget {
  const _EmptyHint(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Text(
        message,
        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
      ),
    );
  }
}
