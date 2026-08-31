import '../../../blockchain/listed_asset.dart';
import '../receive/logic.dart';

/// 管理代币页的纯逻辑，不依赖 UI / 状态框架。
class ManageTokensLogic {
  const ManageTokensLogic._();

  /// 按关键词过滤。口径与接收页保持一致（符号 / 名称 / 链名，忽略大小写），
  /// 所以直接复用 [ReceiveLogic.filter]，不另写一套匹配规则。
  static List<ListedAsset> filter(List<ListedAsset> assets, String query) => ReceiveLogic.filter(assets, query);
}
