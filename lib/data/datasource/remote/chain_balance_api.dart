import 'dart:io';

import '../../../blockchain/chain_registry.dart';
import '../../../blockchain/token.dart';
import '../../../core/utils/erc20_abi.dart';
import '../../../core/utils/evm_hex.dart';
import 'http_config.dart';
import 'json_rpc.dart';
import 'rest_client.dart';

/// 各链原生币余额的远程查询：按 [ChainKind] 分发到对应协议。
///
/// 只返回**原始最小单位**的 [BigInt]（wei / lamport / sun / octa / satoshi），
/// 不做小数换算、不构造领域对象——那是 repository 的职责。
class ChainBalanceApi {
  const ChainBalanceApi();

  /// 查询某条链上某地址的原生币余额（原始最小单位）。
  Future<BigInt> fetchNativeBalance(Chain chain, String address) async {
    return switch (chain.kind) {
      ChainKind.evm || ChainKind.solana || ChainKind.sui => await _rpcNativeBalance(chain, address),
      ChainKind.bitcoin => await _bitcoinBalance(chain, address),
      // Tron / Aptos 原生币余额查询（代币查询见 [fetchTokenBalances]）。
      ChainKind.tron => await _tronBalance(chain, address),
      ChainKind.aptos => await _aptosBalance(chain, address),
    };
  }

  /// 该代币标准是否已接入余额查询。
  ///
  /// 调用方据此**提前过滤**，而不是先发请求再接 [UnimplementedError]——
  /// 未接入的标准（SPL / TRC-20 / Sui / Aptos）目前仍按 0 展示，
  /// 与接入前的行为一致，不给用户凭空多出一堆「取数失败」。
  static bool supportsTokenBalance(TokenStandard standard) => standard == TokenStandard.erc20;

  /// 查询单个代币余额（原始最小单位）。
  ///
  /// 只是 [fetchTokenBalances] 的单元素封装——分发逻辑保持一份实现。
  Future<BigInt> fetchTokenBalance(Chain chain, Token token, String address) async {
    final balances = await fetchTokenBalances(chain, [token], address);
    return balances[token.identifier] ?? BigInt.zero;
  }

  /// 同链多代币批量查询，返回 `token.identifier -> 原始最小单位余额`。
  ///
  /// 合并成一次请求而非逐个查：一条链上十几个代币逐条发就是十几次握手，
  /// 首页要同时刷六条 EVM 链，累加起来的等待非常可观。
  ///
  /// [tokens] 必须都属于 [chain] 且标准一致；混入未接入的标准会抛
  /// [UnimplementedError]，请先用 [supportsTokenBalance] 过滤。
  ///
  /// 后续接入其余标准时的落点：
  /// - SPL：`getTokenAccountsByOwner`（owner + mint 过滤），或对已知 ATA 用
  ///   `getTokenAccountBalance`；Solana JSON-RPC 同样支持批量数组。
  /// - TRC-20：`wallet/triggerconstantcontract`，函数签名 `balanceOf(address)`，
  ///   REST 无批量，只能逐个发。
  /// - Sui / Aptos：现成的原生币查询把币种写死了（`0x2::sui::SUI` /
  ///   `0x1::aptos_coin::AptosCoin`），换成 `token.identifier` 即可，成本极低。
  Future<Map<String, BigInt>> fetchTokenBalances(Chain chain, List<Token> tokens, String address) async {
    if (tokens.isEmpty) return const {};

    final unsupported = tokens.where((t) => !supportsTokenBalance(t.standard)).firstOrNull;
    if (unsupported != null) {
      throw UnimplementedError('${unsupported.standard.name} 代币余额查询暂未接入（${unsupported.symbol}）');
    }

    return _erc20Balances(chain, tokens, address);
  }

