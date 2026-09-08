import 'dart:convert';

import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:on_chain/tron/tron.dart';
import 'package:wallet/blockchain/chain_registry.dart';
import 'package:wallet/blockchain/token.dart';
import 'package:wallet/data/datasource/remote/chain_balance_api.dart';
import 'package:wallet/enums/evm_send_status.dart';
import 'package:wallet/services/tron_transaction_service.dart';

const _privateKeyHex = '4c0883a69102937d6231471b5dbb6204fe5129617082792ae468d01a3f362318';
final _privateKey = BytesUtils.fromHexString(_privateKeyHex);
const _chain = SupportedChains.tronNile;

final _owner = TronPrivateKey.fromBytes(_privateKey).publicKey().toAddress();
final _recipient = TronPrivateKey('${'1' * 63}2').publicKey().toAddress();
final _attacker = TronPrivateKey('${'2' * 63}3').publicKey().toAddress();
final _contract = TronPrivateKey('${'3' * 63}4').publicKey().toAddress();

final _usdt = Token(
  chainId: _chain.id,
  symbol: 'USDT',
  name: 'Tether USD',
  standard: TokenStandard.trc20,
  identifier: _contract.toAddress(),
  coinGeckoId: 'tether',
  decimals: 6,
);

/// 假 Tron 节点，覆盖 TRC-20 转账用到的接口。
class _FakeNode with TronServiceProvider {
  _FakeNode({
    this.energyUsed = 30000,
    this.energyAvailable = 0,
    this.revert = false,
    this.tamperTo,
    this.tamperContract,
  });

  /// 模拟调用返回的能量消耗。
  final int energyUsed;

  /// 账户可用能量。
  final int energyAvailable;

  /// 让模拟调用回滚——余额不足时真实节点就是这样。
  final bool revert;

  /// 让节点在构造交易时把收款方 / 合约地址换掉，验证回解校验拦得住。
  final TronAddress? tamperTo;
  final TronAddress? tamperContract;

  final calls = <String>[];
  String? broadcastPayload;

  @override
  Future<TronServiceResponse> doRequest(TronRequestDetails params, {Duration? timeout}) async {
    calls.add(params.path!);
    final body = jsonDecode(params.bodyString!) as Map<String, dynamic>;

    final response = switch (params.path) {
      'wallet/getaccountresource' => {
        'freeNetLimit': 600,
        'freeNetUsed': 0,
        'NetLimit': 0,
        'NetUsed': 0,
        'EnergyLimit': energyAvailable,
        'EnergyUsed': 0,
      },
      'wallet/getchainparameters' => {
        'chainParameter': [
          {'key': 'getTransactionFee', 'value': 1000},
          {'key': 'getEnergyFee', 'value': 100},
          {'key': 'getCreateAccountFee', 'value': 100000},
          {'key': 'getCreateNewAccountFeeInSystemContract', 'value': 1000000},
        ],
      },
      'wallet/triggerconstantcontract' => {
        'result': revert
            ? {'result': true, 'message': 'REVERT opcode executed'}
            : {'result': true},
        'energy_used': revert ? 1984 : energyUsed,
        'constant_result': [''],
      },
      'wallet/triggersmartcontract' => _buildTransaction(body),
      'wallet/broadcasthex' => _broadcast(body),
      'wallet/gettransactionbyid' => {
        'txID': 'a' * 64,
        'raw_data': <String, dynamic>{},
        'raw_data_hex': '00',
        'signature': <String>[],
        'ret': [
          {'contractRet': 'SUCCESS'},
        ],
      },
      _ => throw StateError('未预期的 Tron 接口：${params.path}'),
    };

    return ServiceSuccessRespose(statusCode: 200, response: jsonEncode(response));
  }

  /// 仿真实节点构造合约调用交易；被要求篡改时改掉 data 或合约地址。
  ///
  /// 真实节点收到的是 `function_selector` + `parameter` 两个字段，由它拼成
  /// calldata 放进交易——这里照同一口径拼，否则测的就不是真实形状。
  Map<String, dynamic> _buildTransaction(Map<String, dynamic> request) {
    final selector = request['function_selector'] as String;
    expect(selector, 'transfer(address,uint256)');
    var data = 'a9059cbb${request['parameter']}';
    if (tamperTo != null) {
      // 把 calldata 里的收款方换成攻击者，金额保持不变。
      final addr = BytesUtils.toHexString(tamperTo!.toBytes().sublist(1)).padLeft(64, '0');
      data = data.substring(0, 8) + addr + data.substring(72);
    }
    return {
      'result': {'result': true},
      'transaction': {
        'visible': true,
        'raw_data': {
          'contract': [
            {
              'parameter': {
                'value': {
                  'owner_address': request['owner_address'],
                  'contract_address': tamperContract?.toAddress() ?? request['contract_address'],
                  'data': data,
                },
                'type_url': 'type.googleapis.com/protocol.TriggerSmartContract',
              },
              'type': 'TriggerSmartContract',
            },
          ],
          'ref_block_bytes': 'aabb',
          'ref_block_hash': '0011223344556677',
          'expiration': 1700000060000,
          'timestamp': 1700000000000,
          'fee_limit': request['fee_limit'],
        },
      },
    };
  }

