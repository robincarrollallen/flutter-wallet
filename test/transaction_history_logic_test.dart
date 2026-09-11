import 'package:flutter_test/flutter_test.dart';
import 'package:wallet/domain/transaction_record.dart';
import 'package:wallet/features/wallet/transaction_history/logic.dart';

TransactionRecord _record({
  required String hash,
  String chainId = 'ethereum-sepolia',
  String walletId = 'wallet-1',
  TransactionStatus status = TransactionStatus.pending,
  DateTime? submittedAt,
}) {
  return TransactionRecord(
    transactionHash: hash,
    walletId: walletId,
    chainId: chainId,
    symbol: 'ETH',
    fromAddress: '0xfrom',
    toAddress: '0xto',
    amount: '1.5',
    submittedAt: submittedAt ?? DateTime(2026, 9, 11, 10),
    status: status,
  );
}

void main() {
  group('mergeTransactions', () {
    test('同链同哈希视为同一笔，以新记录为准', () {
      final merged = mergeTransactions(
        [_record(hash: '0xaa', status: TransactionStatus.pending)],
        [_record(hash: '0xaa', status: TransactionStatus.confirmed)],
      );

      expect(merged, hasLength(1));
      expect(merged.single.status, TransactionStatus.confirmed);
    });

    test('合并时保留本地的提交时刻——远程只知道打包时刻', () {
      final localSubmittedAt = DateTime(2026, 9, 11, 10);
      final merged = mergeTransactions(
        [_record(hash: '0xaa', submittedAt: localSubmittedAt)],
        [_record(hash: '0xaa', submittedAt: DateTime(2026, 9, 11, 12), status: TransactionStatus.confirmed)],
      );

      expect(merged.single.submittedAt, localSubmittedAt);
    });

    test('同一个哈希在不同链上是两笔交易', () {
      final merged = mergeTransactions(
        [_record(hash: '0xaa', chainId: 'ethereum-sepolia')],
        [_record(hash: '0xaa', chainId: 'base-sepolia')],
      );

      expect(merged, hasLength(2));
    });

    test('超出上限时丢弃最旧的', () {
      final existing = [
        for (var index = 0; index < 5; index++)
          _record(hash: '0x$index', submittedAt: DateTime(2026, 9, index + 1)),
      ];

      final merged = mergeTransactions(existing, const [], maximum: 3);

      expect(merged, hasLength(3));
      expect(merged.first.submittedAt, DateTime(2026, 9, 5));
      expect(merged.last.submittedAt, DateTime(2026, 9, 3));
    });
  });

  test('sortByTimeDescending 最新在前', () {
    final sorted = sortByTimeDescending([
      _record(hash: '0xold', submittedAt: DateTime(2026, 9, 1)),
      _record(hash: '0xnew', submittedAt: DateTime(2026, 9, 11)),
    ]);

    expect(sorted.map((record) => record.transactionHash), ['0xnew', '0xold']);
  });

  test('filterTransactions 按钱包与链筛选，null 表示不限', () {
    final records = [
      _record(hash: '0xa', walletId: 'wallet-1', chainId: 'ethereum-sepolia'),
      _record(hash: '0xb', walletId: 'wallet-1', chainId: 'tron-nile'),
      _record(hash: '0xc', walletId: 'wallet-2', chainId: 'ethereum-sepolia'),
    ];

    expect(filterTransactions(records), hasLength(3));
    expect(filterTransactions(records, walletId: 'wallet-1'), hasLength(2));
    expect(filterTransactions(records, walletId: 'wallet-1', chainId: 'tron-nile'), hasLength(1));
  });

  test('groupByDay 按本地日历日分组，同一天的不同时刻落进同一组', () {
    final grouped = groupByDay([
      _record(hash: '0xa', submittedAt: DateTime(2026, 9, 11, 9)),
      _record(hash: '0xb', submittedAt: DateTime(2026, 9, 11, 23)),
      _record(hash: '0xc', submittedAt: DateTime(2026, 9, 10, 8)),
    ]);

    expect(grouped.keys, [DateTime(2026, 9, 11), DateTime(2026, 9, 10)]);
    expect(grouped[DateTime(2026, 9, 11)], hasLength(2));
  });

  test('pendingRecordsToRefresh 只取 pending 且有条数上限', () {
    final records = [
      for (var index = 0; index < 30; index++)
        _record(hash: '0xp$index', submittedAt: DateTime(2026, 9, 1).add(Duration(minutes: index))),
      _record(hash: '0xdone', status: TransactionStatus.confirmed),
    ];

    final pending = pendingRecordsToRefresh(records, maximum: 20);

    expect(pending, hasLength(20));
    expect(pending.every((record) => record.status == TransactionStatus.pending), isTrue);
  });

  test('shortenAddress 缩略长地址、原样返回短地址', () {
    expect(shortenAddress('0x1234567890abcdef1234'), '0x1234…1234');
    expect(shortenAddress('0xabcd'), '0xabcd');
  });

  test('TransactionRecord JSON 往返保真', () {
    final original = _record(hash: '0xaa', status: TransactionStatus.confirmed);
    final restored = TransactionRecord.fromJson(original.toJson());

    expect(restored, isNotNull);
    expect(restored!.transactionHash, original.transactionHash);
    expect(restored.status, TransactionStatus.confirmed);
    expect(restored.submittedAt, original.submittedAt);
    expect(restored.direction, TransactionDirection.outgoing);
  });

  test('脏数据整条丢弃，不拖垮整个列表的恢复', () {
    expect(TransactionRecord.fromJson({'transactionHash': '0xaa'}), isNull);
  });
}
