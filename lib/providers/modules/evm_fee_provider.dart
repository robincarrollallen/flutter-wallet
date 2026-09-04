import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../blockchain/chain_registry.dart';
import '../../core/utils/erc20_abi.dart';
import '../../domain/evm_fee.dart';
import '../../enums/fee_speed.dart';
import '../../enums/prefs_key.dart';
import '../../services/evm_transaction_service.dart';
import '../persistent_notifier.dart';

/// 费率缓存：每条链一份基准，另按「链:收款方:资产」存 gasLimit。
/// gasLimit 对同一个收款方 + 同一个资产是稳定的（EOA 转原生币恒 21000，合约几乎不变），
/// 单独存一份就能让重进确认页时连 eth_getCode 都不用等。
///
/// 键里必须带资产：原生转账 21000，ERC-20 是合约调用、要 5 万上下，
/// 少了这一维会让「先转 ETH 再转 USDT 给同一个人」直接命中错误的 21000。
typedef EvmFeeCache = ({Map<String, EvmGasBasis> basis, Map<String, BigInt> gasLimits});

/// 报价的查询键。带上 [tokenIdentifier]（null = 原生币）——不同资产的 gasLimit 不同。
typedef EvmFeeKey = ({String chainId, String from, String to, String? tokenIdentifier});

/// 一次报价：三档 + 数据是否已经过时。
/// [quotes] 为 null 表示落盘里没有、网络也还没回来——展示 `--`。
typedef EvmFeeView = ({Map<FeeSpeed, EvmFeeQuote>? quotes, bool stale});

/// 展示用的新鲜度门槛。超过它仍然照常展示（避免闪 `--`），但标记为 [EvmFeeView.stale]，
/// 由 UI 提示「更新中」，且不参与 MAX 扣减这类会影响金额的计算。
const _freshFor = Duration(seconds: 60);

/// 轮询间隔，对齐以太坊出块节奏。
const _pollInterval = Duration(seconds: 12);

/// gasLimit 缓存条数上限：只服务最近几个收款方，超出丢最早写入的。
const _gasLimitCacheSize = 30;

/// EVM 费率基准的落盘缓存。跨链共用一份 JSON，键是 chainId。
class EvmGasBasisNotifier extends Notifier<EvmFeeCache> with PersistentNotifier<EvmFeeCache> {
  @override
  PrefsKey get persistKey => PrefsKey.evmGasBasis;

  @override
  Map<String, dynamic> toJson(EvmFeeCache state) => {
    'basis': {for (final entry in state.basis.entries) entry.key: entry.value.toJson()},
    'gasLimits': {for (final entry in state.gasLimits.entries) entry.key: entry.value.toString()},
  };

  @override
  EvmFeeCache fromJson(Map<String, dynamic> json, EvmFeeCache fallback) {
    final basisJson = json['basis'];
    final gasLimitJson = json['gasLimits'];
    return (
      basis: basisJson is! Map
          ? fallback.basis
          : {for (final entry in basisJson.entries) '${entry.key}': ?EvmGasBasis.fromJson(entry.value)},
      gasLimits: gasLimitJson is! Map
          ? fallback.gasLimits
          : {for (final entry in gasLimitJson.entries) '${entry.key}': ?BigInt.tryParse('${entry.value}')},
    );
  }

  @override
  EvmFeeCache build() {
    ref.keepAlive(); // 缓存跨页面复用，离开发送流程也不丢。
    return restore((basis: const {}, gasLimits: const {}));
  }

  static String gasLimitKey(EvmFeeKey key) =>
      '${key.chainId}:${key.to.toLowerCase()}:${key.tokenIdentifier?.toLowerCase() ?? 'native'}';

