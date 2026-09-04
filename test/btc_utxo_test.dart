import 'dart:convert';
import 'dart:io';

import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wallet/blockchain/chain_registry.dart';
import 'package:wallet/data/datasource/remote/bitcoin_utxo_api.dart';
import 'package:wallet/data/datasource/remote/http_config.dart';
import 'package:wallet/domain/btc_utxo.dart';
import 'package:wallet/enums/prefs_key.dart';
import 'package:wallet/providers/modules/broadcast_history_provider.dart';
import 'package:wallet/providers/prefs_provider.dart';

/// 与 chain_balance_api_test 同法：起个本地服务替代真实节点，
/// 顺带把 rest_client 的状态码处理一起覆盖。
Future<HttpServer> _serve(void Function(HttpRequest) handler) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen(handler);
  addTearDown(server.close);
  return server;
}

Chain _bitcoinAt(HttpServer s) => Chain(
  id: 'btc-test',
  name: 'Bitcoin',
  symbol: 'BTC',
  kind: ChainKind.bitcoin,
  coin: Bip44Coins.bitcoinTestnet,
  endpoint: 'http://${s.address.host}:${s.port}',
  coinGeckoId: 'bitcoin',
  decimals: 8,
);

/// Esplora `/address/{addr}/utxo` 的单条。confirmed 为 false 时，
/// 真实响应的 status 里**只有** confirmed 一个字段。
Map<String, Object?> _utxoJson(String txid, int vout, int value, {required bool confirmed, int? height}) => {
  'txid': txid,
  'vout': vout,
  'value': value,
  'status': {
    'confirmed': confirmed,
    if (confirmed) 'block_height': height ?? 2900000,
    if (confirmed) 'block_hash': '00'.padRight(64, '0'),
  },
};

Utxo _utxo(String txid, int value, {required bool confirmed}) =>
    Utxo(txid: txid, vout: 0, value: BigInt.from(value), confirmed: confirmed, address: 'tb1q');

