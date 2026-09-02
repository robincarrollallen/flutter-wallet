import 'dart:convert';
import 'dart:io';

import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallet/blockchain/bundled_token_catalog.dart';
import 'package:wallet/blockchain/chain_registry.dart';
import 'package:wallet/blockchain/token.dart';
import 'package:wallet/data/datasource/remote/chain_balance_api.dart';
import 'package:wallet/data/datasource/remote/http_config.dart';

/// 起一个本地服务替代真实链节点：REST 传输层是顶层函数、没有注入点，
/// 与其为测试重构传输层，不如直接给它一个真的 HTTP 对端——顺带把
/// rest_client 的状态码处理一起覆盖了。
Future<HttpServer> _serve(void Function(HttpRequest) handler) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen(handler);
  addTearDown(server.close);
  return server;
}

Chain _aptosAt(HttpServer s) => Chain(
  id: 'aptos-test',
  name: 'Aptos',
  symbol: 'APT',
  kind: ChainKind.aptos,
  coin: Bip44Coins.aptos,
  endpoint: 'http://${s.address.host}:${s.port}',
  coinGeckoId: 'aptos',
  decimals: 8,
);

Chain _tronAt(HttpServer s) => Chain(
  id: 'tron-test',
  name: 'Tron',
  symbol: 'TRX',
  kind: ChainKind.tron,
  coin: Bip44Coins.tron,
  endpoint: 'http://${s.address.host}:${s.port}',
  coinGeckoId: 'tron',
  decimals: 6,
);

Chain _evmAt(HttpServer s) => Chain(
  id: 'evm-test',
  name: 'EVM',
  symbol: 'ETH',
  kind: ChainKind.evm,
  coin: Bip44Coins.ethereum,
  endpoint: 'http://${s.address.host}:${s.port}',
  coinGeckoId: 'ethereum',
  decimals: 18,
  nativeBalanceRpcMethod: RpcMethod.ethGetBalance,
  evmChainId: 1337,
);

Chain _solanaAt(HttpServer s) => Chain(
  id: 'solana-test',
  name: 'Solana',
  symbol: 'SOL',
  kind: ChainKind.solana,
  coin: Bip44Coins.solana,
  endpoint: 'http://${s.address.host}:${s.port}',
  coinGeckoId: 'solana',
  decimals: 9,
  nativeBalanceRpcMethod: RpcMethod.solGetBalance,
);

Chain _suiAt(HttpServer s, {bool batch = true}) => Chain(
  supportsRpcBatch: batch,
  id: 'sui-test',
  name: 'Sui',
  symbol: 'SUI',
  kind: ChainKind.sui,
  coin: Bip44Coins.sui,
  endpoint: 'http://${s.address.host}:${s.port}',
  coinGeckoId: 'sui',
  decimals: 9,
  nativeBalanceRpcMethod: RpcMethod.suiGetBalance,
);

Token _token(String identifier, TokenStandard standard, {String symbol = 'USDC'}) => Token(
  chainId: 'ignored', // 分发只看 standard 与传入的 chain，chainId 在这一层用不到
  symbol: symbol,
  name: symbol,
  standard: standard,
  identifier: identifier,
  coinGeckoId: 'usd-coin',
  decimals: 6,
);

Token _erc20(String identifier, {String symbol = 'USDC'}) =>
    _token(identifier, TokenStandard.erc20, symbol: symbol);

/// 把整数编成 32 字节的 uint256 返回值。
String _uint256(int value) => '0x${value.toRadixString(16).padLeft(64, '0')}';

/// `getTokenAccountsByOwner` 返回体里的单个代币账户。
Map<String, Object?> _splAccount(String amount) => {
  'account': {
    'data': {
      'parsed': {
        'info': {
          'tokenAmount': {'amount': amount, 'decimals': 6},
        },
      },
    },
  },
};

