import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:on_chain/tron/tron.dart';

/// Tron 转账的费用估算结果。
///
/// 刻意不复用 [EvmFeeQuote] / [EvmGasBasis]：EVM 是「单价 × 用量」且有三档，
/// Tron 是「够带宽就免费、不够按字节烧 TRX」且没有档位（加价也不会更快）。
/// 两套模型硬套在一起只会让双方都变形。
class TronFeeEstimate {
  // 不是 const：feeSun 由两个分量相加得出，而加法不是常量表达式。
  TronFeeEstimate({
    required this.bandwidthNeeded,
    required this.freeBandwidth,
    required this.stakedBandwidth,
    required this.bandwidthFeeSun,
    required this.activationFeeSun,
    required this.fetchedAt,
    this.energyNeeded = 0,
    BigInt? energyAvailable,
    BigInt? energyFeeSun,
  }) : energyAvailable = energyAvailable ?? BigInt.zero,
       energyFeeSun = energyFeeSun ?? BigInt.zero,
       feeSun = bandwidthFeeSun + activationFeeSun + (energyFeeSun ?? BigInt.zero);

  /// 本次交易要消耗的带宽点数（= 上链后交易的字节数）。
  final int bandwidthNeeded;

  /// 发送方每日免费额度的剩余带宽。
  ///
  /// 与 [stakedBandwidth] 分开存不是为了好看：**免费带宽不能用于创建账户**
  /// （java-tron 的 `consumeBandwidthForCreateNewAccount` 只走 `useAccountNet`，
  /// 不走 `useFreeNet`），所以激活场景下只有质押那部分算数。
  final BigInt freeBandwidth;

  /// 发送方质押 / 受代理所得的剩余带宽。
  final BigInt stakedBandwidth;

  /// 可用带宽合计，仅用于展示。判定「够不够」要按场景区分，见 [bandwidthCovered]。
  BigInt get bandwidthAvailable => freeBandwidth + stakedBandwidth;

  /// 本次要烧掉的 TRX 总额（单位 sun）= [bandwidthFeeSun] + [activationFeeSun]。
  /// 带宽够且收款方已激活时为 0。
  final BigInt feeSun;

  /// 其中「带宽不足」那部分。带宽够时为 0。
  final BigInt bandwidthFeeSun;

  /// 本次合约调用要消耗的能量。原生 TRX 转账不碰能量，恒为 0。
  final int energyNeeded;

  /// 账户当前可用能量（质押所得；能量**没有**每日免费额度）。
  final BigInt energyAvailable;

  /// 其中「能量不足」那部分。
  ///
  /// 与带宽的计费方式**相反**：能量是部分消耗——账户里的能量先用掉，只有差额
  /// 按 `sunPerEnergy` 烧 TRX；而带宽是按档全额，某一档不够就整笔都烧。
  final BigInt energyFeeSun;

  /// 其中「激活收款方账户」那部分。收款方已激活时为 0。
  ///
  /// 单独留一个字段是为了让 UI 能**只**说这一笔——[feeSun] 里还可能混着带宽欠费，
  /// 拿总额去说「N TRX 为其激活」在带宽也不足时会把数字说大。
  final BigInt activationFeeSun;

  /// 收款方账户尚未上链，本次转账会顺带激活它。
  bool get activatesRecipient => activationFeeSun > BigInt.zero;

  final DateTime fetchedAt;

  /// 这一笔是否不花钱。
  bool get isFree => feeSun == BigInt.zero;

  /// 带宽是否够用（够用则不烧 TRX 抵带宽，但仍可能有账户创建费）。
  bool get bandwidthCovered => bandwidthFeeSun == BigInt.zero;
}

/// 链上费率，取自 `wallet/getchainparameters`。
///
/// **不写死常量**：这三个值都是链参数，可由委员会提案改动。默认值只在节点没返回
/// 对应字段时兜底，用的是 Tron 主网当前值。
class TronFeeRates {
  const TronFeeRates({
    this.sunPerBandwidthByte = 1000,
    this.createAccountFeeSun = 100000,
    this.createNewAccountFeeSun = 1000000,
    this.sunPerEnergy = 210,
  });

  /// `getTransactionFee`：带宽不足时每字节烧多少 sun（主网 1000 = 0.001 TRX/字节）。
  final int sunPerBandwidthByte;

  /// `getCreateAccountFee`：激活账户时若带宽也不足，额外收的固定费（0.1 TRX）。
  final int createAccountFeeSun;

