import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'dto/send_tx_request.dart';
import '../domain/account_balance.dart';
import '../domain/chain.dart';

/// 业务/接口层：按链类型查询真实余额，并提供实时行情。
/// 余额均走各链**测试网**公共节点 / 浏览器 API；单价走 CoinGecko 主网行情。
class WalletService {
  const WalletService();

  /// 查询某条链上某地址的原生币余额（不含单价，单价由上层 priceProvider 注入）。
  Future<AccountBalance> fetchBalance(Chain chain, String address) async {
    final raw = switch (chain.kind) {
      ChainKind.evm => await _evmBalance(chain, address),
      ChainKind.solana => await _solanaBalance(chain, address),
      ChainKind.bitcoin => await _bitcoinBalance(chain, address),
      // Tron / Sui / Aptos 原生币余额查询（代币查询另见 tokens，暂未接入）。
      ChainKind.tron => await _tronBalance(chain, address),
      ChainKind.sui => await _suiBalance(chain, address),
      ChainKind.aptos => await _aptosBalance(chain, address),
    };
    return AccountBalance(
      address: address,
      amount: _formatUnits(raw, chain.decimals),
      symbol: chain.symbol,
    );
  }

  /// 批量查询多个 CoinGecko 币种的行情：coinGeckoId -> (美元单价, 图标 URL)。
  /// 一次 coins/markets 请求同时取回价格与图标，替代旧的 simple/price。
  Future<Map<String, ({double usd, String? logoUrl})>> fetchMarkets(
    Iterable<String> coinGeckoIds,
  ) async {
    final ids = coinGeckoIds.toSet().join(',');
    final uri = Uri.parse(
      'https://api.coingecko.com/api/v3/coins/markets?vs_currency=usd&ids=$ids',
    );
    try {
      final list = await _getJsonArray(uri);
      return {
        for (final item in list.whereType<Map>())
          item['id'] as String: (
            usd: (item['current_price'] as num?)?.toDouble() ?? 0,
            logoUrl: item['image'] as String?,
          ),
      };
    } catch (e) {
      // 上层只能从空 map 得知「失败了」，得不到原因（限流 429 / 证书 / 解析错误），
      // 这行是唯一的线索来源。
      debugPrint('⚠️ fetchMarkets failed: $e');
      return const {};
    }
  }

  /// 拉取指定链平台的图标：platformId -> 图标 URL。
  ///
  /// 与 [fetchMarkets] 的币图标不同：Base / Arbitrum 这类链虽然都按 ETH 计价，
  /// 在这里各有自己的 logo，地址列表才能把它们区分开。
  ///
  /// 该接口不支持按 id 过滤，461 个平台的整包响应（约 184 KB）省不掉；
  /// [platformIds] 只用于裁剪返回值，免得 400 多个用不上的平台一路带进缓存、
  /// 拖累每次冷启动的 SharedPreferences 读取。
  /// 返回空 map 即代表失败，交由上层回退旧缓存（与 [fetchMarkets] 约定一致）。
  Future<Map<String, String>> fetchChainIcons(
    Iterable<String> platformIds,
  ) async {
    final wanted = platformIds.toSet();
    final uri = Uri.parse('https://api.coingecko.com/api/v3/asset_platforms');
    try {
      final list = await _getJsonArray(uri);
      return {
        for (final item in list.whereType<Map>())
          if (item['id'] is String && wanted.contains(item['id']))
            if (item['image'] is Map &&
                (item['image'] as Map)['large'] is String)
              item['id'] as String: (item['image'] as Map)['large'] as String,
      };
    } catch (e) {
      debugPrint('⚠️ fetchChainIcons failed: $e');
      return const {};
    }
  }

  /// 发起转账：占位实现（签名/广播尚未接入）。
  Future<String> sendTransaction(SendTxRequest request) async {
    final body = request.toJson();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return '0xMockTxHashFor_${body['to']}';
  }

  // —— 各链余额查询 —— //

  /// EVM：eth_getBalance 返回十六进制 wei。
  Future<BigInt> _evmBalance(Chain chain, String address) async {
    final result =
        await _rpcCall(chain.endpoint, 'eth_getBalance', [address, 'latest']);
    return _hexToBigInt(result as String);
  }

  /// Solana：getBalance 返回 lamports（result.value）。
  Future<BigInt> _solanaBalance(Chain chain, String address) async {
    final result = await _rpcCall(chain.endpoint, 'getBalance', [address]);
    final lamports = (result as Map)['value'] as num? ?? 0;
    return BigInt.from(lamports);
  }

