/// 全应用路由路径常量。
///
/// 所有跳转都必须引用这里的常量，禁止在业务代码里写裸路径字符串——
/// 路径一旦散落各处，就退回到了迁移前「目的地只存在于调用点」的状态。
///
/// 命名约定：`xxx` 是可直接跳转的完整路径；`xxxSegment` 是注册子路由时用的
/// 相对片段（go_router 的 `GoRoute.path` 对子路由要求相对路径）。
abstract final class AppRoute {
  // —— 一级 —— //
  static const root = '/';
  static const onboarding = '/onboarding';

  // —— 首页入口 —— //
  static const search = '/search';
  static const scan = '/scan';
  static const manageTokens = '/manage-tokens';
  static const addressManagement = '/address-management';
  static const walletPanel = '/wallet-panel';

  // —— 设置面板及其子页 —— //
  static const settings = '/settings';
  static const settingsAppearanceSegment = 'appearance';
  static const settingsAppearance = '$settings/$settingsAppearanceSegment';
  static const settingsCurrencySegment = 'currency';
  static const settingsCurrency = '$settings/$settingsCurrencySegment';
  static const settingsThemeColorsSegment = 'theme-colors';
  static const settingsThemeColors = '$settings/$settingsThemeColorsSegment';

  // —— 发送流程：逐级嵌套，pop 天然回到上一步 —— //
  static const send = '/send';
  static const sendRecipientSegment = 'recipient';
  static const sendRecipient = '$send/$sendRecipientSegment';
  static const sendAmountSegment = 'amount';
  static const sendAmount = '$sendRecipient/$sendAmountSegment';
  static const sendConfirmSegment = 'confirm';
  static const sendConfirm = '$sendAmount/$sendConfirmSegment';
  static const sendResultSegment = 'result';
  static const sendResult = '$sendConfirm/$sendResultSegment';

  // —— 创建 / 导入钱包 —— //
  static const createWallet = '/create-wallet';
  static const importWallet = '/import-wallet';
  static const importMnemonicSegment = 'mnemonic';
  static const importMnemonic = '$importWallet/$importMnemonicSegment';

  static const placeholder = '/placeholder';
}