/// 批量 JSON-RPC 的应答：每条按请求 id 回同一份 [result]。
void Function(HttpRequest) _rpcBatch(Object? Function(Map<String, dynamic> call) result) => (r) async {
  final batch = jsonDecode(await utf8.decodeStream(r)) as List<dynamic>;
  r.response
    ..write(
      jsonEncode([
        for (final call in batch)
          {'id': (call as Map)['id'], 'result': result(Map<String, dynamic>.from(call))},
      ]),
    )
    ..close();
};

void main() {
  const api = ChainBalanceApi();
  const owner = '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed';

  group('Aptos', () {
    test('404 = 账户不存在，按余额 0 处理', () async {
      final s = await _serve((r) => r.response
        ..statusCode = HttpStatus.notFound
        ..write('{"error_code":"account_not_found"}')
        ..close());

      expect(await api.fetchNativeBalance(_aptosAt(s), '0x1'), BigInt.zero);
    });

    test('429 限流必须抛出，绝不能伪装成余额 0', () async {
      final s = await _serve((r) => r.response
        ..statusCode = HttpStatus.tooManyRequests
        ..write('rate limited')
        ..close());

      expect(
        () => api.fetchNativeBalance(_aptosAt(s), '0x1'),
        throwsA(isA<HttpStatusException>().having((e) => e.statusCode, 'statusCode', 429)),
      );
    });

    test('正常返回标量余额', () async {
      final s = await _serve((r) => r.response
        ..write('"12345"')
        ..close());

      expect(await api.fetchNativeBalance(_aptosAt(s), '0x1'), BigInt.from(12345));
    });
  });

  group('Tron', () {
    test('未激活账户返回 {}，是真实的 0', () async {
      final s = await _serve((r) => r.response
        ..write('{}')
        ..close());

      expect(await api.fetchNativeBalance(_tronAt(s), 'T1'), BigInt.zero);
    });

    test('5xx 必须抛出——原实现会被 catch(_) 吞成 0，让总资产凭空缩水', () async {
      final s = await _serve((r) => r.response
        ..statusCode = HttpStatus.internalServerError
        ..write('<html>oops</html>')
        ..close());

      expect(
        () => api.fetchNativeBalance(_tronAt(s), 'T1'),
        throwsA(isA<HttpStatusException>().having((e) => e.statusCode, 'statusCode', 500)),
      );
    });

    test('正常返回 balance', () async {
      final s = await _serve((r) => r.response
        ..write('{"balance":9000000}')
        ..close());

      expect(await api.fetchNativeBalance(_tronAt(s), 'T1'), BigInt.from(9000000));
    });
  });

  group('ERC-20 代币余额', () {
    test('多代币合并成一次批量 eth_call，按合约地址回填', () async {
      var requestCount = 0;
      late List<dynamic> received;
      final s = await _serve((r) async {
        requestCount++;
        received = jsonDecode(await utf8.decodeStream(r)) as List<dynamic>;
        r.response
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode([
              for (var i = 0; i < received.length; i++)
                {'id': (received[i] as Map)['id'], 'result': _uint256((i + 1) * 1000000)},
            ]),
          )
          ..close();
      });

      final tokens = [_erc20('0xaaa1', symbol: 'USDC'), _erc20('0xbbb2', symbol: 'DAI')];
      final balances = await api.fetchTokenBalances(_evmAt(s), tokens, owner);

      expect(balances, {'0xaaa1': BigInt.from(1000000), '0xbbb2': BigInt.from(2000000)});
      expect(requestCount, 1, reason: '两个代币应当合并成一次往返');
      expect(received.map((c) => (c as Map)['method']), everyElement('eth_call'));
      // calldata 里带的是 balanceOf 选择器与 owner 地址，to 是各自的合约。
      expect(((received[0] as Map)['params'] as List)[0], {
        'to': '0xaaa1',
        'data': startsWith('0x70a08231'),
      });
    });

    test('无持仓返回编码的 0，是真实余额而非失败', () async {
      final s = await _serve((r) async {
        final batch = jsonDecode(await utf8.decodeStream(r)) as List<dynamic>;
        r.response
          ..write(jsonEncode([for (final c in batch) {'id': (c as Map)['id'], 'result': _uint256(0)}]))
          ..close();
      });

      expect(await api.fetchTokenBalance(_evmAt(s), _erc20('0xaaa1'), owner), BigInt.zero);
    });

    // 空返回说明目标地址上根本没有合约，按 0 展示等于谎报「你没有这个币」。
    test('eth_call 返回 0x（非合约地址）时抛出，不当作 0', () async {
      final s = await _serve((r) async {
        final batch = jsonDecode(await utf8.decodeStream(r)) as List<dynamic>;
        r.response
          ..write(jsonEncode([for (final c in batch) {'id': (c as Map)['id'], 'result': '0x'}]))
          ..close();
      });

      expect(() => api.fetchTokenBalance(_evmAt(s), _erc20('0xaaa1'), owner), throwsFormatException);
    });

    test('空代币列表不发请求', () async {
      var requestCount = 0;
      final s = await _serve((r) async {
        requestCount++;
        r.response.close();
      });

      expect(await api.fetchTokenBalances(_evmAt(s), const [], owner), isEmpty);
      expect(requestCount, 0);
    });

    // 目录写错标准时，整条链的批量请求会被这一条带崩——所以要在发请求前就拦下。
    test('代币标准与链对不上时抛 ArgumentError，不发请求', () async {
      var requestCount = 0;
      final s = await _serve((r) async {
        requestCount++;
        r.response.close();
      });
      final spl = _token('mint', TokenStandard.spl);

      expect(ChainBalanceApi.supportsTokenBalance(_evmAt(s), TokenStandard.erc20), isTrue);
      expect(ChainBalanceApi.supportsTokenBalance(_evmAt(s), TokenStandard.spl), isFalse);
      await expectLater(api.fetchTokenBalances(_evmAt(s), [spl], owner), throwsArgumentError);
      expect(requestCount, 0);
    });
  });

  group('SPL 代币余额', () {
    test('同一 mint 的多个代币账户求和', () async {
      final s = await _serve(_rpcBatch((_) => {
        'value': [_splAccount('700000'), _splAccount('300000')],
      }));

      expect(
        await api.fetchTokenBalance(_solanaAt(s), _token('mint1', TokenStandard.spl), 'SoL1'),
        BigInt.from(1000000),
        reason: 'ATA 之外还能手动开账户，只取第一个会漏报持仓',
      );
    });

    test('没有代币账户（value 为空）= 真实的 0', () async {
      final s = await _serve(_rpcBatch((_) => {'value': const []}));

      expect(await api.fetchTokenBalance(_solanaAt(s), _token('mint1', TokenStandard.spl), 'SoL1'), BigInt.zero);
    });

    test('多代币合并成一次批量请求，按 mint 过滤', () async {
      var requestCount = 0;
      late List<dynamic> sent;
      final s = await _serve((r) async {
        requestCount++;
        sent = jsonDecode(await utf8.decodeStream(r)) as List<dynamic>;
        r.response
          ..write(jsonEncode([
            for (var i = 0; i < sent.length; i++)
              {
                'id': (sent[i] as Map)['id'],
                'result': {
                  'value': [_splAccount('${(i + 1) * 100}')],
                },
              },
          ]))
          ..close();
      });

      final tokens = [_token('mint1', TokenStandard.spl), _token('mint2', TokenStandard.spl)];
      final balances = await api.fetchTokenBalances(_solanaAt(s), tokens, 'SoL1');

      expect(balances, {'mint1': BigInt.from(100), 'mint2': BigInt.from(200)});
      expect(requestCount, 1);
      expect(((sent[1] as Map)['params'] as List)[1], {'mint': 'mint2'});
    });

    test('RPC 故障上抛，不伪装成 0', () async {
      final s = await _serve((r) => r.response
        ..statusCode = HttpStatus.internalServerError
        ..write('oops')
        ..close());

      expect(
        () => api.fetchTokenBalance(_solanaAt(s), _token('mint1', TokenStandard.spl), 'SoL1'),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('Sui 代币余额', () {
    test('按 coin type 取 totalBalance', () async {
      late List<dynamic> sent;
      final s = await _serve((r) async {
        sent = jsonDecode(await utf8.decodeStream(r)) as List<dynamic>;
        r.response
          ..write(jsonEncode([
            for (final c in sent)
              {
                'id': (c as Map)['id'],
                'result': {'totalBalance': '4500000'},
              },
          ]))
          ..close();
      });

      final coinType = '0xabc::usdc::USDC';
      expect(
        await api.fetchTokenBalance(_suiAt(s), _token(coinType, TokenStandard.suiCoin), '0x1'),
        BigInt.from(4500000),
      );
      // 与原生币是同一个方法，区别只在第二个参数。
      expect((sent.first as Map)['method'], 'suix_getBalance');
      expect(((sent.first as Map)['params'] as List)[1], coinType);
    });

    // Sui 测试网的公共节点会用 -32005 明确拒绝批量请求，而官方 fullnode 的 JSON-RPC
    // 已整体弃用、换端点也解决不了——所以这条链必须退回并发单条。
    test('supportsRpcBatch 为 false 时发多条单请求，结果仍按顺序对上', () async {
      final bodies = <Object?>[];
      final s = await _serve((r) async {
        final body = jsonDecode(await utf8.decodeStream(r));
        bodies.add(body);
        final id = (body as Map)['id'];
        r.response
          ..write(jsonEncode({
            'jsonrpc': '2.0',
            'id': id,
            'result': {'totalBalance': '${id}00'},
          }))
          ..close();
      });

      final chain = _suiAt(s, batch: false);
      // 真实注册表里的 Sui 测试网也必须是 false，否则线上仍会踩这个坑。
      expect(SupportedChains.suiTestnet.supportsRpcBatch, isFalse);

      final tokens = [_token('0xa::a::A', TokenStandard.suiCoin), _token('0xb::b::B', TokenStandard.suiCoin)];
      final balances = await api.fetchTokenBalances(chain, tokens, '0x1');

      expect(bodies, hasLength(2), reason: '两条独立请求，而不是一个数组');
      expect(bodies.every((b) => b is Map), isTrue, reason: '单条请求体必须是对象，不能是数组');
      // 每条按自己的 id 回不同数字，顺序错乱会立刻露馅。
      final ids = [for (final b in bodies) (b as Map)['id'] as int];
      expect(balances, {
        '0xa::a::A': BigInt.parse('${ids[0]}00'),
        '0xb::b::B': BigInt.parse('${ids[1]}00'),
      });
    });

    test('响应缺 totalBalance 字段时按 0，不抛', () async {
      final s = await _serve(_rpcBatch((_) => const <String, Object?>{}));

      expect(
        await api.fetchTokenBalance(_suiAt(s), _token('0xabc::usdc::USDC', TokenStandard.suiCoin), '0x1'),
        BigInt.zero,
      );
    });
  });

  group('Aptos 代币余额', () {
    test('FA metadata 地址与 coin type 都能取数', () async {
      final paths = <String>[];
      final s = await _serve((r) {
        paths.add(r.uri.path);
        r.response
          ..write('"250000"')
          ..close();
      });

      const fa = '0x69091fbab5f7d635ee7ac5098cf0c1efbe31d68fec0f2cd565e8d168daf52832';
      const coin = '0xabc::usdc::USDC';
      final balances = await api.fetchTokenBalances(
        _aptosAt(s),
        [_token(fa, TokenStandard.aptosCoin), _token(coin, TokenStandard.aptosCoin)],
        '0x1',
      );

      expect(balances, {fa: BigInt.from(250000), coin: BigInt.from(250000)});
      expect(paths, ['/v1/accounts/0x1/balance/$fa', '/v1/accounts/0x1/balance/$coin']);
    });

    test('404 = 没开过这个资产的 store，按 0 处理', () async {
      final s = await _serve((r) => r.response
        ..statusCode = HttpStatus.notFound
        ..write('{"error_code":"resource_not_found"}')
        ..close());

      expect(
        await api.fetchTokenBalance(_aptosAt(s), _token('0xabc::usdc::USDC', TokenStandard.aptosCoin), '0x1'),
        BigInt.zero,
      );
    });

    test('429 限流必须上抛', () async {
      final s = await _serve((r) => r.response
        ..statusCode = HttpStatus.tooManyRequests
        ..write('rate limited')
        ..close());

      expect(
        () => api.fetchTokenBalance(_aptosAt(s), _token('0xabc::usdc::USDC', TokenStandard.aptosCoin), '0x1'),
        throwsA(isA<HttpStatusException>().having((e) => e.statusCode, 'statusCode', 429)),
      );
    });
  });

  group('TRC-20 代币余额', () {
    // Tron 主网上的 USDT 合约地址，格式合法，这里只当作一个可解码的 base58 地址用。
    const tronOwner = 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t';

    test('解码 constant_result，并把 T 地址编成 32 字节参数', () async {
      late Map<String, dynamic> sent;
      final s = await _serve((r) async {
        sent = jsonDecode(await utf8.decodeStream(r)) as Map<String, dynamic>;
        r.response
          ..write(jsonEncode({
            'result': {'result': true},
            'constant_result': [_uint256(7500000).substring(2)],
          }))
          ..close();
      });

      expect(
        await api.fetchTokenBalance(_tronAt(s), _token('TContract', TokenStandard.trc20), tronOwner),
        BigInt.from(7500000),
      );
      expect(sent['function_selector'], 'balanceOf(address)');
      expect(sent['visible'], true);
      expect(sent['parameter'], hasLength(64));
      expect(sent['parameter'], matches(RegExp(r'^0{24}[0-9a-f]{40}$')), reason: '20 字节地址右对齐补零到 32 字节');
    });

    // 合约不存在 / 参数不对时调用根本没执行成功，按 0 展示就是谎报「你没有这个币」。
    test('result.result 为假时抛出，不当作 0', () async {
      final s = await _serve((r) => r.response
        ..write('{"result":{"result":false},"message":"contract not found"}')
        ..close());

      expect(
        () => api.fetchTokenBalance(_tronAt(s), _token('TContract', TokenStandard.trc20), tronOwner),
        throwsA(isA<Exception>()),
      );
    });

    test('constant_result 为空时抛出', () async {
      final s = await _serve((r) => r.response
        ..write('{"result":{"result":true},"constant_result":[]}')
        ..close());

      expect(
        () => api.fetchTokenBalance(_tronAt(s), _token('TContract', TokenStandard.trc20), tronOwner),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('tokenStandardOf', () {
    test('每条链的代币标准与 kind 一一对应，比特币没有代币模型', () {
      for (final chain in SupportedChains.all) {
        final standard = ChainBalanceApi.tokenStandardOf(chain.kind);
        if (chain.kind == ChainKind.bitcoin) {
          expect(standard, isNull, reason: '${chain.name} 不应有代币标准');
        } else {
          expect(standard, isNotNull, reason: '${chain.name} 缺少代币标准映射');
        }
      }
    });

    // 目录里写错 standard 的代币会被 chainTokenBalancesProvider 静默过滤掉，
    // 界面上只表现为「余额恒为 0」，不查这一条根本发现不了。
    test('内置目录里每个代币的标准都与所属链匹配', () {
      for (final token in BundledTokenCatalog.all) {
        final chain = SupportedChains.byId(token.chainId);
        expect(
          ChainBalanceApi.supportsTokenBalance(chain, token.standard),
          isTrue,
          reason: '${chain.name} 的 ${token.symbol} 标准写成了 ${token.standard.name}',
        );
      }
    });
  });
}
