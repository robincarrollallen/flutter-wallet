import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../enums/prefs_key.dart';
import '../persistent_notifier.dart';

/// txid -> 广播时刻（毫秒）。
///
/// 用 Map 而不是 List：需要时刻做兜底过期，且 key 天然去重。
typedef BroadcastState = Map<String, int>;

/// 本机广播过、尚未确认的 BTC 交易 id。
///
/// 存在的唯一理由：在 UTXO 列表里，「我刚发出那笔交易找回来的零」与「别人刚发给我、
/// 随时可能被 RBF 替换掉的转账」长得**一模一样**——找零输出的脚本和普通收款没有
/// 任何区别，链上查不出差异。只有本地记账能把两者分开，而这个区别决定了一笔未确认
/// 的钱能不能安全地拿去当下一笔交易的输入（见 [UtxoSet.spendable]）。
class BroadcastHistoryNotifier extends Notifier<BroadcastState> with PersistentNotifier<BroadcastState> {
  /// 兜底过期时长。
  ///
  /// 正常情况下一条记录会随着交易确认而失去作用（[UtxoSet.spendable] 求交时匹配不上，
  /// 自然不再生效），留着无害。这个 TTL 只防御异常路径：交易被 RBF 替换、或被 mempool
  /// 驱逐后**永远不会确认**，记录会一直挂在盘上。7 天足够覆盖任何合理的确认延迟。
  static const _ttl = Duration(days: 7);

  @override
  PrefsKey get persistKey => PrefsKey.btcBroadcasts;

  @override
  Map<String, dynamic> toJson(BroadcastState state) => state;

  @override
  BroadcastState fromJson(Map<String, dynamic> json, BroadcastState fallback) => {
    for (final entry in json.entries)
      if (entry.value is int) entry.key: entry.value as int,
  };

  @override
  BroadcastState build() {
    ref.keepAlive();
    return _withoutExpired(restore(const {}));
  }

  /// 记下一个刚广播成功的 txid。
  ///
  /// 【未来 BTC 发送链路的写入点】拿到 txid 之后立刻调用。必须在广播**成功**后调：
  /// 失败的交易不会产生找零，记进来只会凭空虚增可花余额，下一笔转账就会构造失败。
  ///
  /// 现在还没有调用方——BTC 发送尚未实现，所以 [UtxoSet.ownTxids] 恒为空集，
  /// 未确认收入一律不计入可花余额。这是安全的一侧。
  void record(String txid) => state = {...state, txid: DateTime.now().millisecondsSinceEpoch};

  /// 丢弃超过 [_ttl] 的记录。刻意只在 [build] 里做一次：
  /// 每次读余额都顺手改一遍状态，会在 provider 构建期间触发别的 provider 重建。
  BroadcastState _withoutExpired(BroadcastState state) {
    final cutoff = DateTime.now().subtract(_ttl).millisecondsSinceEpoch;
    return {
      for (final entry in state.entries)
        if (entry.value >= cutoff) entry.key: entry.value,
    };
  }
}

final broadcastHistoryProvider = NotifierProvider<BroadcastHistoryNotifier, BroadcastState>(
  BroadcastHistoryNotifier.new,
);
