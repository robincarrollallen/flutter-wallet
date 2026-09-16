/// 钱包安全核心的公开面。
///
/// 这个文件是审计的入口：凡是 app 能碰到的安全相关类型与行为，都必须在这里显式列出。
/// `src/` 下的一切默认不公开——`lib/**` 里出现 `package:wallet_core/src/` 由
/// 主工程的 `test/layering_test.dart` 直接判失败。
///
/// 导出遵循一条规则：**每条 export 都要说明「为什么 app 需要它」**。
/// 说不出理由的，就是本该留在 `src/` 里的实现细节。
library;

// 迁移中：内容随 refactor(core) 系列 commit 自底向上填入。
