import 'evm_hex.dart';

/// EVM ABI 里 `balanceOf(address)` 这一个函数的编解码。
///
/// **TRC-20 一并复用**：Tron 的合约调用就是 EVM ABI，只是它的 REST 接口把选择器
/// （`function_selector`）与参数（`parameter`）拆成了两个字段传，所以补零那半截
/// 单独暴露成 [encodeAddressArgument]。

/// ERC-20 `balanceOf(address)` 的函数选择器：keccak256 签名的前 4 字节。
const _balanceOfSelector = '70a08231';

/// 把 20 字节地址编成 32 字节的 ABI 参数：右对齐补零，返回**不带 `0x`** 的 64 位十六进制。
///
/// 这个格式正是 Tron `triggerconstantcontract` 的 `parameter` 字段所需；
/// EVM 侧由 [encodeBalanceOf] 接上选择器后使用。
///
/// 长度不符即抛 [ArgumentError]——地址错了就查不到余额，
/// 静默补零只会得到一个陌生地址的 0。
String encodeAddressArgument(List<int> address20Bytes) {
  if (address20Bytes.length != 20) {
    throw ArgumentError.value(address20Bytes.length, 'address20Bytes', '地址必须是 20 字节');
  }
  return [for (final b in address20Bytes) b.toRadixString(16).padLeft(2, '0')].join().padLeft(64, '0');
}

/// 编码 `balanceOf(address)` 的 calldata，供 `eth_call` 的 `data` 字段使用。
///
/// ABI 定长编码：4 字节选择器 + 地址右对齐补零到 32 字节。只有这一个定长函数，
/// 手写比引入完整 ABI 编码器更轻，也更好测。
///
/// [ownerAddress] 需为 20 字节的十六进制地址（带不带 0x 都可）；长度不符即抛
/// [ArgumentError]。
String encodeBalanceOf(String ownerAddress) {
  final clean = _strip0x(ownerAddress);
  if (clean.length != 40 || !_isHex(clean)) {
    throw ArgumentError.value(ownerAddress, 'ownerAddress', '不是合法的 20 字节 EVM 地址');
  }
  return '0x$_balanceOfSelector${encodeAddressArgument(_hexToBytes(clean))}';
}

List<int> _hexToBytes(String hex) => [
  for (var i = 0; i < hex.length; i += 2) int.parse(hex.substring(i, i + 2), radix: 16),
];

/// 解析 `eth_call` 返回的 uint256。
///
/// 空返回（`0x` 或空串）不当 0：这通常意味着该地址上根本没有合约代码
/// （合约地址填错、或链选错），继续按 0 展示等于谎报「你没有这个币」。
BigInt decodeUint256(String hex) {
  final clean = _strip0x(hex);
  if (clean.isEmpty) {
    throw const FormatException('eth_call 返回空数据：目标地址可能不是合约');
  }
  return parseEvmHexQuantity(clean);
}

String _strip0x(String hex) {
  final trimmed = hex.trim();
  return trimmed.startsWith('0x') || trimmed.startsWith('0X') ? trimmed.substring(2) : trimmed;
}

bool _isHex(String s) => RegExp(r'^[0-9a-fA-F]+$').hasMatch(s);
