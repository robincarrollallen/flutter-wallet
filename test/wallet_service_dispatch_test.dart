import 'package:flutter_test/flutter_test.dart';
import 'package:wallet/blockchain/bundled_token_catalog.dart';
import 'package:wallet/blockchain/chain_registry.dart';
import 'package:wallet/blockchain/token_catalog.dart';
import 'package:wallet/domain/wallet.dart';
import 'package:wallet/dto/request/send_tx_request.dart';
import 'package:wallet/enums/evm_send_status.dart';
import 'package:wallet/services/transfer/chain_transfer_service.dart';
import 'package:wallet/services/wallet_service.dart';

final _catalog = TokenCatalog.merge(chains: SupportedChains.all, remote: BundledTokenCatalog.all);
final _sepoliaUsdc = BundledTokenCatalog.all.firstWhere((t) => t.chainId == SupportedChains.ethereumSepolia.id);

/// 只记录收到的请求，不真的上链。
class _RecordingTransfer implements ChainTransferService {
  _RecordingTransfer(this.kind);

  @override
  final ChainKind kind;

  TransferRequest? received;

  @override
  Future<TransferResult> send(TransferRequest request, Wallet wallet) async {
    received = request;
    return (hash: '0xabc', sentAmount: request.amount, status: EvmSendStatus.confirmed);
  }
}

const _wallet = Wallet(id: 'w1', name: '测试钱包', address: '0x0000000000000000000000000000000000000001');

WalletService _service(_RecordingTransfer transfer) =>
    WalletService(transferServices: {transfer.kind: transfer}, catalog: _catalog);

SendTxRequest _request({String? tokenIdentifier, String? chainId}) => SendTxRequest(
  from: '0x0000000000000000000000000000000000000001',
  to: '0x0000000000000000000000000000000000000002',
  amount: '1',
  chainId: chainId ?? SupportedChains.ethereumSepolia.id,
  tokenIdentifier: tokenIdentifier,
);

void main() {
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
        _service(evm).sendTransaction(
          _request(tokenIdentifier: '0x000000000000000000000000000000000000dead'),
          _wallet,
        ),
        throwsStateError,
      );
      expect(evm.received, isNull);
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
        _service(evm).sendTransaction(
          const SendTxRequest(from: '0x1', to: '0x2', amount: '1'),
          _wallet,
        ),
        throwsArgumentError,
      );
    });
  });
}
