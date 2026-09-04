import 'dart:io';

import 'package:blockchain_utils/blockchain_utils.dart';

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
      // 比特币的余额是 UTXO 集合的投影，不是一个能在这里返回的标量——见 [BitcoinUtxoApi]
      // 与 [BalanceRepository.getBitcoinBalance]。留一条死分支比抛异常危险：两条并行的
      // BTC 余额路径，后来者不知道该信哪个。
      ChainKind.bitcoin => throw UnsupportedError('BTC 余额走 UTXO 路径，见 BitcoinUtxoApi'),
      // Tron / Aptos 原生币余额查询（代币查询见 [fetchTokenBalances]）。
      ChainKind.tron => await _tronBalance(chain, address),
      ChainKind.aptos => await _aptosAssetBalance(chain, address, _aptosNativeCoinType),
    };
  }

  /// 该链的代币采用哪种标准。比特币没有代币模型，返回 null。
  ///
  /// 一条链的代币标准是唯一的，把这层对应关系写在一处，
  /// 分发与校验就都有据可依，不必在每个调用点各判一遍。
  static TokenStandard? tokenStandardOf(ChainKind kind) => switch (kind) {
    ChainKind.evm => TokenStandard.erc20,
    ChainKind.solana => TokenStandard.spl,
    ChainKind.tron => TokenStandard.trc20,
    ChainKind.sui => TokenStandard.suiCoin,
    ChainKind.aptos => TokenStandard.aptosCoin,
    ChainKind.bitcoin => null,
  };

  /// [chain] 上能不能按 [standard] 查代币余额。
  ///
  /// 调用方据此**提前过滤**，而不是先发请求再接错误。它同时挡住目录脏数据：
  /// 一条 standard 与所属链对不上的代币混进批量请求，会让整条链的余额一起失败。
  static bool supportsTokenBalance(Chain chain, TokenStandard standard) =>
      tokenStandardOf(chain.kind) == standard;

  /// 查询单个代币余额（原始最小单位）。
  ///
  /// 只是 [fetchTokenBalances] 的单元素封装——分发逻辑保持一份实现。
  Future<BigInt> fetchTokenBalance(Chain chain, Token token, String address) async {
    final balances = await fetchTokenBalances(chain, [token], address);
    return balances[token.identifier] ?? BigInt.zero;
  }

  /// 同链多代币查询，返回 `token.identifier -> 原始最小单位余额`。
  ///
  /// 能批量的批量，不能批量的并发：EVM / Solana / Sui 是 JSON-RPC，多个代币交给
  /// [_rpcMany] 合成一次请求（节点不支持批量时自动退回并发单条）；
  /// Aptos / Tron 只有 REST、没有批量信封，用 [Future.wait] 并发。
  /// 无论哪种，一条链上的代币都只花一轮往返的时间——逐个串行查，
  /// 首页十来条链累加起来的等待非常可观。
  ///
  /// [tokens] 必须都属于 [chain] 且标准一致（同一条链本来就只有一种标准），
  /// 否则抛 [ArgumentError]；请先用 [supportsTokenBalance] 过滤。
  Future<Map<String, BigInt>> fetchTokenBalances(Chain chain, List<Token> tokens, String address) async {
    if (tokens.isEmpty) return const {};

    final mismatched = tokens.where((t) => !supportsTokenBalance(chain, t.standard)).firstOrNull;
    if (mismatched != null) {
      throw ArgumentError.value(
        mismatched.standard.name,
        'tokens',
        '${mismatched.symbol} 的标准与 ${chain.name} 不匹配（该链应为 ${tokenStandardOf(chain.kind)?.name ?? '无代币'}）',
      );
    }

    // 穷尽 switch：将来新增代币标准会在这里直接编译报错，比运行时才发现好。
    return switch (tokens.first.standard) {
      TokenStandard.erc20 => _erc20Balances(chain, tokens, address),
      TokenStandard.spl => _splBalances(chain, tokens, address),
      TokenStandard.suiCoin => _suiCoinBalances(chain, tokens, address),
      TokenStandard.aptosCoin => _aptosCoinBalances(chain, tokens, address),
      TokenStandard.trc20 => _trc20Balances(chain, tokens, address),
    };
  }

  /// 对同一条链发多条 JSON-RPC，返回顺序与 [calls] 一致。
  ///
  /// 节点支持批量就合成一个请求体（一次往返）；不支持的（见 [Chain.supportsRpcBatch]）
  /// 退回并发发单条——**并发不是串行**，耗时仍是一轮往返，只是多占几条连接。
  /// [Future.wait] 与 [jsonRpcBatch] 的失败语义一致：一条失败即整批失败，
  /// 不会出现「部分代币静默为 0」。
  Future<List<Object?>> _rpcMany(Chain chain, List<JsonRpcRequest> calls) {
    if (chain.supportsRpcBatch) return jsonRpcBatch(chain.endpoint, calls);
    return Future.wait([for (final call in calls) jsonRpcCall(chain.endpoint, call.method, call.params)]);
  }

  /// ERC-20：一次批量 `eth_call`，每条都是对代币合约调 `balanceOf(owner)`。
  ///
  /// 无持仓地址返回的是编码好的 0，属业务真实的 0；而空返回（`0x`）由
  /// [decodeUint256] 抛错——那说明目标地址上没有合约，不是「余额为 0」。
  Future<Map<String, BigInt>> _erc20Balances(Chain chain, List<Token> tokens, String address) async {
    final data = encodeBalanceOf(address); // 同一个 owner，calldata 全批复用
    final results = await _rpcMany(chain, [
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

  /// SPL：每个代币一条 `getTokenAccountsByOwner`，按 mint 过滤，交给 [_rpcMany] 合并。
  ///
  /// 按 mint 查而不是一次拉 owner 名下全部代币账户：前者对 Token-2022 一样有效
  /// （不必按 programId 各发一次），返回的也正好是目录里要的那些代币。
  ///
  /// 同一个 mint 下 owner 可以有**多个**代币账户（ATA 之外还能手动开），
  /// 所以要把 `value` 里各账户的数量加起来，只取第一个会漏报持仓。
  /// `value` 为空数组表示压根没开过代币账户，是业务上真实的 0。
  Future<Map<String, BigInt>> _splBalances(Chain chain, List<Token> tokens, String address) async {
    final results = await _rpcMany(chain, [
      for (final token in tokens)
        (
          method: TokenRpcMethod.splGetTokenAccountsByOwner.wireName,
          params: [
            address,
            {'mint': token.identifier},
            {'encoding': 'jsonParsed'},
          ],
        ),
    ]);

    return {for (var i = 0; i < tokens.length; i++) tokens[i].identifier: _sumSplAccounts(results[i])};
  }

  /// 把 `getTokenAccountsByOwner` 的 `value` 数组里各代币账户的数量求和。
  BigInt _sumSplAccounts(Object? result) {
    final accounts = (result as Map?)?['value'] as List? ?? const [];
    var total = BigInt.zero;
    for (final account in accounts) {
      // account.data.parsed.info.tokenAmount.amount —— 字符串形式的最小单位数量。
      final info = (((account as Map)['account'] as Map?)?['data'] as Map?)?['parsed'] as Map?;
      final amount = ((info?['info'] as Map?)?['tokenAmount'] as Map?)?['amount'];
      if (amount is String) total += BigInt.parse(amount);
    }
    return total;
  }

  /// Sui：每个代币一条 `suix_getBalance`，带上各自的 coin type。
  ///
  /// 与原生币是同一个方法，区别只在第二个参数——原生币传 `0x2::sui::SUI`。
  /// 注意 Sui 测试网的公共节点不接受批量请求，[_rpcMany] 会替它退回并发单条。
  Future<Map<String, BigInt>> _suiCoinBalances(Chain chain, List<Token> tokens, String address) async {
    final results = await _rpcMany(chain, [
      for (final token in tokens) (method: RpcMethod.suiGetBalance.wireName, params: [address, token.identifier]),
    ]);

    return {for (var i = 0; i < tokens.length; i++) tokens[i].identifier: _parseSuiTotalBalance(results[i])};
  }

  /// Aptos：REST 没有批量信封，只能每个代币一条请求，并发发出。
  ///
  /// 端点与原生币完全相同，只是把写死的 `0x1::aptos_coin::AptosCoin` 换成
  /// 代币自己的资产类型——它**同时接受 coin type 结构与 FA metadata 地址**，
  /// 目录里两种写法都能直接查，不必特判。
  ///
  /// [Future.wait] 默认不 eagerError，但会在全部完成后重抛第一个错误——正合口径：
  /// 一条失败即整链失败，不会出现「部分代币静默为 0」。
  Future<Map<String, BigInt>> _aptosCoinBalances(Chain chain, List<Token> tokens, String address) async {
    final balances = await Future.wait([
      for (final token in tokens) _aptosAssetBalance(chain, address, token.identifier),
    ]);

    return {for (var i = 0; i < tokens.length; i++) tokens[i].identifier: balances[i]};
  }

  /// TRC-20：REST 同样没有批量，每个代币一条 `triggerconstantcontract`，并发发出。
  ///
  /// 这是一次**只读**的合约调用（不上链、不花能量），语义等同 EVM 的 `eth_call`；
  /// 返回体里的 `constant_result[0]` 就是 ABI 编码的 uint256，
  /// 可以直接交给 [decodeUint256]。
  Future<Map<String, BigInt>> _trc20Balances(Chain chain, List<Token> tokens, String address) async {
    // T 开头的 base58 地址先解成 20 字节，再补成 32 字节的 ABI 参数。
    final parameter = encodeAddressArgument(TrxAddrDecoder().decodeAddr(address));
    final balances = await Future.wait([
      for (final token in tokens) _trc20Balance(chain, token.identifier, address, parameter),
    ]);

    return {for (var i = 0; i < tokens.length; i++) tokens[i].identifier: balances[i]};
  }

  /// 单个 TRC-20 合约的 `balanceOf` 只读调用。
  ///
  /// 未激活账户 / 无持仓返回的是编码好的 0，属业务真实的 0；
  /// 而 `result.result` 为假（合约不存在、参数不对）说明这次调用根本没执行成功，
  /// 必须抛出——按 0 展示等于谎报「你没有这个币」。
  Future<BigInt> _trc20Balance(Chain chain, String contract, String owner, String parameter) async {
    final json = await postJson('${chain.endpoint}/wallet/triggerconstantcontract', {
      'owner_address': owner,
      'contract_address': contract,
      'function_selector': 'balanceOf(address)',
      'parameter': parameter,
      'visible': true, // owner_address / contract_address 传的都是 base58（T...）
    });

    if ((json['result'] as Map?)?['result'] != true) {
      throw Exception('Tron constant call failed [$contract]: ${previewBody(json.toString())}');
    }
    final constantResult = json['constant_result'] as List?;
    if (constantResult == null || constantResult.isEmpty) {
      throw Exception('Tron constant call empty result [$contract]');
    }
    return decodeUint256(constantResult.first as String);
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
      // 与代币走同一个方法，只是币种参数写死成原生 SUI——见 [_suiCoinBalances]。
      RpcMethod.suiGetBalance => () async {
        final result = await jsonRpcCall(chain.endpoint, method.wireName, [address, _suiNativeCoinType]);
        return _parseSuiTotalBalance(result);
      }(),
    };
  }

  /// 解析 `suix_getBalance` 的 `totalBalance`（字符串形式的最小单位）。
  ///
  /// 无币地址会正常返回 `totalBalance: "0"`，不需要兜底 catch：下面的 null 判断
  /// 已覆盖响应缺字段的情况，再包一层只会把 RPC 故障伪装成「余额 0」。
  BigInt _parseSuiTotalBalance(Object? result) {
    final total = (result as Map?)?['totalBalance'] as String?;
    return total == null ? BigInt.zero : BigInt.parse(total);
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

  /// Aptos：REST GET .../balance/{assetType}，响应体为标量数字。
  ///
  /// [assetType] 既可以是 coin type 结构（如原生币的 `0x1::aptos_coin::AptosCoin`，
  /// 单位 octa，1e8），也可以是 Fungible Asset 的 metadata 地址——
  /// 端点两种都认，所以原生币与代币共用这一个实现。
  Future<BigInt> _aptosAssetBalance(Chain chain, String address, String assetType) async {
    final uri = Uri.parse('${chain.endpoint}/v1/accounts/$address/balance/$assetType');
    try {
      return BigInt.parse((await getText(uri)).trim().replaceAll('"', ''));
    } on HttpStatusException catch (e) {
      // 账户从未上链、或没开过这个资产的 store 时 Aptos 返回 404 ——
      // 这是「确实没有 = 余额 0」，属业务空值。
      // 其余状态码（429 限流 / 5xx）一律上抛，交给上层显示为「取数失败」而非 0。
      if (e.statusCode == HttpStatus.notFound) return BigInt.zero;
      rethrow;
    }
  }
}

/// 两条链原生币的资产类型。代币走 [Token.identifier]，只有原生币需要写死。
const _suiNativeCoinType = '0x2::sui::SUI';
const _aptosNativeCoinType = '0x1::aptos_coin::AptosCoin';
