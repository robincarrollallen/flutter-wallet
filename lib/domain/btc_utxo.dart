/// 【领域模型】一个未花费输出（UTXO）。金额单位是**聪**，不做小数换算——
/// 换算是 repository 的职责，与 [AccountBalance] 保持同一约定。
class Utxo {
  const Utxo({
    required this.txid,
    required this.vout,
    required this.value,
    required this.confirmed,
    required this.address,
    this.blockHeight,
  });

  final String txid; // 产生这个输出的交易 id
  final int vout; // 输出在该交易里的序号；(txid, vout) 合起来才是唯一标识
  final BigInt value; // 面额，单位聪
  final bool confirmed; // 是否已进块

  /// 归属地址。当前只派生一个地址，这个字段看着冗余，但币选择要知道每个输入
  /// 该用哪把私钥签名——等扩到找零链，缺了它就得回头重查一遍归属。
  final String address;

  /// 所在块高；未确认为 null。
  ///
  /// **不能用 `?? 0` 兜底**：0 是创世块高度，一个「未确认」的输出会被误读成
  /// 「确认数已达当前块高」，任何基于确认数的判断都会反过来。
  final int? blockHeight;

  /// 输出点标识。做去重、以及将来比对「这个输入是不是我已经花掉了」时用。
  String get outpoint => '$txid:$vout';

  /// Esplora 的单条 utxo。未确认项的 `status` 只有 `{"confirmed": false}`，
  /// 其余字段整个缺失，所以除 confirmed 外都必须容忍空值。
  factory Utxo.fromJson(Map<String, dynamic> json, String address) {
    final status = json['status'] as Map<String, dynamic>? ?? const {};
    return Utxo(
      txid: json['txid'] as String? ?? '',
      vout: (json['vout'] as num?)?.toInt() ?? 0,
      value: BigInt.from((json['value'] as num?)?.toInt() ?? 0),
      confirmed: status['confirmed'] == true,
      address: address,
      blockHeight: (status['block_height'] as num?)?.toInt(),
    );
  }
}

/// 【领域模型】一组地址的 UTXO 集合，以及从中投影出的三口径余额。
///
/// 为什么保留集合而不是只存三个数字：手续费取决于**输入个数**（vsize），
/// 同样 0.01 BTC 由 1 个输出还是 200 个碎片组成，可发金额差很多。把结构丢在
/// 数据层，发送时还得重查一遍——而那时 UTXO 可能已经变了。
///
/// 集合的来源 `GET /address/{addr}/utxo` **已经把 mempool 计入**：未确认收到的
/// 会出现（confirmed: false），被未确认交易花掉的会直接从列表消失。所以
/// [total] 天然等于「已确认净额 + 未确认净额」，与旧的 chain_stats+mempool_stats
/// 口径等价。代价是「自己花出去但未确认」表现为**消失而非负数**，单看这个集合
/// 无从得知具体流出了多少——要显示它得对每个 [ownTxids] 调 `GET /tx/{txid}`
/// 读 vin 的 prevout，等发送链路落地后再做。
class UtxoSet {
  const UtxoSet(this.utxos, {this.ownTxids = const {}});

  static const empty = UtxoSet([]);

  final List<Utxo> utxos;

  /// 本机广播过、尚未确认的交易 id。
  ///
  /// 链上查不到这个信息——找零输出的脚本与普通收款没有任何区别，只有本地记账
  /// 能把两者分开。见 [BroadcastHistoryNotifier]。
  final Set<String> ownTxids;

  /// 已确认：进了块的部分。最保守的口径。
  BigInt get confirmed => _sum(utxos.where((u) => u.confirmed));

  /// 待确认：还在 mempool 里的**收入**（含自己交易找回来的零）。
  /// 不含「自己花出去未确认」的支出——见类文档。
  BigInt get pending => _sum(utxos.where((u) => !u.confirmed));

  /// 可花：已确认 + 自己的未确认找零。
  ///
  /// 找零能算进来，是因为它的父交易是我们自己广播的、已完整签名的，花它只是
  /// 再挂一节 mempool 链（CPFP 语义），节点会接受。而别人发来的未确认转账，
  /// 对方随时可以 RBF 替换掉，拿它当输入会让我们的交易跟着一起作废——所以
  /// 无论金额多诱人都不计入。
  BigInt get spendable => _sum(utxos.where((u) => u.confirmed || ownTxids.contains(u.txid)));

  /// 总额 = 已确认 + 待确认。与旧的 chain_stats+mempool_stats 口径等价，
  /// 界面主数字用它，改造前后不会跳变。
  BigInt get total => _sum(utxos);

  /// 【下一期】按费率过滤掉不经济碎片后的可花余额。
  ///
  /// 一个 UTXO 的面额低于「花掉它本身要付的手续费」时，它是净负资产，选币时
  /// 必须排除。p2wpkh 单输入 **68 vB**：输入部分 (36 outpoint + 1 scriptSig 长度
  /// + 4 sequence) × 4 = 164 weight，witness 部分 108 weight（1 计数 + 1+72 签名
  /// + 1+33 公钥），合计 272 ÷ 4 = 68。对应地，一个 p2wpkh 输出是 31 vB。
  ///
  /// 现在不实现：碎片过滤只在构造交易时有意义，而费率还没有任何 UI。提前放进
  /// 余额口径反而有害——用户看到「可花 0.00095」而持有 0.001，却没有入口解释
  /// 这 0.00005 去哪了。
  // BigInt spendableAt(int feeRatePerVb) =>
  //     _sum(utxos.where((u) => ... && u.value > BigInt.from(68 * feeRatePerVb)));

  static BigInt _sum(Iterable<Utxo> utxos) => utxos.fold(BigInt.zero, (acc, u) => acc + u.value);
}
