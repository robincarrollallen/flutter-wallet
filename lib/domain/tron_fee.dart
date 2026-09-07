import 'package:on_chain/tron/tron.dart';

/// Tron 转账的费用估算结果。
///
/// 刻意不复用 [EvmFeeQuote] / [EvmGasBasis]：EVM 是「单价 × 用量」且有三档，
/// Tron 是「够带宽就免费、不够按字节烧 TRX」且没有档位（加价也不会更快）。
/// 两套模型硬套在一起只会让双方都变形。
class TronFeeEstimate {
  const TronFeeEstimate({
    required this.bandwidthNeeded,
    required this.bandwidthAvailable,
    required this.feeSun,
    required this.activatesRecipient,
    required this.fetchedAt,
  });

  /// 本次交易要消耗的带宽点数（= 上链后交易的字节数）。
  final int bandwidthNeeded;

  /// 发送方当前可用带宽（每日免费额度 + 质押所得，均已扣除已用部分）。
  final BigInt bandwidthAvailable;

  /// 实际要烧掉的 TRX（单位 sun）。带宽够且收款方已激活时为 0。
  final BigInt feeSun;

  /// 收款方账户尚未上链，本次转账会顺带激活它——[feeSun] 里含固定的账户创建费。
  final bool activatesRecipient;

  final DateTime fetchedAt;

  /// 这一笔是否不花钱。
  bool get isFree => feeSun == BigInt.zero;

  /// 带宽是否够用（够用则不烧 TRX 抵带宽，但仍可能有账户创建费）。
  bool get bandwidthCovered => bandwidthAvailable >= BigInt.from(bandwidthNeeded);
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
  });

  /// `getTransactionFee`：带宽不足时每字节烧多少 sun（主网 1000 = 0.001 TRX/字节）。
  final int sunPerBandwidthByte;

  /// `getCreateAccountFee`：激活账户时若带宽也不足，额外收的固定费（0.1 TRX）。
  final int createAccountFeeSun;

  /// `getCreateNewAccountFeeInSystemContract`：激活一个新账户的固定费（1 TRX）。
  final int createNewAccountFeeSun;

  /// 从 SDK 的链参数模型构造；字段缺失时回落到默认值。
  factory TronFeeRates.fromChainParameters(TronChainParameters params) => TronFeeRates(
    sunPerBandwidthByte: params.getTransactionFee ?? const TronFeeRates().sunPerBandwidthByte,
    createAccountFeeSun: params.getCreateAccountFee ?? const TronFeeRates().createAccountFeeSun,
    createNewAccountFeeSun:
        params.getCreateNewAccountFeeInSystemContract ?? const TronFeeRates().createNewAccountFeeSun,
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

  /// 由「需要多少带宽 / 有多少带宽 / 收款方是否已激活 / 链上费率」算出实付。
  ///
  /// 两条互不重叠的收费规则：
  /// - **带宽不足**：按字节烧 TRX（`需要的带宽 × sunPerBandwidthByte`）；
  /// - **收款方未激活**：固定收 `createNewAccountFeeSun`（1 TRX），若此时带宽也不足，
  ///   则带宽那部分**改按固定的 `createAccountFeeSun`（0.1 TRX）收**，而不是按字节。
  static TronFeeEstimate estimate({
    required int bandwidthNeeded,
    required BigInt bandwidthAvailable,
    required bool recipientActivated,
    TronFeeRates rates = const TronFeeRates(),
    DateTime? fetchedAt,
  }) {
    final covered = bandwidthAvailable >= BigInt.from(bandwidthNeeded);

    final BigInt feeSun;
    if (recipientActivated) {
      feeSun = covered ? BigInt.zero : BigInt.from(bandwidthNeeded) * BigInt.from(rates.sunPerBandwidthByte);
    } else {
      feeSun =
          BigInt.from(rates.createNewAccountFeeSun) +
          (covered ? BigInt.zero : BigInt.from(rates.createAccountFeeSun));
    }

    return TronFeeEstimate(
      bandwidthNeeded: bandwidthNeeded,
      bandwidthAvailable: bandwidthAvailable,
      feeSun: feeSun,
      activatesRecipient: !recipientActivated,
      fetchedAt: fetchedAt ?? DateTime.now(),
    );
  }
}
