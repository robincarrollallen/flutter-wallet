import 'package:on_chain/ethereum/ethereum.dart';
import '../blockchain/units.dart';
import '../blockchain/chain_registry.dart';
import '../blockchain/token.dart';
import '../core/utils/erc20_abi.dart';
import '../core/utils/evm_hex.dart';
import '../data/datasource/remote/json_rpc.dart';
import '../domain/evm_fee.dart';
import '../enums/fee_speed.dart';
import 'transfer/transfer_result.dart';

/// EVM 转账实现：取 nonce / 估费 / 估 gas → 构造交易 → 本地签名 → 广播 → 轮询 receipt
class EvmTransactionService {
  const EvmTransactionService({JsonRpcCaller call = jsonRpcCall}) : _call = call;

  /// 调用 JSON-RPC 的接口，用于与链上交互(测试注入, 生产默认使用[jsonRpcCall])
  final JsonRpcCaller _call;

  /// EOA「原生币」纯转账的固定 gas 用量下限
  static final BigInt _nativeEoaGasLimit = BigInt.from(21000);

  /// 估算 gas 上浮比例「分子[_gasBufferNum] / [_gasBufferDen]分母」，给合约执行留余量
  static const int _gasBufferNum = 12;
  static const int _gasBufferDen = 10;

  /// 等待 receipt 的超时时间
  static const Duration _receiptTimeout = Duration(seconds: 90);
  /// 等待 receipt 的轮询间隔
  static const Duration _receiptPollInterval = Duration(seconds: 2);

  /// eth_feeHistory 回看的区块数：太短受单块抖动影响，太长跟不上拥堵变化
  static const int _feeHistoryBlocks = 10;

