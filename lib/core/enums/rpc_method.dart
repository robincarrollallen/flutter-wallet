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
