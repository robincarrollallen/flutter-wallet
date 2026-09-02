import 'dart:convert';
import 'dart:io';

import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:flutter_test/flutter_test.dart';
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

Token _erc20(String identifier, {String symbol = 'USDC'}) => Token(
  chainId: 'evm-test',
  symbol: symbol,
  name: symbol,
  standard: TokenStandard.erc20,
  identifier: identifier,
  coinGeckoId: 'usd-coin',
  decimals: 6,
);

/// 把 BigInt 编成 32 字节的 uint256 返回值。
String _uint256(int value) => '0x${value.toRadixString(16).padLeft(64, '0')}';

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

    test('未接入的代币标准抛 UnimplementedError，而不是静默给 0', () async {
      final s = await _serve((r) async => r.response.close());
      final spl = Token(
        chainId: 'evm-test',
        symbol: 'X',
        name: 'X',
        standard: TokenStandard.spl,
        identifier: 'mint',
        coinGeckoId: '',
        decimals: 6,
      );

      expect(ChainBalanceApi.supportsTokenBalance(TokenStandard.erc20), isTrue);
      expect(ChainBalanceApi.supportsTokenBalance(TokenStandard.spl), isFalse);
      expect(() => api.fetchTokenBalances(_evmAt(s), [spl], owner), throwsUnsupportedError);
    });
  });
}
