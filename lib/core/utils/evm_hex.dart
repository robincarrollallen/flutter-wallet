/// 解析 EVM JSON-RPC 返回的十六进制 quantity（单位通常为 wei）到 BigInt。
BigInt parseEvmHexQuantity(String hex) {
  final clean = hex.startsWith('0x') ? hex.substring(2) : hex;
  if (clean.isEmpty) return BigInt.zero;
  return BigInt.parse(clean, radix: 16);
}

/// 把十六进制字符串（可带 `0x`）解成字节数组。长度为奇数即抛 [FormatException]——
/// 半个字节没有合法解释，补零或截断都会悄悄改变 calldata 的语义。
List<int> evmHexToBytes(String hex) {
  final clean = hex.startsWith('0x') || hex.startsWith('0X') ? hex.substring(2) : hex;
  if (clean.length.isOdd) {
    throw FormatException('十六进制长度必须为偶数：$hex');
  }
  return [for (var i = 0; i < clean.length; i += 2) int.parse(clean.substring(i, i + 2), radix: 16)];
}

/// 把字节数组编成**不带 `0x`** 的十六进制字符串。
String evmBytesToHex(List<int> bytes) => [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')].join();
