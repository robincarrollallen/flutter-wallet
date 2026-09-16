/// 链元数据：注册表、地址校验、代币与单位换算。
///
/// 单独成库，是因为 UI 层几乎每个页面都要读链名/图标/精度/浏览器模板，
/// 但它们完全不需要 `wallet_core.dart` 里那些能碰到私钥的东西。
/// 分开之后，「哪些页面接触了安全核心」这个问题可以直接靠 import 数出来。
library;

/// 链定义与派生参数的唯一真值源：coin_type、曲线、RPC/浏览器端点。
/// 派生路径改一个字节地址就全变，所以它在包内；但链名、图标、精度到处都要读，所以公开。
export 'src/chains/chain_registry.dart';

/// 收款地址格式校验。转账前的第一道拦截，UI 输入框实时调用。
export 'src/chains/address_validation.dart';

/// 最小单位 ↔ 显示单位换算。金额显示错一个数量级是真实的资损风险，
/// 所以换算只有这一份实现，不允许各页面自己乘除。
export 'src/chains/units.dart';

/// 代币模型与目录。转账要用 contract/decimals 构造 calldata，属于签名输入的一部分。
export 'src/chains/token.dart';
export 'src/chains/token_catalog.dart';
export 'src/chains/bundled_token_catalog.dart';
export 'src/chains/listed_asset.dart';

/// 链与代币的分类枚举。chain_kind 决定走哪条签名路径，token_standard 决定 calldata 形态。
export 'src/model/enums/chain_kind.dart';
export 'src/model/enums/token_standard.dart';
export 'src/model/enums/rpc_method.dart';
export 'src/model/enums/btc_script_type.dart';