void main() {
  // 绑定是 SharedPreferences 打桩的前提，但它会顺手装一个 HttpOverrides——
  // 那个 mock client 对所有请求一律回 400（Flutter 用它拦截 widget 测试里的图片加载）。
  // 本文件同时要用真的 HttpServer 对端，所以初始化完立刻把覆盖摘掉。
  // [sharedHttpClient] 是惰性初始化的顶层 final，这一行跑在它第一次被用到之前。
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  group('Utxo.fromJson', () {
    test('已确认项解出块高', () {
      final u = Utxo.fromJson(_utxoJson('aa', 1, 15000, confirmed: true, height: 2900001), 'tb1q');
      expect(u.txid, 'aa');
      expect(u.vout, 1);
      expect(u.value, BigInt.from(15000));
      expect(u.confirmed, isTrue);
      expect(u.blockHeight, 2900001);
      expect(u.outpoint, 'aa:1');
      expect(u.address, 'tb1q');
    });

    // 用 0 兜底会让「未确认」被读成「已在创世块确认」，任何基于确认数的判断都会反过来。
    test('未确认项的 blockHeight 是 null 而非 0', () {
      final u = Utxo.fromJson(_utxoJson('bb', 0, 500, confirmed: false), 'tb1q');
      expect(u.confirmed, isFalse);
      expect(u.blockHeight, isNull);
    });

    test('status 整个缺失时按未确认处理，不抛', () {
      final u = Utxo.fromJson(const {'txid': 'cc', 'vout': 0, 'value': 1}, 'tb1q');
      expect(u.confirmed, isFalse);
      expect(u.blockHeight, isNull);
    });
  });

  group('parseUtxos', () {
    test('空数组 = 全新地址，返回空列表', () {
      expect(BitcoinUtxoApi.parseUtxos(const [], 'tb1q'), isEmpty);
    });

    // 一条脏数据不该让整条链的余额变成错误态。
    test('非 Map 元素逐条跳过', () {
      final utxos = BitcoinUtxoApi.parseUtxos([
        _utxoJson('aa', 0, 100, confirmed: true),
        'garbage',
        42,
      ], 'tb1q');
      expect(utxos, hasLength(1));
      expect(utxos.single.txid, 'aa');
    });
  });

  group('UtxoSet 三口径', () {
    test('全已确认：confirmed == total，可花即全部', () {
      final set = UtxoSet([_utxo('aa', 70000, confirmed: true), _utxo('bb', 30000, confirmed: true)]);
      expect(set.confirmed, BigInt.from(100000));
      expect(set.pending, BigInt.zero);
      expect(set.spendable, BigInt.from(100000));
      expect(set.total, BigInt.from(100000));
    });

    // 承接旧的「待确认收款立刻计入」，但口径更细：显示出来 ≠ 能花。
    // 别人发来的未确认转账随时可能被 RBF 替换掉，拿去当输入会连累自己的交易一起作废。
    test('别人的未确认转账：计入 pending 与 total，但不计入 spendable', () {
      final set = UtxoSet([_utxo('aa', 70000, confirmed: true), _utxo('zz', 25000, confirmed: false)]);
      expect(set.confirmed, BigInt.from(70000));
      expect(set.pending, BigInt.from(25000));
      expect(set.spendable, BigInt.from(70000), reason: '来源不明的未确认输出不能花');
      expect(set.total, BigInt.from(95000));
    });

    test('自己的未确认找零：同时计入 pending 与 spendable', () {
      final set = UtxoSet([
        _utxo('aa', 70000, confirmed: true),
        _utxo('mine', 25000, confirmed: false),
      ], ownTxids: const {'mine'});
      expect(set.pending, BigInt.from(25000));
      expect(set.spendable, BigInt.from(95000), reason: '父交易是自己签的，花它只是再挂一节 mempool 链');
    });

    test('两种未确认混在一起时只放行自己的那笔', () {
      final set = UtxoSet([
        _utxo('aa', 70000, confirmed: true),
        _utxo('mine', 25000, confirmed: false),
        _utxo('zz', 40000, confirmed: false),
      ], ownTxids: const {'mine'});
      expect(set.pending, BigInt.from(65000));
      expect(set.spendable, BigInt.from(95000));
      expect(set.total, BigInt.from(135000));
    });

    test('空集合三口径全为 0，不抛', () {
      expect(UtxoSet.empty.confirmed, BigInt.zero);
      expect(UtxoSet.empty.pending, BigInt.zero);
      expect(UtxoSet.empty.spendable, BigInt.zero);
      expect(UtxoSet.empty.total, BigInt.zero);
    });

    test('total == confirmed + pending（与旧的 chain_stats+mempool_stats 口径等价）', () {
      final set = UtxoSet([
        _utxo('aa', 70000, confirmed: true),
        _utxo('bb', 1234, confirmed: true),
        _utxo('zz', 25000, confirmed: false),
      ]);
      expect(set.total, set.confirmed + set.pending);
    });

    // 承接旧的「待确认支出立刻扣减」。注意 Esplora 用**消失**而不是负数表达支出：
    // 被未确认交易花掉的输出直接不在列表里，所以这里断言的是两组 fixture 的差值。
    test('待确认支出：被花掉的输出从列表消失，total 立刻减少', () {
      final before = UtxoSet([_utxo('aa', 70000, confirmed: true), _utxo('bb', 30000, confirmed: true)]);
      // 花掉 bb，找零 25000 回到自己手上（手续费 5000）。
      final after = UtxoSet([
        _utxo('aa', 70000, confirmed: true),
        _utxo('mine', 25000, confirmed: false),
      ], ownTxids: const {'mine'});

      expect(before.total - after.total, BigInt.from(5000), reason: '差额正是手续费，而不是整笔支出');
      expect(after.confirmed, BigInt.from(70000), reason: 'bb 已被花掉，不再计入已确认');
      expect(after.spendable, BigInt.from(95000), reason: '找零可以继续花，用户不必等出块');
    });
  });

  group('BitcoinUtxoApi', () {
    const api = BitcoinUtxoApi();

    test('端到端：请求 /address/{addr}/utxo', () async {
      final paths = <String>[];
      final s = await _serve((r) {
        paths.add(r.uri.path);
        r.response
          ..write(jsonEncode([_utxoJson('aa', 0, 15000, confirmed: true)]))
          ..close();
      });

      final utxos = await api.fetchUtxos(_bitcoinAt(s), const ['tb1qxyz']);
      expect(utxos.single.value, BigInt.from(15000));
      expect(paths, ['/address/tb1qxyz/utxo']);
    });

    test('空地址列表不发请求', () async {
      var requestCount = 0;
      final s = await _serve((r) {
        requestCount++;
        r.response.close();
      });

      expect(await api.fetchUtxos(_bitcoinAt(s), const []), isEmpty);
      expect(requestCount, 0);
    });

    // 「集合 API」设计的回归保护：以后加找零链时，归属必须还对得上。
    test('多地址并发查询后合并，每个 Utxo 的 address 归属正确', () async {
      final paths = <String>[];
      final s = await _serve((r) {
        paths.add(r.uri.path);
        final address = r.uri.pathSegments[1];
        r.response
          ..write(jsonEncode([_utxoJson('tx-$address', 0, 1000, confirmed: true)]))
          ..close();
      });

      final utxos = await api.fetchUtxos(_bitcoinAt(s), const ['tb1qaaa', 'tb1qbbb']);

      expect(paths, hasLength(2));
      expect(utxos.map((u) => u.address).toSet(), {'tb1qaaa', 'tb1qbbb'});
      for (final u in utxos) {
        expect(u.txid, 'tx-${u.address}', reason: '合并时不能把 UTXO 挂到别的地址上');
      }
      expect(UtxoSet(utxos).total, BigInt.from(2000));
    });

    test('5xx 必须上抛，不伪装成空集合', () async {
      final s = await _serve((r) => r.response
        ..statusCode = HttpStatus.internalServerError
        ..write('oops')
        ..close());

      expect(
        () => api.fetchUtxos(_bitcoinAt(s), const ['tb1qxyz']),
        throwsA(isA<HttpStatusException>().having((e) => e.statusCode, 'statusCode', 500)),
      );
    });
  });

  group('BroadcastHistoryNotifier', () {
    Future<ProviderContainer> containerWith(Map<String, Object> initial) async {
      SharedPreferences.setMockInitialValues(initial);
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(prefs)]);
      addTearDown(container.dispose);
      return container;
    }

    int daysAgo(int days) => DateTime.now().subtract(Duration(days: days)).millisecondsSinceEpoch;

    test('record 之后能读到，并落盘', () async {
      final container = await containerWith({});
      container.read(broadcastHistoryProvider.notifier).record('abc');

      expect(container.read(broadcastHistoryProvider).keys, ['abc']);
      final prefs = container.read(sharedPrefsProvider);
      expect(jsonDecode(prefs.getString(PrefsKey.btcBroadcasts.value)!), contains('abc'));
    });

    // 被 RBF 替换或被 mempool 驱逐的交易永远不会确认，记录会一直挂在盘上。
    test('超过 7 天的记录在 build 时被丢弃，新的保留', () async {
      final container = await containerWith({
        PrefsKey.btcBroadcasts.value: jsonEncode({'stale': daysAgo(8), 'fresh': daysAgo(1)}),
      });

      expect(container.read(broadcastHistoryProvider).keys, ['fresh']);
    });

    test('脏数据（值不是 int）跳过，不影响其余条目', () async {
      final container = await containerWith({
        PrefsKey.btcBroadcasts.value: jsonEncode({'bad': 'not-a-timestamp', 'good': daysAgo(1)}),
      });

      expect(container.read(broadcastHistoryProvider).keys, ['good']);
    });
  });
}