  /// 发送原生币转账，返回 (交易哈希, 实际发送金额, 上链状态)
  Future<TransferResult> sendNative({
    required Chain chain, // 链信息「实例」
    required List<int> privateKey, // 私钥「原始 32 字节 secp256k1」(仅在本次调用内使用)
    required String fromAddress, // 发送方地址，必须与私钥派生地址一致（忽略大小写）
    required String to, // 接收方地址
    required String amount, // 用户输入的十进制金额字符串，按 [Chain.decimals] 转 wei
    bool deductFeeFromAmount = false, // 是否从金额中扣除费用
    FeeSpeed speed = FeeSpeed.defaultSpeed, // 手续费档位
  }) async {
    final chainId = chain.evmChainId; // EVM 链的 chainId「数字」
    if (chainId == null) {
      throw StateError('链 ${chain.id} 缺少 evmChainId 配置'); // 链缺少 evmChainId 配置抛出异常
    }

    final signer = ETHPrivateKey.fromBytes(privateKey); // 从私钥生成签名器
    final from = signer.publicKey().toAddress(); // 从签名器生成发送方地址
    if (from.address.toLowerCase() != fromAddress.trim().toLowerCase()) {
      throw Exception('签名地址与钱包地址不一致'); // 签名地址与钱包地址不一致抛出异常
    }

    var value = parseUnits(amount, chain.decimals); // 将转出金额转换为wei

    // 交易序号：与 nonce 同口径，pending「含未上链的发出交易」避免未确认转出仍被算作可用余额
    final nonceHex =
        await _call(chain.endpoint, EvmRpcMethod.getTransactionCount.wireName, [from.address, 'pending'])
            as String;
    final fee = (await fetchGasBasis(chain.endpoint)).rateFor(speed); // 获取并计算手续费「实例」(按档位)
    var gasLimit = await _resolveGasLimit(chain.endpoint, from.address, to, value, chain.symbol); // 估算 gas 用量
    var feeCap = fee.capGasPrice * gasLimit; // 计算手续费上限[wei]

    // 余额校验：检查账户余额是否足够支付本次交易费用(金额 + 手续费上限)[wei]
    final balanceHex =
        await _call(chain.endpoint, EvmRpcMethod.getBalance.wireName, [from.address, 'pending']) as String;
    final balance = parseEvmHexQuantity(balanceHex); // 获取账户余额[wei]

    // 如果本次交易费用(金额 + 手续费上限)大于账户余额(后续判断是否需要从余额中扣除手续费或重新估算gas用量)
    if (value + feeCap > balance) {
      // 如果需要从金额中扣除手续费，则计算本次交易所需金额和账户余额, 然后抛出异常
      if (!deductFeeFromAmount) {
        final need = formatUnits(value + feeCap, chain.decimals); // 计算本次交易所需金额[单位：chain.symbol]
        final have = formatUnits(balance, chain.decimals); // 计算账户余额[单位：chain.symbol]
        throw Exception(
          '余额不足：本次需 $need ${chain.symbol}'
          '（含网络费用约 ${formatUnits(feeCap, chain.decimals)}），可用 $have ${chain.symbol}',
        ); // 抛出异常(余额不足)
      }

      value = balance - feeCap; // 重新计算转出金额: 余额扣除手续费后金额[wei]
      if (value <= BigInt.zero) throw Exception('余额不足以支付网络费用'); // 如果扣除手续费后金额小于0，则抛出异常

      gasLimit = await _resolveGasLimit(chain.endpoint, from.address, to, value, chain.symbol); // 重新估算 gas 用量
      feeCap = fee.capGasPrice * gasLimit; // 重新计算手续费上限[wei]

      // 如果重新计算的手续费上限大于账户余额，重新计算转出金额
      if (value + feeCap > balance) {
        value = balance - feeCap; // 重新计算转出金额: 余额扣除手续费后金额[wei]
        if (value <= BigInt.zero) throw Exception('余额不足以支付网络费用'); // 如果扣除手续费后金额小于0，则抛出异常
      }
    }

    // 签名并广播交易
    final (:hash, :status) = await _signAndBroadcast(
      chain: chain,
      evmChainId: chainId,
      signer: signer,
      from: from,
      to: to,
      value: value,
      data: const [],
      nonce: parseEvmHexQuantity(nonceHex).toInt(),
      gasLimit: gasLimit,
      fee: fee,
    );
    return (hash: hash, sentAmount: formatUnits(value, chain.decimals), status: status);
  }