  /// `getCreateNewAccountFeeInSystemContract`：激活一个新账户的固定费（1 TRX）。
  final int createNewAccountFeeSun;

  /// `getEnergyFee`：能量不足时每点能量烧多少 sun（主网 210，Nile 测试网 100）。
  /// 只有合约调用（TRC-20 转账等）才消耗能量，原生 TRX 转账不碰它。
  final int sunPerEnergy;

  /// 从 SDK 的链参数模型构造；字段缺失时回落到默认值。
  factory TronFeeRates.fromChainParameters(TronChainParameters params) => TronFeeRates(
    sunPerBandwidthByte: params.getTransactionFee ?? const TronFeeRates().sunPerBandwidthByte,
    createAccountFeeSun: params.getCreateAccountFee ?? const TronFeeRates().createAccountFeeSun,
    createNewAccountFeeSun:
        params.getCreateNewAccountFeeInSystemContract ?? const TronFeeRates().createNewAccountFeeSun,
    sunPerEnergy: params.getEnergyFee ?? const TronFeeRates().sunPerEnergy,
  );
}

/// Tron 费用的纯计算部分：不碰网络，可离线单测。
class TronFeeCalculator {
  const TronFeeCalculator._();

  /// 链上按「交易的字节数」计带宽，而这个字节数**不等于**我们本地序列化出来的长度。
  /// 还要算上 protobuf 的字段头、上链后才追加的 `result` 字段，以及签名——
  /// 我们本地签出来是 65 字节，链上按 67 计。少算这 134 字节会正好落在
  /// 「够不够免费额度」的判断边界上。
  static const int _protobufOverhead = 3;
  static const int _resultFieldBytes = 64;
  static const int _signatureBytes = 67;

  /// 一笔原生 TRX 转账要消耗多少带宽。
  ///
  /// 本地拼一份**同形**的 [TransactionRaw] 来量长度，而不是调
  /// `wallet/createtransaction` 问节点：那些字段的长度是确定的——`refBlockBytes`
  /// 恒 2 字节、`refBlockHash` 恒 8 字节、两个时间戳都是当前毫秒（varint 长度稳定）、
  /// 地址恒 21 字节。唯一随输入变化的是 [amountSun] 的 varint 长度，而这里用的
  /// 就是真实金额。于是本地结果与节点构造的一致，还省一次网络往返、且能离线测。
  static int bandwidthFor({
    required TronAddress owner,
    required TronAddress to,
    required BigInt amountSun,
  }) {
    final contract = TransferContract(ownerAddress: owner, toAddress: to, amount: amountSun);
    // 时间戳只影响 varint 长度，取当前时刻即与真实交易同量级。
    final now = BigInt.from(DateTime.now().millisecondsSinceEpoch);
    final raw = TransactionRaw(
      refBlockBytes: List.filled(2, 0),
      refBlockHash: List.filled(8, 0),
      expiration: now + BigInt.from(60000),
      timestamp: now,
      contract: [
        TransactionContract(
          type: contract.contractType,
          parameter: Any(typeUrl: contract.typeURL, value: contract),
        ),
      ],
    );
    return raw.toBuffer().length + _protobufOverhead + _resultFieldBytes + _signatureBytes;
  }

  /// TRC-20 转账的费用：带宽（交易字节）+ 能量（合约执行）。
  ///
  /// 与原生转账的两点不同：
  /// - **没有账户创建费**。向未激活地址转 TRC-20 不收那 1 TRX，代价体现为更高的
  ///   能量消耗（合约要为对方写一个新的余额槽），已经含在 [energyNeeded] 里。
  /// - **能量是部分消耗**：账户里的能量先用掉，只有差额烧 TRX。带宽则是按档全额。
  static TronFeeEstimate estimateToken({
    required int bandwidthNeeded,
    required BigInt freeBandwidth,
    required BigInt stakedBandwidth,
    required int energyNeeded,
    required BigInt energyAvailable,
    TronFeeRates rates = const TronFeeRates(),
    DateTime? fetchedAt,
  }) {
    final covered = (freeBandwidth + stakedBandwidth) >= BigInt.from(bandwidthNeeded);
    final bandwidthFee = covered
        ? BigInt.zero
        : BigInt.from(bandwidthNeeded) * BigInt.from(rates.sunPerBandwidthByte);

    // 只烧差额，不是整笔——这是能量与带宽最容易搞混的地方。
    final shortfall = BigInt.from(energyNeeded) - energyAvailable;
    final energyFee = shortfall > BigInt.zero ? shortfall * BigInt.from(rates.sunPerEnergy) : BigInt.zero;

    return TronFeeEstimate(
      bandwidthNeeded: bandwidthNeeded,
      freeBandwidth: freeBandwidth,
      stakedBandwidth: stakedBandwidth,
      bandwidthFeeSun: bandwidthFee,
      activationFeeSun: BigInt.zero,
      energyNeeded: energyNeeded,
      energyAvailable: energyAvailable,
      energyFeeSun: energyFee,
      fetchedAt: fetchedAt ?? DateTime.now(),
    );
  }

