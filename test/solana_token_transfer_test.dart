import 'dart:convert';

import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:on_chain/solana/solana.dart' hide TokenStandard;
import 'package:wallet/blockchain/bundled_token_catalog.dart';
import 'package:wallet/blockchain/chain_registry.dart';
import 'package:wallet/blockchain/token.dart';
import 'package:wallet/enums/fee_speed.dart';
import 'package:wallet/services/solana_transaction_service.dart';
import 'package:wallet/services/transfer/transfer_result.dart';

const _chain = SupportedChains.solanaDevnet;

final _privateKey = List<int>.filled(32, 7);
final _signer = SolanaPrivateKey.fromSeed(_privateKey);
final _owner = _signer.publicKey().toAddress();

final _recipient = SolanaPrivateKey.fromSeed(List<int>.filled(32, 9)).publicKey().toAddress();
final _blockhash = SolanaPrivateKey.fromSeed(List<int>.filled(32, 11)).publicKey().toAddress();

/// 目录里真实的那个 devnet SPL 代币（USDC，6 位精度），而不是手搓一个——
/// 手搓容易和目录的约定漂移，而「精度取代币的还是链的」正是本文件要守的事。
final _token = BundledTokenCatalog.all.firstWhere((t) => t.chainId == _chain.id && t.standard == TokenStandard.spl);
final _mint = SolAddress(_token.identifier);

final _sourceAta = AssociatedTokenAccountProgramUtils.associatedTokenAccount(mint: _mint, owner: _owner).address;
final _destinationAta = AssociatedTokenAccountProgramUtils.associatedTokenAccount(
  mint: _mint,
  owner: _recipient,
).address;

/// 每签名费。
final _fee = BigInt.from(5000);

/// 165 字节账户（ATA）的租金豁免线，devnet 实测量级。
final _ataRent = BigInt.from(2039280);

/// 构造一个 SPL 代币账户的链上数据，供 getAccountInfo 返回。
String _tokenAccountData(BigInt amount) {
  final account = SolanaTokenAccount(
    address: _sourceAta,
    mint: _mint,
    owner: _owner,
    amount: amount,
    delegate: null,
    delegatedAmount: BigInt.zero,
    rentExemptReserve: null,
    closeAuthority: null,
    state: AccountState.initialized,
  );
  return StringUtils.decode(account.toBytes(), encoding: StringEncoding.base64);
}

/// 假 Solana 节点：按 JSON-RPC method 返回预设响应，并记录每次调用。
///
/// 与 `solana_transfer_test.dart` 里那个同构，但多了 `getAccountInfo` 的按地址分流——
/// 两个 ATA 的存在与否是本文件几乎每条用例的分歧点。
class _FakeSolanaService with SolanaServiceProvider {
  _FakeSolanaService({
    BigInt? solBalance,
    BigInt? tokenBalance,
    this.sourceExists = true,
    this.destinationExists = true,
  }) : solBalance = solBalance ?? BigInt.from(1000000000), // 1 SOL
       tokenBalance = tokenBalance ?? BigInt.from(100000000); // 100 USDC（6 位精度）

  /// 发送方的 SOL 余额（lamport），用来付网络费与 ATA 租金。
  final BigInt solBalance;

  /// 发送方 ATA 里的代币余额（最小单位）。
  final BigInt tokenBalance;

  /// 发送方 ATA 是否存在。false = 从没持有过这个币。
  final bool sourceExists;

  /// 收款方 ATA 是否存在。false = 本次要顺带创建。
  final bool destinationExists;

  /// 优先费样本恒为空：本文件只管代币路径的账户与精度，三档分位的算法
  /// 已由 `solana_transfer_test.dart` 的「优先费三档」覆盖，不重复一遍。
  static const List<int> prioritizationFees = [];

  final calls = <String>[];

