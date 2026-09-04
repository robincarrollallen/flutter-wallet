import '../../../blockchain/chain_registry.dart';
import '../../../domain/btc_utxo.dart';
import 'rest_client.dart';

/// 比特币 UTXO 集合的远程查询（Esplora / mempool.space 兼容）。
///
/// 与 [ChainBalanceApi] 同层但**独立成类**：那边的契约是「一条链换一个 BigInt」，
/// 而 UTXO 是集合语义、余额只是它的一个投影。硬塞回那个 switch 分发里，
/// 返回类型就得退化成 Object，分发本身也就失去意义了。
class BitcoinUtxoApi {
  const BitcoinUtxoApi();

  /// 查询一组地址的 UTXO 并合并。
  ///
  /// 现在集合里恒为一个元素（只派生 m/84'/1'/0'/0/0），但签名按集合设计：
  /// 正常的 BTC 钱包必须有找零链，扩到多地址时调用方与下游模型都不用改。
  /// 并发而非串行——地址数一多，串行等待直接线性累加。
  Future<List<Utxo>> fetchUtxos(Chain chain, List<String> addresses) async {
    if (addresses.isEmpty) return const [];
    final lists = await Future.wait([for (final address in addresses) _utxosOf(chain, address)]);
    return [for (final list in lists) ...list];
  }

  Future<List<Utxo>> _utxosOf(Chain chain, String address) async =>
      parseUtxos(await getJsonArray(Uri.parse('${chain.endpoint}/address/$address/utxo')), address);

  /// 解析 `GET /address/{addr}/utxo` 的数组响应。
  ///
  /// 这个接口**已经把 mempool 计入**：未确认收到的会出现在列表里，被未确认交易
  /// 花掉的会直接消失（而不是标成 spent）。所以不必再查一次 mempool 做差集，
  /// 拿到的就是「当前可见的 UTXO 集合」。
  ///
  /// 非 Map 元素逐条跳过而不是整批失败：一条脏数据不该让整条链的余额变成错误态。
  static List<Utxo> parseUtxos(List<dynamic> json, String address) => [
    for (final entry in json)
      if (entry is Map<String, dynamic>) Utxo.fromJson(entry, address),
  ];
}
