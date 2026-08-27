import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../blockchain/bundled_token_catalog.dart';
import '../data/datasource/local/token_catalog_cache.dart';
import '../data/datasource/remote/token_catalog_api.dart';
import '../data/repository/token_repository.dart';
import 'prefs_provider.dart';

/// 组装 [TokenRepository]：prefs 来自 [sharedPrefsProvider]。
final tokenRepositoryProvider = Provider<TokenRepository>((ref) {
  final prefs = ref.watch(sharedPrefsProvider);
  return TokenRepository(
    api: const TokenCatalogApi(),
    cache: TokenCatalogCache(prefs),
    bundled: BundledTokenCatalog.all,
  );
});
