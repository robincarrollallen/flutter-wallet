import 'dart:convert';

import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:on_chain/sui/sui.dart';
import 'package:wallet_core/chains.dart';
import 'package:wallet_core/wallet_core.dart';

/// Sui 代币（`Coin<T>` 标准）转账的离线测试。
///
/// 与 `sui_transfer_test.dart` / `aptos_token_transfer_test.dart` 同一形态：
/// **全程不碰网络**，节点由 [_FakeSuiService] 假扮，断言一律反序列化提交的字节。
///
/// 代币**从真实目录里取**而不是写死 identifier：写死的话目录一改，这里还在测一个
/// 已经不存在的代币，而断言照样全绿。
void main() {
  final chain = SupportedChains.byId('sui-testnet');
  final token = BundledTokenCatalog.all.firstWhere((candidate) => candidate.chainId == chain.id && candidate.standard == TokenStandard.suiCoin);

  final privateKey = List<int>.filled(32, 7);
  final account = SuiEd25519Account(SuiED25519PrivateKey.fromBytes(privateKey));
  final sender = account.toAddress();
  final recipient = SuiEd25519Account(SuiED25519PrivateKey.fromBytes(List<int>.filled(32, 9))).toAddress();

  // 假节点的 dry run 结果：净费用 = 1000000 + 1976000 - 978120，预算 = 净费用 × 3 ÷ 2 + 1000000。
  final netGasFee = BigInt.from(1997880);
  final gasBudget = netGasFee * BigInt.from(3) ~/ BigInt.two + BigInt.from(1000000);

  SuiTransactionService serviceWith(_FakeSuiService node) => SuiTransactionService(provider: SuiProvider(node));

  group('sendToken', () {
    test('合并、拆分并转出代币，gas 仍由 SUI 支付', () async {
      final node = _FakeSuiService();
      final result = await serviceWith(node).sendToken(chain: chain, token: token, privateKey: privateKey, fromAddress: sender.address, to: recipient.address, amount: '0.5');

      expect(result.status, TransactionStatus.pending);
      expect(result.sentAmount, '0.5');
      expect(result.validUntilBlock, isNull);

      final sent = _deserialize(node.submittedTxBytes!);
      expect(result.hash, sent.txHash());

      final programmable = (sent.kind as SuiTransactionKindProgrammableTransaction).transaction;

      // 命令序列：两个代币 coin 先 merge，再从合并后的那个 split，最后转走。
      expect(programmable.commands, hasLength(3));
      final merge = programmable.commands[0] as SuiCommandMergeCoins;
      expect((merge.destination as SuiArgumentInput).input, 2, reason: '代币 coin 从输入 2 开始排');
      expect(merge.sources, hasLength(1));
      expect((merge.sources.single as SuiArgumentInput).input, 3);

      final split = programmable.commands[1] as SuiCommandSplitCoins;
      // **关键**：代币是从代币 object 拆，不是从 gas coin 拆——后者拆出来的是 SUI。
      expect(split.coin, isA<SuiArgumentInput>(), reason: '代币不能从 GasCoin 拆，那会转出 SUI');
      expect((split.coin as SuiArgumentInput).input, 2);

      final transfer = programmable.commands[2] as SuiCommandTransferObjects;
      expect((transfer.objects.single as SuiArgumentResult).result, 1, reason: '转的是 SplitCoins（第 2 条命令）的结果');

      // 金额按**代币精度**换算：0.5 USDC = 500000（6 位），而不是 5e8（SUI 的 9 位）。
      expect(token.decimals, 6, reason: '这条断言的前提：USDC 是 6 位');
      expect(chain.decimals, 9, reason: '而 SUI 是 9 位——用错精度会差 1000 倍');
      expect(_amountOf(programmable), BigInt.from(500000));
      expect(_recipientOf(programmable), recipient);

      // 代币 object 作为输入被带上，且用的是链上查回来的那两个。
      expect(programmable.inputs, hasLength(4));
      expect(programmable.inputs[2], isA<SuiCallArgObject>());
      expect(programmable.inputs[3], isA<SuiCallArgObject>());

      // gas 仍由 SUI coin 付，与代币 object 是两套。
      expect(sent.gasData.payment, hasLength(1));
      expect(sent.gasData.budget, gasBudget);
      expect(sent.gasData.owner, sender);

      // 签名必须真的验得过，且验的是提交上去的那串字节。
      final signature = SuiBaseSignature.deserialize(StringUtils.encode(node.submittedSignatures!.single, encoding: StringEncoding.base64)).cast<SuiEd25519Signature>();
      final digest = SuiCryptoUtils.generateTransactionDigest(txBytes: sent.serializeSign(), hashDigest: true);
      expect(signature.publicKey.verify(message: digest, signature: signature.signature.signature), isTrue);
      expect(signature.publicKey.toAddress(), sender);
    });

    test('只有一个代币 coin 时不发 MergeCoins', () async {
      // 空 sources 的 MergeCoins 是条没有意义的命令，白付一份 computation。
      final node = _FakeSuiService(tokenBalances: [BigInt.from(1000000)]);
      await serviceWith(node).sendToken(chain: chain, token: token, privateKey: privateKey, fromAddress: sender.address, to: recipient.address, amount: '0.5');

      final programmable = (_deserialize(node.submittedTxBytes!).kind as SuiTransactionKindProgrammableTransaction).transaction;
      expect(programmable.commands, hasLength(2));
      expect(programmable.commands[0], isA<SuiCommandSplitCoins>());
      expect(programmable.commands[1], isA<SuiCommandTransferObjects>());
      expect(programmable.commands.whereType<SuiCommandMergeCoins>(), isEmpty);
      expect(programmable.inputs, hasLength(3), reason: '只有一个代币 object 输入');
    });

    test('代币 coin 数量以 32 封顶', () async {
      // 碎片再多也不能无限塞进一笔交易：每个 object 都占体积与 computation。
      final node = _FakeSuiService(tokenBalances: [for (var i = 0; i < 40; i++) BigInt.from(100000)]);
      await serviceWith(node).sendToken(chain: chain, token: token, privateKey: privateKey, fromAddress: sender.address, to: recipient.address, amount: '0.5');

      final programmable = (_deserialize(node.submittedTxBytes!).kind as SuiTransactionKindProgrammableTransaction).transaction;
      expect(programmable.inputs, hasLength(2 + 32), reason: '金额 + 收款方 + 最多 32 个代币 object');
      expect((programmable.commands[0] as SuiCommandMergeCoins).sources, hasLength(31));
    });

    test('代币余额不足时报错，且一个字节都不提交', () async {
      final node = _FakeSuiService(tokenBalances: [BigInt.from(1000)]);
      await expectLater(
        serviceWith(node).sendToken(chain: chain, token: token, privateKey: privateKey, fromAddress: sender.address, to: recipient.address, amount: '0.5'),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('${token.symbol} 余额不足'))),
      );
      expect(node.submittedTxBytes, isNull);
    });

    test('总额够但碎片过多时，话术与「余额不足」区分开', () async {
      // 用户看着余额充足却被拒，若报「余额不足」只会以为是 bug——而实际上
      // 再发一笔小额就会因为合并而好转。这两种情况必须说清楚是哪一种。
      final node = _FakeSuiService(tokenBalances: [for (var i = 0; i < 40; i++) BigInt.one]);
      await expectLater(
        // 总额 40 个最小单位，选中的 32 个只有 32：够不着 35。
        serviceWith(node).sendToken(chain: chain, token: token, privateKey: privateKey, fromAddress: sender.address, to: recipient.address, amount: '0.000035'),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('碎片过多'))),
      );
      expect(node.submittedTxBytes, isNull);
    });

    test('SUI 不足以支付 gas 时报错', () async {
      // 代币再多也付不了手续费——gas 是另一本账。
      final node = _FakeSuiService(coinBalances: [BigInt.from(2000)]);
      await expectLater(
        serviceWith(node).sendToken(chain: chain, token: token, privateKey: privateKey, fromAddress: sender.address, to: recipient.address, amount: '0.5'),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('${chain.symbol} 不足以支付网络费'))),
      );
      expect(node.submittedTxBytes, isNull);
    });

    test('标准不匹配时拒发，且一个请求都没发出去', () async {
      final node = _FakeSuiService();
      final foreign = Token(
        chainId: token.chainId,
        symbol: token.symbol,
        name: token.name,
        standard: TokenStandard.erc20, // 不是 Sui 的 Coin<T>
        identifier: token.identifier,
        coinGeckoId: token.coinGeckoId,
        decimals: token.decimals,
      );
      await expectLater(
        serviceWith(node).sendToken(chain: chain, token: foreign, privateKey: privateKey, fromAddress: sender.address, to: recipient.address, amount: '0.5'),
        throwsA(isA<UnsupportedError>()),
      );
      expect(node.calls, isEmpty, reason: '标准校验在一切之前，不该产生任何网络请求');
    });

    test('identifier 不是 coin type 形状时拒发', () async {
      final node = _FakeSuiService();
      final malformed = Token(
        chainId: token.chainId,
        symbol: token.symbol,
        name: token.name,
        standard: TokenStandard.suiCoin,
        // Sui 的 coin type 必须是 包::模块::类型；裸地址是 Aptos 的形状。
        identifier: '0x1234',
        coinGeckoId: token.coinGeckoId,
        decimals: token.decimals,
      );
      await expectLater(
        serviceWith(node).sendToken(chain: chain, token: malformed, privateKey: privateKey, fromAddress: sender.address, to: recipient.address, amount: '0.5'),
        throwsA(isA<UnsupportedError>()),
      );
      expect(node.calls, isEmpty);
    });

    test('节点自称主网时中止签名', () async {
      final node = _FakeSuiService(chainIdentifier: '35834a8a');
      await expectLater(
        serviceWith(node).sendToken(chain: chain, token: token, privateKey: privateKey, fromAddress: sender.address, to: recipient.address, amount: '0.5'),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('已中止签名'))),
      );
      expect(node.submittedTxBytes, isNull);
    });

    test('签名地址与钱包地址不一致时拒发', () async {
      final node = _FakeSuiService();
      await expectLater(
        serviceWith(node).sendToken(chain: chain, token: token, privateKey: privateKey, fromAddress: recipient.address, to: recipient.address, amount: '0.5'),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('签名地址与钱包地址不一致'))),
      );
      expect(node.submittedTxBytes, isNull);
    });

    test('金额为 0 时拒发', () async {
      final node = _FakeSuiService();
      await expectLater(
        serviceWith(node).sendToken(chain: chain, token: token, privateKey: privateKey, fromAddress: sender.address, to: recipient.address, amount: '0'),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('必须大于 0'))),
      );
      expect(node.submittedTxBytes, isNull);
    });

    test('dry run 报失败时抛错，绝不拿半截的 gasUsed 当费用', () async {
      final node = _FakeSuiService(dryRunStatus: 'failure');
      await expectLater(
        serviceWith(node).sendToken(chain: chain, token: token, privateKey: privateKey, fromAddress: sender.address, to: recipient.address, amount: '0.5'),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('网络费用估算失败'))),
      );
      expect(node.submittedTxBytes, isNull);
    });
  });

  group('estimateTokenFee', () {
    test('费用以 SUI 计价，且用的是与发送同一组代币 coin', () async {
      final node = _FakeSuiService();
      final estimate = await serviceWith(node).estimateTokenFee(chain: chain, token: token, from: sender.address, to: recipient.address);

      expect(estimate.netGasFee, netGasFee);
      expect(estimate.gasBudget, gasBudget);

      // dry run 的那笔必须与真正要发的那笔同构：同样的 merge + split + transfer，
      // 同样的代币 object 数量。差一个 coin，费用就不是同一个数。
      final probed = (_deserialize(node.dryRunTxBytes!).kind as SuiTransactionKindProgrammableTransaction).transaction;
      expect(probed.commands, hasLength(3));
      expect(probed.commands[0], isA<SuiCommandMergeCoins>());
      expect(probed.inputs, hasLength(4));
      expect(_amountOf(probed), BigInt.one, reason: '探测固定用 1 个最小单位');

      expect(node.calls, isNot(contains('sui_executeTransactionBlock')));
    });

    test('标准不匹配时抛 UnsupportedError，不发任何请求', () async {
      final node = _FakeSuiService();
      final foreign = Token(
        chainId: token.chainId,
        symbol: token.symbol,
        name: token.name,
        standard: TokenStandard.spl,
        identifier: token.identifier,
        coinGeckoId: token.coinGeckoId,
        decimals: token.decimals,
      );
      await expectLater(serviceWith(node).estimateTokenFee(chain: chain, token: foreign, from: sender.address, to: recipient.address), throwsA(isA<UnsupportedError>()));
      expect(node.calls, isEmpty);
    });

    test('账户没有该代币时报错', () async {
      final node = _FakeSuiService(tokenBalances: []);
      await expectLater(
        serviceWith(node).estimateTokenFee(chain: chain, token: token, from: sender.address, to: recipient.address),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('${token.symbol} 余额不足'))),
      );
    });
  });
}

