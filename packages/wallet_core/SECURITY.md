# wallet_core 安全说明

给第三方审计的入口文档。这个包是这个钱包里全部安全敏感代码的所在地：
助记词与私钥的生成、派生、存储，交易的构造、签名与广播，安全码的校验。

**审计范围 = 这一个目录。** 这不是一句承诺，而是由几条测试强制的：
`test/layering_test.dart`（在 app 侧，因为只有那里能同时看到边界两边）断言
包不认识状态管理与明文持久化、不反向依赖宿主、app 不得穿透 `src/`。
边界被破坏时 CI 会红，而不是等到下一次人工复查。

---

## 1. 信任边界

| 在边界内（本包） | 在边界外（app，`lib/`） |
|---|---|
| 助记词生成 / 校验 / 派生 | UI、路由、国际化、主题 |
| 私钥派生、导入解码、用后清零 | Riverpod 状态管理与 provider 装配 |
| Keychain / Keystore 读写 | SharedPreferences（仅非敏感数据） |
| 安全码 PBKDF2 与常量时间比对 | 行情、图标缓存、交易历史查询 |
| 交易构造、签名、广播 | 区块浏览器 API key 的持有与注入 |
| 链注册表与派生参数、地址校验 | 截屏/遮罩等表现层防旁路（见 §5） |

**核心不变量**：私钥与助记词明文只存在于 Keychain/Keystore 和一次调用的栈上。
它们不进入 Riverpod 状态、不进入 SharedPreferences、不进入日志。
助记词钱包不额外存私钥，每次转账现场派生（在后台 isolate 里），用完 `wipeKey` 清零。

---

## 2. 从哪里开始读

按依赖顺序，自底向上：

1. `src/chains/chain_registry.dart` — 派生路径与端点的真值源。改一个 coin_type，地址全变。
2. `src/crypto/mnemonic_service.dart` — BIP-39 生成/校验、seed、多链地址派生。
3. `src/crypto/private_key_service.dart` — 导入私钥的格式探测与解码。**按探测出的类别精确解码，不猜格式**——猜错会把一把 Solana 私钥当 EVM 解，派生出用户永远拿不回资产的地址。
4. `src/crypto/private_key_resolver.dart` — 私钥的唯一出口。助记词钱包现场派生、导入钱包读存储，两条路在这里收口，并负责清零。**任何绕过它拿私钥的代码都值得追问。**
5. `src/storage/secure_wallet_storage.dart` — Keychain/Keystore 读写，写后回读校验，孤儿密钥对账。
6. `src/wallet/wallet_commit_service.dart` — 「先写密钥、后写列表」的两阶段提交与 pending 标记。中途崩溃留下的残留由它收拾。
7. `src/transaction/` — 三条链的交易构造与签名，以及 `transfer/` 下的编排（取钥匙 → 签 → `finally` 清零）。

---

## 3. 已知的验证强度

诚实标注，不同部分强度不同：

| 项 | 强度 | 位置 |
|---|---|---|
| EVM 交易签名 | **强**：EIP-155 规范原文向量，逐字节比对 | `test/signing_vectors_test.dart` |
| ERC-20 calldata | **强**：选择器 + 32 字节对齐参数写死 | 同上 |
| chainId 进签名（防跨链重放） | 强 | 同上 |
| Tron「签 rawData 而非 txID」 | 强：双哈希陷阱有专门用例 | `test/tron_transfer_test.dart` |
| Solana 公钥派生 / ATA 推导 | **强**：与 `@solana/web3.js` + `@solana/spl-token` 交叉验证，逐字节一致 | `test/signing_vectors_test.dart` |
| Solana 交易 message | **中**：账户集合、指令组成、金额的语义等价 + devnet 节点实测接受（字节级不可比，见下） | 同上 |
| Solana ed25519 签名 | **中**：验签绑定本笔 message + 篡改必败 + 确定性 | 同上 |
| 密钥派生（BIP-39/32/44） | 中：多链一致性与回导往返 | `test/derivation_test.dart` |
| 密钥不入 SharedPreferences | 强：端到端跑完真实流程后全量搜哨兵，含元测试证明守卫可证伪 | `test/../no_plaintext_secret_in_prefs_test.dart`（app 侧） |
| 端点强制 https | 强 | `test/endpoint_transport_test.dart` |
| 凭据不随异常外流 | 强 | `test/credential_redaction_test.dart` |

**Solana 为什么没有逐字节向量**（不是遗漏，是做不到）：
`@solana/web3.js` 把同权限级的账户按 base58 字典序排序，`on_chain` 保留首次出现顺序。
两份 message 都自洽、都会被验证节点接受——Solana 的消息格式只要求账户按
「签名者/可写」分组，组内不要求排序。EVM 能做逐字节比对是因为 RLP 的字段顺序由规范定死，
Solana 的账户顺序是编码器的自由选择。
所以跨实现钉死的是**没有自由度**的部分（公钥派生、ATA 推导），message 退一步验证语义等价。

