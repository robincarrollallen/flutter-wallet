import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../blockchain/token.dart';
import 'rest_client.dart';

/// 远程代币目录：只负责发请求与解析 JSON，不做缓存、不做回退决策。
///
/// **失败约定**：吞掉异常并返回空列表，由上层的 RemoteTokensNotifier 据此保住旧缓存 / 打包目录。
/// 与 [CoinGeckoApi] 相同——空即失败。
///
/// 测试网合约没有公开的通用 token list。未配置 [catalogUrl] 时立刻返回空列表、不发请求，
/// 避免 15s 超时。接入真实 JSON 用 `--dart-define=TOKEN_CATALOG_URL=https://...`。
class TokenCatalogApi {
  const TokenCatalogApi({this.catalogUrl = defaultCatalogUrl});

  /// `--dart-define=TOKEN_CATALOG_URL=` 注入；默认空字符串 = 未配置远端。
  static const defaultCatalogUrl = String.fromEnvironment('TOKEN_CATALOG_URL');

  final String catalogUrl;

  /// JSON 顶层可以是代币数组，或 `{ "tokens": [ ... ] }`，字段见 [Token.toJson]。
  Future<List<Token>> fetchCatalog() async {
    if (catalogUrl.isEmpty) return const [];
    try {
      final body = await getText(Uri.parse(catalogUrl));
      return Token.listFromJson(jsonDecode(body));
    } catch (e) {
      debugPrint('⚠️ fetchTokenCatalog failed: $e');
      return const [];
    }
  }
}
