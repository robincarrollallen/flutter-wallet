/// 包内部的模型汇总。
///
/// 存在的理由很具体：`src/` 里的文件不能 import `lib/wallet_core.dart`——
/// 那个门面导出的正是这些文件本身，形成循环，而且一旦某个类型停止对外公开，
/// 包内实现就会跟着编译失败。所以门面归门面（给 app 用），这里这份归包内用。
///
/// 只汇总模型：枚举、实体、费用、DTO。不含 crypto / storage / tx，
/// 否则又会绕回同一个循环。
library;

export 'wallet.dart';
export 'wallet_id.dart';
export 'enums/wallet_source.dart';
export 'enums/backup_method.dart';
export 'enums/private_key_kind.dart';
export 'enums/secret_type.dart';
export 'enums/transaction_status.dart';
export 'enums/fee_speed.dart';
export 'fee/fee_quote.dart';
export 'fee/evm_fee.dart';
export 'fee/solana_fee.dart';
export 'fee/tron_fee.dart';
export 'dto/send_tx_request.dart';