  /// `getMinimumBalanceForRentExemption` 收到的 size 参数，用来断言问的是 165 而不是 0。
  final rentExemptionSizes = <int>[];

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
      'getFeeForMessage' => {
        'context': {'slot': 1},
        'value': _fee.toInt(),
      },
      'getMinimumBalanceForRentExemption' => _recordRentExemption(requestParams),
      'getBalance' => {
        'context': {'slot': 1},
        'value': solBalance.toInt(),
      },
      'getAccountInfo' => {
        'context': {'slot': 1},
        'value': _accountInfo(requestParams.first as String),
      },
      'sendTransaction' => _broadcast(requestParams),
      'getRecentPrioritizationFees' => [
        for (final (index, fee) in prioritizationFees.indexed) {'slot': index + 1, 'prioritizationFee': fee},
      ],
      _ => throw StateError('未预设的 RPC 方法: $method'),
    };

    return ServiceSuccessRespose(
      statusCode: 200,
      response: jsonEncode({'jsonrpc': '2.0', 'id': body['id'], 'result': result}),
    );
  }

  int _recordRentExemption(List<dynamic> requestParams) {
    rentExemptionSizes.add(requestParams.first as int);
    return _ataRent.toInt();
  }

  /// 按查询地址分流：两个 ATA 各自可能存在或不存在。
  Map<String, dynamic>? _accountInfo(String address) {
    final exists = switch (address) {
      _ when address == _sourceAta.address => sourceExists,
      _ when address == _destinationAta.address => destinationExists,
      _ => throw StateError('未预期的 getAccountInfo 地址: $address'),
    };
    if (!exists) return null;
    return {
      'executable': false,
      'lamports': _ataRent.toString(),
      'owner': SPLTokenProgramConst.tokenProgramId.address,
      'rentEpoch': 0.0,
      'space': SolanaTokenAccountUtils.accountSize,
      'data': [_tokenAccountData(tokenBalance), 'base64'],
    };
  }

  String _broadcast(List<dynamic> requestParams) {
    broadcastPayload = requestParams.first as String;
    return 'signature-spl';
  }
}

SolanaTransactionService _service(_FakeSolanaService node) => SolanaTransactionService(provider: SolanaProvider(node));

SolanaTransaction _decodeBroadcast(String base64Transaction) =>
    SolanaTransaction.deserialize(StringUtils.encode(base64Transaction, encoding: StringEncoding.base64));

/// 广播出去的交易里那条 transferChecked 指令的金额与精度。
({BigInt amount, int decimals, SolAddress source, SolAddress destination}) _transferCheckedOf(String base64Tx) {
  final message = _decodeBroadcast(base64Tx).message;
  final instruction = message.compiledInstructions.firstWhere(
    (candidate) => message.accountKeys[candidate.programIdIndex] == SPLTokenProgramConst.tokenProgramId,
  );
  final layout = SPLTokenProgramLayout.fromBytes(instruction.data) as SPLTokenTransferCheckedLayout;
  return (
    amount: layout.amount,
    decimals: layout.decimals,
    // transferChecked 的账户顺序：source, mint, destination, owner。
    source: message.accountKeys[instruction.accounts[0]],
    destination: message.accountKeys[instruction.accounts[2]],
  );
}

/// 交易里是否带了「创建收款方 ATA」那条指令。
bool _createsAta(String base64Transaction) {
  final message = _decodeBroadcast(base64Transaction).message;
  return message.compiledInstructions.any(
    (candidate) =>
        message.accountKeys[candidate.programIdIndex] ==
        AssociatedTokenAccountProgramConst.associatedTokenProgramId,
  );
}

/// 交易里声明的计算单元上限。
int _computeUnitLimitOf(String base64Transaction) {
  final message = _decodeBroadcast(base64Transaction).message;
  for (final instruction in message.compiledInstructions) {
    if (message.accountKeys[instruction.programIdIndex] != ComputeBudgetConst.programId) continue;
    final layout = ComputeBudgetProgramLayout.fromBytes(instruction.data);
    if (layout is ComputeBudgetSetComputeUnitLimitLayout) return layout.units;
  }
  throw StateError('交易里没有 SetComputeUnitLimit 指令');
}