  /// 一笔 TRC-20 转账要消耗多少带宽。
  ///
  /// 与 [bandwidthFor] 同一套算法，只是合约体换成 [TriggerSmartContract]：
  /// 多了合约地址与 calldata，所以比原生转账大几十字节。
  ///
  /// [parameter] 为 `transfer(address,uint256)` 的 ABI 参数十六进制（不含选择器），
  /// 与发给节点的 `parameter` 字段同一份。
  static int bandwidthForToken({
    required TronAddress owner,
    required TronAddress contract,
    required String parameter,
  }) {
    // 选择器 4 字节 + 参数：链上 data 是二者拼接后的字节。
    const transferSelector = 'a9059cbb';
    final data = BytesUtils.fromHexString('$transferSelector$parameter');
    final call = TriggerSmartContract(ownerAddress: owner, contractAddress: contract, data: data);
    final now = BigInt.from(DateTime.now().millisecondsSinceEpoch);
    final raw = TransactionRaw(
      refBlockBytes: List.filled(2, 0),
      refBlockHash: List.filled(8, 0),
      expiration: now + BigInt.from(60000),
      timestamp: now,
      contract: [
        TransactionContract(type: call.contractType, parameter: Any(typeUrl: call.typeURL, value: call)),
      ],
    );
    return raw.toBuffer().length + _protobufOverhead + _resultFieldBytes + _signatureBytes;
  }

  /// 由「需要多少带宽 / 有多少带宽 / 收款方是否已激活 / 链上费率」算出实付。
  ///
  /// 两条互不重叠的收费规则：
  /// - **带宽不足**：按字节烧 TRX（`需要的带宽 × sunPerBandwidthByte`）；
  /// - **收款方未激活**：固定收 `createNewAccountFeeSun`（1 TRX），若此时带宽也不足，
  ///   则带宽那部分**改按固定的 `createAccountFeeSun`（0.1 TRX）收**，而不是按字节。
  static TronFeeEstimate estimate({
    required int bandwidthNeeded,
    required BigInt freeBandwidth,
    required BigInt stakedBandwidth,
    required bool recipientActivated,
    TronFeeRates rates = const TronFeeRates(),
    DateTime? fetchedAt,
  }) {
    final needed = BigInt.from(bandwidthNeeded);

    // 带宽是**按档全额**扣的，不是「先用完再烧差额」：某一档不足以覆盖整笔，
    // 这一档就完全用不上，直接进入下一档乃至烧 TRX。所以这里是 >= 判定，
    // 而欠费也按整笔算，不减去已有的那部分。
    //
    // 激活场景刻意只看质押那档：免费额度不能用于创建账户
    // （java-tron 的 consumeBandwidthForCreateNewAccount 只走 useAccountNet）。
    final covered = recipientActivated
        ? (freeBandwidth + stakedBandwidth) >= needed
        : stakedBandwidth >= needed;

    final activationFee = recipientActivated ? BigInt.zero : BigInt.from(rates.createNewAccountFeeSun);

    // 带宽欠费的算法随场景变：普通转账按字节计价，而激活场景下是**固定**的
    // createAccountFee，不按字节——这条容易想当然写成 needed × 单价。
    final BigInt bandwidthFee;
    if (covered) {
      bandwidthFee = BigInt.zero;
    } else if (recipientActivated) {
      bandwidthFee = needed * BigInt.from(rates.sunPerBandwidthByte);
    } else {
      bandwidthFee = BigInt.from(rates.createAccountFeeSun);
    }

    return TronFeeEstimate(
      bandwidthNeeded: bandwidthNeeded,
      freeBandwidth: freeBandwidth,
      stakedBandwidth: stakedBandwidth,
      bandwidthFeeSun: bandwidthFee,
      activationFeeSun: activationFee,
      fetchedAt: fetchedAt ?? DateTime.now(),
    );
  }
}