  /// 发送 ERC-20 代币转账，返回 (交易哈希, 实际发送金额, 上链状态)
  Future<TransferResult> sendToken({
    required Chain chain, // 链信息「实例」
    required Token token, // 代币信息「实例」
    required List<int> privateKey, // 私钥「原始 32 字节 secp256k1」(仅在本次调用内使用)
    required String fromAddress, // 发送方地址，必须与私钥派生地址一致（忽略大小写）
    required String to, // 接收方地址
    required String amount, // 用户输入的十进制金额字符串，按 [Token.decimals] 转 wei
    FeeSpeed speed = FeeSpeed.defaultSpeed, // 手续费档位
  }) async {
    final chainId = chain.evmChainId; // EVM 链的 chainId「数字」
    if (chainId == null) {
      throw StateError('链 ${chain.id} 缺少 evmChainId 配置'); // 链缺少 evmChainId 配置抛出异常
    }
    if (token.standard != TokenStandard.erc20) {
      throw UnsupportedError('${token.symbol} 不是 ERC-20 代币，无法在 ${chain.name} 上转账'); // 代币不是 ERC-20 代币抛出异常
    }

    final signer = ETHPrivateKey.fromBytes(privateKey); // 从私钥生成签名器
    final from = signer.publicKey().toAddress(); // 从签名器生成发送方地址
    if (from.address.toLowerCase() != fromAddress.trim().toLowerCase()) {
      throw Exception('签名地址与钱包地址不一致'); // 签名地址与钱包地址不一致抛出异常
    }

    final value = parseUnits(amount, token.decimals); // 将转出金额转换为wei
    if (value <= BigInt.zero) throw Exception('转账金额必须大于 0'); // 转账金额必须大于 0抛出异常
    final contract = token.identifier; // 代币合约地址
    final data = encodeTransfer(to: to, amount: value); // 构造转账数据「传参」

    // 代币余额：不足时直接报错，绝不静默改小金额（与原生币手输金额同一原则）。
    final tokenBalance = decodeUint256(
      await _call(chain.endpoint, EvmRpcMethod.call.wireName, [
            {'to': contract, 'data': encodeBalanceOf(from.address)},
            'latest',
          ])
          as String,
    );
    // 如果转出金额大于代币余额，则抛出异常
    if (value > tokenBalance) {
      throw Exception(
        '${token.symbol} 余额不足：本次需 ${formatUnits(value, token.decimals)}，'
        '可用 ${formatUnits(tokenBalance, token.decimals)}',
      );
    }

    // 交易序号：与 nonce 同口径，pending「含未上链的发出交易」避免未确认转出仍被算作可用余额
    final nonceHex =
        await _call(chain.endpoint, EvmRpcMethod.getTransactionCount.wireName, [from.address, 'pending'])
            as String;
    final fee = (await fetchGasBasis(chain.endpoint)).rateFor(speed); // 获取并计算手续费「实例」(按档位)
    final gasLimit = await resolveTokenGasLimit(chain, from: from.address, contract: contract, data: data); // 估算 gas 用量
    final feeCap = fee.capGasPrice * gasLimit; // 计算手续费上限[wei]

    // 获取原生币余额(手续费走原生币，与代币余额是两本账，必须单独校验)
    final nativeBalance = parseEvmHexQuantity(
      await _call(chain.endpoint, EvmRpcMethod.getBalance.wireName, [from.address, 'pending']) as String,
    );
    // 如果手续费上限大于原生币余额，则抛出异常
    if (feeCap > nativeBalance) {
      throw Exception(
        '${chain.symbol} 不足以支付网络费：需约 ${formatUnits(feeCap, chain.decimals)} ${chain.symbol}，'
        '可用 ${formatUnits(nativeBalance, chain.decimals)}',
      );
    }

    // 签名并广播交易
    final (:hash, :status) = await _signAndBroadcast(
      chain: chain,
      evmChainId: chainId,
      signer: signer,
      from: from,
      to: contract,
      value: BigInt.zero,
      data: evmHexToBytes(data),
      nonce: parseEvmHexQuantity(nonceHex).toInt(),
      gasLimit: gasLimit,
      fee: fee,
    );
    return (hash: hash, sentAmount: formatUnits(value, token.decimals), status: status);
  }

  /// 构造交易 → 本地签名 → 广播 → 轮询 receipt。原生币与代币共用。
  Future<({String hash, EvmSendStatus status})> _signAndBroadcast({
    required Chain chain, // 链信息「实例」
    required int evmChainId, // EVM 链的 chainId「数字」
    required ETHPrivateKey signer, // 签名器「实例」
    required ETHAddress from, // 发送方地址「实例」
    required String to, // 接收方地址
    required BigInt value, // 转出金额[wei]
    required List<int> data, // 转账数据「传参」
    required int nonce, // 交易序号
    required BigInt gasLimit, // gas 用量[wei]
    required EvmFeeRate fee, // 手续费「实例」
  }) async {
    /// 构造交易「未签名」
    final unsigned = ETHTransaction(
      type: fee.eip1559 ? ETHTransactionType.eip1559 : ETHTransactionType.legacy,
      from: from,
      to: ETHAddress(to),
      nonce: nonce,
      gasLimit: gasLimit,
      maxFeePerGas: fee.eip1559 ? fee.maxFeePerGas : null,
      maxPriorityFeePerGas: fee.eip1559 ? fee.maxPriorityFeePerGas : null,
      gasPrice: fee.eip1559 ? null : fee.gasPrice,
      value: value,
      data: data,
      chainId: BigInt.from(evmChainId),
    );
    final signature = signer.sign(unsigned.serialized); // 给交易添加签名
    final raw = unsigned.copyWith(signature: signature).signedSerialized(); // 签名后的交易

    // 发送签名后的交易
    final hash = await _call(chain.endpoint, EvmRpcMethod.sendRawTransaction.wireName, ['0x${evmBytesToHex(raw)}']) as String;
    return (hash: hash, status: await waitForReceipt(chain.endpoint, hash));
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
      final receipt = await _call(endpoint, EvmRpcMethod.getTransactionReceipt.wireName, [txHash]);
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
    final code = await _call(endpoint, EvmRpcMethod.getCode.wireName, [to, 'latest']) as String;
    final normalized = code.toLowerCase();
    final isEoa = normalized == '0x' || normalized == '0x0';
    if (isEoa) return _nativeEoaGasLimit;

    try {
      return await _estimateGas(endpoint, from: from, to: to, value: value);
    } catch (_) {
      if (value > BigInt.zero) {
        try {
          return await _estimateGas(endpoint, from: from, to: to, value: BigInt.zero);
        } catch (_) {}
      }
      throw Exception('无法估算合约收款所需 gas，请确认地址可接收 $symbol');
    }
  }

