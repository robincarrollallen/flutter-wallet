# flutter-wallet

多链加密钱包。App 在 `lib/`，安全敏感代码全部抽在 `packages/wallet_core/`
——抽出来的目的是让审计只需要看那一个目录，所以这条边界由测试守着，不是靠自觉。

当前接的 11 条链**全是测试网**（EVM ×6、bitcoin-testnet、solana-devnet、tron-nile、
sui-testnet、aptos-testnet），见 `packages/wallet_core/lib/src/chains/chain_registry.dart`。

---

## 命名

**表达语义角色，不只表达类型。** 名字要说清「它在这段逻辑里扮演什么」。

- 禁止占位名：`s`、`e`、`x`、`data`、`info`、`item`、`temp`、`result`、`val`。
  例外：`i`/`j` 循环下标、`e` 作 catch 的异常、生命周期只有一行的 lambda 参数。
- **禁止缩写**，类名 / 变量 / 参数 / 文件名 / 目录名一律用完整单词：
  `TransactionRecord` 不写 `TxRecord`，`transactionHash` 不写 `txHash`，
  `lib/src/transaction/` 不写 `lib/src/tx/`，`address` 不写 `addr`。
  例外是领域内本身就是专有名词的缩写：`EVM`、`RPC`、`UTXO`、`ERC20`、`DTO`、`id`、`url`。
  存量缩写不豁免——改到哪儿顺手改到哪儿，成片的单独开一次重命名收掉。
- 同一作用域出现两个同类事物时，名字必须把它们区分开（哪个是缓存快照、哪个是当前值）。
- 布尔用 `is`/`has`/`should` 开头；返回集合的用复数；异步结果不要叫 `res`。

**Why:** 这个项目里同一概念常有多个变体同时在场（内置链配置 vs 远程下发、
缓存快照 vs 当前值、链原生币 vs 代币），占位名会让读者分不清在比对哪两个东西。

改目录/文件名时记得同步 export、相对 import、**测试里的路径字符串字面量**和文档
——最后一条最容易漏，漏了断言会静默失效（仍然通过，但不再守住任何东西）。

## 文件组织

新页面 / widget 每个目录用**无前缀三件套**：

- `view.dart` —— UI 与动画编排
- `logic.dart` —— 纯函数，无 UI/状态依赖，可单测
- `state.dart` —— 不可变数据模型（`copyWith`）+ 该页私有的 Riverpod 状态

页面私有的 Riverpod 状态必须 `autoDispose`，保证页面关闭即清除。

`pages/` 下的子页目录名不带 `_page` 后缀（父级已表明是页面）：用 `wallet_detail/`
而非 `wallet_detail_page/`。

参考 `lib/features/wallet/wallet_management/`。注意 home、import_wallet、create_wallet
等旧 screen 仍是带前缀的 `*_view.dart` 风格——**新代码用无前缀，不主动重排旧的**。

## 持久化

**任何需要落盘的状态都走 `PersistentNotifier`**（`lib/providers/core/persistent_notifier.dart`），
存储键必须来自 `lib/enums/prefs_key.dart` 的 `PrefsKey` 枚举。

```dart
class XxxNotifier extends Notifier<T> with PersistentNotifier<T>
// build() => restore(默认值)，实现 persistKey / toJson / fromJson
```

state 一变自动落盘，不要也不该手动 `setString`。

- **禁止**业务代码直接 `SharedPreferences.getString/setString`，禁止另造第二套缓存层。
  `test/layering_test.dart` 有一条「能碰 SharedPreferences 的文件是一份固定短名单」的断言拦这个。
- 新增存储键一律加进 `PrefsKey`；`value` 是真正落盘的字符串，**定了不能改**（改 = 丢老用户数据）。
- `toJson` 只放要持久化的字段，`fromJson` 全量还原不做判定。脏数据要能整条丢弃而不拖垮
  整个恢复（见 `TransactionRecord.fromJson` 返回 null 的写法）。
- 唯一例外：助记词 / 私钥走 `flutter_secure_storage`
  （`packages/wallet_core/lib/src/storage/secure_wallet_storage.dart`），绝不进 SharedPreferences。

照着 `lib/providers/modules/transaction/recent_address_provider.dart` 抄。

## 安全边界

详见 `packages/wallet_core/SECURITY.md`。几条硬规则由 `test/layering_test.dart` 守：

- `wallet_core` 不得 import `flutter_riverpod` / `shared_preferences` / `flutter_dotenv`，
  也不得反向 import `package:wallet/`。
- app 不得穿透 `package:wallet_core/src/`，只能走 `wallet_core.dart` / `chains.dart` / `rpc.dart`。
- 包内 `crypto/`、`storage/` 不得依赖 `transaction/`、`wallet/`（派生层留在依赖链底部）。

其它约定：

- 私钥明文用完即弃，签名后在 `finally` 里 `wipeKey`，绝不进 Riverpod 状态、日志或持久化。
- 重 KDF（BIP39 种子推导、安全码 PBKDF2）一律走 `compute()` 进后台 isolate。
- 错误信息里的 URI 必须经 `redactCredentials` 脱敏——URL 会进日志和崩溃上报，
  带 `?apikey=` 的一次 429 就把凭据带出去了。

## 验证

```bash
flutter analyze                          # 应为 0 issues
flutter test                             # app 侧
cd packages/wallet_core && flutter test  # 包侧，两边都要跑
```

`flutter analyze` 与两处 `flutter test` **都应全绿**，把「本来就有几个 warning」当基线是不行的
——那会让新引入的问题混在存量里溜过去。

纯函数测试不覆盖网络与缓存路径，那部分靠 `.claude/skills/run-flutter-wallet/`
的手动验证（**跑模拟器前先问用户**，不要当成改完代码的默认动作）。
