import 'dart:convert';

import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:on_chain/sui/sui.dart';
import 'package:wallet_core/chains.dart';
import 'package:wallet_core/wallet_core.dart';

/// Sui 原生转账的离线测试。
///
/// 与 `aptos_transfer_test.dart` / `solana_transfer_test.dart` 同一形态：
/// **全程不碰网络**，节点由 [_FakeSuiService] 假扮，按 JSON-RPC 方法名路由预设响应
/// 并录下发出去的请求。断言一律**反序列化提交的字节**再看里面是什么——只断言
/// 「调了提交接口」等于没断言，那串字节才是真正会上链的东西。
void main() {
  final chain = SupportedChains.byId('sui-testnet');

  // 私钥固定，地址由它派生。**不写死地址字面量**：写死的话一旦派生实现有任何变动，
  // 断言会连同被改坏的实现一起「通过」。
  final privateKey = List<int>.filled(32, 7);
  final account = SuiEd25519Account(SuiED25519PrivateKey.fromBytes(privateKey));
  final sender = account.toAddress();
  final recipient = SuiEd25519Account(SuiED25519PrivateKey.fromBytes(List<int>.filled(32, 9))).toAddress();

  // 假节点给的 dry run 结果，拆开写是因为**两个数各有各的用途**：
  final computationCost = BigInt.from(1000000);
  final storageCost = BigInt.from(1976000);
  final storageRebate = BigInt.from(978120);
  // 净费用 = 用户实际承担的，确认页显示它。
  final netGasFee = computationCost + storageCost - storageRebate;
  // 毛支出 = 链上按它要求预算（存储返还是执行完才退的，冲抵不了预算）。
  final grossGasCost = computationCost + storageCost;
  // 预算 = 毛支出 × 3 ÷ 2 + 1000000。**不是**按净费用算——按净费用算会在
  // 返还大于支出的账户上给出不够的预算而 InsufficientGas（testnet 实测）。
  final gasBudget = grossGasCost * BigInt.from(3) ~/ BigInt.two + BigInt.from(1000000);
  final referenceGasPrice = BigInt.from(1000);

  /// 发送方余额：1 SUI（decimals = 9），拆成两个 coin 对象，顺带覆盖多对象付款。
  final oneSui = BigInt.from(1000000000);

  SuiTransactionService serviceWith(_FakeSuiService node) => SuiTransactionService(provider: SuiProvider(node));

  group('sendNative', () {
    test('构造、签名并提交一笔转账，返回 pending', () async {
      final node = _FakeSuiService();
      final result = await serviceWith(node).sendNative(chain: chain, privateKey: privateKey, fromAddress: sender.address, to: recipient.address, amount: '0.5');

      expect(result.status, TransactionStatus.pending, reason: '提交只代表节点收下了，不代表已上链');
      expect(result.sentAmount, '0.5');
      // Sui 的失效按 epoch 不按区块高度，塞进这个字段会被过期判定误读。
      expect(result.validUntilBlock, isNull);

      final sent = _deserialize(node.submittedTxBytes!);
      expect(result.hash, sent.txHash(), reason: 'digest 由交易内容算出，必须与本地一致');

      // 签名必须真的验得过，不是「有 64 个字节」就算数。
      // 验的是**提交上去的那串字节**的 intent message——这同时锁死了
      // 「签的那笔」与「发的那笔」是同一笔。
      final signature = SuiBaseSignature.deserialize(StringUtils.encode(node.submittedSignatures!.single, encoding: StringEncoding.base64)).cast<SuiEd25519Signature>();
      final digest = SuiCryptoUtils.generateTransactionDigest(txBytes: sent.serializeSign(), hashDigest: true);
      expect(
        signature.publicKey.verify(message: digest, signature: signature.signature.signature),
        isTrue,
        reason: '签名要能被交易里声明的公钥验过',
      );
      expect(signature.publicKey.toAddress(), sender, reason: '签名公钥推出来的必须就是发送方');

      expect(sent.sender, sender);

      // 命令序列：从 gas coin 拆出金额 → 转给收款方。
      final programmable = (sent.kind as SuiTransactionKindProgrammableTransaction).transaction;
      expect(programmable.commands, hasLength(2));
      final split = programmable.commands[0] as SuiCommandSplitCoins;
      expect(split.coin, isA<SuiArgumentGasCoin>(), reason: '从 gas coin 拆，才能借上 gas smashing 合并碎片');
      final transfer = programmable.commands[1] as SuiCommandTransferObjects;
      expect((transfer.objects.single as SuiArgumentResult).result, 0, reason: '转的是上一步拆出来的那个 coin');

      // 收款方与金额从 PTB 的输入里解出来核对。
      expect(_amountOf(programmable), BigInt.from(500000000));
      expect(_recipientOf(programmable), recipient);

      // gas 参数。
      expect(sent.gasData.price, referenceGasPrice, reason: '必须用实查的参考单价');
      expect(sent.gasData.budget, gasBudget);
      expect(sent.gasData.owner, sender);
      expect(sent.gasData.payment, hasLength(2), reason: '两个 coin 对象都要付款，gas smashing 会合并它们');
    });

    test('节点自称主网时中止签名', () async {
      final node = _FakeSuiService(chainIdentifier: '35834a8a');
      await expectLater(
        serviceWith(node).sendNative(chain: chain, privateKey: privateKey, fromAddress: sender.address, to: recipient.address, amount: '0.5'),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('已中止签名'))),
      );
      // 校验必须在签名之前：一个字节都不该发出去。
      expect(node.submittedTxBytes, isNull);
      expect(node.calls, isNot(contains('sui_executeTransactionBlock')));
    });

    test('签名地址与钱包地址不一致时拒发', () async {
      final node = _FakeSuiService();
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
      expect(node.submittedTxBytes, isNull);
    });

    test('同一地址的不同写法不算「地址不一致」', () async {
      final node = _FakeSuiService();
      // Sui 地址是十六进制，大小写不敏感（与 base58 的 Solana 地址正相反），
      // 所以核对前必须两边都过一遍 SuiAddress，直接比字符串会把合法的一致判成不一致。
      final upperCase = '0x${sender.address.substring(2).toUpperCase()}';
      expect(upperCase, isNot(sender.address));

      final result = await serviceWith(node).sendNative(chain: chain, privateKey: privateKey, fromAddress: upperCase, to: recipient.address, amount: '0.5');
      expect(result.status, TransactionStatus.pending);
    });

    test('余额不足时报错，而不是静默改小金额', () async {
      final node = _FakeSuiService(coinBalances: [BigInt.from(1000)]);
      await expectLater(
        serviceWith(node).sendNative(chain: chain, privateKey: privateKey, fromAddress: sender.address, to: recipient.address, amount: '0.5'),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('余额不足'))),
      );
      expect(node.submittedTxBytes, isNull);
    });

    test('MAX 全额转出按 gas 预算扣费', () async {
      final node = _FakeSuiService();
      final result = await serviceWith(node).sendNative(
        chain: chain,
        privateKey: privateKey,
        fromAddress: sender.address,
        to: recipient.address,
        amount: '1', // 全部余额
        deductFeeFromAmount: true,
      );

      // 扣的是**预算**而不是净费用：链上按预算整额冻结，按净费用扣会让这笔冻不住。
      final expected = oneSui - gasBudget;
      final sent = _deserialize(node.submittedTxBytes!);
      expect(_amountOf((sent.kind as SuiTransactionKindProgrammableTransaction).transaction), expected);
      expect(result.sentAmount, formatUnits(expected, chain.decimals));
    });

    test('MAX 场景下 dry run 用付得起的探测金额，提交用真实金额', () async {
      final node = _FakeSuiService();
      await serviceWith(node).sendNative(chain: chain, privateKey: privateKey, fromAddress: sender.address, to: recipient.address, amount: '1', deductFeeFromAmount: true);

      // 拿全额去 dry run 会因为付不起预算而失败，于是连「这笔要花多少」都问不出来。
      final probed = _deserialize(node.dryRunTxBytes!);
      final probeAmount = _amountOf((probed.kind as SuiTransactionKindProgrammableTransaction).transaction);
      expect(probeAmount, BigInt.one, reason: '探测固定用 1 MIST——费用与金额无关，用最小值才保证探得动');

      // **预算必须给转出额留出空档**。预算吃满余额时，真实节点连 1 MIST 都转不出去，
      // dry run 判 failure 并回一份半截的 gasUsed（testnet 实测：费用会少算一半）。
      expect(probed.gasData.budget, lessThan(oneSui), reason: '预算等于余额会让 dry run 必然失败');

      final sent = _deserialize(node.submittedTxBytes!);
      expect(_amountOf((sent.kind as SuiTransactionKindProgrammableTransaction).transaction), oneSui - gasBudget, reason: '真正提交的是扣完费的金额');
    });

    test('dry run 报失败时抛错，绝不拿半截的 gasUsed 当费用', () async {
      // 失败响应里照样有 gasUsed，但那是执行中断那一刻的半截账。用它会让确认页
      // 显示偏低的数，更糟的是让 MAX 预留不足、放出一笔注定被链上拒收的交易。
      final node = _FakeSuiService(dryRunStatus: 'failure');
      await expectLater(
        serviceWith(node).sendNative(chain: chain, privateKey: privateKey, fromAddress: sender.address, to: recipient.address, amount: '0.5'),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('网络费用估算失败'))),
      );
      expect(node.submittedTxBytes, isNull, reason: '估不出费用就不该签名，更不该广播');
    });

    test('dry run 只跑一次', () async {
      final node = _FakeSuiService();
      await serviceWith(node).sendNative(chain: chain, privateKey: privateKey, fromAddress: sender.address, to: recipient.address, amount: '0.5');
      expect(node.calls.where((method) => method == 'sui_dryRunTransactionBlock'), hasLength(1));
    });

    test('节点返回的哈希与本地不一致时报错', () async {
      final node = _FakeSuiService(responseDigest: 'not-the-digest-we-signed');
      await expectLater(
        serviceWith(node).sendNative(chain: chain, privateKey: privateKey, fromAddress: sender.address, to: recipient.address, amount: '0.5'),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('交易哈希与本地不一致'))),
      );
    });

    test('金额为 0 时拒发', () async {
      final node = _FakeSuiService();
      await expectLater(
        serviceWith(node).sendNative(chain: chain, privateKey: privateKey, fromAddress: sender.address, to: recipient.address, amount: '0'),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('必须大于 0'))),
      );
      expect(node.submittedTxBytes, isNull);
    });

    test('快速档按加价后的单价签名', () async {
      final node = _FakeSuiService();
      await serviceWith(node).sendNative(chain: chain, privateKey: privateKey, fromAddress: sender.address, to: recipient.address, amount: '0.5', speed: FeeSpeed.fast);

      final sent = _deserialize(node.submittedTxBytes!);
      expect(sent.gasData.price, BigInt.from(1200), reason: '快速档 = 参考价 × 1.2');
    });
  });

  group('estimateNativeFee', () {
    test('三档报价：缓慢与普通同价，快速加价', () async {
      final node = _FakeSuiService();
      final estimate = await serviceWith(node).estimateNativeFee(chain: chain, from: sender.address, to: recipient.address);

      expect(estimate.netGasFee, netGasFee, reason: '净费用 = 计算费 + 存储费 - 存储返还');
      expect(estimate.gasBudget, gasBudget);

      final quotes = estimate.quotes;
      // 低于参考价一律被链上拒绝，所以慢档无处可慢——两档同价是事实，不是没取到。
      expect(quotes[FeeSpeed.slow]!.gasPrice, referenceGasPrice);
      expect(quotes[FeeSpeed.normal]!.gasPrice, referenceGasPrice);
      expect(quotes[FeeSpeed.slow]!.expectedFee, quotes[FeeSpeed.normal]!.expectedFee);
      expect(quotes[FeeSpeed.fast]!.gasPrice, BigInt.from(1200));
      expect(quotes[FeeSpeed.fast]!.expectedFee, greaterThan(quotes[FeeSpeed.normal]!.expectedFee));

      // maxFee 是预算、expectedFee 是净费用，两者不等——确认页的「上限」一行靠这个差值。
      for (final quote in quotes.values) {
        expect(quote.maxFee, greaterThan(quote.expectedFee));
      }
    });

    test('估费不需要私钥，也不提交任何东西', () async {
      final node = _FakeSuiService();
      await serviceWith(node).estimateNativeFee(chain: chain, from: sender.address, to: recipient.address);
      // 这正是 Sui 能在确认页显示链上实测费用、而 Aptos 只能用静态上限的原因。
      expect(node.calls, contains('sui_dryRunTransactionBlock'));
      expect(node.calls, isNot(contains('sui_executeTransactionBlock')));
    });

    test('dry run 报失败时抛错，让 UI 回退 --', () async {
      final node = _FakeSuiService(dryRunStatus: 'failure');
      await expectLater(
        serviceWith(node).estimateNativeFee(chain: chain, from: sender.address, to: recipient.address),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('网络费用估算失败'))),
      );
    });

    test('返还大于支出时，预算仍按毛支出算，够覆盖链上要求', () async {
      // 这组数字是 2026-09-19 在 testnet 上实测来的：一个有 3 个 coin 对象的账户做
      // 代币转账，合并销毁对象退回的押金比花掉的还多，净费用是 **负的**。
      //
      // 旧实现按净费用算预算，夹零后得到 1000000——实测那笔 InsufficientGas 直接失败，
      // 而 4632800（= 毛支出）能成功。所以预算必须跟着毛支出走。
      final node = _FakeSuiService(storageCost: BigInt.from(3632800), storageRebate: BigInt.from(4905648));
      final estimate = await serviceWith(node).estimateNativeFee(chain: chain, from: sender.address, to: recipient.address);

      final gross = BigInt.from(1000000) + BigInt.from(3632800);
      expect(estimate.netGasFee, BigInt.zero, reason: '净费用为负，夹到 0');
      expect(estimate.gasBudget, greaterThanOrEqualTo(gross), reason: '预算必须盖住毛支出 $gross——按净费用算会得到 1000000，链上会判 InsufficientGas');
    });

    test('余额低于协议最低预算时说「余额不足」，而不是「估算失败」', () async {
      // 协议最低预算是 1000000（实测：低于它节点在校验入参时就拒）。
      // 余额不够时必须说清是钱不够，说成「网络费用估算失败」会让用户以为是网络问题。
      final node = _FakeSuiService(coinBalances: [BigInt.from(999999)]);
      await expectLater(
        serviceWith(node).estimateNativeFee(chain: chain, from: sender.address, to: recipient.address),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('余额不足以支付网络费用'))),
      );
    });

    test('存储返还大于支出时净费用夹到 0，不让负数流下去', () async {
      final node = _FakeSuiService(storageRebate: BigInt.from(99999999));
      final estimate = await serviceWith(node).estimateNativeFee(chain: chain, from: sender.address, to: recipient.address);
      expect(estimate.netGasFee, BigInt.zero);
      // 负的费用会让「还能转多少」算出比实际更宽松的数。
      expect(estimate.quotes[FeeSpeed.normal]!.maxFee, greaterThan(BigInt.zero));
    });
  });

  group('waitForReceipt', () {
    test('执行成功回 confirmed', () async {
      final node = _FakeSuiService(receiptStatus: 'success');
      expect(await serviceWith(node).waitForReceipt(chain, 'digest'), TransactionStatus.confirmed);
    });

    test('执行失败回 failed（上了链但被 Move 层拒绝，gas 照扣）', () async {
      final node = _FakeSuiService(receiptStatus: 'failure');
      expect(await serviceWith(node).waitForReceipt(chain, 'digest'), TransactionStatus.failed);
    });

    test('查不到回 pending，而不是 failed', () async {
      // 限流与网络故障同样会走到这条分支，报成失败会让一笔其实已上链的交易显示成红叉。
      final node = _FakeSuiService(receiptFound: false);
      expect(await serviceWith(node).waitForReceipt(chain, 'digest'), TransactionStatus.pending);
    });
  });

  group('SuiTransferService 能力声明', () {
    test('原生币与代币都支持', () {
      // supportsToken 为 true 会让 SendLogic.assetsOf 放行 Sui 代币，
      // 目录里那枚 USDC 因此会出现在可发送列表里。代币路径本身由
      // sui_token_transfer_test.dart 覆盖。
      const service = SuiTransferService(_UnusedKeyResolver());
      expect(service.kind, ChainKind.sui);
      expect(service.supportsNative, isTrue);
      expect(service.supportsToken, isTrue);
    });
  });
}

