import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../blockchain/chain_registry.dart';
import '../blockchain/bundled_token_catalog.dart';
import '../blockchain/token.dart';
import '../blockchain/listed_asset.dart';
import '../blockchain/token_catalog.dart';
import '../enums/prefs_key.dart';
import 'modules/custom_tokens_provider.dart';
import 'modules/hidden_assets_provider.dart';
import 'persistent_notifier.dart';
import 'token_catalog_api_provider.dart';

export 'modules/custom_tokens_provider.dart';
export 'modules/hidden_assets_provider.dart';
export 'token_catalog_api_provider.dart';

/// 远程代币目录 + 这份数据的写入时刻。
///
/// [at] 必须进 state：[PersistentNotifier] 只落盘 state，判过期要用的东西不在里面
/// 就落不了盘，重启后也就判不出来。[at] 为 null 表示「手上这份是打包目录，不是远端结果」。
typedef RemoteTokensState = ({List<Token> tokens, DateTime? at});

/// 远程下发的代币目录。
///
/// 取数策略是「先旧后新」，与 [marketsProvider]、[chainIconsProvider] 同一套路：
///
/// 1. [restore] 同步读盘 —— 没有 await，[build] 执行完这行旧目录已经在手上；
/// 2. 失效（超过 [_ttl]）才发请求，且**不 await**，[build] 立刻带着旧目录返回；
/// 3. 请求回来后 `state = ...`，watcher 自动重建，listenSelf 自动落盘。
///
/// 刻意用同步 [Notifier] 而非 FutureProvider：后者把网络挡在「state 建立」的路上，
/// 首帧只能拿到 loading，接收页会先闪一轮「只有原生币」。同步 Notifier 里网络在旁边跑，
/// 首帧永远是一份完整目录——最差也是 [BundledTokenCatalog]。
class RemoteTokensNotifier extends Notifier<RemoteTokensState> with PersistentNotifier<RemoteTokensState> {
  /// 目录缓存有效期。代币合约列表很少变，远宽于行情的 5 分钟。
  static const ttl = Duration(hours: 24);

  /// 正在飞的那次请求；没有请求在飞时为 null。只给 [ready] 用。
  Future<void>? _pending;

  @override
  PrefsKey get persistKey => PrefsKey.tokenCatalog;

  /// `at` / `data` 两个键沿用旧的 TokenCatalogCache，老用户升级后直接读得出旧缓存。
  ///
  /// [at] 为 null 时落一份空 map（[fromJson] 读到会退回 fallback）：手上这份是打包目录，
  /// 把它写进缓存等于把打包结果当成远端结果，会挡住下次重试。
  @override
  Map<String, dynamic> toJson(RemoteTokensState state) => state.at == null
      ? const {}
      : {'at': state.at!.millisecondsSinceEpoch, 'data': [for (final t in state.tokens) t.toJson()]};

  @override
  RemoteTokensState fromJson(Map<String, dynamic> json, RemoteTokensState fallback) {
    final at = json['at'];
    if (at is! int) return fallback;
    final tokens = Token.listFromJson(json['data']);
    if (tokens.isEmpty) return fallback;
    return (tokens: tokens, at: DateTime.fromMillisecondsSinceEpoch(at));
  }

  @override
  RemoteTokensState build() {
    ref.keepAlive();

    // 打包目录当默认值：没有任何缓存时首帧也有一份完整目录，不必等网络。
    final restored = restore((tokens: BundledTokenCatalog.all, at: null)); // 同步读盘

    _pending = _isExpired(restored.at) ? refresh() : null; // 刻意不 await

    return restored; // 立刻带着旧目录返回，UI 首帧即有完整代币列表
  }

  /// 过期（含从没抓到过远端结果，此时 [at] 为 null）就重取。
  bool _isExpired(DateTime? at) => at == null || DateTime.now().difference(at) >= ttl;

  /// 取数：无视 TTL 直接重取，返回是否拿到了新目录——失败时旧目录原封不动。
  ///
  /// [build] 里的后台补拉与下拉刷新是同一件事（目录没有 currency 之类的参数要分），
  /// 所以只有这一个方法，不再套一层同名转发。
  /// 不需要调用方再 invalidate：拿到新目录就直接赋值 state，watcher 自动重建。
  Future<bool> refresh() async {
    final fresh = await ref.read(tokenCatalogApiProvider).fetchCatalog();

    // 空列表即失败（数据源约定）：保持旧目录与旧 at 不动，下次再试，
    // 绝不把「失败」写成空目录——旧目录（或打包目录）远好过一个空列表。
    if (fresh.isEmpty) return false;
    // fire-and-forget 期间 provider 可能已销毁，此时赋值会抛。
    if (!ref.mounted) return false;

    state = (tokens: fresh, at: DateTime.now()); // listenSelf 监听到，自动落盘
    return true;
  }

  /// 给「必须等目录落地」的调用方用：有请求在飞就等它，等完返回当前目录。
  ///
  /// 与行情不同，这里永远有兜底数据（打包目录），因此不存在「取不到就报错」那条路。
  Future<List<Token>> get ready async {
    await _pending;
    return state.tokens;
  }
}

/// 远程目录（落盘缓存 / HTTP / 打包回退）。keepAlive 避免离开页面就丢掉已拉到的列表。
final remoteTokensProvider = NotifierProvider<RemoteTokensNotifier, RemoteTokensState>(RemoteTokensNotifier.new);

/// 当前可展示的代币目录：远程 ∪ 自定义。
///
/// 远端还没拉到时 [remoteTokensProvider] 给的是 [BundledTokenCatalog]，
/// 且是同步给出的——接收页不会先闪一轮「只有原生币」。
/// 页面只 watch 这一份，不要自己拼 [SupportedChains] 与代币列表。
final tokenCatalogProvider = Provider<TokenCatalog>((ref) {
  final remote = ref.watch(remoteTokensProvider).tokens;
  final custom = ref.watch(customTokensProvider);
  return TokenCatalog.merge(chains: SupportedChains.all, remote: remote, custom: custom);
});

/// 剔除用户隐藏项后的可展示资产；首页与接收页共用，不要在 UI 里各自过滤。
///
/// 参数是 chainId 而非 [Chain]：family 的键要参与 `==`，字符串比对象稳定。
/// 传 null 表示全部链。管理页要看到被隐藏的项，故它直接读 [tokenCatalogProvider]。
final visibleAssetsProvider = Provider.family<List<ListedAsset>, String?>((ref, chainId) {
  final catalog = ref.watch(tokenCatalogProvider);
  final hidden = ref.watch(hiddenAssetsProvider);
  final chain = chainId == null ? null : SupportedChains.byId(chainId);
  return [
    for (final asset in ListedAsset.fromCatalog(catalog, chain: chain))
      if (!hidden.contains(asset.key)) asset,
  ];
});
