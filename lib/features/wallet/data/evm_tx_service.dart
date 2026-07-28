import 'dart:convert';
import 'dart:io';

import 'package:on_chain/ethereum/ethereum.dart';

import '../domain/chain.dart';

/// EVM 原生币转账：取 nonce / 估费 → 构造 EIP-1559 交易 → 本地签名 → 广播。
/// 仅处理原生币（ERC20 暂未接入），gasLimit 固定 21000。
class EvmTxService {
  const EvmTxService();

  /// 原生转账的固定 gas 用量。
  static final BigInt _nativeGasLimit = BigInt.from(21000);

  /// 发送原生币转账，返回 (交易哈希, 实际发送金额字符串)。
  ///
  /// [privateKeyHex] 为 0x 前缀的 secp256k1 私钥，仅在本次调用内使用。
  /// [amount] 为用户输入的十进制金额字符串，按 [Chain.decimals] 转 wei。
  ///
  /// 若「金额 + 费用上限」超过实时余额（如 MAX 全额转出），自动把费用从
  /// 转出额中扣除；扣完不为正则抛 [EvmRpcException]。实际金额随结果返回。
  Future<({String hash, String sentAmount})> sendNative({
    required Chain chain,
    required String privateKeyHex,
    required String to,
    required String amount,
  }) async {
    final chainId = chain.evmChainId;
    if (chainId == null) {
      throw StateError('链 ${chain.id} 缺少 evmChainId 配置');
    }

    final signer = ETHPrivateKey(privateKeyHex);
    final from = signer.publicKey().toAddress();
    var value = parseUnits(amount, chain.decimals);

    final nonceHex =
        await _rpcCall(chain.endpoint, 'eth_getTransactionCount', [
              from.address,
              'pending',
            ])
            as String;
    final fee = await _estimateFee(chain.endpoint);

    // —— gas 不足时从转出额中扣费：按费用上限口径，保证签出的交易必然付得起 —— //
    final feeCap =
        (fee.eip1559 ? fee.maxFeePerGas : fee.gasPrice)! * _nativeGasLimit;
    final balanceHex =
        await _rpcCall(chain.endpoint, 'eth_getBalance', [
              from.address,
              'latest',
            ])
            as String;
    final balance = _hexToBigInt(balanceHex);
    if (value + feeCap > balance) {
      value = balance - feeCap;
      if (value <= BigInt.zero) {
        throw const EvmRpcException('余额不足以支付网络费用');
      }
    }

    final unsigned = ETHTransaction(
      type: fee.eip1559
          ? ETHTransactionType.eip1559
          : ETHTransactionType.legacy,
      from: from,
      to: ETHAddress(to),
      nonce: _hexToBigInt(nonceHex).toInt(),
      gasLimit: _nativeGasLimit,
      maxFeePerGas: fee.eip1559 ? fee.maxFeePerGas : null,
      maxPriorityFeePerGas: fee.eip1559 ? fee.maxPriorityFeePerGas : null,
      gasPrice: fee.eip1559 ? null : fee.gasPrice,
      value: value,
      data: const [],
      chainId: BigInt.from(chainId),
    );
    final signature = signer.sign(unsigned.serialized);
    final raw = unsigned.copyWith(signature: signature).signedSerialized();

    final hash =
        await _rpcCall(chain.endpoint, 'eth_sendRawTransaction', [
              '0x${_toHex(raw)}',
            ])
            as String;
    return (hash: hash, sentAmount: formatUnits(value, chain.decimals));
  }

  /// 预估一笔原生转账的费用上限（wei）：费率上限 × 21000。
  /// EIP-1559 按 maxFeePerGas 口径（实际支付通常更低）。
  Future<BigInt> estimateNativeFee(Chain chain) async {
    final fee = await _estimateFee(chain.endpoint);
    return (fee.eip1559 ? fee.maxFeePerGas : fee.gasPrice)! * _nativeGasLimit;
  }