// —— 断言辅助 —— //

SuiTransactionDataV1 _deserialize(String base64TxBytes) {
  final bytes = StringUtils.encode(base64TxBytes, encoding: StringEncoding.base64);
  return SuiTransactionData.deserialize(bytes) as SuiTransactionDataV1;
}

/// PTB 的输入 0 是要转的金额（u64 pure）。
BigInt _amountOf(SuiProgrammableTransaction programmable) {
  final pure = programmable.inputs[0] as SuiCallArgPure;
  return LayoutConst.u64().deserialize(pure.bytes).value;
}

/// PTB 的输入 1 是收款方地址（address pure）。
SuiAddress _recipientOf(SuiProgrammableTransaction programmable) {
  final pure = programmable.inputs[1] as SuiCallArgPure;
  return SuiAddress.fromBytes(pure.bytes);
}

/// 只为构造 [SuiTransferService] 做能力断言，永远不会被调用到。
class _UnusedKeyResolver implements PrivateKeyResolver {
  const _UnusedKeyResolver();

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError('能力断言不该走到私钥解析');
}

/// 假 Sui 节点：按 JSON-RPC 方法名路由预设响应，并录下发出去的请求。
class _FakeSuiService with SuiServiceProvider {
  _FakeSuiService({
    this.chainIdentifier = '4c78adac',
    List<BigInt>? coinBalances,
    BigInt? storageRebate,
    BigInt? storageCost,
    this.responseDigest,
    this.receiptStatus = 'success',
    this.receiptFound = true,
    this.dryRunStatus = 'success',
  }) : coinBalances = coinBalances ?? [BigInt.from(600000000), BigInt.from(400000000)],
       storageRebate = storageRebate ?? BigInt.from(978120),
       storageCost = storageCost ?? BigInt.from(1976000);

