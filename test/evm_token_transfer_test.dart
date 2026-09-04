import 'package:flutter_test/flutter_test.dart';
import 'package:on_chain/ethereum/ethereum.dart';
import 'package:wallet/blockchain/chain_registry.dart';
import 'package:wallet/blockchain/token.dart';
import 'package:wallet/core/utils/erc20_abi.dart';
import 'package:wallet/enums/evm_send_status.dart';
import 'package:wallet/services/evm_transaction_service.dart';

/// 测试用私钥；地址由它现场派生，不写死。
const _privateKey = '0x4c0883a69102937d6231471b5dbb6204fe5129617082792ae468d01a3f362318';
const _recipient = '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed';
const _chain = SupportedChains.ethereumSepolia;

final _usdc = Token(
  chainId: _chain.id,
  symbol: 'USDC',
  name: 'USD Coin',
  standard: TokenStandard.erc20,
  identifier: '0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238',
  coinGeckoId: 'usd-coin',
  decimals: 6,
);

/// 记录下每一次 RPC 调用的假节点，各方法的返回值可逐项覆盖。
class _FakeNode {
  _FakeNode({this.tokenBalance = '1000000', this.nativeBalance = '0xde0b6b3a7640000', this.gasEstimate = '0xfde8'});

  /// 代币余额（最小单位十进制字符串），默认 1 USDC。
  final String tokenBalance;

  /// 原生币余额（hex quantity），默认 1 ETH。
  final String nativeBalance;

  /// eth_estimateGas 返回值，默认 65000。
  final String gasEstimate;

  final calls = <({String method, List<Object?> params})>[];

  Future<Object?> call(String url, String method, List<Object?> params) async {
    calls.add((method: method, params: params));
    return switch (method) {
      'eth_call' => '0x${BigInt.parse(tokenBalance).toRadixString(16).padLeft(64, '0')}',
      'eth_getTransactionCount' => '0x1',
      'eth_getBalance' => nativeBalance,
      'eth_getBlockByNumber' => {'baseFeePerGas': '0x3b9aca00'}, // 1 gwei
      'eth_feeHistory' => {
        'reward': [
          ['0x3b9aca00', '0x3b9aca00', '0x3b9aca00'],
        ],
      },
      'eth_estimateGas' => gasEstimate,
      'eth_sendRawTransaction' => '0xdeadbeef',
      'eth_getTransactionReceipt' => {'status': '0x1'},
      _ => throw StateError('未预期的 RPC 方法：$method'),
    };
  }

  /// 取某个方法的第一次调用参数；没调过返回 null。
  List<Object?>? paramsOf(String method) {
    for (final c in calls) {
      if (c.method == method) return c.params;
    }
    return null;
  }
}

String get _from => ETHPrivateKey(_privateKey).publicKey().toAddress().address;

Future<({String hash, String sentAmount, EvmSendStatus status})> _send(_FakeNode node, {String amount = '0.5'}) {
  return EvmTransactionService(call: node.call).sendToken(
    chain: _chain,
    token: _usdc,
    privateKeyHex: _privateKey,
    fromAddress: _from,
    to: _recipient,
    amount: amount,
  );
}

void main() {
  group('EvmTransactionService.sendToken', () {
    test('构造 transfer 交易：to 为合约、value 为 0、calldata 带收款人与金额', () async {
      final node = _FakeNode();
      final result = await _send(node);

      expect(result.hash, '0xdeadbeef');
      expect(result.status, EvmSendStatus.confirmed);
      // 金额按代币的 6 位精度换算，不是链的 18 位。
      expect(result.sentAmount, '0.5');

      final estimate = node.paramsOf('eth_estimateGas')!.first as Map<String, Object?>;
      expect(estimate['to'], _usdc.identifier, reason: '交易发往代币合约');
      expect(estimate['value'], '0x0', reason: '代币转账不带原生币');
      expect(estimate['data'], encodeTransfer(to: _recipient, amount: BigInt.from(500000)));
    });

    test('gasLimit 按 estimateGas 上浮 20%，不退回 21000', () async {
      final node = _FakeNode(gasEstimate: '0xfde8'); // 65000
      await _send(node);
      // 广播成功即说明用的是估算值；此处校验确实发起了带 data 的估算。
      expect(node.paramsOf('eth_estimateGas'), isNotNull);
      expect(node.paramsOf('eth_sendRawTransaction'), isNotNull);
    });

    test('代币余额不足即报错，不静默改小金额', () async {
      final node = _FakeNode(tokenBalance: '100000'); // 0.1 USDC
      await expectLater(
        _send(node),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('USDC 余额不足'))),
      );
      expect(node.paramsOf('eth_sendRawTransaction'), isNull, reason: '校验失败不该广播');
    });

    test('原生币不足以支付 gas 即报错', () async {
      final node = _FakeNode(nativeBalance: '0x1'); // 1 wei
      await expectLater(
        _send(node),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('不足以支付网络费'))),
      );
      expect(node.paramsOf('eth_sendRawTransaction'), isNull);
    });

    test('金额为 0 即报错', () async {
      await expectLater(_send(_FakeNode(), amount: '0'), throwsA(isA<Exception>()));
    });

    test('签名地址与钱包地址不一致即报错', () async {
      final node = _FakeNode();
      await expectLater(
        EvmTransactionService(call: node.call).sendToken(
          chain: _chain,
          token: _usdc,
          privateKeyHex: _privateKey,
          fromAddress: _recipient, // 与私钥不对应
          to: _recipient,
          amount: '0.5',
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('非 ERC-20 标准的代币不走这条路径', () async {
      final node = _FakeNode();
      final spl = Token(
        chainId: _chain.id,
        symbol: 'USDC',
        name: 'USD Coin',
        standard: TokenStandard.spl,
        identifier: '4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU',
        coinGeckoId: 'usd-coin',
        decimals: 6,
      );
      await expectLater(
        EvmTransactionService(call: node.call).sendToken(
          chain: _chain,
          token: spl,
          privateKeyHex: _privateKey,
          fromAddress: _from,
          to: _recipient,
          amount: '0.5',
        ),
        throwsUnsupportedError,
      );
    });
  });
}
