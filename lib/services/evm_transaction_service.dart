import 'package:on_chain/ethereum/ethereum.dart';
import '../blockchain/units.dart';
import '../blockchain/chain_registry.dart';
import '../core/utils/evm_hex.dart';
import '../data/datasource/remote/json_rpc.dart';
import '../domain/evm_fee.dart';
import '../enums/evm_send_status.dart';
import '../enums/fee_speed.dart';

/// EVM 原生币转账：取 nonce / 估费 / 估 gas → 构造交易 → 本地签名 → 广播 → 轮询 receipt。
/// 仅处理原生币（ERC20 暂未接入）。EOA→EOA 通常为 21000；合约收款走 eth_estimateGas。
class EvmTransactionService {
  const EvmTransactionService();

  /// EOA 纯转账的固定 gas 用量下限。
  static final BigInt _nativeEoaGasLimit = BigInt.from(21000);

  /// 估算 gas 上浮比例（分子/分母），给合约执行留余量。
  static const int _gasBufferNum = 12;
  static const int _gasBufferDen = 10;

  /// 等待 receipt 的默认超时与轮询间隔。
  static const Duration _receiptTimeout = Duration(seconds: 90);
  static const Duration _receiptPollInterval = Duration(seconds: 2);

  /// eth_feeHistory 回看的区块数：太短受单块抖动影响，太长跟不上拥堵变化。
  static const int _feeHistoryBlocks = 10;

