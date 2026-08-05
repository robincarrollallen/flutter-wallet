import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../core/blockchain/chain_registry.dart';
import '../../../core/blockchain/units.dart';
import '../../../core/constants/currency_symbols.dart';
import '../../../core/utils/evm_hex.dart';
import '../../../core/utils/json_rpc.dart';
import 'dto/send_tx_request.dart';
import 'evm_transaction_service.dart';
import '../domain/account_balance.dart';
import '../domain/wallet.dart';
import '../services/wallet_key_service.dart';

/// 业务/接口层：按链类型查询真实余额，并提供实时行情。
/// 余额均走各链**测试网**公共节点 / 浏览器 API；单价走 CoinGecko 主网行情。
class WalletService {
  const WalletService({this.keyService});

  /// 签名私钥解析器；发送转账必需，仅查余额/行情的场景可不注入。
  final WalletKeyService? keyService;

  /// 查询某条链上某地址的原生币余额（不含单价，单价由上层 priceProvider 注入）。
  Future<AccountBalance> fetchBalance(Chain chain, String address) async {
    final raw = switch (chain.kind) {
      ChainKind.evm ||
      ChainKind.solana ||
      ChainKind.sui => await _rpcNativeBalance(chain, address),
      ChainKind.bitcoin => await _bitcoinBalance(chain, address),
      // Tron / Aptos 原生币余额查询（代币查询另见 tokens，暂未接入）。
      ChainKind.tron => await _tronBalance(chain, address),
      ChainKind.aptos => await _aptosBalance(chain, address),
    };
    return AccountBalance(
      address: address,
      amount: formatUnits(raw, chain.decimals),
      symbol: chain.symbol,
    );
  }

  /// 批量查询多个 CoinGecko 币种的行情：coinGeckoId -> (单价, 图标 URL)。
  /// 一次 coins/markets 请求同时取回价格与图标，替代旧的 simple/price。
  ///
  /// [vsCurrency] 为计价法币代码（大小写不限，如 'USD' / 'CNY'），
  /// 由接口原生按该币种返回价格，不做本地汇率换算；
  /// 传入接口不支持的币种会拿到空数组，等同一次失败。
  Future<Map<String, ({double price, String? logoUrl})>> fetchMarkets(
    Iterable<String> coinGeckoIds, {
    String vsCurrency = defaultCurrencyCode,
  }) async {
    final ids = coinGeckoIds.toSet().join(',');
    final uri = Uri.parse(
      'https://api.coingecko.com/api/v3/coins/markets'
      '?vs_currency=${vsCurrency.toLowerCase()}&ids=$ids',
    );
    try {
      final list = await _getJsonArray(uri);
      return {
        for (final item in list.whereType<Map>())
          item['id'] as String: (
            price: (item['current_price'] as num?)?.toDouble() ?? 0,
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

  /// 发起转账：按链类型分发。EVM 已接入真实签名广播；其余链暂未支持。
  /// [wallet] 用于解析签名私钥（私钥明文仅在本次调用内使用）。
  /// 返回 (交易哈希, 实际发送金额)——gas 不足自动扣费时实际金额会小于入参。
  Future<({String hash, String sentAmount})> sendTransaction(
    SendTxRequest request,
    Wallet wallet,
  ) async {
    final chainId = request.chainId;
    if (chainId == null) {
      throw ArgumentError('sendTransaction 缺少 chainId');
    }
    final chain = SupportedChains.byId(chainId);
    switch (chain.kind) {
      case ChainKind.evm:
        final keys = keyService;
        if (keys == null) {
          throw StateError('WalletService 未注入 WalletKeyService，无法签名');
        }
        final privateKey = await keys.resolveEvmSigningKey(wallet);
        return const EvmTransactionService().sendNative(
          chain: chain,
          privateKeyHex: privateKey,
          to: request.to,
          amount: request.amount,
        );
      case ChainKind.bitcoin:
      case ChainKind.solana:
      case ChainKind.tron:
      case ChainKind.sui:
      case ChainKind.aptos:
        throw UnsupportedError('${chain.name} 转账暂未支持');
    }
  }

  // —— 各链余额查询 —— //

  /// JSON-RPC 链（EVM/Solana/Sui）的原生币余额查询。
  Future<BigInt> _rpcNativeBalance(Chain chain, String address) async {
    final method = chain.nativeBalanceRpcMethod;
    if (method == null) {
      throw StateError('${chain.name} 未配置 nativeBalanceRpcMethod');
    }
    return switch (method) {
      RpcMethod.ethGetBalance => () async {
        final result = await jsonRpcCall(chain.endpoint, method.wireName, [
          address,
          'latest',
        ]);
        return parseEvmHexQuantity(result as String);
      }(),
      RpcMethod.solGetBalance => () async {
        final result = await jsonRpcCall(chain.endpoint, method.wireName, [
          address,
        ]);
        return BigInt.from(((result as Map)['value'] as num?) ?? 0);
      }(),
      RpcMethod.suiGetBalance => () async {
        try {
          final result = await jsonRpcCall(chain.endpoint, method.wireName, [
            address,
            '0x2::sui::SUI',
          ]);
          final total = (result as Map)['totalBalance'] as String?;
          return total == null ? BigInt.zero : BigInt.parse(total);
        } catch (_) {
          return BigInt.zero;
        }
      }(),
    };
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

  /// 纯 REST POST（非 JSON-RPC 信封），返回解码后的 JSON 对象。供 Tron 使用。
  Future<Map<String, dynamic>> _postJson(
    String url,
    Map<String, Object?> body,
  ) async {
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
}