  /// 节点自称的链身份。默认 testnet 钉死值，测换网时改成主网的 35834a8a。
  final String chainIdentifier;

  /// 发送方名下的 SUI coin 对象各自的余额。默认两个，合计 1 SUI。
  final List<BigInt> coinBalances;

  /// dry run 回的存储返还。调大可让净费用变成负数，用于测夹零。
  final BigInt storageRebate;

  /// dry run 回的存储支出。与 [storageRebate] 分开可调，用来构造
  /// 「返还大于支出、净费用为负」这种碎片账户上的真实场景。
  final BigInt storageCost;

  /// 让节点回一个与本地算出的不同的 digest，用于测那条一致性校验。null 表示回真 digest。
  final String? responseDigest;

  /// `sui_getTransactionBlock` 回的执行状态。
  final String receiptStatus;

  /// 交易是否已被节点索引到。false 时直接报错（真实节点对未知 digest 就是报错）。
  final bool receiptFound;

  /// dry run 报的执行状态。真实节点在预算不够时会回 failure，
  /// 且**照样带回一份半截的 gasUsed**——这正是要被拦下的那种响应。
  final String dryRunStatus;

  final List<String> calls = [];
  String? submittedTxBytes;
  List<String>? submittedSignatures;
  String? dryRunTxBytes;