  /// 发送原生币转账，返回 (交易哈希, 实际发送金额, 上链状态)。
  ///
  /// [privateKeyHex] 为 0x 前缀的 secp256k1 私钥，仅在本次调用内使用。
  /// [fromAddress] 为 UI/钱包展示的发送方地址，必须与私钥派生地址一致（忽略大小写）。
  /// [amount] 为用户输入的十进制金额字符串，按 [Chain.decimals] 转 wei。
  ///
  /// [deductFeeFromAmount] 仅在「全额转出（MAX）」场景传 true：此时若
  /// 「金额 + 费用上限」超过实时余额（例如从填入 MAX 到确认之间 baseFee 上涨），
  /// 自动把费用从转出额中扣除，扣完不为正则抛 [Exception]，实际金额随结果返回。
  ///
  /// 默认 false——用户手输的金额是明确意图，余额不足时必须报错，
  /// **绝不能**静默改小金额后广播。
  Future<({String hash, String sentAmount, EvmSendStatus status})> sendNative({
    required Chain chain,
    required String privateKeyHex,
    required String fromAddress,
    required String to,
    required String amount,
    bool deductFeeFromAmount = false,
    FeeSpeed speed = FeeSpeed.defaultSpeed,
  }) async {
    final chainId = chain.evmChainId;
    if (chainId == null) {
      throw StateError('链 ${chain.id} 缺少 evmChainId 配置');
    }

    final signer = ETHPrivateKey(privateKeyHex);
    final from = signer.publicKey().toAddress();
    if (from.address.toLowerCase() != fromAddress.trim().toLowerCase()) {
      throw Exception('签名地址与钱包地址不一致');
    }

    var value = parseUnits(amount, chain.decimals);

    // pending：与 nonce 同口径，避免未确认转出仍被算作可用余额。
    final nonceHex =
        await jsonRpcCall(chain.endpoint, EvmRpcMethod.getTransactionCount.wireName, [from.address, 'pending'])
            as String;
    final fee = (await fetchGasBasis(chain.endpoint)).rateFor(speed);
    var gasLimit = await _resolveGasLimit(chain.endpoint, from.address, to, value, chain.symbol);
    var feeCap = fee.capGasPrice * gasLimit;

    final balanceHex =
        await jsonRpcCall(chain.endpoint, EvmRpcMethod.getBalance.wireName, [from.address, 'pending']) as String;
    final balance = parseEvmHexQuantity(balanceHex);
    if (value + feeCap > balance) {
      if (!deductFeeFromAmount) {
        final need = formatUnits(value + feeCap, chain.decimals);
        final have = formatUnits(balance, chain.decimals);
        throw Exception(
          '余额不足：本次需 $need ${chain.symbol}'
          '（含网络费用约 ${formatUnits(feeCap, chain.decimals)}），可用 $have ${chain.symbol}',
        );
      }
      value = balance - feeCap;
      if (value <= BigInt.zero) throw Exception('余额不足以支付网络费用');
      // MAX 扣费后金额变了，合约收款可能需重新估 gas，再按新 feeCap 收敛一次。
      gasLimit = await _resolveGasLimit(chain.endpoint, from.address, to, value, chain.symbol);
      feeCap = fee.capGasPrice * gasLimit;
      if (value + feeCap > balance) {
        value = balance - feeCap;
        if (value <= BigInt.zero) throw Exception('余额不足以支付网络费用');
      }
    }

    final unsigned = ETHTransaction(
      type: fee.eip1559 ? ETHTransactionType.eip1559 : ETHTransactionType.legacy,
      from: from,
      to: ETHAddress(to),
      nonce: parseEvmHexQuantity(nonceHex).toInt(),
      gasLimit: gasLimit,
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
        await jsonRpcCall(chain.endpoint, EvmRpcMethod.sendRawTransaction.wireName, ['0x${_toHex(raw)}']) as String;
    final status = await waitForReceipt(chain.endpoint, hash);
    return (hash: hash, sentAmount: formatUnits(value, chain.decimals), status: status);
  }

  /// 轮询 [eth_getTransactionReceipt]，直到确认/失败或超时（返回 pending）。
  Future<EvmSendStatus> waitForReceipt(
    String endpoint,
    String txHash, {
    Duration timeout = _receiptTimeout,
    Duration interval = _receiptPollInterval,
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final receipt = await jsonRpcCall(endpoint, EvmRpcMethod.getTransactionReceipt.wireName, [txHash]);
      if (receipt is Map) {
        final statusHex = receipt['status'] as String?;
        if (statusHex == null) return EvmSendStatus.confirmed; // 极老节点无 status，有回执即视为上链
        final status = parseEvmHexQuantity(statusHex);
        return status == BigInt.one ? EvmSendStatus.confirmed : EvmSendStatus.failed;
      }
      await Future<void>.delayed(interval);
    }
    return EvmSendStatus.pending;
  }

  /// EOA→EOA 用 21000；合约收款走 eth_estimateGas（失败则明确报错）。
  Future<BigInt> _resolveGasLimit(String endpoint, String from, String to, BigInt value, String symbol) async {
    final code = await jsonRpcCall(endpoint, EvmRpcMethod.getCode.wireName, [to, 'latest']) as String;
    final normalized = code.toLowerCase();
    final isEoa = normalized == '0x' || normalized == '0x0';
    if (isEoa) return _nativeEoaGasLimit;

    Future<BigInt> estimate(BigInt v) async {
      final params = <String, Object?>{'from': from, 'to': to, 'value': '0x${v.toRadixString(16)}'};
      final gasHex = await jsonRpcCall(endpoint, EvmRpcMethod.estimateGas.wireName, [params]) as String;
      final estimated = parseEvmHexQuantity(gasHex);
      final buffered = (estimated * BigInt.from(_gasBufferNum)) ~/ BigInt.from(_gasBufferDen);
      return buffered < _nativeEoaGasLimit ? _nativeEoaGasLimit : buffered;
    }

    try {
      return await estimate(value);
    } catch (_) {
      if (value > BigInt.zero) {
        try {
          return await estimate(BigInt.zero);
        } catch (_) {}
      }
      throw Exception('无法估算合约收款所需 gas，请确认地址可接收 $symbol');
    }
  }

  /// 抓取全网费率基准：有 baseFee 则走 EIP-1559（附各档小费），否则回退 legacy。
  /// 网络/解析错误上抛，避免瞬时抖动把交易类型静默改成 legacy。
  Future<EvmGasBasis> fetchGasBasis(String endpoint) async {
    final block = await jsonRpcCall(endpoint, EvmRpcMethod.getBlockByNumber.wireName, ['latest', false]) as Map;
    final baseFeeHex = block['baseFeePerGas'] as String?;
    if (baseFeeHex == null) {
      final priceHex = await jsonRpcCall(endpoint, EvmRpcMethod.gasPrice.wireName, []) as String;
      return EvmGasBasis.legacy(parseEvmHexQuantity(priceHex), fetchedAt: DateTime.now());
    }
    return EvmGasBasis.eip1559(
      baseFee: parseEvmHexQuantity(baseFeeHex),
      tipByPercentile: await _fetchTips(endpoint),
      fetchedAt: DateTime.now(),
    );
  }

  /// 一笔原生转账的 gasLimit：提供 [from]/[to] 时按收款方估，否则按 EOA 21000。
  Future<BigInt> resolveNativeGasLimit(Chain chain, {String? from, String? to}) {
    if (from == null || to == null || from.isEmpty || to.isEmpty) return Future.value(_nativeEoaGasLimit);
    return _resolveGasLimit(chain.endpoint, from, to, BigInt.zero, chain.symbol);
  }

  /// 各档小费：取最近 [_feeHistoryBlocks] 个区块 reward 各分位的均值。
  /// 节点不支持 eth_feeHistory（或返回残缺）时回退 eth_maxPriorityFeePerGas，
  /// 以它作为「普通」档，另两档按档位倍率上下浮动——降级后档位仍有区分度。
  Future<Map<int, BigInt>> _fetchTips(String endpoint) async {
    final percentiles = FeeSpeed.values.map((speed) => speed.rewardPercentile).toList();
    try {
      final history =
          await jsonRpcCall(endpoint, EvmRpcMethod.feeHistory.wireName, [
                '0x${_feeHistoryBlocks.toRadixString(16)}',
                'latest',
                percentiles,
              ])
              as Map;
      // reward: 每个区块一行，行内按 percentiles 顺序给出对应分位的小费。
      final rewards = (history['reward'] as List).cast<List<Object?>>();
      if (rewards.isEmpty) throw const FormatException('reward 为空');
      return {
        for (var column = 0; column < percentiles.length; column++)
          percentiles[column]:
              rewards.map((row) => parseEvmHexQuantity(row[column] as String)).reduce((sum, tip) => sum + tip) ~/
              BigInt.from(rewards.length),
      };
    } catch (_) {
      final tipHex = await jsonRpcCall(endpoint, EvmRpcMethod.maxPriorityFeePerGas.wireName, []) as String;
      final tip = parseEvmHexQuantity(tipHex);
      return {for (final speed in FeeSpeed.values) speed.rewardPercentile: scaleFee(tip, speed.legacyMultiplier)};
    }
  }

  String _toHex(List<int> bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