// —— 断言辅助 —— //

SuiTransactionDataV1 _deserialize(String base64TxBytes) => SuiTransactionData.deserialize(StringUtils.encode(base64TxBytes, encoding: StringEncoding.base64)) as SuiTransactionDataV1;

/// PTB 的输入 0 是要转的金额（u64 pure）。
BigInt _amountOf(SuiProgrammableTransaction programmable) => LayoutConst.u64().deserialize((programmable.inputs[0] as SuiCallArgPure).bytes).value;

/// PTB 的输入 1 是收款方地址（address pure）。
SuiAddress _recipientOf(SuiProgrammableTransaction programmable) => SuiAddress.fromBytes((programmable.inputs[1] as SuiCallArgPure).bytes);

/// 假 Sui 节点。与 `sui_transfer_test.dart` 里那个的关键差别：
/// `suix_getCoins` **按 coinType 分流**——SUI 与代币是两份不同的 coin 列表。
class _FakeSuiService with SuiServiceProvider {
  _FakeSuiService({this.chainIdentifier = '4c78adac', List<BigInt>? coinBalances, List<BigInt>? tokenBalances, this.dryRunStatus = 'success'})
    : coinBalances = coinBalances ?? [BigInt.from(1000000000)],
      tokenBalances = tokenBalances ?? [BigInt.from(600000), BigInt.from(400000)];