  /// ERC-20：一次批量 `eth_call`，每条都是对代币合约调 `balanceOf(owner)`。
  ///
  /// 无持仓地址返回的是编码好的 0，属业务真实的 0；而空返回（`0x`）由
  /// [decodeUint256] 抛错——那说明目标地址上没有合约，不是「余额为 0」。
  Future<Map<String, BigInt>> _erc20Balances(Chain chain, List<Token> tokens, String address) async {
    final data = encodeBalanceOf(address); // 同一个 owner，calldata 全批复用
    final results = await jsonRpcBatch(chain.endpoint, [
      for (final token in tokens)
        (
          method: EvmRpcMethod.call.wireName,
          params: [
            {'to': token.identifier, 'data': data},
            'latest',
          ],
        ),
    ]);

    return {
      for (var i = 0; i < tokens.length; i++) tokens[i].identifier: decodeUint256(results[i] as String? ?? ''),
    };
  }

  /// JSON-RPC 链（EVM/Solana/Sui）的原生币余额查询。
  Future<BigInt> _rpcNativeBalance(Chain chain, String address) async {
    final method = chain.nativeBalanceRpcMethod;
    if (method == null) {
      throw StateError('${chain.name} 未配置 nativeBalanceRpcMethod');
    }
    return switch (method) {
      RpcMethod.ethGetBalance => () async {
        final result = await jsonRpcCall(chain.endpoint, method.wireName, [address, 'latest']);
        return parseEvmHexQuantity(result as String);
      }(),
      RpcMethod.solGetBalance => () async {
        final result = await jsonRpcCall(chain.endpoint, method.wireName, [address]);
        return BigInt.from(((result as Map)['value'] as num?) ?? 0);
      }(),
      // 无币地址 suix_getBalance 会正常返回 totalBalance:"0"，不需要兜底 catch：
      // 下面的 null 判断已覆盖响应缺字段的情况，再包一层只会把 RPC 故障伪装成「余额 0」。
      RpcMethod.suiGetBalance => () async {
        final result = await jsonRpcCall(chain.endpoint, method.wireName, [address, '0x2::sui::SUI']);
        final total = (result as Map)['totalBalance'] as String?;
        return total == null ? BigInt.zero : BigInt.parse(total);
      }(),
    };
  }

  /// Bitcoin：浏览器 API 返回已收到/已花费的聪，差值即余额。
  Future<BigInt> _bitcoinBalance(Chain chain, String address) async {
    final uri = Uri.parse('${chain.endpoint}/address/$address');
    final json = await getJson(uri);
    final stats = json['chain_stats'] as Map<String, dynamic>? ?? const {};
    final funded = (stats['funded_txo_sum'] as num?)?.toInt() ?? 0;
    final spent = (stats['spent_txo_sum'] as num?)?.toInt() ?? 0;
    return BigInt.from(funded - spent);
  }

  /// Tron：REST POST wallet/getaccount，返回 balance（单位 sun，1e6）。
  ///
  /// 未激活账户返回 {}（无 balance 字段）——这是**业务上真实的 0**，由下面的 `?? 0`
  /// 覆盖，不需要 catch。反过来说，能抛出来的都是传输故障，必须原样上抛：
  /// 把它伪装成「余额 0」会让用户的总资产凭空缩水且毫无提示。
  Future<BigInt> _tronBalance(Chain chain, String address) async {
    final json = await postJson('${chain.endpoint}/wallet/getaccount', {
      'address': address,
      'visible': true, // 传入的是 base58（T...）地址
    });
    return BigInt.from((json['balance'] as num?)?.toInt() ?? 0);
  }

  /// Aptos：REST GET .../balance/0x1::aptos_coin::AptosCoin，响应体为标量数字
  /// （单位 octa，1e8）。
  Future<BigInt> _aptosBalance(Chain chain, String address) async {
    final uri = Uri.parse('${chain.endpoint}/v1/accounts/$address/balance/0x1::aptos_coin::AptosCoin');
    try {
      return BigInt.parse((await getText(uri)).trim().replaceAll('"', ''));
    } on HttpStatusException catch (e) {
      // 账户从未上链时 Aptos 返回 404 —— 这是「确实没有这个账户 = 余额 0」，属业务空值。
      // 其余状态码（429 限流 / 5xx）一律上抛，交给上层显示为「取数失败」而非 0。
      if (e.statusCode == HttpStatus.notFound) return BigInt.zero;
      rethrow;
    }
  }
}
