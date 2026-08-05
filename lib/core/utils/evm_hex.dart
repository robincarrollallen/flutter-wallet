/// 解析 EVM JSON-RPC 返回的十六进制 quantity（单位通常为 wei）到 BigInt。
BigInt parseEvmHexQuantity(String hex) {
  final clean = hex.startsWith('0x') ? hex.substring(2) : hex;
  if (clean.isEmpty) return BigInt.zero;
  return BigInt.parse(clean, radix: 16);
}
