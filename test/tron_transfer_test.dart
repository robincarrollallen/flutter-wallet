import 'dart:convert';

import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:on_chain/tron/tron.dart';
import 'package:wallet/blockchain/chain_registry.dart';
import 'package:wallet/data/datasource/remote/chain_balance_api.dart';
import 'package:wallet/domain/tron_fee.dart';
import 'package:wallet/enums/evm_send_status.dart';
import 'package:wallet/services/tron_transaction_service.dart';

/// 测试用私钥；地址由它现场派生，不写死。
const _privateKeyHex = '4c0883a69102937d6231471b5dbb6204fe5129617082792ae468d01a3f362318';
final _privateKey = BytesUtils.fromHexString(_privateKeyHex);
const _chain = SupportedChains.tronNile;

/// 收款方与「被篡改的收款方」同样由私钥派生——写死 base58 字面量很容易
/// 拼出校验和不合法的地址，TronAddress 会直接拒绝。
final _signer = TronPrivateKey.fromBytes(_privateKey);
final _owner = _signer.publicKey().toAddress();
final _recipient = TronPrivateKey('${'1' * 63}2').publicKey().toAddress();
final _attacker = TronPrivateKey('${'2' * 63}3').publicKey().toAddress();

/// 假 Tron 节点：按 path 返回预设响应，并记录每次调用。
///
/// [tamperTo] / [tamperAmount] 用于模拟「节点返回的交易与本地意图不符」，
/// 验证签名前的回解校验确实拦得住。
class _FakeTronService with TronServiceProvider {
  _FakeTronService({
    this.balance = '10000000', // 10 TRX（sun）
    this.tamperTo,
    this.tamperAmount,
    this.broadcastOk = true,
    this.receiptSuccess = true,
    this.freeBandwidth = 600,
    this.stakedBandwidth = 0,
    this.recipientActivated = true,
  });

  final String balance;

  /// 账户当日剩余免费带宽。默认 600（够一笔转账），设为 0 可模拟「要烧 TRX」。
  final int freeBandwidth;

  /// 质押所得带宽。默认 0（普通账户没质押过）——注意激活账户时只有这一档算数。
  final int stakedBandwidth;

  /// 收款方账户是否已上链。false 时 `wallet/getaccount` 返回空对象。
  final bool recipientActivated;
  final TronAddress? tamperTo;
  final BigInt? tamperAmount;
  final bool broadcastOk;
  final bool receiptSuccess;

  final calls = <String>[];

  /// 广播时收到的已签名交易 hex，供断言签名确实发出去了。
  String? broadcastPayload;

  @override
  Future<TronServiceResponse> doRequest(TronRequestDetails params, {Duration? timeout}) async {
    calls.add(params.path!);
    final body = jsonDecode(params.bodyString!) as Map<String, dynamic>;

    final response = switch (params.path) {
      'wallet/createtransaction' => _createTransaction(body),
      'wallet/broadcasthex' => _broadcast(body),
      'wallet/gettransactionbyid' => _receipt(),
      // —— 费用估算用到的三个接口 —— //
      'wallet/getaccountresource' => {
        'freeNetLimit': freeBandwidth,
        'freeNetUsed': 0,
        'NetLimit': stakedBandwidth,
        'NetUsed': 0,
      },
      // 收款方是否已激活：非空且带 address 即视为已激活。
      'wallet/getaccount' => recipientActivated ? {'address': body['address']} : <String, dynamic>{},
      'wallet/getchainparameters' => {
        'chainParameter': [
          {'key': 'getTransactionFee', 'value': 1000},
          {'key': 'getCreateAccountFee', 'value': 100000},
          {'key': 'getCreateNewAccountFeeInSystemContract', 'value': 1000000},
        ],
      },
      _ => throw StateError('未预期的 Tron 接口：${params.path}'),
    };

    return ServiceSuccessRespose(statusCode: 200, response: jsonEncode(response));
  }

