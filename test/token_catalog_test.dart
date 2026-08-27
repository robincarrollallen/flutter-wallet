import 'package:flutter_test/flutter_test.dart';
import 'package:wallet/blockchain/chain_registry.dart';
import 'package:wallet/blockchain/bundled_token_catalog.dart';
import 'package:wallet/blockchain/token.dart';
import 'package:wallet/blockchain/token_catalog.dart';

const _chains = [SupportedChains.ethereumSepolia, SupportedChains.bscTestnet];

final _usdcEth = Token(
  chainId: SupportedChains.ethereumSepolia.id,
  symbol: 'USDC',
  name: 'USD Coin',
  standard: TokenStandard.erc20,
  identifier: '0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238',
  coinGeckoId: 'usd-coin',
  decimals: 6,
);

/// 与 [_usdcEth] 同一合约，地址大小写不同，字段故意改过以证明覆盖。
final _usdcEthCustom = Token(
  chainId: SupportedChains.ethereumSepolia.id,
  symbol: 'USDC',
  name: 'My USDC',
  standard: TokenStandard.erc20,
  identifier: '0x1c7d4b196cb0c7b01d743fbc6116a902379c7238',
  coinGeckoId: 'usd-coin',
  decimals: 8,
);

final _fooBsc = Token(
  chainId: SupportedChains.bscTestnet.id,
  symbol: 'FOO',
  name: 'Foo Token',
  standard: TokenStandard.erc20,
  identifier: '0x1111111111111111111111111111111111111111',
  coinGeckoId: 'foo',
  decimals: 18,
);

const _unknownChain = Token(
  chainId: 'not-a-supported-chain',
  symbol: 'GHOST',
  name: 'Ghost',
  standard: TokenStandard.erc20,
  identifier: '0x2222222222222222222222222222222222222222',
  coinGeckoId: 'ghost',
  decimals: 18,
);

void main() {
  group('TokenCatalog.merge', () {
    test('远程 ∪ 自定义：同键覆盖且留在原位，新币追加到该链末尾', () {
      final catalog = TokenCatalog.merge(chains: _chains, remote: [_usdcEth], custom: [_usdcEthCustom, _fooBsc]);

      expect(catalog.tokensOf(SupportedChains.ethereumSepolia.id).single.name, 'My USDC');
      expect(catalog.tokensOf(SupportedChains.ethereumSepolia.id).single.decimals, 8);
      expect(catalog.tokensOf(SupportedChains.bscTestnet.id).single.symbol, 'FOO');

      // 链顺序不变；ETH 上 USDC 仍紧跟原生币，FOO 出现在 BNB 之后。
      expect(catalog.allAssets.map((e) => e.$2?.symbol ?? e.$1.symbol).toList(), ['ETH', 'USDC', 'BNB', 'FOO']);
    });

    test('ERC-20 合约地址忽略大小写视为同一代币', () {
      final catalog = TokenCatalog.merge(chains: _chains, remote: [_usdcEth], custom: [_usdcEthCustom]);
      expect(catalog.tokensOf(SupportedChains.ethereumSepolia.id), hasLength(1));
    });

    test('未知 chainId 被丢弃', () {
      final catalog = TokenCatalog.merge(chains: _chains, remote: [_usdcEth, _unknownChain]);
      expect(catalog.tokens.map((e) => e.$2.symbol), ['USDC']);
    });

    test('远程与自定义都为空时只剩原生币', () {
      final catalog = TokenCatalog.merge(chains: _chains, remote: const []);
      expect(catalog.allAssets.map((e) => e.$2).every((t) => t == null), isTrue);
      expect(catalog.allAssets, hasLength(2));
    });

    test('按链展开：指定链只含该链原生币 + 代币', () {
      final catalog = TokenCatalog.merge(chains: _chains, remote: [_usdcEth, _fooBsc]);
      final eth = catalog.assetsOf(SupportedChains.ethereumSepolia);
      expect(eth, hasLength(2));
      expect(eth.first.$2, isNull);
      expect(eth.last.$2?.symbol, 'USDC');
    });

    test('coinGeckoIds 含原生币与代币，去重；空 coinGeckoId 不进清单', () {
      final catalog = TokenCatalog.merge(
        chains: _chains,
        remote: [_usdcEth],
        custom: [
          Token(
            chainId: SupportedChains.bscTestnet.id,
            symbol: 'FOO',
            name: 'Foo',
            standard: TokenStandard.erc20,
            identifier: '0x1111111111111111111111111111111111111111',
            coinGeckoId: '',
            decimals: 18,
          ),
        ],
      );
      expect(catalog.coinGeckoIds, ['ethereum', 'binancecoin', 'usd-coin']);
    });

    test('identityKey 含 chainId，同合约不同链不是同一键', () {
      expect(TokenCatalog.identityKey(_usdcEth), isNot(TokenCatalog.identityKey(_fooBsc)));
      expect(TokenCatalog.identityKey(_usdcEth), TokenCatalog.identityKey(_usdcEthCustom));
    });
  });

  group('Token JSON', () {
    test('toJson / fromJson 往返', () {
      expect(Token.fromJson(_usdcEth.toJson()).identifier, _usdcEth.identifier);
      expect(Token.fromJson(_usdcEth.toJson()).standard, TokenStandard.erc20);
    });

    test('listFromJson 接受数组或 {tokens: []}，跳过脏条目', () {
      expect(Token.listFromJson([_usdcEth.toJson()]).single.symbol, 'USDC');
      expect(
        Token.listFromJson({
          'tokens': [_usdcEth.toJson()],
        }).single.symbol,
        'USDC',
      );
      expect(
        Token.listFromJson([
          {'symbol': 'NOPE'},
          _usdcEth.toJson(),
        ]).single.symbol,
        'USDC',
      );
      expect(Token.listFromJson('nope'), isEmpty);
    });
  });

  group('BundledTokenCatalog 作为打包回退', () {
    test('与原先 Chain.tokens 展开结果一致：11 原生币 + 7 USDC', () {
      final catalog = TokenCatalog.merge(chains: SupportedChains.all, remote: BundledTokenCatalog.all);
      expect(catalog.allAssets, hasLength(SupportedChains.all.length + BundledTokenCatalog.all.length));
      expect(catalog.tokens, hasLength(7));
      expect(catalog.tokens.every((e) => e.$2.symbol == 'USDC'), isTrue);

      final eth = catalog.assetsOf(SupportedChains.ethereumSepolia);
      expect(eth.first.$1.symbol, 'ETH');
      expect(eth.first.$2, isNull);
      expect(eth.last.$2?.symbol, 'USDC');
      expect(eth.last.$2?.identifier, '0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238');
    });
  });
}