  /// 重抓某条链的基准（以及该收款方 + 该资产的 gasLimit）并落盘。
  /// 失败不清空旧值——旧报价带 stale 标记继续展示，好过整行变 `--`。
  Future<void> refresh(EvmFeeKey key) async {
    final chain = SupportedChains.byId(key.chainId);
    if (chain.kind != ChainKind.evm) return; // 非 EVM 链没有这套费率模型，别在它上面空转轮询。
    const service = EvmTransactionService();
    try {
      final basis = await service.fetchGasBasis(chain.endpoint);
      final gasLimit = await _resolveGasLimit(service, chain, key);
      if (!ref.mounted) return;
      final gasLimits = {...state.gasLimits};
      if (gasLimit != null && key.to.isNotEmpty) {
        final cacheKey = gasLimitKey(key);
        gasLimits.remove(cacheKey); // 先删再插，保证重新排到插入序末尾，淘汰时先走最久没用的。
        gasLimits[cacheKey] = gasLimit;
        while (gasLimits.length > _gasLimitCacheSize) {
          gasLimits.remove(gasLimits.keys.first);
        }
      }
      state = (basis: {...state.basis, key.chainId: basis}, gasLimits: gasLimits); // listenSelf 监听到，自动落盘
    } catch (_) {
      // 网络抖动：保持旧缓存，等下一次轮询。
    }
  }

  /// 本次报价该用哪个 gasLimit：原生币按收款方类型（EOA 21000 / 合约实估），
  /// 代币按 `transfer` 的 calldata 实估。
  ///
  /// 报价页拿不到用户要转的具体金额，估算统一按 **1 个最小单位**——同一收款方下
  /// 决定用量的是接收方余额槽是否从 0 变非 0，与转多少无关，因此这个估值有代表性；
  /// 实际发送时 [EvmTransactionService.sendToken] 会按真实金额重估一次。
  Future<BigInt?> _resolveGasLimit(EvmTransactionService service, Chain chain, EvmFeeKey key) async {
    final token = key.tokenIdentifier;
    if (token == null) return service.resolveNativeGasLimit(chain, from: key.from, to: key.to);
    if (key.from.isEmpty || key.to.isEmpty) return null;
    return service.resolveTokenGasLimit(
      chain,
      from: key.from,
      contract: token,
      data: encodeTransfer(to: key.to, amount: BigInt.one),
    );
  }
}

/// 费率缓存状态管理<落盘持久化>
final evmGasBasisProvider = NotifierProvider<EvmGasBasisNotifier, EvmFeeCache>(EvmGasBasisNotifier.new);

/// 轮询副作用：进页面立刻抓一次，之后按出块节奏重抓，离开页面自动停。
/// 单独一个 provider 是为了不跟着缓存变化重建——否则每次刷新都会再起一个 timer。
/// 状态是自增的轮次号：即便本轮抓取失败、缓存没变，它也会推动读端重算新鲜度，
/// 否则一直抓不到数据时页面会永远显示「不过期」。
class _FeePoller extends Notifier<int> {
  _FeePoller(this.key);

  final EvmFeeKey key;

  @override
  int build() {
    Future<void> tick() async {
      await ref.read(evmGasBasisProvider.notifier).refresh(key);
      if (ref.mounted) state = state + 1;
    }

    unawaited(tick());
    final timer = Timer.periodic(_pollInterval, (_) => tick());
    ref.onDispose(timer.cancel);
    return 0;
  }
}

final _feePollerProvider = NotifierProvider.autoDispose.family<_FeePoller, int, EvmFeeKey>(_FeePoller.new);

/// 查询键 -> 各档位报价。
///
/// 同步返回：落盘有数据就先拿旧值渲染（标 stale），同时后台刷新并定时轮询，
/// 落盘也没有才给 null 让 UI 显示 `--`。三档共享同一份基准，切档不发 RPC。
final evmFeeProvider = Provider.autoDispose.family<EvmFeeView, EvmFeeKey>((ref, key) {
  ref.watch(_feePollerProvider(key));

  final cache = ref.watch(evmGasBasisProvider);
  final basis = cache.basis[key.chainId];
  final gasLimit = cache.gasLimits[EvmGasBasisNotifier.gasLimitKey(key)];
  if (basis == null || gasLimit == null) return (quotes: null, stale: false);

  return (
    quotes: {
      for (final speed in FeeSpeed.values)
        speed: EvmFeeQuote(speed: speed, rate: basis.rateFor(speed), gasLimit: gasLimit),
    },
    stale: DateTime.now().difference(basis.fetchedAt) >= _freshFor,
  );
});
