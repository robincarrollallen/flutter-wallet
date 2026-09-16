/// 构建期注入的本机配置。
///
/// 原先走 flutter_dotenv：`.env` 被声明成 asset，于是那份明文配置文件会原样
/// 打进 IPA / APK，任何人 unzip 就能读到。改成 `--dart-define-from-file` 之后，
/// 值在编译期内联进二进制，安装包里不再有一个可直接打开的配置文件。
///
/// **这不是"把 key 藏起来了"**，必须说清楚：任何随客户端分发的凭据都是公开的，
/// 反编译一样拿得到。改动消除的是"包里躺着一份明文配置文件"这个具体问题，
/// 以及 dotenv 的运行期文件读取和"资产缺失"分支。真正的防线是
/// [ETHERSCAN_API_KEY] 这类 key 本身权限足够低、可随时轮换——
/// 详见 packages/wallet_core/SECURITY.md 的凭据一节。
///
/// 用法：`flutter run --dart-define-from-file=config/local.json`
/// （模板见 config/local.example.json；config/local.json 不进 git）。
class AppConfig {
  const AppConfig._();

  /// Etherscan V2 的 API key，一个 key 覆盖全部 EVM 链。
  ///
  /// 留空是受支持的状态，不是错误：EVM 链只是不查远程历史、退回只显示本机
  /// 发出的交易，其余链完全不受影响。所以这里给空串默认值而不是抛异常——
  /// 没配 key 就起不来的 App，只会逼着每个人把 key 硬编码进源码。
  static const String etherscanApiKey = String.fromEnvironment('ETHERSCAN_API_KEY');
}