  /// 估算费率：优先 EIP-1559（baseFee * 2 + tip），节点不支持时回退 legacy gasPrice。
  Future<_EvmFee> _estimateFee(String endpoint) async {
    try {
      final block =
          await _rpcCall(endpoint, 'eth_getBlockByNumber', ['latest', false])
              as Map;
      final baseFeeHex = block['baseFeePerGas'] as String?;
      if (baseFeeHex == null) throw const FormatException('no baseFee');
      final baseFee = _hexToBigInt(baseFeeHex);

      BigInt tip;
      try {
        final tipHex =
            await _rpcCall(endpoint, 'eth_maxPriorityFeePerGas', []) as String;
        tip = _hexToBigInt(tipHex);
      } catch (_) {
        tip = BigInt.from(1500000000); // 1.5 gwei 兜底
      }
      // baseFee 翻倍留余量，防止打包前 baseFee 上涨导致交易卡住。
      return _EvmFee.eip1559(
        maxFeePerGas: baseFee * BigInt.two + tip,
        maxPriorityFeePerGas: tip,
      );
    } catch (_) {
      final priceHex = await _rpcCall(endpoint, 'eth_gasPrice', []) as String;
      return _EvmFee.legacy(_hexToBigInt(priceHex));
    }
  }

  /// 十进制金额字符串 → 最小单位 BigInt（不经过 double，避免精度丢失）。
  /// 小数位超过 [decimals] 时抛 [FormatException]。
  static BigInt parseUnits(String amount, int decimals) {
    final s = amount.trim();
    if (s.isEmpty || !RegExp(r'^\d+(\.\d+)?$').hasMatch(s)) {
      throw FormatException('金额格式非法: $amount');
    }
    final parts = s.split('.');
    final whole = parts[0];
    final fraction = parts.length > 1 ? parts[1] : '';
    if (fraction.length > decimals) {
      throw FormatException('小数位超过精度上限 $decimals: $amount');
    }
    final padded = fraction.padRight(decimals, '0');
    return BigInt.parse(whole + (decimals == 0 ? '' : padded));
  }

  /// 最小单位 BigInt → 十进制金额字符串（[parseUnits] 的逆运算，去尾零）。
  static String formatUnits(BigInt value, int decimals) {
    if (decimals == 0) return value.toString();
    final divisor = BigInt.from(10).pow(decimals);
    final whole = value ~/ divisor;
    final fraction = value.remainder(divisor).toString().padLeft(decimals, '0');
    final trimmed = fraction.replaceFirst(RegExp(r'0+$'), '');
    return trimmed.isEmpty ? whole.toString() : '$whole.$trimmed';
  }

  // —— 网络与进制工具（与 WalletService 一致的轻量实现） —— //

  Future<Object?> _rpcCall(
    String url,
    String method,
    List<Object?> params,
  ) async {
    final client = HttpClient();
    try {
      final request = await client.postUrl(Uri.parse(url));
      request.headers.contentType = ContentType.json;
      request.add(
        utf8.encode(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': 1,
            'method': method,
            'params': params,
          }),
        ),
      );
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final error = json['error'];
      if (error != null) {
        // 节点错误里 message 最有指向性（余额不足 / nonce 过低等），单独抛出。
        final message = error is Map ? error['message'] : null;
        throw EvmRpcException(message?.toString() ?? error.toString());
      }
      return json['result'];
    } finally {
      client.close();
    }
  }

  BigInt _hexToBigInt(String hex) {
    final clean = hex.startsWith('0x') ? hex.substring(2) : hex;
    if (clean.isEmpty) return BigInt.zero;
    return BigInt.parse(clean, radix: 16);
  }

  String _toHex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// 节点返回的 JSON-RPC 错误（携带节点原始 message，供 UI 透传展示）。
class EvmRpcException implements Exception {
  const EvmRpcException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 费率估算结果：EIP-1559 或 legacy 二选一。
class _EvmFee {
  const _EvmFee.eip1559({
    required BigInt this.maxFeePerGas,
    required BigInt this.maxPriorityFeePerGas,
  }) : eip1559 = true,
       gasPrice = null;

  const _EvmFee.legacy(BigInt this.gasPrice)
    : eip1559 = false,
      maxFeePerGas = null,
      maxPriorityFeePerGas = null;

  final bool eip1559;
  final BigInt? maxFeePerGas;
  final BigInt? maxPriorityFeePerGas;
  final BigInt? gasPrice;
}
