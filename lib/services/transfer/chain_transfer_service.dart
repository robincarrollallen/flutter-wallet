import '../../blockchain/chain_registry.dart';
import '../../blockchain/token.dart';
import '../../domain/wallet.dart';
import '../../enums/fee_speed.dart';
import 'transfer_result.dart';

export 'transfer_result.dart';

/// 一次转账的链无关入参。[token] 为 null 表示转原生币。
class TransferRequest {
  const TransferRequest({
    required this.chain,
    required this.from,
    required this.to,
    required this.amount,
    this.token,
    this.deductFeeFromAmount = false,
    this.speed = FeeSpeed.defaultSpeed,
  });

  /// 链类型
  final Chain chain;

  /// 要转的代币；null 表示 [chain] 的原生币
  final Token? token;

  /// 发送方地址，必须与解析出的签名私钥对应的地址一致。
  final String from;

  /// 接收方地址
  final String to;

  /// 用户输入的十进制金额字符串，由实现方按原生币或代币各自的精度换算。
  final String amount;

  /// 是否为「全额转出（MAX）」：仅原生币场景有意义——链上重估费用后允许从转出额中扣费
  final bool deductFeeFromAmount;

  /// 用户选择的网络费档位「缓慢、正常、快速」
  final FeeSpeed speed;

  /// 是否为原生币「token 为 null 表示原生币」
  bool get isNative => token == null;
}

/// 单条链（准确说是单个 [ChainKind]）的转账实现(新增一条链的转账支持 = 新增一个实现类 + 在 `walletServiceProvider` 的 map 加一行)
abstract interface class ChainTransferService {
  /// 本实现负责的链类型，用作分发表的键。
  ChainKind get kind;

  /// 是否支持该链原生币转账。发送页据此决定入口是否放行。
  bool get supportsNative;

  /// 是否支持该链代币转账。一条链可能原生币能转、代币还不能。
  bool get supportsToken;

  /// 执行转账。私钥明文由实现方自行解析，仅在本次调用内使用、用完即弃(不得留存到字段、状态或日志中)
  Future<TransferResult> send(TransferRequest request, Wallet wallet);
}
