import 'package:flutter_test/flutter_test.dart';
import 'package:wallet/blockchain/chain_registry.dart';
import 'package:wallet/domain/transaction_record.dart';
import 'package:wallet/services/history/bitcoin_transaction_history_service.dart';
import 'package:wallet/services/history/evm_transaction_history_service.dart';
import 'package:wallet/services/history/solana_transaction_history_service.dart';
import 'package:wallet/services/history/tron_transaction_history_service.dart';

// 各家浏览器响应的解析。只测解析，不测网络：网络那一层是 rest_client / json_rpc 的事，
// 这里关心的是「同一笔链上交易怎么变成一条 TransactionRecord」——方向、金额换算、
// 失败状态、翻页游标，每一项错了都会直接显示给用户。

const _wallet = 'wallet-1';

void main() {
  group('Etherscan（EVM）', () {
    const chain = SupportedChains.ethereumSepolia;
    const own = '0xAAAA000000000000000000000000000000000001';
    const other = '0xBBBB000000000000000000000000000000000002';

    Map<String, dynamic> nativeEntry({String from = own, String to = other, String isError = '0'}) => {
      'hash': '0xhash',
      'from': from,
      'to': to,
      'value': '1500000000000000000', // 1.5 ETH
      'timeStamp': '1757894400',
      'blockNumber': '8000001',
      'gasUsed': '21000',
      'gasPrice': '1000000000', // 21000 × 1 gwei = 0.000021 ETH
      'isError': isError,
      'txreceipt_status': '1',
    };

    test('原生转账：方向、金额、手续费、区块高度都解析出来', () {
      final page = parseEtherscanPage(
        nativeResults: [nativeEntry()],
        tokenResults: const [],
        chain: chain,
        address: own,
        walletId: _wallet,
        page: 1,
        limit: 25,
      );

      final record = page.records.single;
      expect(record.direction, TransactionDirection.outgoing);
      expect(record.amount, '1.5');
      expect(record.symbol, 'ETH');
      expect(record.isNativeCoin, isTrue);
      expect(record.feeAmount, '0.000021');
      expect(record.blockNumber, 8000001);
      expect(record.status, TransactionStatus.confirmed);
      // 远程记录没有本机提交时刻，两个时间都取区块时间。
      expect(record.confirmedAt, record.submittedAt);
    });

    test('方向判定忽略大小写——Etherscan 返回的地址是全小写的', () {
      final page = parseEtherscanPage(
        nativeResults: [nativeEntry(from: own.toLowerCase())],
        tokenResults: const [],
        chain: chain,
        address: own,
        walletId: _wallet,
        page: 1,
        limit: 25,
      );

      expect(page.records.single.direction, TransactionDirection.outgoing);
    });

    test('收款方向：from 不是自己就是转入', () {
      final page = parseEtherscanPage(
        nativeResults: [nativeEntry(from: other, to: own)],
        tokenResults: const [],
        chain: chain,
        address: own,
        walletId: _wallet,
        page: 1,
        limit: 25,
      );

      expect(page.records.single.direction, TransactionDirection.incoming);
    });

    test('失败交易标成 failed，不能当成功', () {
      final page = parseEtherscanPage(
        nativeResults: [nativeEntry(isError: '1')],
        tokenResults: const [],
        chain: chain,
        address: own,
        walletId: _wallet,
        page: 1,
        limit: 25,
      );

      expect(page.records.single.status, TransactionStatus.failed);
    });

    test('代币精度取接口返回值，不查本地目录', () {
      final page = parseEtherscanPage(
        nativeResults: const [],
        tokenResults: [
          {
            'hash': '0xtoken',
            'from': own,
            'to': other,
            'value': '2500000', // 6 位精度 => 2.5
            'timeStamp': '1757894400',
            'blockNumber': '8000002',
            'tokenDecimal': '6',
            'tokenSymbol': 'USDC',
            'contractAddress': '0xcontract',
          },
        ],
        chain: chain,
        address: own,
        walletId: _wallet,
        page: 1,
        limit: 25,
      );

      final record = page.records.single;
      expect(record.amount, '2.5');
      expect(record.symbol, 'USDC');
      expect(record.tokenIdentifier, '0xcontract');
      expect(record.isNativeCoin, isFalse);
    });

    test('满页给出下一页页码，不满页表示到底', () {
      final full = parseEtherscanPage(
        nativeResults: List.filled(2, nativeEntry()),
        tokenResults: const [],
        chain: chain,
        address: own,
        walletId: _wallet,
        page: 3,
        limit: 2,
      );
      final partial = parseEtherscanPage(
        nativeResults: [nativeEntry()],
        tokenResults: const [],
        chain: chain,
        address: own,
        walletId: _wallet,
        page: 3,
        limit: 2,
      );

      expect(full.nextCursor, '4');
      expect(partial.nextCursor, isNull);
    });
  });

  group('Solana', () {
    const chain = SupportedChains.solanaDevnet;
    const own = 'OwnPubkey';
    const other = 'OtherPubkey';

    Map<String, dynamic> detail({Object? err, int ownIndex = 0}) => {
      'slot': 123,
      'blockTime': 1757894400,
      'transaction': {
        'message': {
          'accountKeys': ownIndex == 0
              ? [
                  {'pubkey': own},
                  {'pubkey': other},
                ]
              : [
                  {'pubkey': other},
                  {'pubkey': own},
                ],
        },
      },
      'meta': {
        'err': err,
        'fee': 5000,
        // 付款方少了 1 SOL + 手续费，收款方多了 1 SOL。
        'preBalances': ownIndex == 0 ? [2000000000, 0] : [2000000000, 0],
        'postBalances': ownIndex == 0 ? [999995000, 1000000000] : [999995000, 1000000000],
      },
    };

    test('原生转出：金额刨掉自己付的手续费', () {
      final record = parseSolanaTransaction(detail(), hash: '0xsig', chain: chain, address: own, walletId: _wallet)!;

      expect(record.direction, TransactionDirection.outgoing);
      // 余额差是 1.000005 SOL，其中 0.000005 是手续费，转出的是整 1 SOL。
      expect(record.amount, '1');
      expect(record.feeAmount, '0.000005');
      expect(record.toAddress, other);
      expect(record.blockNumber, 123);
    });

    test('收款方向：不是 fee payer 时不记手续费', () {
      final record = parseSolanaTransaction(
        detail(ownIndex: 1),
        hash: '0xsig',
        chain: chain,
        address: own,
        walletId: _wallet,
      )!;

      expect(record.direction, TransactionDirection.incoming);
      expect(record.amount, '1');
      expect(record.feeAmount, isNull);
      expect(record.fromAddress, other);
    });

    test('链上失败的交易标成 failed', () {
      final record = parseSolanaTransaction(
        detail(err: {'InstructionError': []}),
        hash: '0xsig',
        chain: chain,
        address: own,
        walletId: _wallet,
      )!;

      expect(record.status, TransactionStatus.failed);
    });

    test('SPL 代币按代币账户余额差算，精度取链上返回值', () {
      final withToken = detail();
      (withToken['meta'] as Map<String, dynamic>).addAll({
        'preTokenBalances': [
          {
            'owner': own,
            'mint': 'MintAddress',
            'uiTokenAmount': {'amount': '5000000', 'decimals': 6},
          },
        ],
        'postTokenBalances': [
          {
            'owner': own,
            'mint': 'MintAddress',
            'uiTokenAmount': {'amount': '2500000', 'decimals': 6},
          },
        ],
      });

      final record = parseSolanaTransaction(withToken, hash: '0xsig', chain: chain, address: own, walletId: _wallet)!;

      expect(record.tokenIdentifier, 'MintAddress');
      expect(record.amount, '2.5');
      expect(record.direction, TransactionDirection.outgoing);
    });

    test('这笔交易没动自己的余额时整条丢弃', () {
      final untouched = detail();
      (untouched['meta'] as Map<String, dynamic>)['postBalances'] = [2000000000 - 5000, 0];

      expect(parseSolanaTransaction(untouched, hash: '0xsig', chain: chain, address: own, walletId: _wallet), isNull);
    });
  });

  group('TronGrid', () {
    const chain = SupportedChains.tronNile;
    // 41 开头的 hex 与它对应的 base58，TronGrid 原生接口返回前者。
    const ownHex = '4198927ffb9f554dc4a453c64b2e553a02d6df514b';
    const ownBase58 = 'TPswDDCAWhJAZGdHPidFg5nEf8TkNToDX1';
    const otherHex = '41e552f6487585c2b58bc2c9bb4492bc1f17132cd0';

    Map<String, dynamic> nativeTx({String from = ownHex, String to = otherHex, String ret = 'SUCCESS'}) => {
      'txID': '0xtron',
      'block_timestamp': 1757894400000,
      'ret': [
        {'contractRet': ret, 'fee': 1100000},
      ],
      'raw_data': {
        'contract': [
          {
            'type': 'TransferContract',
            'parameter': {
              'value': {'owner_address': from, 'to_address': to, 'amount': 1500000},
            },
          },
        ],
      },
    };

    test('TRX 转账：hex 地址换成 base58，金额按 6 位精度换算', () {
      final page = parseTronPage(
        nativeResponse: {
          'data': [nativeTx()],
        },
        tokenResponse: const {},
        chain: chain,
        address: ownBase58,
        walletId: _wallet,
      );

      final record = page.records.single;
      expect(record.fromAddress, ownBase58);
      expect(record.direction, TransactionDirection.outgoing);
      expect(record.amount, '1.5');
      expect(record.feeAmount, '1.1');
    });

    test('contractRet 不是 SUCCESS 就是失败', () {
      final page = parseTronPage(
        nativeResponse: {
          'data': [nativeTx(ret: 'OUT_OF_ENERGY')],
        },
        tokenResponse: const {},
        chain: chain,
        address: ownBase58,
        walletId: _wallet,
      );

      expect(page.records.single.status, TransactionStatus.failed);
    });

    test('只认 TransferContract：质押、投票之类的不进历史', () {
      final staking = nativeTx();
      ((staking['raw_data'] as Map)['contract'] as List).first['type'] = 'FreezeBalanceV2Contract';

      final page = parseTronPage(
        nativeResponse: {
          'data': [staking],
        },
        tokenResponse: const {},
        chain: chain,
        address: ownBase58,
        walletId: _wallet,
      );

      expect(page.records, isEmpty);
    });

    test('TRC-20 条目的地址已是 base58，精度取 token_info', () {
      final page = parseTronPage(
        nativeResponse: const {},
        tokenResponse: {
          'data': [
            {
              'transaction_id': '0xtrc20',
              'from': 'TOtherAddress',
              'to': ownBase58,
              'value': '3000000',
              'block_timestamp': 1757894400000,
              'token_info': {'symbol': 'USDT', 'decimals': 6, 'address': 'TContract'},
            },
          ],
        },
        chain: chain,
        address: ownBase58,
        walletId: _wallet,
      );

      final record = page.records.single;
      expect(record.direction, TransactionDirection.incoming);
      expect(record.amount, '3');
      expect(record.symbol, 'USDT');
      expect(record.tokenIdentifier, 'TContract');
    });

    test('两条接口都没有 next 才算到底；只剩一条能翻时另一段留空', () {
      const withNext = {
        'data': [],
        'meta': {
          'fingerprint': 'fp-native',
          'links': {'next': 'https://…'},
        },
      };
      const lastPage = {
        'data': [],
        'meta': {'fingerprint': 'fp-token'},
      };

      final more = parseTronPage(
        nativeResponse: withNext,
        tokenResponse: lastPage,
        chain: chain,
        address: ownBase58,
        walletId: _wallet,
      );
      final done = parseTronPage(
        nativeResponse: lastPage,
        tokenResponse: lastPage,
        chain: chain,
        address: ownBase58,
        walletId: _wallet,
      );

      expect(more.nextCursor, 'fp-native|');
      expect(done.nextCursor, isNull);
    });
  });

  group('mempool.space（Bitcoin）', () {
    const chain = SupportedChains.bitcoinTestnet;
    const own = 'tb1qown';
    const other = 'tb1qother';

    Map<String, dynamic> transaction({
      required List<dynamic> vin,
      required List<dynamic> vout,
      bool confirmed = true,
    }) => {
      'txid': '0xbtc',
      'fee': 1000,
      'vin': vin,
      'vout': vout,
      'status': {'confirmed': confirmed, 'block_height': 800001, 'block_time': 1757894400},
    };

    Map<String, dynamic> input(String address, int value) => {
      'prevout': {'scriptpubkey_address': address, 'value': value},
    };
    Map<String, dynamic> output(String address, int value) => {'scriptpubkey_address': address, 'value': value};

    test('付款：找零自动抵消，金额刨掉手续费', () {
      // 花掉 100000 聪，转出 60000，找零 39000，手续费 1000。
      final page = parseMempoolPage(
        entries: [
          transaction(vin: [input(own, 100000)], vout: [output(other, 60000), output(own, 39000)]),
        ],
        chain: chain,
        address: own,
        walletId: _wallet,
      );

      final record = page.records.single;
      expect(record.direction, TransactionDirection.outgoing);
      expect(record.amount, '0.0006'); // 60000 聪
      expect(record.feeAmount, '0.00001');
      expect(record.toAddress, other);
      expect(record.blockNumber, 800001);
    });

    test('收款：净额为正，手续费是对方付的不记在自己头上', () {
      final page = parseMempoolPage(
        entries: [
          transaction(vin: [input(other, 100000)], vout: [output(own, 60000), output(other, 39000)]),
        ],
        chain: chain,
        address: own,
        walletId: _wallet,
      );

      final record = page.records.single;
      expect(record.direction, TransactionDirection.incoming);
      expect(record.amount, '0.0006');
      expect(record.feeAmount, isNull);
      expect(record.fromAddress, other);
    });

    test('未确认交易是 pending，且没有上链时刻', () {
      final page = parseMempoolPage(
        entries: [
          transaction(vin: [input(own, 100000)], vout: [output(other, 60000), output(own, 39000)], confirmed: false),
        ],
        chain: chain,
        address: own,
        walletId: _wallet,
      );

      expect(page.records.single.status, TransactionStatus.pending);
      expect(page.records.single.confirmedAt, isNull);
    });

    test('与自己无关的交易（净额为零）不进历史', () {
      final page = parseMempoolPage(
        entries: [
          transaction(vin: [input(other, 100000)], vout: [output(other, 99000)]),
        ],
        chain: chain,
        address: own,
        walletId: _wallet,
      );

      expect(page.records, isEmpty);
    });

    test('游标是本页最后一条 txid，空页表示到底', () {
      final page = parseMempoolPage(
        entries: [
          transaction(vin: [input(own, 100000)], vout: [output(other, 60000), output(own, 39000)]),
        ],
        chain: chain,
        address: own,
        walletId: _wallet,
      );
      final empty = parseMempoolPage(entries: const [], chain: chain, address: own, walletId: _wallet);

      expect(page.nextCursor, '0xbtc');
      expect(empty.nextCursor, isNull);
    });
  });
}
