import 'dart:convert';

import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:on_chain/solana/solana.dart';
import 'package:wallet_core/chains.dart';
import 'package:wallet_core/wallet_core.dart';

const _chain = SupportedChains.solanaDevnet;

/// 测试用私钥；地址由它现场派生，不写死。
final _privateKey = List<int>.filled(32, 7);
final _signer = SolanaPrivateKey.fromSeed(_privateKey);
final _owner = _signer.publicKey().toAddress();

/// 收款方与 blockhash 同样由私钥派生——写死 base58 字面量很容易拼出长度或
/// 字符集不合法的值，SolAddress 会直接拒绝。
final _recipient = SolanaPrivateKey.fromSeed(List<int>.filled(32, 9)).publicKey().toAddress();
final _blockhash = SolanaPrivateKey.fromSeed(List<int>.filled(32, 11)).publicKey().toAddress();

/// 租金豁免线：0 字节账户。取 devnet 实测值——这个数各网不同，代码里也从不写死。
final _rentExempt = BigInt.from(650240);

/// 每签名费。
final _fee = BigInt.from(5000);

/// 假 Solana 节点：按 JSON-RPC method 返回预设响应，并记录每次调用。
class _FakeSolanaService with SolanaServiceProvider {
  _FakeSolanaService({
    BigInt? balance,
    BigInt? recipientBalance,
    this.signatureStatus = const {'confirmationStatus': 'finalized', 'slot': 1, 'err': null},
    this.statusFound = true,
    this.prioritizationFees = const [],
    this.blockHeight = 50,
    this.genesisHash = 'EtWTRABZaYq6iMfeYKouRu166VU2xqa1wcaWoxPkrZBG',
  }) : balance = balance ?? BigInt.from(1000000000), // 1 SOL
       recipientBalance = recipientBalance ?? _rentExempt;

  /// 发送方余额（lamport）。
  final BigInt balance;

  /// 收款方余额（lamport）。默认已达豁免线，设为 0 可模拟全新账户。
  final BigInt recipientBalance;

  /// `getSignatureStatuses` 返回的单条状态。
  final Map<String, dynamic> signatureStatus;

  /// 交易是否已被节点看到。false 时状态返回 null（刚广播、还没上链）。
  final bool statusFound;

  /// `getRecentPrioritizationFees` 的样本（micro-lamport / 计算单元）。
  /// 默认空 = 链不拥堵，三档都不付优先费。
  final List<int> prioritizationFees;

  /// 当前区块高度。默认 50，小于 blockhash 的 lastValidBlockHeight（100）= 交易尚未过期。
  final int blockHeight;

  /// 节点自称的创世哈希。默认 Nile/devnet 钉死值，测换网时改成主网哈希。
  final String genesisHash;

  final calls = <String>[];

  /// 广播时收到的 base64 交易，供断言签名确实发出去了。
  String? broadcastPayload;

  @override
  Future<SolanaServiceResponse> doRequest(SolanaRequestDetails params, {Duration? timeout}) async {
    final body = jsonDecode(params.bodyString!) as Map<String, dynamic>;
    final method = body['method'] as String;
    calls.add(method);
    final requestParams = body['params'] as List<dynamic>;

    final result = switch (method) {
      'getLatestBlockhash' => {
        'context': {'slot': 1},
        'value': {'blockhash': _blockhash.address, 'lastValidBlockHeight': 100},
      },
      'getGenesisHash' => genesisHash,
      'getFeeForMessage' => {
        'context': {'slot': 1},
        'value': _fee.toInt(),
      },
      'getMinimumBalanceForRentExemption' => _rentExempt.toInt(),
      // 按查询的地址分流：发送方与收款方的余额是两个不同的断言点。
      'getBalance' => {
        'context': {'slot': 1},
        'value': (requestParams.first == _owner.address ? balance : recipientBalance).toInt(),
      },
      'sendTransaction' => _broadcast(requestParams),
      'getRecentPrioritizationFees' => [
        for (final (index, fee) in prioritizationFees.indexed) {'slot': index + 1, 'prioritizationFee': fee},
      ],
      'getBlockHeight' => blockHeight,
      'getSignatureStatuses' => {
        'context': {'slot': 1},
        'value': [statusFound ? signatureStatus : null],
      },
      _ => throw StateError('未预设的 RPC 方法: $method'),
    };

    return ServiceSuccessRespose(statusCode: 200, response: jsonEncode({'jsonrpc': '2.0', 'id': body['id'], 'result': result}));
  }

  String _broadcast(List<dynamic> requestParams) {
    broadcastPayload = requestParams.first as String;
    return 'signature-abc';
  }
}

SolanaTransactionService _service(_FakeSolanaService node) => SolanaTransactionService(provider: SolanaProvider(node));

