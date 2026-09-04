import '../../blockchain/chain_registry.dart';
import '../../blockchain/token.dart';
import '../../blockchain/token_catalog.dart';
import '../../blockchain/units.dart';
import '../../domain/account_balance.dart';
import '../../domain/btc_utxo.dart';
import '../datasource/remote/bitcoin_utxo_api.dart';
import '../datasource/remote/chain_balance_api.dart';

/// 账户余额的统一入口：把数据源返回的原始最小单位换算成领域对象。
///
/// 不含单价——单价来自 [MarketRepository]，由上层按需合并。
class BalanceRepository {
  const BalanceRepository(this._api, [this._utxoApi = const BitcoinUtxoApi()]);

  final ChainBalanceApi _api;
  final BitcoinUtxoApi _utxoApi;

  /// 查询某条链上某地址的原生币余额。**比特币不走这里**，见 [getBitcoinBalance]。
  Future<AccountBalance> getBalance(Chain chain, String address) async {
    final raw = await _api.fetchNativeBalance(chain, address);
    return AccountBalance(address: address, amount: formatUnits(raw, chain.decimals), symbol: chain.symbol);
  }

  /// 比特币余额：从 UTXO 集合投影出总额与三口径明细。
  ///
  /// 单独一条路径，是因为 BTC 的余额本质是**一个集合**而不是一个数字——手续费取决
  /// 于输入个数，可花与否取决于每个输出的确认状态与来源。只留一个标量，发送时还得
  /// 重查一遍，而那时集合可能已经变了。
  ///
  /// [addresses] 现在恒为单元素（只派生 m/84'/1'/0'/0/0），签名按集合设计，
  /// 将来加找零链不用改这一层。[ownTxids] 是本机广播过的交易 id，用来认出自己的找零。
  ///
  /// [AccountBalance.amount] 取 [UtxoSet.total]，与改造前的 chain_stats+mempool_stats
  /// 口径等价——总资产、资产行主数字、发送页 MAX 全部不受影响。
  Future<AccountBalance> getBitcoinBalance(Chain chain, List<String> addresses, Set<String> ownTxids) async {
    final set = UtxoSet(await _utxoApi.fetchUtxos(chain, addresses), ownTxids: ownTxids);
    String readable(BigInt satoshi) => formatUnits(satoshi, chain.decimals);
    return AccountBalance(
      address: addresses.first,
      amount: readable(set.total),
      symbol: chain.symbol,
      utxo: UtxoBreakdown(
        confirmed: readable(set.confirmed),
        pending: readable(set.pending),
        spendable: readable(set.spendable),
      ),
    );
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
