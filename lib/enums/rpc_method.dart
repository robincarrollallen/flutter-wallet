/// JSON-RPC 方法（用于原生币余额查询）。
enum RpcMethod { ethGetBalance, solGetBalance, suiGetBalance }

/// RpcMethod 枚举映射逻辑(映射逻辑和枚举本体分开更灵活)
extension RpcMethodX on RpcMethod {
  String get wireName => switch (this) {
    RpcMethod.ethGetBalance => 'eth_getBalance',
    RpcMethod.solGetBalance => 'getBalance',
    RpcMethod.suiGetBalance => 'suix_getBalance',
  };
}

/// EVM JSON-RPC 方法（用于交易发送与估费流程）。
enum EvmRpcMethod {
  getTransactionCount,
  getBalance,
  sendRawTransaction,
  getBlockByNumber,
  maxPriorityFeePerGas,
  gasPrice,
  estimateGas,
  getCode,
  getTransactionReceipt,
  call,
}

/// EvmRpcMethod 的链上方法名映射。
extension EvmRpcMethodX on EvmRpcMethod {
  String get wireName => switch (this) {
    EvmRpcMethod.getTransactionCount => 'eth_getTransactionCount',
    EvmRpcMethod.getBalance => 'eth_getBalance',
    EvmRpcMethod.sendRawTransaction => 'eth_sendRawTransaction',
    EvmRpcMethod.getBlockByNumber => 'eth_getBlockByNumber',
    EvmRpcMethod.maxPriorityFeePerGas => 'eth_maxPriorityFeePerGas',
    EvmRpcMethod.gasPrice => 'eth_gasPrice',
    EvmRpcMethod.estimateGas => 'eth_estimateGas',
    EvmRpcMethod.getCode => 'eth_getCode',
    EvmRpcMethod.getTransactionReceipt => 'eth_getTransactionReceipt',
    EvmRpcMethod.call => 'eth_call',
  };
}
