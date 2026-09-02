import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wallet/data/datasource/remote/json_rpc.dart';

/// 与 chain_balance_api_test 同一套路：传输层是顶层函数、没有注入点，
/// 直接给它一个真的 HTTP 对端最省事，顺带覆盖状态码与报文解析。
Future<String> _serve(Future<String> Function(List<dynamic> batch) respond) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  addTearDown(server.close);
  server.listen((r) async {
    final body = await utf8.decodeStream(r);
    r.response
      ..headers.contentType = ContentType.json
      ..write(await respond(jsonDecode(body) as List<dynamic>))
      ..close();
  });
  return 'http://${server.address.host}:${server.port}';
}

/// 按请求顺序原样回结果的应答体。
String _ok(List<dynamic> batch, List<String> results) => jsonEncode([
  for (var i = 0; i < batch.length; i++) {'jsonrpc': '2.0', 'id': (batch[i] as Map)['id'], 'result': results[i]},
]);

void main() {
  test('空批次不发请求，直接返回空列表', () async {
    // 端点故意指向一个不存在的地址：真发出去就会抛连接错误。
    expect(await jsonRpcBatch('http://127.0.0.1:1/none', const []), isEmpty);
  });

  test('一次往返发出全部调用', () async {
    var requestCount = 0;
    var batchSize = 0;
    final url = await _serve((batch) async {
      requestCount++;
      batchSize = batch.length;
      return _ok(batch, ['0x1', '0x2', '0x3']);
    });

    final results = await jsonRpcBatch(url, [
      for (final to in ['a', 'b', 'c']) (method: 'eth_call', params: [to]),
    ]);

    expect(results, ['0x1', '0x2', '0x3']);
    expect(requestCount, 1, reason: '批量的意义就是合成一次往返；退回逐条发这里会变成 3');
    expect(batchSize, 3);
  });

  // 规范允许服务端乱序返回。按数组下标取结果会把余额安到别的代币头上——
  // 界面上不会报错，只会显示一堆错位的数字，是最难被发现的一类 bug。
  test('服务端乱序返回时，仍按请求顺序回填', () async {
    final url = await _serve((batch) async {
      final ordered = _ok(batch, ['0xa', '0xb', '0xc']);
      return jsonEncode((jsonDecode(ordered) as List).reversed.toList());
    });

    final results = await jsonRpcBatch(url, [
      for (final to in ['a', 'b', 'c']) (method: 'eth_call', params: [to]),
    ]);

    expect(results, ['0xa', '0xb', '0xc']);
  });

  test('单条 error 即整批抛出，不做部分成功', () async {
    final url = await _serve((batch) async {
      final items = [
        for (var i = 0; i < batch.length; i++)
          {
            'jsonrpc': '2.0',
            'id': (batch[i] as Map)['id'],
            if (i == 1) 'error': {'code': -32000, 'message': 'execution reverted'} else 'result': '0x1',
          },
      ];
      return jsonEncode(items);
    });

    await expectLater(
      jsonRpcBatch(url, [for (var i = 0; i < 3; i++) (method: 'eth_call', params: const [])]),
      throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('execution reverted'))),
    );
  });

  test('条目数量对不上时抛出，不静默截断', () async {
    final url = await _serve((batch) async => _ok(batch.take(1).toList(), ['0x1']));

    await expectLater(
      jsonRpcBatch(url, [for (var i = 0; i < 2; i++) (method: 'eth_call', params: const [])]),
      throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('size mismatch'))),
    );
  });

  test('HTTP 非 2xx 抛出', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((r) => r.response
      ..statusCode = HttpStatus.tooManyRequests
      ..write('rate limited')
      ..close());

    await expectLater(
      jsonRpcBatch('http://${server.address.host}:${server.port}', [(method: 'eth_call', params: const [])]),
      throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('status=429'))),
    );
  });
}
