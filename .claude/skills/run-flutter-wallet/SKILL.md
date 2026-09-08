---
name: run-flutter-wallet
description: Build, launch, drive, and screenshot this Flutter crypto wallet app on the iOS Simulator. Use when asked to run the app, start it, take a screenshot, tap/swipe through a flow, verify UI changes in the real app, or assert on the SharedPreferences market/icon cache. Covers pull-to-refresh, currency switching, and the send-ETH flow.
---

# 跑 Flutter 钱包 App

macOS 主机 + iOS 模拟器。手势通过 CGEvent 注入（`driver.sh`），断言通过直接读模拟器的
SharedPreferences plist。路径均相对仓库根目录。

**为什么不用 macOS 桌面版**：`macos/Runner/DebugProfile.entitlements` 只有
`app-sandbox` / `network.server`，**缺 `com.apple.security.network.client`**，
沙盒会静默掐断所有出站请求 —— 行情、余额、RPC 全部拿不到。除非你先加这条权限，
否则 macOS target 无法用于任何联网验证。

## 前置

- Xcode（`swiftc` 用于编译 CGEvent 注入工具，首次调用 `tap` 时自动编译）
- **辅助功能权限**：系统设置 → 隐私与安全性 → 辅助功能 → 勾选你的终端。
  没有它 `osascript` 读不到窗口几何，报 `-1719 不允许辅助访问`。
- 屏幕录制权限**不需要** —— 截图走 `xcrun simctl io`，不走 `screencapture`。

无需 `flutter pub get` 以外的额外安装。

## 启动

```bash
D=.claude/skills/run-flutter-wallet/driver.sh

$D boot     # 启动 iPhone 17 Pro 模拟器
$D run      # flutter run --debug，后台跑，日志 /tmp/wallet-run/run.log（首次 ~45s）
```

App 已装过时，回到干净首页用 `$D restart`（terminate + launch，约 8s），
**比点返回键可靠得多** —— 见 Gotchas。

## 驱动（agent 路径）

坐标一律是**设备像素**，iPhone 17 Pro = 1206×2622（即 `xcrun simctl io screenshot` 的原图尺寸）。

```bash
$D tap 368 2417                  # 点击
$D drag 603 900 603 1900         # 下拉刷新
$D type "0x56Ad2AA6Ad55f66131f6d5b24A7B53f5D6DA3229"   # 先 tap 输入框再 type
$D shot home                     # 截图 -> /tmp/wallet-run/home.png + home_view.png(700px 可读版)
$D crop home 540 200             # 裁 device y 540..740，用来精确定位控件坐标
$D cache                         # 打印计价币种 + 各缓存写入时刻
$D changed a b                   # 比对两张截图（已裁掉状态栏）
```

### 已标定的坐标（首页）

| 控件 | 设备坐标 |
|---|---|
| 设置齿轮 | `84 262` |
| 底部 tab：首页 / 市场 | `161 2417` / `368 2417` |
| 发送 / 接收 | `232 1029` / `450 1029` |
| 下拉刷新 | `drag 603 900 603 1900` |
| 设置面板「计价货币」行 | `600 779` |
| 货币页 USD / CNY | `600 655` / `600 1517` |

发送流程：`tap 232 1029`（发送）→ `tap 603 634`（首行资产）→ `tap 599 487` + `type 地址`
→ `tap 603 2395`（下一步）→ `tap 599 536` + `type 0.001` → `tap 599 1053`（下一步）→ 确认页。
发送弹窗的搜索框在 `603 378`。

**确认页的「确认发送」没有固定坐标** —— 它在内容下方，位置随卡片高度变化：
有「收款方未激活」提示时约 `603 1536`，没有时约 `603 1437`。点空了不会有任何反馈，
和「焦点没拿到」的表现一模一样。**每次都用 `$D crop <截图名> 1350 250` 现场量**，
别照抄上一次的值。

**发送列表只显示有余额的资产**（`view.dart` 把 `SendLogic.partition` 的第二组直接丢弃）。
所以新加的代币在领到测试币之前**不会出现在发送列表里**，这是设计而非 bug——
要确认代币是否已进目录，去**首页**列表看（它零余额也显示）。

资产按法币价值降序排，**首行是哪个币会随余额变化**，别把 `603 634` 当成固定的某个币。

**不要点「确认发送」**（确认页 `599 1053`）—— 会真实广播交易。

## 缓存断言

重构 `data/repository` 相关代码后，`$D cache` 是最硬的证据来源：

```
计价币种: USD
  chain_icons_cache      08:32:15  条目=10
  markets_cache_CNY      16:11:33  条目=10
  markets_cache_EUR      10:12:04  条目=10
  markets_cache_USD      16:42:28  条目=10
```

可直接验证的性质：

- **按币种分键不串**：切到 CNY 后只有 `markets_cache_CNY` 的时刻变，USD/EUR 不动。
- **TTL 短路**：`chain_icons_cache` TTL 7 天，命中期内时刻不变即代表没发请求。
- **下拉刷新确实重取**：`drag` 后 `markets_cache_<币种>` 时刻必须前进。
- **失败不污染缓存**：注入故障后（见下）时刻与条目数应保持不变。

