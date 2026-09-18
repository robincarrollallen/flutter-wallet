import 'dart:convert';

import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:on_chain/aptos/aptos.dart';
import 'package:wallet_core/chains.dart';
import 'package:wallet_core/rpc.dart';
import 'package:wallet_core/wallet_core.dart';

/// Aptos 代币（Fungible Asset）转账的离线测试。
///
/// 与 `aptos_transfer_test.dart` / `solana_token_transfer_test.dart` 同一形态：
/// **全程不碰网络**，节点由 [_FakeAptosService] 假扮，断言一律反序列化提交的字节。
///
/// 代币**从真实目录里取**而不是写死 identifier：写死的话目录一改，这里还在测一个
/// 已经不存在的代币，而断言照样全绿。
void main() {
  final chain = SupportedChains.byId('aptos-testnet');
  final token = BundledTokenCatalog.all.firstWhere(
    (candidate) => candidate.chainId == chain.id && candidate.standard == TokenStandard.aptosCoin,
  );

  final privateKey = List<int>.filled(32, 7);
  final signer = AptosED25519PrivateKey.fromBytes(privateKey);
  final sender = signer.publicKey.toAddress();
  final recipient = AptosED25519PrivateKey.fromBytes(List<int>.filled(32, 9)).publicKey.toAddress();

  // 假节点的模拟回 700 gas，服务据此算出上限 700 × 3 ÷ 2 + 200。
  final maxGasAmount = BigInt.from(1250);
  const regularGasPrice = 100;
  final normalFee = BigInt.from(regularGasPrice) * maxGasAmount; // 125000 octa = 0.00125 APT

  /// 代币余额 20 USDC（6 位精度），原生币 1 APT——两者都够，负例再单独调小。
  final twentyUsdc = BigInt.from(20000000);
  final oneApt = BigInt.from(100000000);

  AptosTransactionService serviceWith(
    _FakeAptosService node, {
    BigInt? nativeBalance,
    BigInt? tokenBalance,
  }) => AptosTransactionService(
    provider: AptosProvider(node),
    balances: _FixedBalances(native: nativeBalance ?? oneApt, token: tokenBalance ?? twentyUsdc),
  );

  group('sendToken', () {
    test('构造 primary_fungible_store::transfer 并提交', () async {
      final node = _FakeAptosService();
      final result = await serviceWith(node).sendToken(
        chain: chain,
        token: token,
        privateKey: privateKey,
        fromAddress: sender.address,
        to: recipient.address,
        amount: '1.5',
      );

      expect(result.status, TransactionStatus.pending);
      expect(result.validUntilBlock, isNull);

      final sent = AptosSignedTransaction.deserialize(node.submittedTransaction!);
      expect(result.hash, '0x${sent.txHash()}');

      final entry = _entryFunctionOf(sent);
      // 走 primary_fungible_store 而不是 fungible_asset：前者会在收款方没有主存储时
      // 顺带建一个。选错模块，转给一个没持有过这个币的人就会失败。
      expect(entry.moduleId.address, AptosAddress.one);
      expect(entry.moduleId.name, 'primary_fungible_store');
      expect(entry.functionName, 'transfer');

      // 类型参数不能少：transfer 的签名是 <T: key>，缺了 Move 层对不上。
      expect(entry.typeArgs, hasLength(1));
      final typeArg = entry.typeArgs.single as AptosTypeTagStruct;
      expect(typeArg.value.address, AptosAddress.one);
      expect(typeArg.value.moduleName, 'fungible_asset');
      expect(typeArg.value.name, 'Metadata');

      // 三个实参：metadata（转的是哪种资产）、收款方、金额。
      expect(entry.args, hasLength(3));
      expect(_addressArgument(sent, 0), AptosAddress(token.identifier));
      expect(_addressArgument(sent, 1), recipient);
      expect(_amountArgument(sent, 2), BigInt.from(1500000));

      // 签名必须真的验得过。
      final authenticator = sent.authenticator as AptosTransactionAuthenticatorEd25519;
      expect(
        authenticator.publicKey.verify(
          message: sent.rawTransaction.signingSerialize(),
          signature: authenticator.signature.signature,
        ),
        isTrue,
      );
    });

    test('金额按代币精度换算，不是链的精度', () async {
      final node = _FakeAptosService();
      final result = await serviceWith(node).sendToken(
        chain: chain,
        token: token,
        privateKey: privateKey,
        fromAddress: sender.address,
        to: recipient.address,
        amount: '1',
      );

      expect(token.decimals, 6, reason: '本例依赖 USDC 是 6 位');
      expect(chain.decimals, 8, reason: '而 APT 是 8 位——拿错一个差 100 倍');
      final sent = AptosSignedTransaction.deserialize(node.submittedTransaction!);
      expect(_amountArgument(sent, 2), BigInt.from(1000000));
      expect(result.sentAmount, '1');
    });

    test('代币余额不足时报错，且不提交', () async {
      final node = _FakeAptosService();
      await expectLater(
        serviceWith(node, tokenBalance: BigInt.from(500000)).sendToken(
          chain: chain,
          token: token,
          privateKey: privateKey,
          fromAddress: sender.address,
          to: recipient.address,
          amount: '1',
        ),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('${token.symbol} 余额不足'))),
      );
      expect(node.calls, isNot(contains('/transactions')));
    });

    test('原生币不足以支付网络费时报错，且不提交', () async {
      final node = _FakeAptosService();
      await expectLater(
        // 代币够，APT 不够——这是与代币余额分开的第二本账。
        serviceWith(node, nativeBalance: normalFee - BigInt.one).sendToken(
          chain: chain,
          token: token,
          privateKey: privateKey,
          fromAddress: sender.address,
          to: recipient.address,
          amount: '1',
        ),
        throwsA(
          isA<Exception>().having((e) => e.toString(), 'message', contains('${chain.symbol} 不足以支付网络费')),
        ),
      );
      expect(node.calls, isNot(contains('/transactions')));
    });

    test('标准不是 aptosCoin 时拒绝', () async {
      final node = _FakeAptosService();
      final foreign = Token(
        chainId: token.chainId,
        symbol: token.symbol,
        name: token.name,
        standard: TokenStandard.erc20,
        identifier: token.identifier,
        coinGeckoId: token.coinGeckoId,
        decimals: token.decimals,
      );
      await expectLater(
        serviceWith(node).sendToken(
          chain: chain,
          token: foreign,
          privateKey: privateKey,
          fromAddress: sender.address,
          to: recipient.address,
          amount: '1',
        ),
        throwsA(isA<UnsupportedError>()),
      );
      expect(node.calls, isEmpty, reason: '标准校验在一切之前，连链上数据都不该取');
    });

    test('Coin 标准（identifier 含 ::）明确拒绝，而不是当成 FA 发出去', () async {
      final node = _FakeAptosService();
      // 旧的 Coin 标准用类型结构做 identifier，入口函数是
      // aptos_account::transfer_coins<T>，与 FA 完全不同。TokenStandard 分不出来，
      // 只能看形状——分错的后果是拿一个类型结构当对象地址去转，必然失败。
      final coin = Token(
        chainId: token.chainId,
        symbol: 'LEGACY',
        name: 'Legacy Coin',
        standard: TokenStandard.aptosCoin,
        identifier: '0x1::legacy_coin::LegacyCoin',
        coinGeckoId: token.coinGeckoId,
        decimals: 6,
      );
      await expectLater(
        serviceWith(node).sendToken(
          chain: chain,
          token: coin,
          privateKey: privateKey,
          fromAddress: sender.address,
          to: recipient.address,
          amount: '1',
        ),
        throwsA(
          isA<UnsupportedError>().having((e) => e.message, 'message', contains('Fungible Asset')),
        ),
      );
      expect(node.calls, isEmpty);
    });

    test('签名地址与钱包地址不一致时拒发', () async {
      final node = _FakeAptosService();
      await expectLater(
        serviceWith(node).sendToken(
          chain: chain,
          token: token,
          privateKey: privateKey,
          fromAddress: recipient.address,
          to: recipient.address,
          amount: '1',
        ),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('签名地址与钱包地址不一致'))),
      );
      expect(node.calls, isNot(contains('/transactions')));
    });

    test('金额为 0 时拒发', () async {
      final node = _FakeAptosService();
      await expectLater(
        serviceWith(node).sendToken(
          chain: chain,
          token: token,
          privateKey: privateKey,
          fromAddress: sender.address,
          to: recipient.address,
          amount: '0',
        ),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('必须大于 0'))),
      );
      expect(node.calls, isEmpty);
    });

    test('模拟判定会失败时不提交，并带上 vm_status', () async {
      // 这条不只是凑负例：目录里这枚 USDC 是**可派发**（dispatchable）FA，带
      // override_deposit 钩子。万一 primary_fungible_store::transfer 对它 abort，
      // 暴露出来的正是这条路径——模拟失败、原样把 vm_status 抛给用户。
      final node = _FakeAptosService(simulationSucceeds: false);
      await expectLater(
        serviceWith(node).sendToken(
          chain: chain,
          token: token,
          privateKey: privateKey,
          fromAddress: sender.address,
          to: recipient.address,
          amount: '1',
        ),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('INSUFFICIENT_BALANCE'))),
      );
      expect(node.calls, isNot(contains('/transactions')));
    });

    test('模拟用探测金额而不是用户填的金额', () async {
      final node = _FakeAptosService();
      await serviceWith(node).sendToken(
        chain: chain,
        token: token,
        privateKey: privateKey,
        fromAddress: sender.address,
        to: recipient.address,
        amount: '1.5',
        speed: FeeSpeed.fast,
      );

      expect(node.calls.where((path) => path == '/transactions/simulate').length, 1);
      final simulated = AptosSignedTransaction.deserialize(node.simulatedTransaction!);
      expect(_amountArgument(simulated, 2), BigInt.one);
      expect(simulated.rawTransaction.gasUnitPrice, BigInt.from(150), reason: '模拟与提交同一档单价');
      // 探测交易也必须是代币那份 payload——拿原生转账去探测，量出来的 gas 是另一回事。
      expect(_entryFunctionOf(simulated).moduleId.name, 'primary_fungible_store');
    });
  });

  group('estimateTokenFee', () {
    test('用静态上限，不走模拟', () async {
      final node = _FakeAptosService();
      final estimate = await serviceWith(node).estimateTokenFee(
        chain: chain,
        token: token,
        from: sender.address,
        to: recipient.address,
      );

      // 模拟会校验公钥（对不上回 INVALID_AUTH_KEY），走它就等于要解锁私钥。
      expect(node.calls, isNot(contains('/transactions/simulate')));
      // 9000 来自 testnet 实测：建存储那一笔 5715，留约 1.6 倍余量。
      expect(estimate.maxGasAmount, BigInt.from(9000));
      final quote = estimate.quoteFor(FeeSpeed.normal);
      // 没模拟就没有「实际消耗」，预计实付与上限相等，不编一个更小的值。
      expect(quote.expectedFee, quote.maxFee);
      expect(quote.maxFee, BigInt.from(regularGasPrice) * BigInt.from(9000));
    });

    test('三档单价仍取自节点', () async {
      final node = _FakeAptosService();
      final estimate = await serviceWith(node).estimateTokenFee(
        chain: chain,
        token: token,
        from: sender.address,
        to: recipient.address,
      );
      expect(estimate.priceFor(FeeSpeed.slow), BigInt.from(90));
      expect(estimate.priceFor(FeeSpeed.normal), BigInt.from(regularGasPrice));
      expect(estimate.priceFor(FeeSpeed.fast), BigInt.from(150));
    });

    test('Coin 标准在估费阶段就拒绝，不等到发送', () async {
      final node = _FakeAptosService();
      final coin = Token(
        chainId: token.chainId,
        symbol: 'LEGACY',
        name: 'Legacy Coin',
        standard: TokenStandard.aptosCoin,
        identifier: '0x1::legacy_coin::LegacyCoin',
        coinGeckoId: token.coinGeckoId,
        decimals: 6,
      );
      await expectLater(
        serviceWith(node).estimateTokenFee(chain: chain, token: coin, from: sender.address, to: recipient.address),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });
}

AptosTransactionEntryFunction _entryFunctionOf(AptosSignedTransaction transaction) {
  final payload = transaction.rawTransaction.transactionPayload as AptosTransactionPayloadEntryFunction;
  return payload.entryFunction;
}

/// entry function 的实参在 BCS 里是一串裸字节，反序列化回来是
/// [AptosTransactionArgumentBytes]，所以要按参数位置自己解读。
List<int> _argumentBytes(AptosSignedTransaction transaction, int index) =>
    _entryFunctionOf(transaction).args[index].value as List<int>;

AptosAddress _addressArgument(AptosSignedTransaction transaction, int index) =>
    AptosAddress.fromBytes(_argumentBytes(transaction, index));

/// u64 小端。
BigInt _amountArgument(AptosSignedTransaction transaction, int index) {
  final bytes = _argumentBytes(transaction, index);
  var value = BigInt.zero;
  for (var i = bytes.length - 1; i >= 0; i--) {
    value = (value << 8) | BigInt.from(bytes[i]);
  }
  return value;
}

/// 固定余额的余额源。原生与代币都要覆盖——只覆盖原生的话，代币那一路会真打网络。
class _FixedBalances extends ChainBalanceApi {
  const _FixedBalances({required this.native, required this.token});

  final BigInt native;
  final BigInt token;

  @override
  Future<BigInt> fetchNativeBalance(Chain chain, String address) async => native;

  @override
  Future<BigInt> fetchTokenBalance(Chain chain, Token token, String address) async => this.token;
}

/// 假节点：按 REST 路径路由预设响应，录下请求路径与提交的字节。
///
/// 与 `aptos_transfer_test.dart` 里那份同形。刻意各留一份而不是抽公共文件：
/// 两边预设的响应会各自随被测路径演化，共用一份只会让其中一边被迫迁就另一边。
class _FakeAptosService with AptosServiceProvider {
  _FakeAptosService({this.simulationSucceeds = true});

  final bool simulationSucceeds;

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
      // 真实节点回的哈希带 `0x`，SDK 的 txHash() 不带——保留这个差异，
      // 否则那条一致性校验的归一化就没被测到。
      return _ok(jsonEncode(_pendingTransaction('0x${AptosSignedTransaction.deserialize(body).txHash()}')));
    }
    if (path == '/estimate_gas_price') {
      return _ok(
        jsonEncode({
          'deprioritized_gas_estimate': 90,
          'gas_estimate': 100,
          'prioritized_gas_estimate': 150,
        }),
      );
    }
    if (path == '/') return _ok(jsonEncode(_ledgerInfo));
    if (path.startsWith('/accounts/')) {
      return _ok(jsonEncode({'sequence_number': '5', 'authentication_key': '0x${'0' * 64}'}));
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
    'function': '0x1::primary_fungible_store::transfer',
    'type_arguments': <String>['0x1::fungible_asset::Metadata'],
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
    'max_gas_amount': '30000',
    'gas_unit_price': '100',
    'expiration_timestamp_secs': '1700000060',
    'payload': _payload,
    'signature': null,
    'events': <Map<String, dynamic>>[],
    'timestamp': '1700000000000000',
  };
}
