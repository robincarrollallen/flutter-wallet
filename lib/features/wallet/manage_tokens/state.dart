import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../blockchain/listed_asset.dart';
import '../../../providers/token_catalog_provider.dart';

/// 管理页的资产列表：**全量**目录，含已被隐藏的项。
///
/// 刻意不用 `visibleAssetsProvider`——隐藏项在这里必须可见，否则用户没法开回来。
final manageTokenListProvider = Provider.autoDispose<List<ListedAsset>>((ref) {
  return ListedAsset.fromCatalog(ref.watch(tokenCatalogProvider));
});