  /// 仿真实节点：回填区块引用与过期时间，合约体照抄请求（除非被要求篡改）。
  Map<String, dynamic> _createTransaction(Map<String, dynamic> request) {
    final amount = tamperAmount ?? BigInt.parse('${request['amount']}');
    final to = tamperTo?.toAddress() ?? request['to_address'] as String;
    return {
      'visible': true,
      'raw_data': {
        'contract': [
          {
            'parameter': {
              'value': {
                'amount': amount.toInt(),
                'owner_address': request['owner_address'],
                'to_address': to,
              },
              'type_url': 'type.googleapis.com/protocol.TransferContract',
            },
            'type': 'TransferContract',
          },
        ],
        'ref_block_bytes': 'aabb',
        'ref_block_hash': '0011223344556677',
        'expiration': 1700000060000,
        'timestamp': 1700000000000,
      },
    };
  }

  Map<String, dynamic> _broadcast(Map<String, dynamic> request) {
    broadcastPayload = request['transaction'] as String;
    // 真实节点广播成功时回的是签名后交易的 txID。
    final signed = Transaction.deserialize(BytesUtils.fromHexString(broadcastPayload!));
    return broadcastOk
        ? {'result': true, 'txid': signed.rawData.txID, 'transaction': jsonEncode(signed.toJson())}
        : {'result': false, 'txid': '', 'code': 'SIGERROR', 'message': '签名无效', 'transaction': '{}'};
  }

  Map<String, dynamic> _receipt() => {
    'txID': 'a' * 64,
    'raw_data': <String, dynamic>{},
    'raw_data_hex': '00',
    'signature': <String>[],
    'ret': [
      {'contractRet': receiptSuccess ? 'SUCCESS' : 'REVERT'},
    ],
  };
}

/// 假余额源，替掉真实的 `wallet/getaccount` 网络查询。
class _FakeBalances implements ChainBalanceApi {
  const _FakeBalances(this.balance);

  /// 原生币余额（sun）。
  final String balance;