  static const String _nativeCoinType = '0x2::sui::SUI';

  final String chainIdentifier;

  /// 发送方名下的 **SUI** coin，用来付 gas。默认 1 SUI。
  final List<BigInt> coinBalances;

  /// 发送方名下的**代币** coin。默认两个，合计 1 USDC（6 位精度）。
  final List<BigInt> tokenBalances;

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
      'suix_getCoins' => _coins(requestParams),
      'sui_dryRunTransactionBlock' => _dryRun(requestParams),
      'sui_executeTransactionBlock' => _execute(requestParams),
      _ => throw StateError('假节点没有为 $method 准备响应'),
    };

    return ServiceSuccessRespose(statusCode: 200, response: jsonEncode({'jsonrpc': '2.0', 'id': body['id'], 'result': result}));
  }

  /// 按请求里的 coinType 决定回哪一份列表。分流是这个假节点存在的理由：
  /// 不分流的话「gas 用 SUI、转出用代币」这条最核心的性质就测不到。
  Map<String, dynamic> _coins(List<dynamic> requestParams) {
    final coinType = requestParams[1] as String?;
    final isNative = coinType == null || coinType == _nativeCoinType;
    final balances = isNative ? coinBalances : tokenBalances;
    // 两份列表的 objectId 不能重叠，否则「拿去付 gas 的」和「拿去转账的」
    // 在断言里分不开。代币用 0xaa… 段，SUI 用 0x00… 段。
    final prefix = isNative ? 1 : 170;
    return {
      'data': [for (final (index, balance) in balances.indexed) _coin(prefix + index, balance, coinType ?? _nativeCoinType)],
      'hasNextPage': false,
      'nextCursor': null,
    };
  }

  Map<String, dynamic> _coin(int seed, BigInt balance, String coinType) => {
    'balance': balance.toString(),
    'coinObjectId': '0x${seed.toRadixString(16).padLeft(64, '0')}',
    'coinType': coinType,
    'digest': Base58Encoder.encode(List<int>.filled(32, seed % 256)),
    'previousTransaction': Base58Encoder.encode(List<int>.filled(32, 200)),
    'version': '$seed',
  };

  Map<String, dynamic> _dryRun(List<dynamic> requestParams) {
    dryRunTxBytes = requestParams.first as String;
    return {
      'balanceChanges': <dynamic>[],
      'events': <dynamic>[],
      'objectChanges': <dynamic>[],
      'input': _inputBlock(),
      // 失败时把 storageCost 减半，模拟真实节点「执行中断、只算到一半」的响应。
      'effects': _effects(status: dryRunStatus, storageCost: dryRunStatus == 'success' ? '1976000' : '988000'),
    };
  }

  Map<String, dynamic> _execute(List<dynamic> requestParams) {
    submittedTxBytes = requestParams[0] as String;
    submittedSignatures = (requestParams[1] as List<dynamic>).cast<String>();
    return {'digest': _deserialize(submittedTxBytes!).txHash()};
  }

  /// dry run 响应里的 `input`。服务不读它，但 SDK 的 fromJson 会急切解析。
  Map<String, dynamic> _inputBlock() => {
    'sender': '0x${'0'.padLeft(64, '0')}',
    'gasData': {'budget': '1000000', 'owner': '0x${'0'.padLeft(64, '0')}', 'payment': <dynamic>[], 'price': '1000'},
    'transaction': {'kind': 'ProgrammableTransaction', 'inputs': <dynamic>[], 'transactions': <dynamic>[]},
  };

  Map<String, dynamic> _effects({String status = 'success', String storageCost = '1976000'}) => {
    'executedEpoch': '1',
    'gasObject': {
      'owner': {'AddressOwner': '0x${'0'.padLeft(64, '0')}'},
      'reference': {'digest': Base58Encoder.encode(List<int>.filled(32, 1)), 'objectId': '0x${'1'.padLeft(64, '0')}', 'version': '1'},
    },
    'gasUsed': {'computationCost': '1000000', 'storageCost': storageCost, 'storageRebate': '978120', 'nonRefundableStorageFee': '0'},
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
}