### 故障注入：验证「失败回退旧缓存」

这条路径最容易在重构中丢失，且只能靠注入验证：

```bash
cp lib/data/datasource/remote/coingecko_api.dart /tmp/cg.bak
perl -pi -e "s{static const _base = 'https://api.coingecko.com/api/v3';}\
{static const _base = 'https://127.0.0.1:9/blocked';}" \
  lib/data/datasource/remote/coingecko_api.dart
# 重新 flutter run，然后：
#   run.log 应出现 ⚠️ fetchMarkets failed: SocketException: Connection refused
#   界面应仍显示旧价格（而非 $0.00）
#   $D cache 的时刻与条目数应不变
cp /tmp/cg.bak lib/data/datasource/remote/coingecko_api.dart      # 务必还原
```

## Gotchas

这些都是实际踩过的，没一个能靠猜。

- **改了代码但界面还是旧的**，这是最费时间的一个坑，因为它伪装成业务 bug。
  `flutter run` 不会自己退出，反复调用会叠加多个进程，新构建装不上去——日志里
  照样写着 `Xcode build done`，你会以为构建成功了。`$D run` 现在会先 `pkill`
  再跑，并在出现 `Lost connection to device` 时自动重启已装的新二进制。
  **怀疑构建没生效时，别猜，去核对安装时间**：
  ```bash
  for d in ~/Library/Developer/CoreSimulator/Devices/<UDID>/data/Containers/Bundle/Application/*/; do
    a=$(ls -d "$d"*.app 2>/dev/null|head -1); [ -n "$a" ] &&
    [ "$(plutil -extract CFBundleIdentifier raw "$a/Info.plist" 2>/dev/null)" = "com.crypto.wallet.flutter.wallet" ] &&
    stat -f "%Sm  $a" "$a"; done
  ```
  注意目录里还躺着别的 App，按 bundle id 过滤，别 `head -1` 抓错。
- **`osascript` 的 `click at {x,y}` 必然失败**，报 `error -25204`。必须用 CGEvent
  （`click.swift`）。
- **前台焦点是最大的坑，而且是双向的**：Simulator 不在前台时点击静默落到别的 App
  （比如 VS Code），完全没反应；但 `activate` 之后**必须等足 ~1.2 秒**再点，
  延时 0.3s 会把紧接着的第一次点击吞掉 —— 两种情况的表现一模一样，都是
  「坐标算对了但界面不动」。`driver.sh` 的 `_front()` 已处理：只在非前台时 activate，
  且固定等 1.2s。手写点击时务必照做。
- **标题栏是 58px，不是 28px。** 坐标换算 `s = min(WW/1206, (WH-58)/2622)`，原点
  `oy = WY + 58`。用 28 会让屏幕中部偏 ~17px：大控件（底部 tab）还能命中，
  小控件（发送按钮、列表行）全部落空。这个值是靠扫描命中反推的，换机型/换 Simulator
  版本需重新标定：`$D crop` 定位控件中心 → 用一次 y 方向扫描找真实命中点。
- **截图哈希比对会被状态栏时钟骗到。** 每分钟跳一次，两张完全相同的界面也会 hash 不等。
  必须裁掉顶部再比 —— 用 `$D changed`，它裁的是设备 y>320。
- **顶部小控件（返回箭头 ~`82 266`）命中率很低**，多点几次也不灵。要回首页别硬点，
  直接 `$D restart`。
- **`screencapture -R` 会静默失败**（不报错、不产文件），因为缺屏幕录制权限。
  截图一律用 `xcrun simctl io booted screenshot`。
- **`plutil -extract flutter.xxx`** 会把 key 里的点当路径分隔符而取不到值。
  要读 SharedPreferences 得 `plutil -convert json` 出来整个解析（`driver.sh cache` 已处理）。
- **SharedPreferences 的 key 全部带 `flutter.` 前缀**，Dart 侧写的 `markets_cache_USD`
  在 plist 里是 `flutter.markets_cache_USD`。

## 排错

| 症状 | 原因 / 处理 |
|---|---|
| `osascript` 报 `-1719 不允许辅助访问` | 终端没有辅助功能权限，见「前置」 |
| 坐标算出来了但点击无反应 | 三选一：Simulator 不在前台；activate 后没等够 1.2s；标题栏偏移用错（应为 58）|
| Simulator 窗口被挪动过 | 无需处理，`driver.sh` 每次调用都重读窗口几何 |
| `$D cache` 报 `No such file or directory` | App 尚未启动过，或 bundle id 变了；确认 `com.crypto.wallet.flutter.wallet` |
| 界面价格全是 `$0.00` / 图标是首字母 | CoinGecko 限流（429）或断网，且无可回退的旧缓存 |
| 余额一直 0 | 用的是各链**测试网**，地址本来就没币；行情仍应正常 |

## 测试

```bash
flutter analyze     # 基线 5 个 warning/info，0 error
flutter test        # 84 个纯函数测试，不覆盖网络与缓存路径 —— 故本 skill 的手动验证不可省
```
