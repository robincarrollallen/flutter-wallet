import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wallet/blockchain/chain_registry.dart';
import 'package:wallet/data/datasource/remote/coingecko_api.dart';
import 'package:wallet/data/repository/market_repository.dart';
import 'package:wallet/domain/account_balance.dart';
import 'package:wallet/domain/wallet.dart';
import 'package:wallet/providers/market_repository_provider.dart';
import 'package:wallet/providers/modules/balance_provider.dart';
import 'package:wallet/providers/prefs_provider.dart';

/// 测试用钱包：给 EVM 之外的链也铺上地址，好让跨链并发真的展开。
const _walletId = 'w1';
final _chains = SupportedChains.all;

/// 假余额：按 chainId 给定结果，或让指定链抛错模拟取数失败。
///
/// 挂在 [balanceProvider] 上，不经过 repository / 链上 API——本文件测的是
/// 汇总与并发，不是换算或 RPC。
///
/// 同时记录并发峰值——串行退化是本次改动最容易被悄悄改回去的地方，
/// 光断言结果正确是拦不住的，必须直接盯住「有没有同时在飞」。
class _FakeBalances {
  _FakeBalances({this.failing = const {}});

  /// 这些 chainId 的查询会抛异常。
  final Set<String> failing;

  /// 每条链都挂一个 Completer，测试自己决定何时放行，避免依赖 sleep。
  final gates = <String, Completer<void>>{};

  int _inFlight = 0;
  int maxInFlight = 0;

  Future<AccountBalance> fetch((String, String) key) async {
    final (chainId, address) = key;
    _inFlight++;
    maxInFlight = _inFlight > maxInFlight ? _inFlight : maxInFlight;
    try {
      await (gates[chainId]?.future ?? Future<void>.value());
      if (failing.contains(chainId)) throw Exception('boom: $chainId');
      return AccountBalance(address: address, amount: '1', symbol: 'X', price: 2.0);
    } finally {
      _inFlight--;
    }
  }
}

/// 假行情：每种币单价固定 2.0。
/// [walletTotalProvider] 仍会先等 [marketsProvider]，失败会整单抛错，所以这里必须成功。
class _FakeMarketRepository implements MarketRepository {
  const _FakeMarketRepository();

  @override
  Future<Markets> getMarkets({required String currency, required Iterable<String> ids}) async => {
    for (final id in ids) id: (price: 2.0, logoUrl: null),
  };

  @override
  Future<ChainIcons> getChainIcons(Iterable<String> platformIds) async => const {};

  @override
  Future<bool> refreshMarkets({required String currency, required Iterable<String> ids}) async => true;
}

Future<ProviderContainer> _container(_FakeBalances balances) async {
  // 用真实的 walletListProvider，靠预置的 prefs 还原出一个钱包，
  // 免得为测试再造一套 Notifier 替身。
  final wallet = Wallet(
    id: _walletId,
    name: 'W',
    address: '0xabc',
    addresses: {for (final c in _chains) c.id: 'addr-${c.id}'},
  );
  SharedPreferences.setMockInitialValues({
    'wallet.list': jsonEncode({
      'wallets': [wallet.toJson()],
    }),
  });
  final prefs = await SharedPreferences.getInstance();

  final container = ProviderContainer(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      marketRepositoryProvider.overrideWithValue(const _FakeMarketRepository()),
      balanceProvider.overrideWith((ref, key) => balances.fetch(key)),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('aggregateWalletTotal', () {
    AccountBalance b(double amount, double price) =>
        AccountBalance(address: 'a', amount: '$amount', symbol: 'X', price: price);

    test('全部成功：求和，不算部分失败', () {
      final r = aggregateWalletTotal([('a', b(2, 3)), ('b', b(1, 4))]);
      expect(r.value, 10);
      expect(r.isPartial, isFalse);
      expect(r.failedChainIds, isEmpty);
    });

    test('部分失败：只累加成功的链，并记下失败链 id', () {
      final r = aggregateWalletTotal([('a', b(2, 3)), ('b', null), ('c', b(1, 1))]);
      expect(r.value, 7);
      expect(r.isPartial, isTrue);
      expect(r.failedChainIds, ['b']);
    });

    test('全部失败：总额 0，但明确标记为不完整（区别于真的没钱）', () {
      final r = aggregateWalletTotal([('a', null), ('b', null)]);
      expect(r.value, 0);
      expect(r.failedChainIds, ['a', 'b']);
    });
  });

  group('walletTotalProvider', () {
    test('全链成功：总额 = 各链 1 枚 × 单价 2', () async {
      final balances = _FakeBalances();
      final c = await _container(balances);
      final total = await c.read(walletTotalProvider(_walletId).future);

      expect(total.isPartial, isFalse);
      expect(total.value, _chains.length * 2.0);
    });

    test('单链失败不连坐：其余链照常计入，整体不抛错', () async {
      final failed = _chains.first.id;
      final balances = _FakeBalances(failing: {failed});
      final c = await _container(balances);
      final total = await c.read(walletTotalProvider(_walletId).future);

      expect(total.isPartial, isTrue);
      expect(total.failedChainIds, [failed]);
      expect(total.value, (_chains.length - 1) * 2.0);
    });

    test('失败链 id 顺序与 SupportedChains.all 一致', () async {
      final failed = {_chains[1].id, _chains[3].id};
      final balances = _FakeBalances(failing: failed);
      final c = await _container(balances);
      final total = await c.read(walletTotalProvider(_walletId).future);

      expect(total.failedChainIds, [_chains[1].id, _chains[3].id]);
    });

    test('无此钱包：返回 empty 而非抛错', () async {
      final c = await _container(_FakeBalances());
      final total = await c.read(walletTotalProvider('nope').future);

      expect(total.value, 0);
      expect(total.isPartial, isFalse);
    });

    // Riverpod 3.x 默认失败重试 10 次、指数退避，最长要拖近 40 秒 .future 才落定，
    // 期间总资产一直转圈。balanceProvider 已用 retry:_noRetry 关掉；
    // 这条用时间上限把它钉住——一旦有人去掉 retry 参数，这里会立刻超时。
    test('失败链立即落定，不走 Riverpod 默认的退避重试', () async {
      final balances = _FakeBalances(failing: {_chains.first.id});
      final c = await _container(balances);
      final total = await c.read(walletTotalProvider(_walletId).future).timeout(const Duration(seconds: 2));

      expect(total.isPartial, isTrue);
    });

    // 本次改动的核心。断言的是「多条链同时在飞」，不是「快了多少」——
    // 后者依赖机器状态会 flaky，前者能精确拦住退回串行的改动。
    test('各链并发发起，而非一条等一条', () async {
      final balances = _FakeBalances();
      // 全部闸门先关上：只要是串行的，第一条链就会卡住，后面根本不会开始。
      for (final ch in _chains) {
        balances.gates[ch.id] = Completer<void>();
      }

      final c = await _container(balances);
      final future = c.read(walletTotalProvider(_walletId).future);

      // 让已发起的请求都跑到 await 闸门处。
      await Future<void>.delayed(Duration.zero);
      expect(
        balances.maxInFlight,
        _chains.length,
        reason: '应当所有链同时在飞；若为 1 说明退回了循环内 await 的串行写法',
      );

      for (final g in balances.gates.values) {
        g.complete();
      }
      expect((await future).value, _chains.length * 2.0);
    });
  });
}
