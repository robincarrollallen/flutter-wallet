import 'dart:convert';

import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:on_chain/aptos/aptos.dart';
import 'package:wallet_core/chains.dart';
import 'package:wallet_core/rpc.dart';
import 'package:wallet_core/wallet_core.dart';

/// Aptos 原生转账的离线测试。
///
/// 与 `solana_transfer_test.dart` 同一形态：**全程不碰网络**，节点由 [_FakeAptosService]
/// 假扮，按 REST 路径路由预设响应并录下发出去的请求。断言一律**反序列化提交的字节**
/// 再看里面是什么——只断言「调了提交接口」等于没断言，那串字节才是真正会上链的东西。
void main() {
  final chain = SupportedChains.byId('aptos-testnet');

  // 私钥固定，地址由它派生。**不写死地址字面量**：写死的话一旦派生实现有任何变动，
  // 断言会连同被改坏的实现一起「通过」。
  final privateKey = List<int>.filled(32, 7);
  final signer = AptosED25519PrivateKey.fromBytes(privateKey);
  final sender = signer.publicKey.toAddress();
  final recipient = AptosED25519PrivateKey.fromBytes(List<int>.filled(32, 9)).publicKey.toAddress();

  // 假节点的模拟回 700 gas，服务据此算出的上限是 700 × 3 ÷ 2 + 200。
  final maxGasAmount = BigInt.from(1250);
  const regularGasPrice = 100;
  final normalFee = BigInt.from(regularGasPrice) * maxGasAmount; // 125000 octa

  /// 一份够用的发送方余额：1 APT（decimals = 8）。
  final oneApt = BigInt.from(100000000);

  AptosTransactionService serviceWith(_FakeAptosService node, {BigInt? balance}) => AptosTransactionService(
    provider: AptosProvider(node),
    balances: _FixedBalances(balance ?? oneApt),
  );

  group('sendNative', () {
    test('构造、签名并提交一笔转账，返回 pending', () async {
      final node = _FakeAptosService();
      final result = await serviceWith(node).sendNative(
        chain: chain,
        privateKey: privateKey,
        fromAddress: sender.address,
        to: recipient.address,
        amount: '0.5',
      );

      expect(result.status, TransactionStatus.pending, reason: '提交只代表节点收下了，不代表已上链');
      expect(result.sentAmount, '0.5');
      // Aptos 的失效是时间戳不是区块高度，塞进这个字段会被过期判定误读。
      expect(result.validUntilBlock, isNull);

      final sent = AptosSignedTransaction.deserialize(node.submittedTransaction!);
      // 返回的是节点那份带 `0x` 的哈希：区块浏览器链接与按哈希查询都按这个口径。
      expect(result.hash, '0x${sent.txHash()}');

      // 签名必须真的验得过，不是「有 64 个字节」就算数。
      final authenticator = sent.authenticator as AptosTransactionAuthenticatorEd25519;
      expect(
        authenticator.publicKey.verify(
          message: sent.rawTransaction.signingSerialize(),
          signature: authenticator.signature.signature,
        ),
        isTrue,
      );
      expect(authenticator.publicKey.toAddress(), sender);

      // 收款方与金额从 entry function 的实参里解出来核对。
      expect(_recipientOf(sent), recipient);
      expect(_amountOf(sent), BigInt.from(50000000));

      expect(sent.rawTransaction.sequenceNumber, BigInt.from(5), reason: '必须用实查的序列号');
      expect(sent.rawTransaction.gasUnitPrice, BigInt.from(regularGasPrice));
      expect(sent.rawTransaction.maxGasAmount, maxGasAmount);
      expect(sent.rawTransaction.chainId, 2, reason: 'chainId 取自 ledger info');

      // 走的是 aptos_account::transfer 而不是 coin::transfer——后者对未上链的
      // 收款方会直接失败。
      final payload = sent.rawTransaction.transactionPayload as AptosTransactionPayloadEntryFunction;
      expect(payload.entryFunction.moduleId.address, AptosAddress.one);
      expect(payload.entryFunction.moduleId.name, 'aptos_account');
      expect(payload.entryFunction.functionName, 'transfer');
    });

    test('序列号只查一次', () async {
      final node = _FakeAptosService();
      await serviceWith(node).sendNative(
        chain: chain,
        privateKey: privateKey,
        fromAddress: sender.address,
        to: recipient.address,
        amount: '0.5',
      );

      expect(node.calls.where((path) => path.startsWith('/accounts/')).length, 1);
    });

    test('模拟只跑一次，且用的是本档单价', () async {
      final node = _FakeAptosService();
      await serviceWith(node).sendNative(
        chain: chain,
        privateKey: privateKey,
        fromAddress: sender.address,
        to: recipient.address,
        amount: '0.5',
        speed: FeeSpeed.fast,
      );

      expect(node.calls.where((path) => path == '/transactions/simulate').length, 1);
      final simulated = AptosSignedTransaction.deserialize(node.simulatedTransaction!);
      expect(simulated.rawTransaction.gasUnitPrice, BigInt.from(150), reason: '模拟的预扣校验要与提交同口径');
      // 模拟用的是探测金额而不是用户填的金额：gas 与转多少无关，而 MAX 场景下
      // 拿全额去模拟会因为付不起预扣而失败。
      expect(_amountOf(simulated), BigInt.one);

      final sent = AptosSignedTransaction.deserialize(node.submittedTransaction!);
      expect(sent.rawTransaction.gasUnitPrice, BigInt.from(150));
      expect(_amountOf(sent), BigInt.from(50000000), reason: '真正提交的是用户填的金额');
    });

    test('签名地址与钱包地址不一致时拒发', () async {
      final node = _FakeAptosService();
      await expectLater(
        serviceWith(node).sendNative(
          chain: chain,
          privateKey: privateKey,
          fromAddress: recipient.address, // 不是这把私钥的地址
          to: recipient.address,
          amount: '0.5',
        ),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('签名地址与钱包地址不一致'))),
      );
      expect(node.calls, isNot(contains('/transactions')));
    });

    test('同一地址的不同写法不算「地址不一致」', () async {
      final node = _FakeAptosService();
      // 十六进制地址大小写不敏感（与 base58 的 Solana 地址正相反），
      // 所以核对前必须两边都过一遍 AptosAddress，直接比字符串会把合法的一致判成不一致。
      final upperCase = '0x${sender.address.substring(2).toUpperCase()}';
      expect(upperCase, isNot(sender.address));

      final result = await serviceWith(node).sendNative(
        chain: chain,
        privateKey: privateKey,
        fromAddress: upperCase,
        to: recipient.address,
        amount: '0.5',
      );
      expect(result.status, TransactionStatus.pending);
    });

    test('余额不足时报错，而不是静默改小金额', () async {
      final node = _FakeAptosService();
      await expectLater(
        serviceWith(node, balance: BigInt.from(1000)).sendNative(
          chain: chain,
          privateKey: privateKey,
          fromAddress: sender.address,
          to: recipient.address,
          amount: '0.5',
        ),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('余额不足'))),
      );
      expect(node.calls, isNot(contains('/transactions')));
    });

    test('MAX 全额转出按 gas 上限扣费', () async {
      final node = _FakeAptosService();
      final result = await serviceWith(node).sendNative(
        chain: chain,
        privateKey: privateKey,
        fromAddress: sender.address,
        to: recipient.address,
        amount: '1', // 全部余额
        deductFeeFromAmount: true,
      );

      final expected = oneApt - normalFee;
      expect(_amountOf(AptosSignedTransaction.deserialize(node.submittedTransaction!)), expected);
      expect(result.sentAmount, formatUnits(expected, chain.decimals));
    });

    test('扣完费不为正时报错', () async {
      final node = _FakeAptosService();
      await expectLater(
        serviceWith(node, balance: normalFee).sendNative(
          chain: chain,
          privateKey: privateKey,
          fromAddress: sender.address,
          to: recipient.address,
          amount: '0.00125',
          deductFeeFromAmount: true,
        ),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('余额不足以支付网络费用'))),
      );
      expect(node.calls, isNot(contains('/transactions')));
    });

    test('模拟判定会失败时不提交，并带上 vm_status', () async {
      final node = _FakeAptosService(simulationSucceeds: false);
      await expectLater(
        serviceWith(node).sendNative(
          chain: chain,
          privateKey: privateKey,
          fromAddress: sender.address,
          to: recipient.address,
          amount: '0.5',
        ),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('INSUFFICIENT_BALANCE'))),
      );
      expect(node.calls, isNot(contains('/transactions')));
    });

    test('节点返回的哈希与本地算的不一致时报错', () async {
      final node = _FakeAptosService(submitHash: '0xdeadbeef');
      await expectLater(
        serviceWith(node).sendNative(
          chain: chain,
          privateKey: privateKey,
          fromAddress: sender.address,
          to: recipient.address,
          amount: '0.5',
        ),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('交易哈希与本地不一致'))),
      );
    });

    test('金额为 0 时拒发', () async {
      final node = _FakeAptosService();
      await expectLater(
        serviceWith(node).sendNative(
          chain: chain,
          privateKey: privateKey,
          fromAddress: sender.address,
          to: recipient.address,
          amount: '0',
        ),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('必须大于 0'))),
      );
      expect(node.calls, isEmpty, reason: '连链上数据都不必取');
    });
  });

  group('estimateNativeFee', () {
    test('三档单价直接取自节点，费用按静态 gas 上限算', () async {
      final node = _FakeAptosService();
      final estimate = await serviceWith(node).estimateNativeFee(
        chain: chain,
        from: sender.address,
        to: recipient.address,
      );

      // 收款方账户已存在（假节点的 /accounts/ 一律回 200），走低的那档上限。
      // 300 来自 testnet 实测的 62 gas 加余量，不是拍的。
      expect(estimate.maxGasAmount, BigInt.from(300));
      expect(estimate.priceFor(FeeSpeed.slow), BigInt.from(90));
      expect(estimate.priceFor(FeeSpeed.normal), BigInt.from(regularGasPrice));
      expect(estimate.priceFor(FeeSpeed.fast), BigInt.from(150));

      final quote = estimate.quoteFor(FeeSpeed.normal);
      // 没模拟就没有「实际消耗」这个数，预计实付与上限相等——不编一个更小的值。
      expect(quote.expectedFee, quote.maxFee);
      expect(quote.maxFee, BigInt.from(regularGasPrice) * BigInt.from(300));
      expect(estimate.quotes.keys, FeeSpeed.values);
    });

    test('收款方账户不存在时取更高的那档上限', () async {
      final node = _FakeAptosService(recipientAccountExists: false);
      final estimate = await serviceWith(node).estimateNativeFee(
        chain: chain,
        from: sender.address,
        to: recipient.address,
      );
      // 建号实测 10336 gas，比纯转账的 62 高两个数量级——估低了会让 MAX 付不起预扣。
      expect(estimate.maxGasAmount, BigInt.from(16000));
    });

    test('节点缺「缓慢」档时回落到推荐单价，而不是自行打折', () async {
      final node = _FakeAptosService(deprioritizedGasPrice: null);
      final estimate = await serviceWith(node).estimateNativeFee(
        chain: chain,
        from: sender.address,
        to: recipient.address,
      );
      expect(estimate.priceFor(FeeSpeed.slow), BigInt.from(regularGasPrice));
    });

    test('估费不模拟、也不碰私钥', () async {
      final node = _FakeAptosService();
      await serviceWith(node).estimateNativeFee(chain: chain, from: sender.address, to: recipient.address);

      // 模拟接口会校验公钥（对不上回 INVALID_AUTH_KEY），走它就等于要解锁私钥。
      // 进一次确认页解一次锁，代价远超估费本身的价值——所以这条路必须是走不到的。
      expect(node.calls, isNot(contains('/transactions/simulate')));
      expect(node.simulatedTransaction, isNull);
    });
  });

  group('waitForReceipt', () {
    test('已上链且成功 → confirmed', () async {
      final node = _FakeAptosService();
      final status = await serviceWith(node).waitForReceipt(chain, '0xabc');
      expect(status, TransactionStatus.confirmed);
    });

    test('已上链但被 Move 层拒绝 → failed', () async {
      final node = _FakeAptosService(lookupSucceeds: false);
      final status = await serviceWith(node).waitForReceipt(chain, '0xabc');
      expect(status, TransactionStatus.failed);
    });

    test('还在内存池里 → pending', () async {
      final node = _FakeAptosService(lookupPending: true);
      final status = await serviceWith(node).waitForReceipt(chain, '0xabc');
      expect(status, TransactionStatus.pending);
    });

    test('查不到（404）→ pending，而不是 failed', () async {
      final node = _FakeAptosService(lookupNotFound: true);
      final status = await serviceWith(node).waitForReceipt(chain, '0xabc');
      expect(status, TransactionStatus.pending, reason: '查不到可能只是还没传播开，报成失败会冤枉一笔已上链的交易');
    });
  });
}

