import 'dart:io';

import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallet/blockchain/chain_registry.dart';
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

void main() {
  const api = ChainBalanceApi();

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
}