/// 从广播出去的 base64 交易里解出那条 SystemProgram 转账指令。
///
/// 不能再用 `compiledInstructions.single`：现在每笔交易都带两条 ComputeBudget 指令
/// （声明计算单元上限与优先单价），转账指令只是其中之一。
({SolAddress recipient, BigInt lamports}) _transferOf(String base64Transaction) {
  final transaction = SolanaTransaction.deserialize(StringUtils.encode(base64Transaction, encoding: StringEncoding.base64));
  final message = transaction.message;
  final instruction = message.compiledInstructions.firstWhere((candidate) => message.accountKeys[candidate.programIdIndex] == SystemProgramConst.programId);
  final layout = SystemProgramLayout.fromBytes(instruction.data) as SystemTransferLayout;
  return (recipient: message.accountKeys[instruction.accounts[1]], lamports: layout.lamports);
}

/// 广播出去的交易里声明的优先单价（micro-lamport / 计算单元）。
BigInt _computeUnitPriceOf(String base64Transaction) {
  final transaction = SolanaTransaction.deserialize(StringUtils.encode(base64Transaction, encoding: StringEncoding.base64));
  final message = transaction.message;
  for (final instruction in message.compiledInstructions) {
    if (message.accountKeys[instruction.programIdIndex] != ComputeBudgetConst.programId) continue;
    final layout = ComputeBudgetProgramLayout.fromBytes(instruction.data);
    if (layout is ComputeBudgetSetComputeUnitPriceLayout) return layout.microLamports;
  }
  throw StateError('交易里没有 SetComputeUnitPrice 指令');
}