/// 从已签名交易里解出收款方。
///
/// entry function 的实参在 BCS 里就是一串裸字节，反序列化回来是
/// [AptosTransactionArgumentBytes]，所以要自己按参数位置解读。
AptosAddress _recipientOf(AptosSignedTransaction transaction) {
  return AptosAddress.fromBytes(_argumentBytes(transaction, 0));
}

/// 从已签名交易里解出转账金额（u64，小端）。
BigInt _amountOf(AptosSignedTransaction transaction) {
  final bytes = _argumentBytes(transaction, 1);
  var value = BigInt.zero;
  for (var i = bytes.length - 1; i >= 0; i--) {
    value = (value << 8) | BigInt.from(bytes[i]);
  }
  return value;
}

List<int> _argumentBytes(AptosSignedTransaction transaction, int index) {
  final payload = transaction.rawTransaction.transactionPayload as AptosTransactionPayloadEntryFunction;
  return payload.entryFunction.args[index].value as List<int>;
}

/// 固定余额的余额源。真实实现直接打 HTTP，测试里不该有网络。
class _FixedBalances extends ChainBalanceApi {
  const _FixedBalances(this.balance);

  final BigInt balance;

  @override
  Future<BigInt> fetchNativeBalance(Chain chain, String address) async => balance;
}

