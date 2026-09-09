import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/datasource/remote/token_catalog_api.dart';

/// 远程代币目录数据源。单独成 provider 是为了让测试能整体替身——
/// 落盘缓存、TTL 与失败回退都由 [RemoteTokensNotifier] 承担，中间不再有 repository 层。
final tokenCatalogApiProvider = Provider<TokenCatalogApi>((ref) => const TokenCatalogApi());
