import 'package:on_chain/ethereum/ethereum.dart';
import '../blockchain/units.dart';
import '../blockchain/chain_registry.dart';
import '../core/utils/evm_hex.dart';
import '../data/datasource/remote/json_rpc.dart';

/// EVM 原生币转账：取 nonce / 估费 → 构造 EIP-1559 交易 → 本地签名 → 广播。
/// 仅处理原生币（ERC20 暂未接入），gasLimit 固定 21000。
class EvmTransactionService {
  const EvmTransactionService();

  /// 原生转账的固定 gas 用量。
  static final BigInt _nativeGasLimit = BigInt.from(21000);

  /// 发送原生币转账，返回 (交易哈希, 实际发送金额字符串)。
  ///
  /// [privateKeyHex] 为 0x 前缀的 secp256k1 私钥，仅在本次调用内使用。
  /// [amount] 为用户输入的十进制金额字符串，按 [Chain.decimals] 转 wei。
  ///
  /// 若「金额 + 费用上限」超过实时余额（如 MAX 全额转出），自动把费用从
  /// 转出额中扣除；扣完不为正则抛 [Exception]。实际金额随结果返回。
  Future<({String hash, String sentAmount})> sendNative({
    required Chain chain, // 链信息
    required String privateKeyHex, // 私钥
    required String to, // 接收者地址
    required String amount, // 转账金额
  }) async {
    final chainId = chain.evmChainId; // 链 ID<防重放>()
    if (chainId == null) {
      throw StateError('链 ${chain.id} 缺少 evmChainId 配置');
    }

    final signer = ETHPrivateKey(privateKeyHex); // 创建私钥对象
    final from = signer.publicKey().toAddress(); // 获取发送者地址<公钥转换为地址>
    var value = parseUnits(amount, chain.decimals); // 将金额转换为 wei<小数转整数>

    // 获取某地址已使用的交易计数 <nonce>(pending 包含待确认的交易, latest 只看最新已上链状态)
    final nonceHex =
        await jsonRpcCall(chain.endpoint, EvmRpcMethod.getTransactionCount.wireName, [from.address, 'pending'])
            as String;
    // 估算费用
    final fee = await _estimateFee(chain.endpoint);
    // gas 不足时从转出额中扣费：按费用上限口径，保证签出的交易必然付得起
    final feeCap = (fee.eip1559 ? fee.maxFeePerGas : fee.gasPrice)! * _nativeGasLimit;

    // 获取地址余额（单位 Wei），用于判断是否够支付 value + gasFee
    final balanceHex =
        await jsonRpcCall(chain.endpoint, EvmRpcMethod.getBalance.wireName, [from.address, 'latest']) as String;
    final balance = parseEvmHexQuantity(balanceHex);
    if (value + feeCap > balance) {
      value = balance - feeCap;
      if (value <= BigInt.zero) throw Exception('余额不足以支付网络费用');
    }

    /// 构造交易<序列化字节>
    final unsigned = ETHTransaction(
      type: fee.eip1559 ? ETHTransactionType.eip1559 : ETHTransactionType.legacy, // 发送交易类型
      from: from, // 发送者地址
      to: ETHAddress(to), // 接收者地址
      nonce: parseEvmHexQuantity(nonceHex).toInt(), // 交易计数
      gasLimit: _nativeGasLimit, // 固定 gas 用量<ETH原生币>
      maxFeePerGas: fee.eip1559 ? fee.maxFeePerGas : null, // 最大费用<仅 EIP-1559 机制设置>
      maxPriorityFeePerGas: fee.eip1559 ? fee.maxPriorityFeePerGas : null, // 最大优先费用<仅 EIP-1559 机制设置>
      gasPrice: fee.eip1559 ? null : fee.gasPrice, // legacy 机制下的费用<EIP-1559 为null>
      value: value, // 实际转账金额<wei>
      data: const [], // 表示普通转账不带合约调用数据<空数组>
      chainId: BigInt.from(chainId), // 链 ID(用于防重放，签名时会写入)
    );
    final signature = signer.sign(unsigned.serialized); // 对交易<序列化字节>进行签名
    final raw = unsigned.copyWith(signature: signature).signedSerialized(); // 生成最终的 raw 字节流<可上链广播的最终数据>

    final hash =
        await jsonRpcCall(chain.endpoint, EvmRpcMethod.sendRawTransaction.wireName, ['0x${_toHex(raw)}']) as String;
    return (hash: hash, sentAmount: formatUnits(value, chain.decimals));
  }

  /// 预估一笔原生转账的费用上限（wei）：费率上限 × 21000。
  /// EIP-1559 按 maxFeePerGas 口径（实际支付通常更低）。
  Future<BigInt> estimateNativeFee(Chain chain) async {
    final fee = await _estimateFee(chain.endpoint);
    return (fee.eip1559 ? fee.maxFeePerGas : fee.gasPrice)! * _nativeGasLimit;
  }

  /// 估算费率：优先 EIP-1559（baseFee * 2 + tip），节点不支持时回退 legacy gasPrice。
  Future<_EvmGasFee> _estimateFee(String endpoint) async {
    try {
      /// 获取最新区块头信息
      final block = await jsonRpcCall(endpoint, EvmRpcMethod.getBlockByNumber.wireName, ['latest', false]) as Map;

      /// 检查返回的区块中是否包含 baseFeePerGas 字段(存在说明该链支持 EIP-1559)
      final baseFeeHex = block['baseFeePerGas'] as String?;

      /// 如果 baseFeePerGas 不存在则抛出异常<走catch>
      if (baseFeeHex == null) throw const FormatException('no baseFee');

      final baseFee = parseEvmHexQuantity(baseFeeHex); // 解析返回 BigInt 值<baseFeePerGas 为16进制>

      BigInt tip; // 定义转账小费

      try {
        /// 获取优先费用(小费 - MaxPriorityFeePerGas)
        final tipHex = await jsonRpcCall(endpoint, EvmRpcMethod.maxPriorityFeePerGas.wireName, []) as String;
        tip = parseEvmHexQuantity(tipHex); // 解析返回 BigInt 值<baseFeePerGas 为16进制>
      } catch (_) {
        tip = BigInt.from(1500000000); // 1.5 gwei 兜底
      }

      /// baseFee 翻倍留余量，防止打包前 baseFee 上涨导致交易卡住。
      return _EvmGasFee.eip1559(maxFeePerGas: baseFee * BigInt.two + tip, maxPriorityFeePerGas: tip);
    } catch (_) {
      /// 获取旧机制链的手续费
      final priceHex = await jsonRpcCall(endpoint, EvmRpcMethod.gasPrice.wireName, []) as String;
      return _EvmGasFee.legacy(parseEvmHexQuantity(priceHex));
    }
  }

  String _toHex(List<int> bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// 费率估算结果：EIP-1559<新机制> 或 legacy<旧机制> 二选一。
class _EvmGasFee {
  const _EvmGasFee.eip1559({required BigInt this.maxFeePerGas, required BigInt this.maxPriorityFeePerGas})
    : eip1559 = true,
      gasPrice = null;

  const _EvmGasFee.legacy(BigInt this.gasPrice) : eip1559 = false, maxFeePerGas = null, maxPriorityFeePerGas = null;

  final bool eip1559;
  final BigInt? maxFeePerGas;
  final BigInt? maxPriorityFeePerGas;
  final BigInt? gasPrice;
}