  @override
  Future<SuiServiceResponse> doRequest(SuiRequestDetails params, {Duration? timeout}) async {
    final body = jsonDecode(params.bodyString!) as Map<String, dynamic>;
    final method = body['method'] as String;
    calls.add(method);
    final requestParams = body['params'] as List<dynamic>;

    final result = switch (method) {
      'sui_getChainIdentifier' => chainIdentifier,
      'suix_getReferenceGasPrice' => '1000',
      'suix_getCoins' => {
        'data': [for (final (index, balance) in coinBalances.indexed) _coin(index, balance)],
        'hasNextPage': false,
        'nextCursor': null,
      },
      'sui_dryRunTransactionBlock' => _dryRun(requestParams),
      'sui_executeTransactionBlock' => _execute(requestParams),
      'sui_getTransactionBlock' => _receipt(requestParams),
      _ => throw StateError('假节点没有为 $method 准备响应'),
    };

    return ServiceSuccessRespose(statusCode: 200, response: jsonEncode({'jsonrpc': '2.0', 'id': body['id'], 'result': result}));
  }

  Map<String, dynamic> _coin(int index, BigInt balance) => {
    'balance': balance.toString(),
    'coinObjectId': '0x${(index + 1).toString().padLeft(64, '0')}',
    'coinType': '0x2::sui::SUI',
    'digest': Base58Encoder.encode(List<int>.filled(32, index + 1)),
    'previousTransaction': Base58Encoder.encode(List<int>.filled(32, 200)),
    'version': '${index + 1}',
  };