/// 假节点：按 REST 路径路由预设响应，录下请求路径与提交的字节。
///
/// 未预设的路径一律抛错而不是返回空——沉默地放过一个没想到的请求，
/// 会让测试在实现多打了一轮网络时依然通过。
class _FakeAptosService with AptosServiceProvider {
  _FakeAptosService({
    this.simulationSucceeds = true,
    this.lookupSucceeds = true,
    this.lookupPending = false,
    this.lookupNotFound = false,
    this.deprioritizedGasPrice = 90,
    this.recipientAccountExists = true,
    this.submitHash,
  });

  final bool simulationSucceeds;
  final bool lookupSucceeds;
  final bool lookupPending;
  final bool lookupNotFound;
  final int? deprioritizedGasPrice;

  /// 收款方账户在链上存不存在。节点对未上链的账户回 404，估费据此选 gas 上限档。
  final bool recipientAccountExists;

  /// 让节点回一个与本地算出的不同的哈希，用于测那条一致性校验。null 表示回真哈希。
  final String? submitHash;

  /// 发送方地址，用来把「查发送方序列号」和「查收款方存不存在」两次 /accounts 分开。
  static final String _senderAddress =
      AptosED25519PrivateKey.fromBytes(List<int>.filled(32, 7)).publicKey.toAddress().address.substring(2);

