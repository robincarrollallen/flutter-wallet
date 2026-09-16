# Solana 向量生成器

`test/signing_vectors_test.dart` 里 Solana 那组的期望值由这个脚本生成。

期望值**必须**来自与被测代码独立的实现。用 `on_chain` 自己算一遍再贴进测试，
测的只是「它等于它自己」——那种断言看起来很权威，实际上一个 bug 也抓不到。

## 重跑

```bash
cd packages/wallet_core/tool/solana_vectors
npm install @solana/web3.js@1 @solana/spl-token bs58
node gen.js
```

生成时用的版本：`@solana/web3.js 1.99.0` + `@solana/spl-token 0.4.15`（2026-09-16）。
全部输入（seed、收款方 seed、blockhash 字节、金额、CU 参数）都写死在脚本里，不查链、不联网取值。

## 为什么 message 和签名没有做逐字节比对

跑完会发现 `messageHex` / `signatureHex` 和 `on_chain` 的输出不一致。**这不是 bug**：

- `@solana/web3.js` 把同权限级的账户按 base58 字典序排序
  （SystemProgram 是全零，排在 ComputeBudget 前面）；
- `on_chain` 保留账户首次出现的顺序。

两份 message 都自洽，也都会被验证节点接受——Solana 的消息格式只要求账户按
「签名者/可写」分组，组内不要求排序。这正是 Solana 做不到 EVM 那种跨实现字节级
向量的原因：RLP 的字段顺序由规范定死，Solana 的账户顺序是编码器的自由选择。

所以测试里跨实现钉死的是**没有自由度**的部分——公钥派生和 ATA 推导，
这两项与 spl-token / web3.js 完全一致；message 那条退一步验证语义等价。

`node_modules/` 不进 git：这是一次性的核对工具，不是构建依赖。
