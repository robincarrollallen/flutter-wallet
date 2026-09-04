import '../../blockchain/chain_registry.dart';
import '../../blockchain/token.dart';
import '../../domain/wallet.dart';
import '../../enums/evm_send_status.dart';
import '../../enums/fee_speed.dart';

export '../../enums/evm_send_status.dart';

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

  final Chain chain;

  /// 要转的代币；null 表示 [chain] 的原生币。
  final Token? token;

  /// 发送方地址，必须与解析出的签名私钥对应的地址一致。
  final String from;
  final String to;

  /// 用户输入的十进制金额字符串，由实现方按原生币或代币各自的精度换算。
  final String amount;

  /// 是否为「全额转出（MAX）」：仅原生币场景有意义——链上重估费用后允许从
  /// 转出额中扣费。代币转账的手续费付的是原生币，扣不出来，实现方应忽略本标志。
  final bool deductFeeFromAmount;

  /// 用户选择的网络费档位。
  final FeeSpeed speed;

  bool get isNative => token == null;
}

/// 转账结果：(交易哈希, 实际发送金额, 上链状态)。
///
/// 实际金额仅在原生币 MAX 扣费场景才可能小于入参金额。
typedef TransferResult = ({String hash, String sentAmount, EvmSendStatus status});

/// 单条链（准确说是单个 [ChainKind]）的转账实现。
///
/// 新增一条链的转账支持 = 新增一个实现类 + 在 `walletServiceProvider` 里注册一行，
/// `WalletService` 无需改动。
abstract interface class ChainTransferService {
  /// 本实现负责的链类型，用作分发表的键。
  ChainKind get kind;

  /// 执行转账。私钥明文由实现方自行解析，仅在本次调用内使用、用完即弃，
  /// 不得留存到字段、状态或日志中。
  Future<TransferResult> send(TransferRequest request, Wallet wallet);
}
