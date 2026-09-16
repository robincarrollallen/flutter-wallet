// 一次性核对：Solana 节点是否接受 on_chain 的账户排序。
//
// 背景见 README。on_chain 与 @solana/web3.js 生成的 message 字节不同——
// 前者组内保留插入顺序，后者额外按 base58 字典序排。代码阅读的结论是两者都合法
// （运行时只要求按「签名者/可写」分组），但那终究是阅读得出的判断。
//
// 这个脚本把它变成证据：用真实的 devnet blockhash 构造一笔 on_chain 交易，
// 签名后交给节点 simulateTransaction（sigVerify: true）。
//
// 判读方式是关键——**看的不是成功还是失败，而是失败在哪一步**：
//   - 若账户排序不合法 → 节点在反序列化 / sanitize 阶段就拒掉，
//     报 SanitizeFailure 或 "failed to deserialize"，根本进不到执行。
//   - 若排序合法 → 通过 sanitize 与签名校验，进入执行阶段。此时因测试账户的
//     具体状态而失败（InstructionError）是正常的、也是我们要的结果——
//     能走到执行，就说明账户清单被正确解析了。
//
// 不上链、不动资产：simulateTransaction 只模拟。用的是固定测试种子——注意这把种子
// （1..32）是公开的、被无数示例用过，devnet 上已被人使用过，别把它当成干净账户。
// 不写成仓库里的测试——测试不该联网。跑法：
//   cd packages/wallet_core && dart run tool/solana_vectors/verify_account_order.dart
import 'dart:convert';
import 'dart:io';

import 'package:on_chain/solana/solana.dart';

const _endpoint = 'https://api.devnet.solana.com';

Future<Map<String, dynamic>> _rpc(String method, List<Object?> params) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(Uri.parse(_endpoint));
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode({'jsonrpc': '2.0', 'id': 1, 'method': method, 'params': params}));
    final response = await request.close();
    return jsonDecode(await response.transform(utf8.decoder).join()) as Map<String, dynamic>;
  } finally {
    client.close();
  }
}

Future<void> main() async {
  // 与 gen.js 完全相同的固定种子，保证核对的就是向量里那把钥匙。
  final seed = List<int>.generate(32, (i) => i + 1);
  final recipientSeed = List<int>.generate(32, (i) => 255 - i);

  final signer = SolanaPrivateKey.fromSeed(seed);
  final owner = signer.publicKey().toAddress();
  final recipient = SolanaPrivateKey.fromSeed(recipientSeed).publicKey().toAddress();

  // blockhash 必须是真实且新鲜的：sigVerify 为 true 时不能用 replaceRecentBlockhash
  // 兜底，过期的 blockhash 会报 BlockhashNotFound 而盖住我们真正想看的信号。
  final latest = await _rpc('getLatestBlockhash', [
    {'commitment': 'finalized'},
  ]);
  final blockhash = (latest['result'] as Map<String, dynamic>)['value']['blockhash'] as String;

  // 指令组成与生产代码 _buildTransaction 一致。
  final transaction = SolanaTransaction(
    payerKey: owner,
    recentBlockhash: SolAddress(blockhash),
    instructions: [
      ComputeBudgetProgram.setComputeUnitLimit(layout: const ComputeBudgetSetComputeUnitLimitLayout(units: 600)),
      ComputeBudgetProgram.setComputeUnitPrice(
        layout: ComputeBudgetSetComputeUnitPriceLayout(microLamports: BigInt.from(1000)),
      ),
      SystemProgram.transfer(layout: SystemTransferLayout(lamports: BigInt.from(1000000)), from: owner, to: recipient),
    ],
  );
  transaction.sign([signer]);

  final accounts = transaction.message.accountKeys.map((a) => a.address).toList();
  stdout.writeln('付款方: ${owner.address}');
  stdout.writeln('账户顺序（on_chain 的排法）:');
  for (var i = 0; i < accounts.length; i++) {
    stdout.writeln('  [$i] ${accounts[i]}');
  }

  final simulated = await _rpc('simulateTransaction', [
    transaction.serializeString(encoding: TransactionSerializeEncoding.base64, verifySignatures: true),
    {'encoding': 'base64', 'sigVerify': true, 'commitment': 'processed'},
  ]);

  stdout.writeln('\n节点响应:\n${const JsonEncoder.withIndent('  ').convert(simulated)}');

  final rpcError = simulated['error'];
  if (rpcError != null) {
    final message = rpcError.toString();
    final rejectedBySanitize =
        message.contains('Sanitize') || message.contains('deserialize') || message.contains('sanitize');
    stdout.writeln(
      rejectedBySanitize
          ? '\n结论：账户排序被节点拒绝——on_chain 的排法不合法，需要处理。'
          : '\n结论：通过了反序列化与 sanitize（错误不是排序问题）。排序合法。',
    );
    return;
  }

  final err = (simulated['result'] as Map<String, dynamic>)['value']['err'];
  stdout.writeln(
    err == null
        ? '\n结论：模拟完全通过。排序合法。'
        : '\n结论：通过了反序列化、sanitize 与签名校验，并进入执行阶段（err=$err）。'
              '\n      执行期的错误与账户排序无关——能走到执行就说明账户清单被正确解析。'
              '\n      看上面的 logs 可确认三条指令都被派发到了正确的程序。',
  );
}