  @override
  Future<BigInt> fetchNativeBalance(Chain chain, String address) async => BigInt.parse(balance);

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

TronTransactionService _service(_FakeTronService node) =>
    TronTransactionService(provider: TronProvider(node), balances: _FakeBalances(node.balance));

Future<({String hash, String sentAmount, EvmSendStatus status})> _send(
  _FakeTronService node, {
  String amount = '1.5',
  String? from,
}) => _service(node).sendNative(
  chain: _chain,
  privateKey: _privateKey,
  fromAddress: from ?? _owner.toAddress(),
  to: _recipient.toAddress(),
  amount: amount,
);

void main() {
  group('TronTransactionService.estimateNativeFee', () {
    Future<TronFeeEstimate> estimate(_FakeTronService node) => _service(node).estimateNativeFee(
      chain: _chain,
      from: _owner.toAddress(),
      to: _recipient.toAddress(),
      amount: '1.5',
    );

    test('带宽充足且收款方已激活时免费', () async {
      final fee = await estimate(_FakeTronService(freeBandwidth: 600));
      expect(fee.isFree, isTrue);
      expect(fee.activatesRecipient, isFalse);
      expect(fee.bandwidthAvailable, BigInt.from(600));
    });

    test('带宽为 0 时按字节烧 TRX', () async {
      final fee = await estimate(_FakeTronService(freeBandwidth: 0));
      expect(fee.isFree, isFalse);
      expect(fee.feeSun, BigInt.from(fee.bandwidthNeeded * 1000));
    });

    // 未激活的账户 wallet/getaccount 返回 {}，绝不能被当成「已激活且余额 0」。
    //
    // 只有免费带宽（普通账户的常态）时总额是 1.1 TRX：免费额度不能用于创建账户，
    // 所以那 0.1 TRX 的带宽费躲不掉。
    test('收款方未激活时识别出激活费，且免费带宽抵不掉带宽费', () async {
      final fee = await estimate(_FakeTronService(recipientActivated: false));
      expect(fee.activatesRecipient, isTrue);
      expect(fee.activationFeeSun, BigInt.from(1000000));
      expect(fee.bandwidthFeeSun, BigInt.from(100000));
      expect(fee.feeSun, BigInt.from(1100000));
    });

    test('有足够质押带宽时激活只花 1 TRX', () async {
      final fee = await estimate(_FakeTronService(recipientActivated: false, stakedBandwidth: 600));
      expect(fee.feeSun, BigInt.from(1000000));
      expect(fee.bandwidthFeeSun, BigInt.zero);
    });
  });

  group('TronTransactionService.sendNative', () {
    test('按 6 位精度把金额换算成 sun 并发给节点', () async {
      final node = _FakeTronService();
      final result = await _send(node, amount: '1.5');

      // 1.5 TRX = 1_500_000 sun。若误用 18 位精度这里会差 12 个数量级。
      final signed = Transaction.deserialize(BytesUtils.fromHexString(node.broadcastPayload!));
      final contract = signed.rawData.contract.single.parameter.value as TransferContract;
      expect(contract.amount, BigInt.from(1500000));
      expect(contract.toAddress, _recipient);
      expect(contract.ownerAddress, _owner);

      expect(result.sentAmount, '1.5');
      expect(result.status, EvmSendStatus.confirmed);
      expect(result.hash, signed.rawData.txID);
    });

    test('交易确实被签名后才广播', () async {
      final node = _FakeTronService();
      await _send(node);

      final signed = Transaction.deserialize(BytesUtils.fromHexString(node.broadcastPayload!));
      expect(signed.signature, hasLength(1));
      expect(signed.signature.single, isNotEmpty);
    });


    // 下面两条是本实现的安全支点：createtransaction 由节点构造，
    // 若不校验就签，一个被劫持的节点即可改掉收款方或金额。
    test('节点篡改收款方时中止签名', () async {
      final node = _FakeTronService(tamperTo: _attacker);

      await expectLater(_send(node), throwsA(isA<Exception>()));
      expect(node.broadcastPayload, isNull, reason: '不该广播任何东西');
      expect(node.calls, isNot(contains('wallet/broadcasthex')));
    });

    test('节点篡改金额时中止签名', () async {
      final node = _FakeTronService(tamperAmount: BigInt.from(9999999));

      await expectLater(_send(node), throwsA(isA<Exception>()));
      expect(node.broadcastPayload, isNull);
    });

    test('余额不足即报错，且不构造交易', () async {
      final node = _FakeTronService(balance: '1000000'); // 1 TRX，不够转 1.5

      await expectLater(_send(node, amount: '1.5'), throwsA(isA<Exception>()));
      expect(node.calls, isNot(contains('wallet/createtransaction')));
    });

    test('签名地址与钱包地址不一致时报错', () async {
      final node = _FakeTronService();

      await expectLater(_send(node, from: _attacker.toAddress()), throwsA(isA<Exception>()));
      expect(node.calls, isEmpty);
    });

    test('金额为 0 时报错', () async {
      final node = _FakeTronService();
      await expectLater(_send(node, amount: '0'), throwsA(isA<Exception>()));
    });

    test('广播失败时上抛节点给的原因', () async {
      final node = _FakeTronService(broadcastOk: false);

      await expectLater(
        _send(node),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('签名无效'))),
      );
    });

    // 余额刚好等于金额时，带宽够就该放行、带宽不够就该拦下——这正是「余额校验
    // 计入网络费」的意义：不然这笔会广播出去再在链上失败。
    test('余额刚好等于金额：带宽够则放行', () async {
      final node = _FakeTronService(balance: '1500000', freeBandwidth: 600);
      final result = await _send(node, amount: '1.5');
      expect(result.status, EvmSendStatus.confirmed);
    });

    test('余额刚好等于金额：带宽不足则报错并提示含网络费', () async {
      final node = _FakeTronService(balance: '1500000', freeBandwidth: 0);
      await expectLater(
        _send(node, amount: '1.5'),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('含网络费用'))),
      );
      expect(node.calls, isNot(contains('wallet/broadcasthex')));
    });

    // 向未激活账户转账要多付 1 TRX 创建费，余额校验必须算上。
    test('收款方未激活时把 1 TRX 创建费计入余额校验', () async {
      // 余额 1.5 TRX，转 1.5 TRX：带宽够，但激活费 1 TRX 让总额超出。
      final node = _FakeTronService(balance: '1500000', recipientActivated: false);
      await expectLater(_send(node, amount: '1.5'), throwsA(isA<Exception>()));
      expect(node.calls, isNot(contains('wallet/broadcasthex')));
    });

    test('回执显示执行失败时状态为 failed', () async {
      final node = _FakeTronService(receiptSuccess: false);
      final result = await _send(node);

      expect(result.status, EvmSendStatus.failed);
    });
  });
}
