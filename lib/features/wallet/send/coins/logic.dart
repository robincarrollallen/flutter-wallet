import '../../../../blockchain/address_validation.dart';
import '../../../../blockchain/chain_registry.dart';
import '../../../../blockchain/units.dart';

import '../../../../blockchain/listed_asset.dart';
import '../../../../blockchain/token_catalog.dart';
import '../../../../services/transfer/chain_transfer_service.dart';

/// 发送弹窗的纯逻辑：资产列表构建/过滤与地址、金额校验，不依赖 UI/状态框架。
class SendLogic {
  const SendLogic._();

  /// 顶部 Tab 顺序即首页链顺序。
  static List<Chain> get chains => SupportedChains.all;

  /// 指定链的可发送资产（原生币 + 该链代币）；[chain] 为空表示全部链。
  /// 代币来自 [catalog]。
  ///
  /// 代币只列出 [transfers] 已声明支持代币转账的链。把发不出去的代币列进来，
  /// 用户点进去才被拦下，比看不到更糟。接入新链时在 `walletServiceProvider` 的 map 加一行即可。
  static List<ListedAsset> assetsOf(
    Chain? chain,
    TokenCatalog catalog,
    Map<ChainKind, ChainTransferService> transfers,
  ) => [
    for (final asset in ListedAsset.fromCatalog(catalog, chain: chain))
      if (asset.token == null || (transfers[asset.chain.kind]?.supportsToken ?? false)) asset,
  ];

  /// 该资产当前能否发起转账。发送入口据此拦截，避免用户点进流程才被拦下。
  static bool canTransfer(ListedAsset asset, Map<ChainKind, ChainTransferService> transfers) {
    final service = transfers[asset.chain.kind];
    if (service == null) return false;
    return asset.token == null ? service.supportsNative : service.supportsToken;
  }

  /// 按关键词过滤（匹配符号 / 名称，忽略大小写）。
  static List<ListedAsset> filter(List<ListedAsset> assets, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return assets;
    return assets.where((a) {
      return a.symbol.toLowerCase().contains(q) || a.name.toLowerCase().contains(q);
    }).toList();
  }

  /// 把资产分成「可发送」与「零余额」两组。
  ///
  /// [fiatValueOf] 返回该资产的法币价值：null 表示余额仍在加载
  /// （留在可发送组尾部，数据到达后自动重排）；0（含无地址按 0 处理）
  /// 归入零余额组，保持链默认顺序。可发送组按价值降序排列。
  static (List<ListedAsset> sendable, List<ListedAsset> rest) partition(
    List<ListedAsset> assets,
    double? Function(ListedAsset) fiatValueOf,
  ) {
    final sendable = <ListedAsset>[];
    final rest = <ListedAsset>[];
    for (final a in assets) {
      final value = fiatValueOf(a);
      if (value == null || value > 0) {
        sendable.add(a);
      } else {
        rest.add(a);
      }
    }
    // 稳定排序：价值降序，加载中（null 视为 0）沉底且互相保持原顺序。
    final indexed = sendable.asMap().entries.toList()
      ..sort((x, y) {
        final vx = fiatValueOf(x.value) ?? 0;
        final vy = fiatValueOf(y.value) ?? 0;
        final byValue = vy.compareTo(vx);
        return byValue != 0 ? byValue : x.key.compareTo(y.key);
      });
    return (indexed.map((e) => e.value).toList(), rest);
  }

  /// 校验收款地址是否符合 [chain] 的地址格式。合法返回 null，否则返回错误文案。
  ///
  /// 实现已下沉到 [AddressValidation]，这里只做转发——同一份判断也被
  /// [WalletService.sendTransaction] 用着，两边口径必须是同一个。
  static String? validateAddress(Chain chain, String input) => AddressValidation.validate(chain, input);

  /// 校验发送金额。合法返回 null，否则返回错误文案。
  /// [balance] 为当前可用余额的十进制字符串（来自余额查询）。
  /// 用 [parseUnits] 做精确比较，避免 double 精度误差。
  static String? validateAmount(String input, String balance, {int decimals = 18}) {
    final raw = input.trim();
    if (raw.isEmpty) return '请输入金额';
    try {
      final value = parseUnits(raw, decimals);
      if (value <= BigInt.zero) return '金额无效';
      final availableRaw = balance.trim().isEmpty ? '0' : balance.trim();
      final available = parseUnits(availableRaw, decimals);
      if (value > available) return '余额不足';
      return null;
    } on FormatException {
      return '金额无效';
    }
  }
}
