import '../../blockchain/chain_registry.dart';
import '../../blockchain/token.dart';
import '../../blockchain/token_catalog.dart';
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

  /// 查询某条链上某地址持有的多个代币余额，键为 [TokenCatalog.identityKey]。
  ///
  /// 换算用 **[Token.decimals]** 而非 `chain.decimals`：同一条链上代币精度各不相同
  /// （USDC 是 6，多数 ERC-20 是 18），用链的精度会把金额差出十几个数量级。
  ///
  /// 未接入的代币标准由调用方用 [ChainBalanceApi.supportsTokenBalance] 先行过滤。
  Future<Map<String, AccountBalance>> getTokenBalances(Chain chain, List<Token> tokens, String address) async {
    final raw = await _api.fetchTokenBalances(chain, tokens, address);
    return {
      for (final token in tokens)
        TokenCatalog.identityKey(token): AccountBalance(
          address: address,
          amount: formatUnits(raw[token.identifier] ?? BigInt.zero, token.decimals),
          symbol: token.symbol,
        ),
    };
  }
}