void main() {
  group('SolanaTransactionService.sendNative', () {
    test('广播成功后返回签名与 pending，不等上链', () async {
      final node = _FakeSolanaService();

      final result = await _service(node).sendNative(chain: _chain, privateKey: _privateKey, fromAddress: _owner.address, to: _recipient.address, amount: '0.1');

      expect(result.hash, 'signature-abc');
      expect(result.sentAmount, '0.1');
      // 广播只代表节点收下了，此处必须是 pending——由结果页与历史页回填。
      expect(result.status, TransactionStatus.pending);
      expect(node.broadcastPayload, isNotNull);
      expect(node.calls, contains('sendTransaction'));
    });

    test('一次发送只取一次 blockhash：估费与签名共用', () async {
      final node = _FakeSolanaService();

      await _service(node).sendNative(chain: _chain, privateKey: _privateKey, fromAddress: _owner.address, to: _recipient.address, amount: '0.1');

      // 估费那次和签名那次是同一个 blockhash，多取一次就是一轮白费的往返。
      expect(node.calls.where((m) => m == 'getLatestBlockhash'), hasLength(1));
    });

    test('节点返回主网创世哈希时中止签名', () async {
      final node = _FakeSolanaService(genesisHash: '5eykt4UsFv8P8NJdTREpY1vzq2piYYL4jUksMNPE5cyk');
      await expectLater(
        _service(node).sendNative(chain: _chain, privateKey: _privateKey, fromAddress: _owner.address, to: _recipient.address, amount: '0.1'),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('节点不在'))),
      );
      expect(node.broadcastPayload, isNull);
    });

    test('广播出去的是一笔签名有效、收款方与金额正确的转账', () async {
      final node = _FakeSolanaService();

      await _service(node).sendNative(chain: _chain, privateKey: _privateKey, fromAddress: _owner.address, to: _recipient.address, amount: '0.1');

      final sent = SolanaTransaction.deserialize(StringUtils.encode(node.broadcastPayload!, encoding: StringEncoding.base64));
      // areSignaturesReady 不只看「有没有填」，它会逐个 verify 签名本身。
      expect(sent.areSignaturesReady(), isTrue);

      // 指令里的收款方与金额必须与入参一致——这是整个链路的意图落地点。
      final transfer = _transferOf(node.broadcastPayload!);
      expect(transfer.recipient, _recipient);
      expect(transfer.lamports, BigInt.from(100000000));
    });

    test('签名地址与钱包地址不一致时拒绝发送', () async {
      final node = _FakeSolanaService();

      await expectLater(
        _service(node).sendNative(
          chain: _chain,
          privateKey: _privateKey,
          fromAddress: _recipient.address, // 不是这把私钥的地址
          to: _recipient.address,
          amount: '0.1',
        ),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('签名地址与钱包地址不一致'))),
      );
      expect(node.calls, isNot(contains('sendTransaction')));
    });

    test('余额不足时报错，绝不静默改小金额', () async {
      final node = _FakeSolanaService(balance: BigInt.from(1000000)); // 0.001 SOL

      await expectLater(
        _service(node).sendNative(chain: _chain, privateKey: _privateKey, fromAddress: _owner.address, to: _recipient.address, amount: '0.1'),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('余额不足'))),
      );
      expect(node.calls, isNot(contains('sendTransaction')));
    });

    test('全额转出时从转出额里扣掉网络费', () async {
      final balance = BigInt.from(1000000000); // 1 SOL
      final node = _FakeSolanaService(balance: balance);

      final result = await _service(node).sendNative(
        chain: _chain,
        privateKey: _privateKey,
        fromAddress: _owner.address,
        to: _recipient.address,
        amount: '1', // 全额，与余额相等 → 加上费用就超了
        deductFeeFromAmount: true,
      );

      // 实发 = 余额 − 每签名费，账户被清空（余额 0 是合法的）。
      expect(result.sentAmount, '0.999995');
      expect(_transferOf(node.broadcastPayload!).lamports, balance - _fee);
    });

    test('向新账户转账低于租金豁免线时拦下', () async {
      // 收款方余额 0 = 链上还不存在，转 0.0001 SOL 达不到豁免线。
      final node = _FakeSolanaService(recipientBalance: BigInt.zero);

      await expectLater(
        _service(node).sendNative(chain: _chain, privateKey: _privateKey, fromAddress: _owner.address, to: _recipient.address, amount: '0.0001'),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('租金豁免线'))),
      );
      expect(node.calls, isNot(contains('sendTransaction')));
    });

    test('收款方已过豁免线时，小额转账照常放行', () async {
      // 同样是 0.0001 SOL，但收款方已有余额——不该被上一条规则误伤。
      final node = _FakeSolanaService(recipientBalance: _rentExempt);

      final result = await _service(node).sendNative(chain: _chain, privateKey: _privateKey, fromAddress: _owner.address, to: _recipient.address, amount: '0.0001');

      expect(result.status, TransactionStatus.pending);
    });

    test('转出后自己的余额卡在 0 与豁免线之间时拦下', () async {
      // 余额 1 SOL，转掉 0.9999999 后只剩几百 lamport——账户会被链上回收。
      final node = _FakeSolanaService(balance: BigInt.from(1000000000));

      await expectLater(
        _service(node).sendNative(chain: _chain, privateKey: _privateKey, fromAddress: _owner.address, to: _recipient.address, amount: '0.999994'),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('转出后余额将低于租金豁免线'))),
      );
      expect(node.calls, isNot(contains('sendTransaction')));
    });
  });

  group('SolanaTransactionService.waitForReceipt', () {
    Future<TransactionStatus> statusOf(_FakeSolanaService node) => _service(node).waitForReceipt(_chain, 'signature-abc');

    test('finalized 视为已确认', () async {
      final node = _FakeSolanaService(signatureStatus: const {'confirmationStatus': 'finalized', 'slot': 1, 'err': null});
      expect(await statusOf(node), TransactionStatus.confirmed);
    });

    test('confirmed 视为已确认', () async {
      final node = _FakeSolanaService(signatureStatus: const {'confirmationStatus': 'confirmed', 'slot': 1, 'err': null});
      expect(await statusOf(node), TransactionStatus.confirmed);
    });

    test('processed 仍算 pending——可能因分叉被回滚', () async {
      final node = _FakeSolanaService(signatureStatus: const {'confirmationStatus': 'processed', 'slot': 1, 'err': null});
      expect(await statusOf(node), TransactionStatus.pending);
    });

    test('err 非空即为失败，哪怕已经 finalized', () async {
      final node = _FakeSolanaService(
        signatureStatus: const {
          'confirmationStatus': 'finalized',
          'slot': 1,
          'err': {'InstructionError': <dynamic>[]},
        },
      );
      expect(await statusOf(node), TransactionStatus.failed);
    });

    test('查不到交易时返回 pending', () async {
      final node = _FakeSolanaService(statusFound: false);
      expect(await statusOf(node), TransactionStatus.pending);
    });
  });

  group('优先费三档', () {
    // 近期区块的优先费样本；三档取 10 / 50 / 90 分位 → 0 / 1000 / 5000。
    const samples = [0, 1000, 5000];

    /// 优先费 = 单价 × 计算单元上限(600) ÷ 1e6，向上取整。
    /// 1000 → 0.6 → 1；5000 → 3.0 → 3。
    test('各档按近期区块优先费的分位数出价', () async {
      final node = _FakeSolanaService(prioritizationFees: samples);
      final estimate = await _service(node).estimateNativeFee(chain: _chain, from: _owner.address, to: _recipient.address, amount: '0.1');

      expect(estimate.baseFeeLamports, _fee);
      expect(estimate.quoteFor(FeeSpeed.slow).priorityFee, BigInt.zero);
      expect(estimate.quoteFor(FeeSpeed.normal).priorityFee, BigInt.one);
      expect(estimate.quoteFor(FeeSpeed.fast).priorityFee, BigInt.from(3));

      // 总费用 = 签名费 + 优先费；签名费三档同价。
      expect(estimate.quoteFor(FeeSpeed.slow).expectedFee, _fee);
      expect(estimate.quoteFor(FeeSpeed.fast).expectedFee, _fee + BigInt.from(3));
    });

    test('链不拥堵（无样本）时三档同价，都不付优先费', () async {
      final node = _FakeSolanaService();
      final estimate = await _service(node).estimateNativeFee(chain: _chain, from: _owner.address, to: _recipient.address, amount: '0.1');

      for (final speed in FeeSpeed.values) {
        expect(estimate.quoteFor(speed).expectedFee, _fee, reason: '$speed 不该凭空多出优先费');
      }
    });

    test('选中的档位会原样写进交易的 SetComputeUnitPrice', () async {
      final node = _FakeSolanaService(prioritizationFees: samples);

      await _service(node).sendNative(chain: _chain, privateKey: _privateKey, fromAddress: _owner.address, to: _recipient.address, amount: '0.1', speed: FeeSpeed.fast);

      // 估费与实扣必须是同一个数：估的是 90 分位，发出去的也得是 90 分位。
      expect(_computeUnitPriceOf(node.broadcastPayload!), BigInt.from(5000));
    });

    test('MAX 全额转出按所选档位扣费', () async {
      final balance = BigInt.from(1000000000);
      final node = _FakeSolanaService(balance: balance, prioritizationFees: samples);

      final result = await _service(node)
          .sendNative(chain: _chain, privateKey: _privateKey, fromAddress: _owner.address, to: _recipient.address, amount: '1', speed: FeeSpeed.fast, deductFeeFromAmount: true);

      // 快速档要多扣 3 lamport 的优先费，不能只扣签名费。
      expect(_transferOf(node.broadcastPayload!).lamports, balance - _fee - BigInt.from(3));
      expect(result.sentAmount, formatUnits(balance - _fee - BigInt.from(3), _chain.decimals));
    });
  });

  group('交易过期（blockhash 失效）', () {
    test('广播结果带回失效高度', () async {
      final node = _FakeSolanaService();
      final result = await _service(node).sendNative(chain: _chain, privateKey: _privateKey, fromAddress: _owner.address, to: _recipient.address, amount: '0.1');

      // 没有它，回填时就分不清「还在等」和「已经死透」。
      expect(result.validUntilBlock, 100);
    });

    test('查不到交易且已越过失效高度 → expired', () async {
      // 高度 200 > lastValidBlockHeight 100，且签名查不到：这笔永远不会上链了。
      final node = _FakeSolanaService(statusFound: false, blockHeight: 200);

      final status = await _service(node).waitForReceipt(_chain, 'signature-abc', validUntilBlock: 100);

      expect(status, TransactionStatus.expired);
      expect(status.isFinal, isTrue, reason: '终态才能让轮询停下来');
    });

    test('查不到交易但还没到失效高度 → 仍是 pending', () async {
      final node = _FakeSolanaService(statusFound: false, blockHeight: 50);

      final status = await _service(node).waitForReceipt(_chain, 'signature-abc', validUntilBlock: 100);

      expect(status, TransactionStatus.pending);
    });

    test('不给失效高度时绝不判过期——别的链没有这个概念', () async {
      final node = _FakeSolanaService(statusFound: false, blockHeight: 99999);

      final status = await _service(node).waitForReceipt(_chain, 'signature-abc');

      expect(status, TransactionStatus.pending);
      expect(node.calls, isNot(contains('getBlockHeight')), reason: '没有判定依据就不该白发这轮请求');
    });

    test('已上链的交易不会因高度越界被误判成过期', () async {
      // 高度早已越过失效高度，但签名查得到且已 finalized —— 必须是 confirmed。
      final node = _FakeSolanaService(blockHeight: 999999);

      final status = await _service(node).waitForReceipt(_chain, 'signature-abc', validUntilBlock: 100);

      expect(status, TransactionStatus.confirmed);
    });
  });

  group('SolanaTransferService', () {
    // 构造不触发任何平台调用；下面的用例也都在解析私钥之前就返回了。
    final service = SolanaTransferService(PrivateKeyResolver(SecureWalletStorage()));

    test('原生币与 SPL 代币都声明支持', () {
      expect(service.kind, ChainKind.solana);
      expect(service.supportsNative, isTrue);
      // 发送页按这个标志决定要不要把该链的代币列进可选资产。
      expect(service.supportsToken, isTrue);
    });
  });
}
