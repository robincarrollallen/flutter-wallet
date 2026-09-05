import '../blockchain/listed_asset.dart';
import '../domain/wallet.dart';
import '../enums/evm_send_status.dart';

/// 各带参页面的路由参数。
///
/// 本应用不做深链接，参数走 go_router 的 `extra` 直接传对象，不序列化进路径；
/// 用具名类而非裸 record，是为了跳转点自解释且能被类型检查。
/// 每个参数类承载「进入该页所需的全部输入」，页面自身不再从上一页反查。

/// 地址管理页：展示某个钱包在各链上的地址。
final class AddressManagementArgs {
  const AddressManagementArgs({required this.wallet});

  final Wallet wallet;
}

/// 占位页（尚未实现的入口，如硬件钱包）。
final class PlaceholderArgs {
  const PlaceholderArgs({required this.title});

  final String title;
}

/// 发送流程第二步：填写收款地址。
///
/// 图标 URL 由资产列表行解析后透传，避免子页重复查询行情。
final class SendRecipientArgs {
  const SendRecipientArgs({required this.asset, this.tokenLogoUrl, this.chainLogoUrl});

  final ListedAsset asset;
  final String? tokenLogoUrl;
  final String? chainLogoUrl;
}

/// 发送流程第三步：输入金额。
final class SendAmountArgs {
  const SendAmountArgs({required this.asset, required this.toAddress, this.tokenLogoUrl, this.chainLogoUrl});

  final ListedAsset asset;
  final String toAddress;
  final String? tokenLogoUrl;
  final String? chainLogoUrl;
}

/// 发送流程第四步：确认并提交。
final class SendConfirmArgs {
  const SendConfirmArgs({
    required this.asset,
    required this.toAddress,
    required this.amount,
    this.isMaxAmount = false,
    this.tokenLogoUrl,
    this.chainLogoUrl,
  });

  final ListedAsset asset;
  final String toAddress;
  final String amount;

  /// 金额是否来自「最大」按钮：仅该场景允许从转出额中扣除网络费用。
  final bool isMaxAmount;
  final String? tokenLogoUrl;
  final String? chainLogoUrl;
}

/// 发送流程终点：上链结果。
final class SendResultArgs {
  const SendResultArgs({
    required this.asset,
    required this.toAddress,
    required this.amount,
    required this.txHash,
    this.status = EvmSendStatus.pending,
  });

  final ListedAsset asset;
  final String toAddress;
  final String amount;
  final String txHash;
  final EvmSendStatus status;
}
