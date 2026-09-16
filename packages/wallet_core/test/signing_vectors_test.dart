import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:on_chain/ethereum/ethereum.dart';
import 'package:on_chain/solana/solana.dart';
import 'package:wallet_core/wallet_core.dart';
import 'package:wallet_core/src/internal/erc20_abi.dart';

/// 签名的已知向量（known-answer）测试。
///
/// 现有的转账测试验证的是「流程跑通了」——打桩的 RPC 收到了一串字节。
/// 它们不会发现签名本身算错：只要 signer 稳定地算错，流程测试照样全绿。
/// 这里换一个问法：给定完全确定的输入，产出的字节必须**逐字节**等于
/// 规范文档里写死的那一串。
///
/// 三条规矩，每条都是为了让这些断言在几年后仍然可信：
/// 1. 不联网。nonce、gasPrice、chainId 全部作为参数注入。
/// 2. 每条向量都注明出处与获取日期，让后来者能自己复核，而不是相信这个文件。
/// 3. 期望值写死成字面量，绝不由被测代码反算——那样测的就只是"它等于它自己"。
void main() {
  group('EVM', () {
    // 出处：EIP-155 规范原文的示例交易（https://eips.ethereum.org/EIPS/eip-155，
    // 2026-09-16 核对）。规范给出了私钥、全部交易字段与最终的签名值，
    // 是整个以太坊生态被复核次数最多的一条向量。
    final privateKey = BytesUtils.fromHexString(
      '4646464646464646464646464646464646464646464646464646464646464646',
    );
    const expectedSignedRawTx =
        '0xf86c098504a817c800825208943535353535353535353535353535353535353535880de0b6b3a764000080'
        '25a028ef61340bd939bc2195fe537567866003e1a15d3c71ff63e1590620aa636276a067cbe9d8997f761aec'
        'b703304b3800ccf555c9f3dc64214b297fb1966a3b6d83';

    test('EIP-155 规范向量：签出的 raw tx 与文档逐字节一致', () {
      final signer = ETHPrivateKey.fromBytes(privateKey);

      final raw = buildAndSignEvmTransaction(
        evmChainId: 1,
        signer: signer,
        from: signer.publicKey().toAddress(),
        to: '0x3535353535353535353535353535353535353535',
        value: BigInt.parse('1000000000000000000'), // 1 ETH
        data: const [],
        nonce: 9,
        gasLimit: BigInt.from(21000),
        fee: EvmFeeRate.legacy(BigInt.from(20000000000)), // 20 gwei
      );

      expect('0x${BytesUtils.toHexString(raw)}', expectedSignedRawTx);
    });

    test('签名是确定性的：同样的输入签两次，字节完全相同', () {
      // 这条不是凑数。ECDSA 如果用随机 k，同一笔交易两次签名会得到不同的 s；
      // 而重复使用的 k 又会直接泄漏私钥。RFC 6979 的确定性 k 是唯一安全的选择，
      // 这条断言保证依赖升级时不会悄悄换掉它——升级后上面那条向量也会一起红。
      List<int> signOnce() => buildAndSignEvmTransaction(
        evmChainId: 1,
        signer: ETHPrivateKey.fromBytes(privateKey),
        from: ETHPrivateKey.fromBytes(privateKey).publicKey().toAddress(),
        to: '0x3535353535353535353535353535353535353535',
        value: BigInt.parse('1000000000000000000'),
        data: const [],
        nonce: 9,
        gasLimit: BigInt.from(21000),
        fee: EvmFeeRate.legacy(BigInt.from(20000000000)),
      );

      expect(BytesUtils.toHexString(signOnce()), BytesUtils.toHexString(signOnce()));
    });

    test('换一条链（chainId 变化）签出的字节必须不同', () {
      // EIP-155 的全部意义就是把 chainId 绑进签名，让主网交易不能在测试网重放。
      // 如果哪天 chainId 传丢了，上面的向量仍会通过（它就是 chainId=1），
      // 只有这条能发现"chainId 根本没进签名"。
      List<int> signOn(int chainId) => buildAndSignEvmTransaction(
        evmChainId: chainId,
        signer: ETHPrivateKey.fromBytes(privateKey),
        from: ETHPrivateKey.fromBytes(privateKey).publicKey().toAddress(),
        to: '0x3535353535353535353535353535353535353535',
        value: BigInt.parse('1000000000000000000'),
        data: const [],
        nonce: 9,
        gasLimit: BigInt.from(21000),
        fee: EvmFeeRate.legacy(BigInt.from(20000000000)),
      );

      expect(BytesUtils.toHexString(signOn(1)), isNot(BytesUtils.toHexString(signOn(11155111))));
    });

    test('ERC-20 transfer 的 calldata 是 a9059cbb + 两个 32 字节对齐参数', () {
      // 出处：ERC-20 的 transfer(address,uint256) 函数选择器，
      // keccak256("transfer(address,uint256)") 的前 4 字节 = a9059cbb。
      // 代币转账里 value 字段恒为 0，金额只存在于 calldata——这段编码错了，
      // 用户会看到"转账成功"而资产纹丝不动，或者转出一个数量级之差的金额。
      final calldata = encodeTransfer(
        to: '0x3535353535353535353535353535353535353535',
        amount: BigInt.from(1000000),
      );

      expect(
        calldata,
        '0xa9059cbb'
        '0000000000000000000000003535353535353535353535353535353535353535'
        '00000000000000000000000000000000000000000000000000000000000f4240',
      );
    });
  });

  group('Solana', () {
    // 交易级向量由 @solana/web3.js 1.99.0 + @solana/spl-token 0.4.15 离线生成
    // （2026-09-16），这是与被测代码完全独立的另一套实现。生成脚本连同全部输入
    // 记录在 tool/solana_vectors/gen.js，任何人可以自己重跑一遍核对。
    //
    // 期望值绝不能由被测代码反算——那测的只是"它等于它自己"。用另一个实现算出来
    // 再钉死，才谈得上交叉验证。
    final seed = List<int>.generate(32, (i) => i + 1);
    final recipientSeed = List<int>.generate(32, (i) => 255 - i);

    // 与生产代码 _buildTransaction 一致的三条指令组成。少一条，向量验证的就是
    // 一个生产里并不存在的交易形态。
    const computeUnitLimit = 600;
    final computeUnitPrice = BigInt.from(1000);
    final blockhash = SolAddress.uncheckBytes(List<int>.generate(32, (i) => (i * 3 + 7) % 256));

    SolanaTransaction buildFixedTransaction(SolAddress owner, SolAddress recipient) => SolanaTransaction(
      payerKey: owner,
      recentBlockhash: blockhash,
      instructions: [
        ComputeBudgetProgram.setComputeUnitLimit(
          layout: const ComputeBudgetSetComputeUnitLimitLayout(units: computeUnitLimit),
        ),
        ComputeBudgetProgram.setComputeUnitPrice(
          layout: ComputeBudgetSetComputeUnitPriceLayout(microLamports: computeUnitPrice),
        ),
        SystemProgram.transfer(layout: SystemTransferLayout(lamports: BigInt.from(1000000)), from: owner, to: recipient),
      ],
    );

    test('公钥派生与 web3.js 一致', () {
      expect(SolanaPrivateKey.fromSeed(seed).publicKey().toAddress().address, '9C6hybhQ6Aycep9jaUnP6uL9ZYvDjUp1aSkFWPUFJtpj');
      expect(
        SolanaPrivateKey.fromSeed(recipientSeed).publicKey().toAddress().address,
        'Dav6Vxmr7BEgvQW4osrzWutwgPEqQ4Ji3zWxKp6nX9AD',
      );
    });

    test('message 的账户集合与指令语义与 web3.js 等价', () {
      // 这里刻意**不**做字节级比对，原因值得记下来，免得后来者以为是漏写了：
      //
      // web3.js 把同权限级的账户按 base58 字典序排（SystemProgram 全零，排在
      // ComputeBudget 前面），on_chain 保留首次出现的顺序。两份 message 都自洽，
      // 也都会被验证节点接受——Solana 只要求账户按「签名者/可写」分组，
      // 组内不要求排序。所以 Solana 做不到 EVM 那种跨实现的逐字节向量：
      // RLP 的字段顺序是规范定死的，Solana 的账户顺序不是。
      //
      // 能跨实现钉死的是密钥层（见上一条与 ATA 那条），已经钉了。
      // 这里退一步验证语义等价：账户集合、指令数量、转账金额。
      final owner = SolanaPrivateKey.fromSeed(seed).publicKey().toAddress();
      final recipient = SolanaPrivateKey.fromSeed(recipientSeed).publicKey().toAddress();

      final transaction = buildFixedTransaction(owner, recipient);
      final accounts = transaction.message.accountKeys.map((a) => a.address).toSet();

      // web3.js 生成的同一笔交易里的四个账户，逐个在这里出现。
      expect(accounts, contains('9C6hybhQ6Aycep9jaUnP6uL9ZYvDjUp1aSkFWPUFJtpj')); // payer
      expect(accounts, contains('Dav6Vxmr7BEgvQW4osrzWutwgPEqQ4Ji3zWxKp6nX9AD')); // 收款方
      expect(accounts, contains(SystemProgramConst.programId.address));
      expect(accounts, contains(ComputeBudgetConst.programId.address));
      expect(accounts, hasLength(4), reason: '多出账户说明指令组成变了，费用与权限都会跟着变');

      expect(transaction.message.compiledInstructions, hasLength(3), reason: '两条 ComputeBudget + 一条 transfer，少一条优先费就失效');

      // 转账金额编在 SystemProgram 指令的 data 里（小端 u64，1000000 = 0x0f4240）。
      final transferIx = transaction.message.compiledInstructions.firstWhere(
        (CompiledInstruction i) =>
            transaction.message.accountKeys[i.programIdIndex].address == SystemProgramConst.programId.address,
      );
      expect(BytesUtils.toHexString(transferIx.data), '0200000040420f0000000000');
    });

    test('签名能被公钥验过，且绑定的是这一笔 message', () {
      // 字节级比对既然做不成，就换成一条不依赖对方实现的性质：
      // 签名必须在**我们自己序列化出的 message** 上验得过。
      // 验签是另一条代码路径，签错消息、用错私钥、种子与密钥对混用
      // （fromSeed vs fromBytes 是这里踩过的坑）都会被它抓住。
      final signer = SolanaPrivateKey.fromSeed(seed);
      final transaction = buildFixedTransaction(
        signer.publicKey().toAddress(),
        SolanaPrivateKey.fromSeed(recipientSeed).publicKey().toAddress(),
      );

      transaction.sign([signer]);
      final signature = transaction.signatures.first;

      expect(signature, hasLength(64));
      expect(
        signer.publicKey().verify(message: transaction.serializeMessage(), signature: signature),
        isTrue,
      );
    });

    test('ATA 派生与 spl-token 一致', () {
      // SPL 转账最容易静默回归的一处：ATA 是本地 PDA 派生，算错了钱会打到一个
      // 没人控制的地址上，而交易本身完全成功。生产代码直接委托给这个 util，
      // 所以这条断言钉的是依赖升级不会改变派生结果。
      final owner = SolanaPrivateKey.fromSeed(seed).publicKey().toAddress();
      final mint = SolAddress('EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v'); // USDC

      final ata = AssociatedTokenAccountProgramUtils.associatedTokenAccount(mint: mint, owner: owner).address;

      expect(ata.address, 'FjCjyojZLVYVQ2dEdDKQx76msks96TdH9xqvc8BQ9UUx');
    });

    test('ed25519 签名能被对应公钥验过', () {
      final signer = SolanaPrivateKey.fromSeed(seed);
      final message = List<int>.generate(64, (i) => (i * 7) % 256);

      final signature = signer.sign(message);

      expect(signature, hasLength(64));
      expect(signer.publicKey().verify(message: message, signature: signature), isTrue);
    });

    test('消息改一个字节，验签就必须失败', () {
      // 没有这条，上一条可能被一个"永远返回 true"的验签实现骗过去。
      final signer = SolanaPrivateKey.fromSeed(seed);
      final message = List<int>.generate(64, (i) => (i * 7) % 256);
      final signature = signer.sign(message);

      final tampered = [...message]..[0] ^= 0x01;

      expect(signer.publicKey().verify(message: tampered, signature: signature), isFalse);
    });

    test('ed25519 签名是确定性的：同一把种子、同一条消息，两次结果相同', () {
      // ed25519 本身就是确定性签名（nonce 由私钥和消息推出）。
      // 这条断言保证依赖升级不会换成带随机数的变体——那会让同一笔交易
      // 产生不同的签名，破坏重试与去重的前提。
      final message = List<int>.generate(64, (i) => (i * 7) % 256);
      List<int> signOnce() => SolanaPrivateKey.fromSeed(seed).sign(message);

      expect(BytesUtils.toHexString(signOnce()), BytesUtils.toHexString(signOnce()));
    });
  });
}