  Map<String, dynamic> _dryRun(List<dynamic> requestParams) {
    dryRunTxBytes = requestParams.first as String;
    return {
      'balanceChanges': <dynamic>[],
      'events': <dynamic>[],
      'objectChanges': <dynamic>[],
      'input': _inputBlock(),
      // 失败时把 storageCost 减半，模拟真实节点「执行中断、只算到一半」的响应：
      // 实现若不看 status 就用这份数，费用会少算一半（testnet 上实际发生过）。
      'effects': _effects(status: dryRunStatus, storageCost: dryRunStatus == 'success' ? storageCost.toString() : '988000'),
    };
  }

  Map<String, dynamic> _execute(List<dynamic> requestParams) {
    submittedTxBytes = requestParams[0] as String;
    submittedSignatures = (requestParams[1] as List<dynamic>).cast<String>();
    final digest = responseDigest ?? _deserialize(submittedTxBytes!).txHash();
    return {'digest': digest};
  }

  Map<String, dynamic> _receipt(List<dynamic> requestParams) {
    if (!receiptFound) throw StateError('节点查不到这笔交易');
    return {'digest': requestParams.first, 'effects': _effects(status: receiptStatus)};
  }

  /// dry run 响应里的 `input`。服务不读它，但 SDK 的 fromJson 会急切解析，
  /// 所以必须给一份形状对得上的。
  Map<String, dynamic> _inputBlock() => {
    'sender': '0x${'0'.padLeft(64, '0')}',
    'gasData': {'budget': '1000000', 'owner': '0x${'0'.padLeft(64, '0')}', 'payment': <dynamic>[], 'price': '1000'},
    'transaction': {'kind': 'ProgrammableTransaction', 'inputs': <dynamic>[], 'transactions': <dynamic>[]},
  };

  Map<String, dynamic> _effects({String status = 'success', String storageCost = '1976000'}) => {
    'executedEpoch': '1',
    'gasObject': {
      'owner': {'AddressOwner': '0x${'0'.padLeft(64, '0')}'},
      'reference': _objectRef(),
    },
    'gasUsed': {'computationCost': '1000000', 'storageCost': storageCost, 'storageRebate': storageRebate.toString(), 'nonRefundableStorageFee': '0'},
    'status': {'status': status, 'error': null},
    'transactionDigest': Base58Encoder.encode(List<int>.filled(32, 3)),
    'created': null,
    'deleted': null,
    'dependencies': null,
    'eventsDigest': null,
    'modifiedAtVersion': null,
    'mutated': null,
    'sharedObjects': null,
    'unwrapped': null,
    'unwrappedThenDeleted': null,
    'wrapped': null,
  };

  Map<String, dynamic> _objectRef() => {'digest': Base58Encoder.encode(List<int>.filled(32, 1)), 'objectId': '0x${'1'.padLeft(64, '0')}', 'version': '1'};
}