  Map<String, dynamic> _broadcast(Map<String, dynamic> request) {
    broadcastPayload = request['transaction'] as String;
    final signed = Transaction.deserialize(BytesUtils.fromHexString(broadcastPayload!));
    return {'result': true, 'txid': signed.rawData.txID, 'transaction': jsonEncode(signed.toJson())};
  }
}

/// 假余额源：代币余额与 TRX 余额分别可控——它们是两本账。
class _FakeBalances implements ChainBalanceApi {
  const _FakeBalances({this.tokenBalance = '1000000000', this.trxBalance = '1000000000'});

  final String tokenBalance;
  final String trxBalance;

  @override
  Future<BigInt> fetchNativeBalance(Chain chain, String address) async => BigInt.parse(trxBalance);

  @override
  Future<BigInt> fetchTokenBalance(Chain chain, Token token, String address) async =>
      BigInt.parse(tokenBalance);

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

TronTransactionService _service(_FakeNode node, {_FakeBalances balances = const _FakeBalances()}) =>
    TronTransactionService(provider: TronProvider(node), balances: balances);

Future<({String hash, String sentAmount, EvmSendStatus status})> _send(
  _FakeNode node, {
  String amount = '5',
  _FakeBalances balances = const _FakeBalances(),
}) => _service(node, balances: balances).sendToken(
  chain: _chain,
  token: _usdt,
  privateKey: _privateKey,
  fromAddress: _owner.toAddress(),
  to: _recipient.toAddress(),
  amount: amount,
);

void main() {
  group('estimateTokenFee', () {
    Future<void> expectFee(_FakeNode node, BigInt expected) async {
      final fee = await _service(node).estimateTokenFee(
        chain: _chain,
        token: _usdt,
        from: _owner.toAddress(),
        to: _recipient.toAddress(),
        amount: '5',
      );
      expect(fee.energyFeeSun, expected);
    }

    // 能量按 1.2 倍上浮后再算差额；Nile 费率 100 sun/energy。
    test('无能量时按上浮后的用量全额烧', () async {
      await expectFee(_FakeNode(energyUsed: 30000), BigInt.from(36000 * 100));
    });

    test('能量充足时不烧 TRX', () async {
      await expectFee(_FakeNode(energyUsed: 30000, energyAvailable: 50000), BigInt.zero);
    });

    // 回滚的模拟只花了 1984 能量，照单全收会把费用说成真实值的 1/15。
    test('模拟回滚时报错，而不是拿回滚前的能量当估算', () async {
      await expectLater(
        _service(_FakeNode(revert: true)).estimateTokenFee(
          chain: _chain,
          token: _usdt,
          from: _owner.toAddress(),
          to: _recipient.toAddress(),
          amount: '5',
        ),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('模拟失败'))),
      );
    });
  });

  group('sendToken', () {
    test('按代币精度换算金额，并广播已签名交易', () async {
      final node = _FakeNode();
      final result = await _send(node, amount: '5');

      final signed = Transaction.deserialize(BytesUtils.fromHexString(node.broadcastPayload!));
      final call = signed.rawData.contract.single.parameter.value as TriggerSmartContract;
      // USDT 是 6 位精度：5 USDT = 5_000_000。
      expect(BytesUtils.toHexString(call.data!).endsWith(BigInt.from(5000000).toRadixString(16).padLeft(64, '0')), isTrue);
      expect(call.contractAddress, _contract);
      expect(result.sentAmount, '5');
      expect(result.status, EvmSendStatus.confirmed);
    });

    // 与原生转账同一个安全支点：合约调用的收款方与金额都藏在 ABI 编码的 data 里，
    // 不比对就等于让节点决定这笔代币转给谁。
    test('节点篡改 calldata 里的收款方时中止签名', () async {
      final node = _FakeNode(tamperTo: _attacker);
      await expectLater(_send(node), throwsA(isA<Exception>()));
      expect(node.broadcastPayload, isNull);
    });

    test('节点篡改合约地址时中止签名', () async {
      final node = _FakeNode(tamperContract: _attacker);
      await expectLater(_send(node), throwsA(isA<Exception>()));
      expect(node.broadcastPayload, isNull);
    });

    test('代币余额不足即报错，且不构造交易', () async {
      final node = _FakeNode();
      await expectLater(
        _send(node, amount: '5', balances: const _FakeBalances(tokenBalance: '1000000')),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('USDT 余额不足'))),
      );
      expect(node.calls, isNot(contains('wallet/triggersmartcontract')));
    });

    // 手续费付的是 TRX，与代币余额是两本账：代币够、TRX 不够也得拦下。
    test('TRX 不足以付网络费时报错', () async {
      final node = _FakeNode(energyUsed: 30000);
      await expectLater(
        _send(node, balances: const _FakeBalances(trxBalance: '1000')),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('不足以支付网络费'))),
      );
      expect(node.broadcastPayload, isNull);
    });

    test('非 TRC-20 代币直接拒绝', () async {
      final erc20 = Token(
        chainId: _chain.id,
        symbol: 'FAKE',
        name: 'Fake',
        standard: TokenStandard.erc20,
        identifier: _contract.toAddress(),
        coinGeckoId: 'fake',
        decimals: 6,
      );
      await expectLater(
        _service(_FakeNode()).sendToken(
          chain: _chain,
          token: erc20,
          privateKey: _privateKey,
          fromAddress: _owner.toAddress(),
          to: _recipient.toAddress(),
          amount: '1',
        ),
        throwsUnsupportedError,
      );
    });
  });
}
