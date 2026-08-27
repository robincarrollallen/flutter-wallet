import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../blockchain/chain_registry.dart';
import '../blockchain/bundled_token_catalog.dart';
import '../blockchain/token.dart';
import '../blockchain/token_catalog.dart';
import 'modules/custom_tokens_provider.dart';
import 'token_repository_provider.dart';

export 'modules/custom_tokens_provider.dart';
export 'token_repository_provider.dart';

/// 远程目录（缓存 / HTTP / 打包回退）。keepAlive 避免离开页面就丢掉已拉到的列表。
final remoteTokensProvider = FutureProvider<List<Token>>((ref) async {
  ref.keepAlive();
  return ref.watch(tokenRepositoryProvider).getCatalog();
});

/// 当前可展示的代币目录：远程 ∪ 自定义。
///
/// 远程还在 loading 时用 [BundledTokenCatalog] 占位，避免接收页先闪一轮「只有原生币」。
/// 页面只 watch 这一份，不要自己拼 [SupportedChains] 与代币列表。
final tokenCatalogProvider = Provider<TokenCatalog>((ref) {
  final remote = ref.watch(remoteTokensProvider).value ?? BundledTokenCatalog.all;
  final custom = ref.watch(customTokensProvider);
  return TokenCatalog.merge(chains: SupportedChains.all, remote: remote, custom: custom);
});
