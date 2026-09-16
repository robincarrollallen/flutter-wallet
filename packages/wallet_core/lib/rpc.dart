/// 远程调用的传输层：共享 HttpClient、JSON-RPC 与 REST 客户端。
///
/// 签名服务要用它广播交易，所以必须在包内；但 app 的余额/行情/历史也在用同一套，
/// 因此单独开一个二级库，而不是把它塞进 `wallet_core.dart`——
/// 否则每个查余额的地方都要 import 安全核心，审计边界就被稀释了。
library;

// 迁移中：内容随 refactor(core) 系列 commit 自底向上填入。