  final List<String> calls = [];
  List<int>? submittedTransaction;
  List<int>? simulatedTransaction;

  @override
  Future<AptosServiceResponse> doRequest(AptosRequestDetails params, {Duration? timeout}) async {
    final path = params.path ?? '';
    calls.add(path);

    if (path == '/transactions/simulate') {
      simulatedTransaction = params.bodyBytes;
      return _ok(jsonEncode([_userTransaction(hash: '0xsimulated', success: simulationSucceeds)]));
    }
    if (path == '/transactions') {
      final body = params.bodyBytes!;
      submittedTransaction = body;
      // 真实节点回的哈希带 `0x`，而 SDK 的 txHash() 不带——这个差异要保留在假节点里，
      // 否则那条一致性校验的归一化就没被测到。
      final hash = submitHash ?? '0x${AptosSignedTransaction.deserialize(body).txHash()}';
      return _ok(jsonEncode(_pendingTransaction(hash)));
    }
    if (path == '/estimate_gas_price') {
      return _ok(
        jsonEncode({
          'deprioritized_gas_estimate': deprioritizedGasPrice,
          'gas_estimate': 100,
          'prioritized_gas_estimate': 150,
        }),
      );
    }
    if (path == '/') {
      return _ok(jsonEncode(_ledgerInfo));
    }
    if (path.startsWith('/accounts/')) {
      if (!recipientAccountExists && !path.contains(_senderAddress)) {
        return ServiceProviderUtils.findError(
          object: jsonEncode({'message': 'account not found', 'error_code': 'account_not_found'}),
          statusCode: 404,
          allowStatusCode: params.errorStatusCodes,
        );
      }
      return _ok(jsonEncode({'sequence_number': '5', 'authentication_key': '0x${'0' * 64}'}));
    }
    if (path.startsWith('/transactions/by_hash/')) {
      if (lookupNotFound) {
        return ServiceProviderUtils.findError(
          object: jsonEncode({'message': 'transaction not found', 'error_code': 'transaction_not_found'}),
          statusCode: 404,
          allowStatusCode: params.errorStatusCodes,
        );
      }
      if (lookupPending) return _ok(jsonEncode(_pendingTransaction('0xabc')));
      return _ok(jsonEncode(_userTransaction(hash: '0xabc', success: lookupSucceeds)));
    }
    throw StateError('未预设的 Aptos 路径: $path');
  }

