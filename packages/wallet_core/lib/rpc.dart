/// 远程调用的传输层：共享 HttpClient、JSON-RPC 与 REST 客户端。
///
/// 签名服务要用它广播交易，所以必须在包内；但 app 的余额/行情/历史也在用同一套，
/// 因此单独开一个二级库，而不是把它塞进 `wallet_core.dart`——
/// 否则每个查余额的地方都要 import 安全核心，审计边界就被稀释了。
library;

/// 进程级共享的 HttpClient、统一超时、结构化的非 2xx 异常。
/// TLS 行为（是否校验证书、是否允许明文）全部落在这里，是网络侧的单一审计点。
export 'src/rpc/http_config.dart';

/// JSON-RPC 客户端。广播已签名交易、读 nonce/blockhash 都走它，
/// 请求 id 的匹配校验在这里——响应错配会让交易按错误的 nonce 构造。
export 'src/rpc/json_rpc.dart';

/// REST 客户端。区块浏览器与行情接口用，查询串里可能带 API key。
export 'src/rpc/rest_client.dart';

/// 链上余额查询。
///
/// 原计划留在 app，实际不行：Tron 的交易服务在签名前要读原生币与 TRC-20 余额做预检，
/// 留在 app 就形成 package → app 的反向依赖。它本身只依赖 chains + rpc，
/// 而「签名前的余额预检」本来就属于签名路径的一部分，迁进来比拆开更诚实。
export 'src/rpc/chain_balance_api.dart';

/// Solana / Tron / Aptos 的专用 RPC 封装。这三条链的广播和确认轮询不走通用
/// JSON-RPC 形态（Aptos 干脆是 REST），与各自的交易服务强绑定，
/// 所以和签名放在同一个包里。
export 'src/rpc/aptos_service.dart';
export 'src/rpc/solana_service.dart';
export 'src/rpc/tron_service.dart';
