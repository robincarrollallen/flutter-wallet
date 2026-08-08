import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../persistent_notifier.dart';

/// 一条最近使用过的收款地址记录。
class RecentAddress {
  const RecentAddress({required this.chainId, required this.address});

  final String chainId;
  final String address;

  Map<String, dynamic> toJson() => {'chainId': chainId, 'address': address};

  static RecentAddress? fromJson(Map<String, dynamic> json) {
    final chainId = json['chainId'];
    final address = json['address'];
    if (chainId is! String || address is! String) return null;
    return RecentAddress(chainId: chainId, address: address);
  }
}

/// 发送流程「最近使用」地址列表：最新在前，去重，持久化到 SharedPreferences。
class RecentAddressesNotifier extends Notifier<List<RecentAddress>> with PersistentNotifier<List<RecentAddress>> {
  /// 每条链下最多保留的条数上限（整体上限，防止无限增长）。
  static const _maxEntries = 20;

  @override
  List<RecentAddress> build() => restore(const []);

  @override
  String get persistKey => 'send.recentAddresses';

  @override
  Map<String, dynamic> toJson(List<RecentAddress> state) => {'entries': state.map((e) => e.toJson()).toList()};

  @override
  List<RecentAddress> fromJson(Map<String, dynamic> json, List<RecentAddress> fallback) {
    final raw = json['entries'];
    if (raw is! List) return fallback;
    return raw
        .whereType<Map<String, dynamic>>()
        .map(RecentAddress.fromJson)
        .whereType<RecentAddress>()
        .toList(growable: false);
  }

  /// 记录一次发送成功的收款地址：同链同地址去重并置顶。
  void record(String chainId, String address) {
    final rest = state.where((e) => !(e.chainId == chainId && e.address == address)).toList();
    state = [RecentAddress(chainId: chainId, address: address), ...rest.take(_maxEntries - 1)];
  }
}

final recentAddressesProvider = NotifierProvider<RecentAddressesNotifier, List<RecentAddress>>(
  RecentAddressesNotifier.new,
);

/// 指定链下的最近使用地址（保持最新在前）。
final recentAddressesOfChainProvider = Provider.family<List<String>, String>((ref, chainId) {
  return ref
      .watch(recentAddressesProvider)
      .where((e) => e.chainId == chainId)
      .map((e) => e.address)
      .toList(growable: false);
});