  AptosServiceResponse _ok(String body) => ServiceSuccessRespose(statusCode: 200, response: body);

  static const Map<String, dynamic> _ledgerInfo = {
    'chain_id': 2,
    'epoch': '1',
    'ledger_version': '100',
    'oldest_ledger_version': '0',
    'ledger_timestamp': '1700000000000000',
    'node_role': 'full_node',
    'oldest_block_height': '0',
    'block_height': '10',
    'git_hash': null,
  };

  static const Map<String, dynamic> _payload = {
    'type': 'entry_function_payload',
    'function': '0x1::aptos_account::transfer',
    'type_arguments': <String>[],
    'arguments': <String>[],
  };

  Map<String, dynamic> _pendingTransaction(String hash) => {
    'type': 'pending_transaction',
    'hash': hash,
    'sender': '0x1',
    'sequence_number': '5',
    'max_gas_amount': '1250',
    'gas_unit_price': '100',
    'expiration_timestamp_secs': '1700000060',
    'payload': _payload,
    'signature': null,
  };

  Map<String, dynamic> _userTransaction({required String hash, required bool success}) => {
    'type': 'user_transaction',
    'version': '100',
    'hash': hash,
    'state_change_hash': '0x0',
    'event_root_hash': '0x0',
    'state_checkpoint_hash': null,
    'gas_used': '700',
    'success': success,
    'vm_status': success ? 'Executed successfully' : 'INSUFFICIENT_BALANCE',
    'accumulator_root_hash': '0x0',
    'changes': <Map<String, dynamic>>[],
    'sender': '0x1',
    'sequence_number': '5',
    'max_gas_amount': '20000',
    'gas_unit_price': '100',
    'expiration_timestamp_secs': '1700000060',
    'payload': _payload,
    'signature': null,
    'events': <Map<String, dynamic>>[],
    'timestamp': '1700000000000000',
  };
}