Future<TransferResult> _send(_FakeSolanaService node, {String amount = '1.5'}) => _service(node).sendToken(
  chain: _chain,
  token: _token,
  privateKey: _privateKey,
  fromAddress: _owner.address,
  to: _recipient.address,
  amount: amount,
);

void main() {
  group('SolanaTransactionService.sendToken', () {
    test('广播成功后返回签名与 pending，金额按代币精度回显', () async {
      final node = _FakeSolanaService();

      final result = await _send(node);

      expect(result.hash, 'signature-spl');
      expect(result.sentAmount, '1.5');
      expect(result.status, TransactionStatus.pending);
      // 带上失效高度，历史页才判得出「死了」还是「还在等」。
      expect(result.validUntilBlock, 100);
    });

    test('金额按 token.decimals(6) 换算，不是 chain.decimals(9)', () async {
      final node = _FakeSolanaService();

      await _send(node, amount: '1.5');

      final transfer = _transferCheckedOf(node.broadcastPayload!);
      // 1.5 USDC = 1500000（6 位）。若误用链的 9 位会是 1500000000，差一千倍。
      expect(transfer.amount, BigInt.from(1500000));
      expect(_chain.decimals, 9, reason: '本用例的意义建立在两个精度确实不同之上');
      expect(_token.decimals, 6);
    });

    test('把代币精度写进 transferChecked，交给链上比对', () async {
      final node = _FakeSolanaService();

      await _send(node);

      // 用 transferChecked 而不是 transfer：目录里的精度若与链上 mint 不符，
      // 这笔交易会失败，而不是照错的精度把钱转错数量级。
      expect(_transferCheckedOf(node.broadcastPayload!).decimals, _token.decimals);
    });

    test('写的是两个 ATA，而不是钱包地址本身', () async {
      final node = _FakeSolanaService();

      await _send(node);

      final transfer = _transferCheckedOf(node.broadcastPayload!);
      expect(transfer.source, _sourceAta);
      expect(transfer.destination, _destinationAta);
      expect(transfer.destination, isNot(_recipient), reason: 'SPL 余额不在钱包地址上');
    });

    group('收款方 ATA 已存在', () {
      test('不带创建指令，也不问 165 字节的租金', () async {
        final node = _FakeSolanaService();

        await _send(node);

        expect(_createsAta(node.broadcastPayload!), isFalse);
        expect(node.calls, isNot(contains('getMinimumBalanceForRentExemption')), reason: '不建账户就不该白发这轮请求');
      });

      test('计算单元上限取不含建账户的那一档', () async {
        final node = _FakeSolanaService();

        await _send(node);

        expect(_computeUnitLimitOf(node.broadcastPayload!), 6000);
      });
    });

    group('收款方 ATA 不存在', () {
      test('同一笔交易里顺带创建，并按 165 字节问租金', () async {
        final node = _FakeSolanaService(destinationExists: false);

        await _send(node);

        expect(_createsAta(node.broadcastPayload!), isTrue);
        expect(node.rentExemptionSizes, [SolanaTokenAccountUtils.accountSize]);
        expect(SolanaTokenAccountUtils.accountSize, 165, reason: 'ATA 的布局跨度就是 165 字节');
      });

      test('创建指令排在转账之前', () async {
        final node = _FakeSolanaService(destinationExists: false);

        await _send(node);

        final message = _decodeBroadcast(node.broadcastPayload!).message;
        final programs = [
          for (final instruction in message.compiledInstructions) message.accountKeys[instruction.programIdIndex],
        ];
        // 顺序反了的话，转账会写进一个还不存在的账户，整笔失败。
        expect(
          programs.indexOf(AssociatedTokenAccountProgramConst.associatedTokenProgramId),
          lessThan(programs.indexOf(SPLTokenProgramConst.tokenProgramId)),
        );
      });

      test('计算单元上限抬到含建账户的那一档', () async {
        final node = _FakeSolanaService(destinationExists: false);

        await _send(node);

        // 沿用不含建账户的 6000 会让交易因超限直接失败。
        expect(_computeUnitLimitOf(node.broadcastPayload!), 30000);
      });

      test('估费把那笔租金算进总花费，但不算进网络费', () async {
        final node = _FakeSolanaService(destinationExists: false);

        final estimate = await _service(node).estimateTokenFee(
          chain: _chain,
          token: _token,
          from: _owner.address,
          to: _recipient.address,
          amount: '1.5',
        );

        expect(estimate.createsTokenAccount, isTrue);
        expect(estimate.ataRentLamports, _ataRent);
        // 租金不是网络费：混进三档报价会让手续费凭空高出几百倍。
        expect(estimate.quoteFor(FeeSpeed.defaultSpeed).maxFee, _fee);
        expect(estimate.lamportsCostFor(FeeSpeed.defaultSpeed), _fee + _ataRent);
      });
    });

    group('拦在广播之前的失败', () {
      test('代币余额不足时报错，不静默改小金额', () async {
        // 余额 1 USDC，要转 1.5。
        final node = _FakeSolanaService(tokenBalance: BigInt.from(1000000));

        await expectLater(
          _send(node, amount: '1.5'),
          throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('余额不足'))),
        );
        expect(node.calls, isNot(contains('sendTransaction')));
      });

      test('发送方没有该代币账户时报错', () async {
        final node = _FakeSolanaService(sourceExists: false);

        await expectLater(
          _send(node),
          throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('还没有'))),
        );
        expect(node.calls, isNot(contains('sendTransaction')));
      });

      test('SOL 不够付「网络费 + ATA 租金」时报错', () async {
        // SOL 只够付签名费，付不起建 ATA 的租金。
        final node = _FakeSolanaService(destinationExists: false, solBalance: _fee + BigInt.one);

        await expectLater(
          _send(node),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              allOf(contains('不足以支付网络费'), contains('租金')),
            ),
          ),
        );
        expect(node.calls, isNot(contains('sendTransaction')));
      });

      test('SOL 够付费用时不会因租金误拦', () async {
        final node = _FakeSolanaService(destinationExists: false, solBalance: _fee + _ataRent);

        await _send(node);

        expect(node.calls, contains('sendTransaction'));
      });

      test('金额为 0 时报错', () async {
        final node = _FakeSolanaService();

        await expectLater(
          _send(node, amount: '0'),
          throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('必须大于 0'))),
        );
      });

      test('非 SPL 标准的代币被拒绝', () async {
        final node = _FakeSolanaService();
        // 拿一个 ERC-20 的标准贴到 Solana 链上，模拟目录配置错误。
        final wrongStandard = Token(
          chainId: _chain.id,
          symbol: _token.symbol,
          name: _token.name,
          standard: TokenStandard.erc20,
          identifier: _token.identifier,
          coinGeckoId: _token.coinGeckoId,
          decimals: _token.decimals,
        );

        await expectLater(
          _service(node).sendToken(
            chain: _chain,
            token: wrongStandard,
            privateKey: _privateKey,
            fromAddress: _owner.address,
            to: _recipient.address,
            amount: '1',
          ),
          throwsA(isA<UnsupportedError>()),
        );
      });

      test('签名地址与钱包地址不一致时报错', () async {
        final node = _FakeSolanaService();

        await expectLater(
          _service(node).sendToken(
            chain: _chain,
            token: _token,
            privateKey: _privateKey,
            fromAddress: _recipient.address, // 不是这把私钥派生出的地址
            to: _recipient.address,
            amount: '1',
          ),
          throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('不一致'))),
        );
      });
    });

    test('一次发送只取一次 blockhash：估费与签名共用', () async {
      final node = _FakeSolanaService();

      await _send(node);

      expect(node.calls.where((m) => m == 'getLatestBlockhash'), hasLength(1));
    });
  });
}