「on_chain 的排序合法」**不是推断**：`tool/solana_vectors/verify_account_order.dart`
拿真实 devnet blockhash 构造交易并 `simulateTransaction`（`sigVerify: true`），
2026-09-16 实测节点把三条指令全部执行完（两条 ComputeBudget 成功、System transfer
被正确派发），说明账户清单与 `programIdIndex` 解析全对。排序若不合法，会停在
反序列化 / sanitize，根本进不到执行。生成与核对脚本见 `tool/solana_vectors/`。

**已知缺口**：
- Tron 缺交易级的已知向量（固定 rawData → 固定签名字节）。双哈希陷阱已有专门用例，
  但完整的 rawData → signature 向量还没有。
- 没有 `SecretGuard` / `secret_reveal` 的 widget 测试。
- 没有「wipeKey 之后内存确已归零」的断言（Dart 层难以可靠验证）。

---

## 4. 凭据

本 App 只持有一个外部凭据：**Etherscan V2 的 API key**。

- **它是公开凭据。** 任何随客户端分发的 key 都可以被反编译取出，无论用 `.env`、
  `--dart-define` 还是字符串混淆。我们不假装它是秘密。
- **权限范围**：只读的区块浏览器查询，免费额度，**不承载任何用户数据访问权**。
  泄漏的后果上限是额度被人蹭掉，轮换成本接近零。
- **它不在本包内。** 唯一的消费者是 app 侧的交易历史查询服务。这样安全包可以
  保持「不读任何配置」——`layering_test` 直接禁止包内出现配置读取。
- **已修的真实泄漏路径**：请求 URL 带 `?apikey=`，而 URL 原本会随 `HttpStatusException`
  进入日志、崩溃上报甚至 UI 错误提示。线上一次 429 就会把 key 带出去。
  现在所有错误信息里的 URI 都经 `redactCredentials` 脱敏。
  **这一条的实际价值远大于换配置方式。**
- **明确不做**：字符串混淆、拆分拼接、塞进原生层。不改变可提取性，只增加复杂度。

---

## 5. 已评估并拒绝

### 证书 pinning

**结论：现阶段不做。**

当前所有 RPC 都是公共 testnet / 社区端点（Solana devnet、Tron Nile、公共 EVM RPC）。
这些服务方随时更换 CDN、负载均衡乃至 CA，且不会通知我们。pinning 的运维失败模式是
**「App 突然全链不可用」**——而它要挡的威胁在这里很轻：这些端点上不传任何秘密
（私钥永不出设备，广播出去的是已签名交易），MITM 能做的最坏事是返回假余额或假 nonce，
后果由链上重放保护和用户在确认页看到的金额兜住。

拿全局不可用的风险，去挡一个已被 TLS 覆盖的威胁，不划算。

替代做法（都已落地）：
1. **强制 https**：遍历所有链的端点断言 scheme 与非 IP 字面量（`endpoint_transport_test.dart`）。
2. **平台层禁明文 + 不信任用户 CA**：Android `network_security_config.xml`
   设 `cleartextTrafficPermitted="false"` 且 `trust-anchors` 只含 system；
   iOS 无 ATS 例外。**这比 pinning 实用**——它挡的是「用户被诱导装了一张代理 CA」，
   这是移动端真实发生的攻击面，而 pinning 挡的那部分 TLS 本身已经覆盖。
   （副作用：release 包无法被 Charles / mitmproxy 抓包，调试走 debug-overrides。）
3. **条件触发**：若将来自建代理持有 API key，届时对自家域名做 pinning——
   那时我们控制轮换节奏，可以做 backup pin 和过期告警。

### 把包拆成纯 Dart 核 + Flutter 外壳

不做。唯一的插件依赖 `flutter_secure_storage` 正是安全边界的核心
（Keychain accessibility 选项、key 命名、孤儿对账），把它推到包外等于把最该审的东西
移出审计范围。依赖 `flutter` SDK 本身不增加攻击面。

---

## 6. 边界外但相关的控制项

这些不在本包内，但审计时应一并看：

- `lib/widgets/secret_guard.dart` — 敏感页的截屏保护与切后台遮罩。
  依赖 Flutter widget 树，属表现层。**已知不足**：不覆盖普通截屏，
  无 Android `FLAG_SECURE`，无 iOS `isCaptured` 监听。
- `lib/providers/core/persistent_notifier.dart` + `lib/enums/prefs_key.dart` —
  所有非敏感落盘的唯一通道。`layering_test` 限制了能碰 `SharedPreferences` 的文件
  是一份三个文件的固定名单。
- `lib/features/scan/scan_view.dart` — 目前是占位页，无相机插件。
  **引入扫码时需要重新评估**（二维码是助记词的常见输入路径）。

---

## 7. 运行验证

```bash
flutter test                                   # app 侧
cd packages/wallet_core && flutter test        # 包内，必须单独跑
cd packages/wallet_core && flutter analyze --fatal-infos --fatal-warnings
```

包内测试必须单独跑：少一条命令它们会静默不执行，而「全绿」看不出任何异常。
`layering_test` 里有一条断言包内测试文件非空，就是这个失效模式的哨兵。
