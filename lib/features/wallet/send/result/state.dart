import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../enums/transaction_status.dart';
import '../../../../providers/core/service_provider.dart';
import '../../../../providers/modules/transaction/transaction_history_provider.dart';

/// 结果页轮询的间隔。EVM 出块 12 秒、Tron 3 秒，3 秒一轮足够跟上，又不至于把节点打爆。
const Duration sendResultPollInterval = Duration(seconds: 3);

/// 结果页轮询的最大轮数（约 1 分钟）。
///
/// 必须有上限：用户把 App 挂在结果页忘了，无上限就是一个永远在打 RPC 的后台任务。
/// 超出后停下，状态维持 pending，后续由历史页的下拉刷新接管回填。
const int sendResultMaxPolls = 20;

/// 一笔交易在历史里的当前状态。找不到记录（比如历史被清空）时按 pending 处理。
///
/// 结果页读它而不是读路由参数：状态只有 [transactionHistoryProvider] 一个来源，
/// 结果页与历史页看到的永远是同一份，不会两处不一致。
final sendResultStatusProvider = Provider.family<TransactionStatus, ({String chainId, String transactionHash})>((
  ref,
  target,
) {
  final identity = '${target.chainId}:${target.transactionHash}';
  final record = ref.watch(transactionHistoryProvider).where((record) => record.identity == identity).firstOrNull;
  return record?.status ?? TransactionStatus.pending;
});

/// 结果页的有界轮询：查到终态或轮满 [sendResultMaxPolls] 次即停，结果写回历史。
///
/// 生命周期挂在结果页上（页面 dispose 时调 [stop]）——用户点「完成」走人就不再发请求，
/// 这正是把轮询放在 service 层里 fire-and-forget 做不到的。
class SendResultStatusPoller {
  SendResultStatusPoller(this._ref, {required this.chainId, required this.transactionHash});

  final Ref _ref;
  final String chainId;
  final String transactionHash;

  Timer? _timer;
  int _polls = 0;

  /// 开始轮询。已在轮询中则忽略，避免重复启动叠加请求。
  void start() {
    if (_timer != null) return;
    _timer = Timer.periodic(sendResultPollInterval, (_) => _poll());
  }

  /// 停止轮询。可重复调用。
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _poll() async {
    if (_polls >= sendResultMaxPolls) {
      stop();
      return;
    }
    _polls++;

    final TransactionStatus status;
    try {
      status = await _ref.read(walletServiceProvider).queryTransactionStatus(chainId, transactionHash);
    } catch (_) {
      // 节点抖动不该中断轮询，也不该惊动用户——这一轮跳过，等下一轮。
      return;
    }
    if (status == TransactionStatus.pending) return;

    stop(); // 终态不会再变，没必要继续查。
    _ref.read(transactionHistoryProvider.notifier).updateStatus(chainId, transactionHash, status);
  }
}

/// 按「链 + 哈希」建轮询器。autoDispose：结果页销毁后连同轮询器一起回收。
final sendResultStatusPollerProvider =
    Provider.autoDispose.family<SendResultStatusPoller, ({String chainId, String transactionHash})>((ref, target) {
      final poller = SendResultStatusPoller(
        ref,
        chainId: target.chainId,
        transactionHash: target.transactionHash,
      );
      ref.onDispose(poller.stop);
      return poller;
    });
