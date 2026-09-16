import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_core/chains.dart';
import 'package:wallet_core/wallet_core.dart';

final _catalog = TokenCatalog.merge(chains: SupportedChains.all, remote: BundledTokenCatalog.all);
final _sepoliaUsdc = BundledTokenCatalog.all.firstWhere((t) => t.chainId == SupportedChains.ethereumSepolia.id);

/// 只记录收到的请求，不真的上链。
class _RecordingTransfer implements ChainTransferService {
  _RecordingTransfer(this.kind);

  @override
  final ChainKind kind;

  @override
  bool get supportsNative => true;

  // 这个假实现只服务分发测试，两种转账都放行；
  // 「不支持代币」那条路径由 send_logic_test 覆盖，不必在这里再留一个没人用的开关。
  @override
  bool get supportsToken => true;

  TransferRequest? received;

  /// 最近一次被查询状态的交易哈希。
  String? statusQueriedFor;

  @override
  Future<TransferResult> send(TransferRequest request, Wallet wallet) async {
    received = request;
    return (hash: '0xabc', sentAmount: request.amount, status: TransactionStatus.confirmed, validUntilBlock: null);
  }

  @override
  Future<TransactionStatus> queryStatus(Chain chain, String transactionHash, {int? validUntilBlock}) async {
    statusQueriedFor = transactionHash;
    return TransactionStatus.confirmed;
  }
}

const _wallet = Wallet(id: 'w1', name: '测试钱包');

WalletService _service(_RecordingTransfer transfer) =>
    WalletService(transferServices: {transfer.kind: transfer}, catalog: _catalog);

SendTxRequest _request({String? tokenIdentifier, String? chainId, String? to}) => SendTxRequest(
  from: '0x0000000000000000000000000000000000000001',
  // 默认收款地址必须是**校验得过**的：服务层现在会拦非法地址，
  // 随手写的 0x...02 是合法的 40 位十六进制，正好可用。
  to: to ?? '0x0000000000000000000000000000000000000002',
  amount: '1',
  chainId: chainId ?? SupportedChains.ethereumSepolia.id,
  tokenIdentifier: tokenIdentifier,
);

void main() {
  group('WalletService.sendTransaction 地址校验', () {
    // 这组用例守的是「绕过 UI 也必须有校验」这个不变量。
    // 发送页早就校验过一遍，但那是输入提示；这里是资金出口，脚本 / 深链 /
    // 以后的 WalletConnect 都会直接打到这个方法上。

    /// 各链的一个**合法**地址与一个**非法**地址。
    /// 合法地址取自各链真实格式，非法的是「长得像但过不了校验」的那种，
    /// 而不是空字符串——后者太容易被随便一个 isEmpty 挡住，证明不了什么。
    const cases = [
      (
        chain: SupportedChains.ethereumSepolia,
        valid: '0x687F8B54dfeDd622CA535dd381127dD44d6bF064',
        invalid: '0x687F8B54dfeDd622CA535dd381127dD44d6bF06', // 少一位
      ),
      (
        chain: SupportedChains.solanaDevnet,
        valid: '22ACv29Anj696pdw5T5v7TaB5ZynqwHaWXFZWLvzHZGv',
        invalid: '22ACv29Anj696pdw5T5v7TaB5ZynqwHaWXFZWLvzHZG0', // base58 无 '0'
      ),
      (
        chain: SupportedChains.tronNile,
        valid: 'TJRabPrwbZy45sbavfcjinPJC18kjpRTv8',
        invalid: 'TJRabPrwbZy45sbavfcjinPJC18kjpRTv9', // 校验和不对
      ),
    ];

    for (final c in cases) {
      test('${c.chain.name}：非法地址在服务层被拒，不进签名流程', () async {
        final transfer = _RecordingTransfer(c.chain.kind);
        await expectLater(
          _service(transfer).sendTransaction(_request(chainId: c.chain.id, to: c.invalid), _wallet),
          throwsA(isA<ArgumentError>()),
        );
        // 最关键的一条断言：请求根本没到达 transfer service。
        expect(transfer.received, isNull, reason: '非法地址不该被交给任何链实现');
      });

      test('${c.chain.name}：合法地址照常放行', () async {
        final transfer = _RecordingTransfer(c.chain.kind);
        await _service(transfer).sendTransaction(_request(chainId: c.chain.id, to: c.valid), _wallet);
        expect(transfer.received!.to, c.valid);
      });
    }

    test('空地址同样被拒', () async {
      final evm = _RecordingTransfer(ChainKind.evm);
      await expectLater(_service(evm).sendTransaction(_request(to: ''), _wallet), throwsA(isA<ArgumentError>()));
      expect(evm.received, isNull);
    });
  });

  group('WalletService.sendTransaction 分发', () {
    test('无 tokenIdentifier 时按原生币分发', () async {
      final evm = _RecordingTransfer(ChainKind.evm);
      await _service(evm).sendTransaction(_request(), _wallet);

      expect(evm.received!.token, isNull);
      expect(evm.received!.isNative, isTrue);
      expect(evm.received!.chain.id, SupportedChains.ethereumSepolia.id);
    });

    test('带 tokenIdentifier 时从目录解析出代币', () async {
      final evm = _RecordingTransfer(ChainKind.evm);
      await _service(evm).sendTransaction(_request(tokenIdentifier: _sepoliaUsdc.identifier), _wallet);

      expect(evm.received!.token?.symbol, 'USDC');
      expect(evm.received!.token?.decimals, 6);
    });

    test('合约地址大小写不影响解析', () async {
      final evm = _RecordingTransfer(ChainKind.evm);
      await _service(evm).sendTransaction(_request(tokenIdentifier: _sepoliaUsdc.identifier.toLowerCase()), _wallet);

      expect(evm.received!.token?.symbol, 'USDC');
    });

    // 降级成「转原生币」会把一笔 USDC 转账悄悄变成一笔 ETH 转账。
    test('目录里查不到代币即报错，不降级为原生币', () async {
      final evm = _RecordingTransfer(ChainKind.evm);
      await expectLater(
        _service(evm).sendTransaction(_request(tokenIdentifier: '0x000000000000000000000000000000000000dead'), _wallet),
        throwsStateError,
      );
      expect(evm.received, isNull);
    });

    test('Tron 原生币分发到 tron 实现，且带上该链配置', () async {
      final tron = _RecordingTransfer(ChainKind.tron);
      // 收款地址必须是真的 Tron 地址：服务层现在按链校验格式，
      // 默认那个 0x 开头的 EVM 地址在这里会被直接拒掉。
      await _service(tron).sendTransaction(
        _request(chainId: SupportedChains.tronNile.id, to: 'TJRabPrwbZy45sbavfcjinPJC18kjpRTv8'),
        _wallet,
      );

      expect(tron.received!.isNative, isTrue);
      expect(tron.received!.chain.id, SupportedChains.tronNile.id);
      // TRX 是 6 位精度，不是 18——金额换算全靠它。
      expect(tron.received!.chain.decimals, 6);
    });

    test('未注册实现的链类型报「暂未支持」', () async {
      final evm = _RecordingTransfer(ChainKind.evm);
      await expectLater(
        _service(evm).sendTransaction(_request(chainId: SupportedChains.solanaDevnet.id), _wallet),
        throwsUnsupportedError,
      );
    });

    test('缺少 chainId 即报错', () async {
      final evm = _RecordingTransfer(ChainKind.evm);
      await expectLater(
        _service(evm).sendTransaction(const SendTxRequest(from: '0x1', to: '0x2', amount: '1'), _wallet),
        throwsArgumentError,
      );
    });
  });
}