  /// 一笔 ERC-20 转账的 gasLimit：合约执行用量因实现（首次写入 storage、
  /// 手续费代币等）而异，只能实测，没有 21000 那样的常量可用。
  ///
  /// [data] 为 `transfer(address,uint256)` 的 calldata（0x 前缀）。估算失败即报错，
  /// 不猜一个默认值——猜低了交易 out of gas，gas 照扣，钱没转到。
  Future<BigInt> resolveTokenGasLimit(
    Chain chain, {
    required String from,
    required String contract,
    required String data,
  }) async {
    try {
      return await _estimateGas(chain.endpoint, from: from, to: contract, value: BigInt.zero, data: data);
    } catch (_) {
      throw Exception('无法估算代币转账所需 gas，请确认合约地址与代币余额');
    }
  }

  /// 调 eth_estimateGas 并上浮 [_gasBufferNum]/[_gasBufferDen]，下限 21000。
  Future<BigInt> _estimateGas(
    String endpoint, {
    required String from,
    required String to,
    required BigInt value,
    String? data,
  }) async {
    final params = <String, Object?>{
      'from': from,
      'to': to,
      'value': '0x${value.toRadixString(16)}',
      'data': ?data,
    };
    final gasHex = await _call(endpoint, EvmRpcMethod.estimateGas.wireName, [params]) as String;
    final buffered = (parseEvmHexQuantity(gasHex) * BigInt.from(_gasBufferNum)) ~/ BigInt.from(_gasBufferDen);
    return buffered < _nativeEoaGasLimit ? _nativeEoaGasLimit : buffered;
  }

  /// 抓取全网费率基准：有 baseFee 则走 EIP-1559（附各档小费），否则回退 legacy。
  /// 网络/解析错误上抛，避免瞬时抖动把交易类型静默改成 legacy。
  Future<EvmGasBasis> fetchGasBasis(String endpoint) async {
    final block = await _call(endpoint, EvmRpcMethod.getBlockByNumber.wireName, ['latest', false]) as Map;
    final baseFeeHex = block['baseFeePerGas'] as String?;
    if (baseFeeHex == null) {
      final priceHex = await _call(endpoint, EvmRpcMethod.gasPrice.wireName, []) as String;
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
          await _call(endpoint, EvmRpcMethod.feeHistory.wireName, [
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
      final tipHex = await _call(endpoint, EvmRpcMethod.maxPriorityFeePerGas.wireName, []) as String;
      final tip = parseEvmHexQuantity(tipHex);
      return {for (final speed in FeeSpeed.values) speed.rewardPercentile: scaleFee(tip, speed.legacyMultiplier)};
    }
  }
}
