/// 钱包安全核心的公开面。
///
/// 这个文件是审计的入口：凡是 app 能碰到的安全相关类型与行为，都必须在这里显式列出。
/// `src/` 下的一切默认不公开——`lib/**` 里出现 `package:wallet_core/src/` 由
/// 主工程的 `test/layering_test.dart` 直接判失败。
///
/// 导出遵循一条规则：**每条 export 都要说明「为什么 app 需要它」**。
/// 说不出理由的，就是本该留在 `src/` 里的实现细节。
library;

/// 钱包实体。它会被序列化进 SharedPreferences（明文），
/// 所以 `toJson` 的字段集合是安全断言的对象，由守卫测试钉死白名单。
export 'src/model/wallet.dart';

/// 钱包 id 生成。id 参与 secure storage 的 key 拼接（`wallet.<id>.mnemonic`），
/// 生成方式必须在包内统一，否则换一种实现就可能撞 key 或读不出旧密钥。
export 'src/model/wallet_id.dart';

/// 钱包来源。不只是展示字段——它决定私钥是「现场从助记词派生」还是「从存储读」。
export 'src/model/enums/wallet_source.dart';

/// 备份方式。决定助记词除了本机 Keychain 之外还去过哪里，是威胁模型的输入。
export 'src/model/enums/backup_method.dart';

/// 导入私钥的格式类别（EVM hex / Solana base58 / Sui bech32 …）。
/// 导入页要据此提示用户，且解码必须按类别精确匹配、不能靠猜。
export 'src/model/enums/private_key_kind.dart';

/// 明文展示的是助记词还是私钥。决定倒计时与遮罩策略。
export 'src/model/enums/secret_type.dart';

/// 交易状态。转账结果页与历史列表共用同一套状态，避免两处判定不一致。
export 'src/model/enums/transaction_status.dart';

/// 手续费档位与报价模型。费用是用户在确认页唯一能核对的东西，
/// 构造过程必须和签名在同一个包里，不能让 UI 自己算一份。
export 'src/model/enums/fee_speed.dart';
export 'src/model/fee/fee_quote.dart';
export 'src/model/fee/evm_fee.dart';
export 'src/model/fee/solana_fee.dart';
export 'src/model/fee/tron_fee.dart';

/// 转账请求。UI 唯一能向签名层递交的入参形态——收敛成一个类型，
/// 是为了让「有多少条路径能触发签名」可以被一眼数清。
export 'src/model/dto/send_tx_request.dart';

/// 助记词的生成、校验与多链地址派生。创建/导入/备份流程的入口。
export 'src/crypto/mnemonic_service.dart';

/// 导入私钥的格式探测与解码。解码按探测出的类别精确进行，不做格式猜测——
/// 猜错格式会把一把 Solana 私钥当 EVM 解，派生出一个用户永远拿不回资产的地址。
export 'src/crypto/private_key_service.dart';

/// 私钥的统一出口。助记词钱包现场派生、导入钱包读存储，两条路都在这里收口，
/// 并负责用完 wipeKey 清零。任何绕过它拿私钥的代码都是审计要揪的对象。
export 'src/crypto/private_key_resolver.dart';

/// 安全存储。provider 声明留在 app 侧（lib/providers/core/storage_provider.dart），
/// 包内只有纯类——否则 flutter_riverpod 会被拖进安全包的依赖里。
export 'src/storage/secure_wallet_storage.dart';
export 'src/storage/security_password_storage.dart';

/// 安全码的 PBKDF2 派生、常量时间比对与旧明文记录升级。
export 'src/security/security_password_service.dart';

/// 敏感文本复制到剪贴板后的自动清除。剪贴板是跨 app 共享的，
/// 「密钥在那里待多久」是一个可被审计的确定数值，所以只有这一个入口。
export 'src/security/secure_clipboard.dart';

/// 明文屏显的时长上限。和剪贴板同理：把"暴露多久"变成一个常量而非各页面自行决定。
export 'src/security/secret_reveal.dart';
