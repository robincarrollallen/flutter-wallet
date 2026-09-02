import 'package:blockchain_utils/blockchain_utils.dart';
import '../../../../blockchain/chain_registry.dart';
import '../../../../blockchain/units.dart';

import '../../../../blockchain/listed_asset.dart';

/// 发送弹窗的纯逻辑：资产列表构建/过滤与地址、金额校验，不依赖 UI/状态框架。
class SendLogic {
  const SendLogic._();

  /// 顶部 Tab 顺序即首页链顺序。
  static List<Chain> get chains => SupportedChains.all;

  /// 指定链的可发送资产；[chain] 为空表示全部链。
  ///
  /// 目前只造原生币（`token` 留空）——**代币余额已接入，但代币转账尚未接入**
  /// （见 EvmTransactionService，只会构造原生币转账）。把代币列进来用户能选、
  /// 却发不出去，比看不到更糟。等转账接入后这里改成从 TokenCatalog 展开即可，
  /// 列表行与后续页面读余额的路径已经是资产维度的，无需再动。
  static List<ListedAsset> assetsOf(Chain? chain) {
    final source = chain == null ? SupportedChains.all : [chain];
    return [for (final c in source) ListedAsset(chain: c)];
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
  static String? validateAddress(Chain chain, String input) {
    final addr = input.trim();
    if (addr.isEmpty) return '请输入收款地址';
    final valid = switch (chain.kind) {
      ChainKind.evm => _isValidEvm(addr),
      ChainKind.solana => _decodes(() => SolAddrDecoder().decodeAddr(addr)),
      ChainKind.tron => _decodes(() => TrxAddrDecoder().decodeAddr(addr)),
      ChainKind.bitcoin => _isValidBitcoinTestnet(addr),
      // Sui / Aptos：32 字节十六进制，允许省略前导零。
      ChainKind.sui || ChainKind.aptos => RegExp(r'^0x[0-9a-fA-F]{1,64}$').hasMatch(addr),
    };
    return valid ? null : '地址格式不正确，请检查是否为 ${chain.name} 地址';
  }

  /// EVM：0x + 40 位十六进制；混合大小写时额外校验 EIP-55 checksum。
  static bool _isValidEvm(String addr) {
    if (!RegExp(r'^0x[0-9a-fA-F]{40}$').hasMatch(addr)) return false;
    final hex = addr.substring(2);
    final mixedCase = hex.toLowerCase() != hex && hex.toUpperCase() != hex;
    if (!mixedCase) return true;
    return _decodes(() => EthAddrDecoder().decodeAddr(addr));
  }

  /// Bitcoin（项目为测试网）：收款方地址类型不受本钱包自身脚本类型限制，三种都放行——
  /// tb1q…（SegWit v0 / P2WPKH）、tb1p…（Taproot v1 / P2TR）、以及 legacy（m/n/2 开头）。
  static bool _isValidBitcoinTestnet(String addr) {
    if (addr.toLowerCase().startsWith('tb1')) {
      return _decodes(() => P2WPKHAddrDecoder().decodeAddr(addr, hrp: 'tb')) ||
          _decodes(() => P2TRAddrDecoder().decodeAddr(addr, hrp: 'tb'));
    }
    return RegExp(r'^[mn2][1-9A-HJ-NP-Za-km-z]{25,39}$').hasMatch(addr);
  }

  /// 解码不抛异常即视为合法。
  static bool _decodes(void Function() decode) {
    try {
      decode();
      return true;
    } catch (_) {
      return false;
    }
  }

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