  /// Bitcoin：浏览器 API 返回已收到/已花费的聪，差值即余额。
  Future<BigInt> _bitcoinBalance(Chain chain, String address) async {
    final uri = Uri.parse('${chain.endpoint}/address/$address');
    final json = await _getJson(uri);
    final stats = json['chain_stats'] as Map<String, dynamic>? ?? const {};
    final funded = (stats['funded_txo_sum'] as num?)?.toInt() ?? 0;
    final spent = (stats['spent_txo_sum'] as num?)?.toInt() ?? 0;
    return BigInt.from(funded - spent);
  }

  /// Tron：REST POST wallet/getaccount，返回 balance（单位 sun，1e6）。
  /// 未激活账户返回 {}（无 balance 字段）；查询失败均按 0 处理。
  Future<BigInt> _tronBalance(Chain chain, String address) async {
    try {
      final json = await _postJson('${chain.endpoint}/wallet/getaccount', {
        'address': address,
        'visible': true, // 传入的是 base58（T...）地址
      });
      return BigInt.from((json['balance'] as num?)?.toInt() ?? 0);
    } catch (_) {
      return BigInt.zero;
    }
  }

  /// Sui：JSON-RPC suix_getBalance，result.totalBalance 为字符串（单位 MIST，1e9）。
  /// 未激活账户返回 "0"；查询失败按 0 处理。
  Future<BigInt> _suiBalance(Chain chain, String address) async {
    try {
      final result = await _rpcCall(
        chain.endpoint,
        'suix_getBalance',
        [address, '0x2::sui::SUI'],
      );
      final total = (result as Map)['totalBalance'] as String?;
      return total == null ? BigInt.zero : BigInt.parse(total);
    } catch (_) {
      return BigInt.zero;
    }
  }

  /// Aptos：REST GET .../balance/0x1::aptos_coin::AptosCoin，响应体为标量数字
  /// （单位 octa，1e8）。账户不存在时返回 404，按 0 处理。
  Future<BigInt> _aptosBalance(Chain chain, String address) async {
    try {
      final uri = Uri.parse(
        '${chain.endpoint}/v1/accounts/$address/balance/0x1::aptos_coin::AptosCoin',
      );
      final body = await _getText(uri); // 404 时抛异常，下方 catch 归零
      return BigInt.parse(body.trim().replaceAll('"', ''));
    } catch (_) {
      return BigInt.zero;
    }
  }

  // —— 网络工具 —— //

  Future<Object?> _rpcCall(
      String url, String method, List<Object?> params) async {
    final client = HttpClient();
    try {
      final request = await client.postUrl(Uri.parse(url));
      request.headers.contentType = ContentType.json;
      request.add(utf8.encode(jsonEncode({
        'jsonrpc': '2.0',
        'id': 1,
        'method': method,
        'params': params,
      })));
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      if (json['error'] != null) {
        throw Exception('RPC error: ${json['error']}');
      }
      return json['result'];
    } finally {
      client.close();
    }
  }

  /// 纯 REST POST（非 JSON-RPC 信封），返回解码后的 JSON 对象。供 Tron 使用。
  Future<Map<String, dynamic>> _postJson(String url, Map<String, Object?> body) async {
    final client = HttpClient();
    try {
      final request = await client.postUrl(Uri.parse(url));
      request.headers.contentType = ContentType.json;
      request.add(utf8.encode(jsonEncode(body)));
      final response = await request.close();
      final text = await response.transform(utf8.decoder).join();
      return jsonDecode(text) as Map<String, dynamic>;
    } finally {
      client.close();
    }
  }

  /// GET 返回原始文本；非 200 抛异常。供 Aptos 标量余额接口使用。
  Future<String> _getText(Uri uri) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(uri);
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode != 200) {
        throw HttpException('HTTP ${response.statusCode}: $body');
      }
      return body;
    } finally {
      client.close();
    }
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(uri);
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      return jsonDecode(body) as Map<String, dynamic>;
    } finally {
      client.close();
    }
  }

  Future<List<dynamic>> _getJsonArray(Uri uri) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(uri);
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode != 200) {
        throw HttpException('HTTP ${response.statusCode}: $body');
      }
      return jsonDecode(body) as List<dynamic>;
    } finally {
      client.close();
    }
  }

  BigInt _hexToBigInt(String hex) {
    final clean = hex.startsWith('0x') ? hex.substring(2) : hex;
    if (clean.isEmpty) return BigInt.zero;
    return BigInt.parse(clean, radix: 16);
  }

  /// 将最小单位（大整数）按 decimals 转为可读金额字符串。
  String _formatUnits(BigInt value, int decimals) {
    if (decimals == 0) return value.toString();
    final divisor = BigInt.from(10).pow(decimals);
    final whole = value ~/ divisor;
    final fraction = value.remainder(divisor).toString().padLeft(decimals, '0');
    final trimmed = fraction.replaceFirst(RegExp(r'0+$'), '');
    return trimmed.isEmpty ? whole.toString() : '$whole.$trimmed';
  }
}
