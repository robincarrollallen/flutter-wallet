import '../../blockchain/chain_registry.dart';
import '../../blockchain/units.dart';
import '../../domain/account_balance.dart';
import '../datasource/remote/chain_balance_api.dart';

/// 账户余额的统一入口：把数据源返回的原始最小单位换算成领域对象。
///
/// 不含单价——单价来自 [MarketRepository]，由上层按需合并。
class BalanceRepository {
  const BalanceRepository(this._api);

  final ChainBalanceApi _api;

  /// 查询某条链上某地址的原生币余额。
  Future<AccountBalance> getBalance(Chain chain, String address) async {
    final raw = await _api.fetchNativeBalance(chain, address);
    return AccountBalance(address: address, amount: formatUnits(raw, chain.decimals), symbol: chain.symbol);
  }
}
