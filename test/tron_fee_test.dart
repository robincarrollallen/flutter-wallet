import 'package:flutter_test/flutter_test.dart';
import 'package:on_chain/tron/tron.dart';
import 'package:wallet/domain/tron_fee.dart';

final _owner = TronPrivateKey('${'1' * 63}2').publicKey().toAddress();
final _to = TronPrivateKey('${'2' * 63}3').publicKey().toAddress();

/// 主网默认费率，便于在用例里显式对照。
const _rates = TronFeeRates();

/// [available] 默认落在**免费**额度上——普通账户没质押过，这才是常态。
/// 要测激活场景必须用 [staked]，因为免费额度不能用于创建账户。
TronFeeEstimate _estimate({
  int needed = 268,
  int available = 600,
  int staked = 0,
  bool activated = true,
  TronFeeRates rates = _rates,
}) => TronFeeCalculator.estimate(
  bandwidthNeeded: needed,
  freeBandwidth: BigInt.from(available),
  stakedBandwidth: BigInt.from(staked),
  recipientActivated: activated,
  rates: rates,
);

void main() {
  group('TronFeeCalculator.bandwidthFor', () {
    // 链上按「交易字节数」计带宽，一笔标准 TRX 转账约 268。若这个数字明显跑偏，
    // 说明本地拼的交易与节点构造的不同形，后面所有费用都会跟着错。
    test('标准转账的带宽在 260~275 之间', () {
      final bandwidth = TronFeeCalculator.bandwidthFor(
        owner: _owner,
        to: _to,
        amountSun: BigInt.from(1000000), // 1 TRX
      );
      expect(bandwidth, greaterThanOrEqualTo(260));
      expect(bandwidth, lessThanOrEqualTo(275));
    });

    // 金额只通过 varint 长度影响字节数，所以大额只多几个字节——
    // 这条同时说明「不必为了准确性去问节点」。
    test('金额放大 2000 倍也只多几个字节', () {
      final small = TronFeeCalculator.bandwidthFor(owner: _owner, to: _to, amountSun: BigInt.from(1000000));
      final large = TronFeeCalculator.bandwidthFor(owner: _owner, to: _to, amountSun: BigInt.from(2000000000));
      expect(large - small, inInclusiveRange(0, 4));
    });

    // 协议开销（3 + 64 + 67 = 134 字节）必须计入：漏掉会少算一半，
    // 正好落在「够不够免费额度」的判断边界上。
    test('已计入 protobuf / result / 签名的固定开销', () {
      final bandwidth = TronFeeCalculator.bandwidthFor(owner: _owner, to: _to, amountSun: BigInt.one);
      // raw_data 本身约 131 字节，加上 134 字节固定开销才到 260+。
      expect(bandwidth, greaterThan(200));
    });
  });

  group('TronFeeCalculator.estimate 分档', () {
    test('带宽够且收款方已激活 → 免费', () {
      final fee = _estimate(needed: 268, available: 600);
      expect(fee.feeSun, BigInt.zero);
      expect(fee.isFree, isTrue);
      expect(fee.bandwidthCovered, isTrue);
      expect(fee.activatesRecipient, isFalse);
    });

    test('带宽不足 → 按字节烧 TRX', () {
      final fee = _estimate(needed: 268, available: 100);
      expect(fee.feeSun, BigInt.from(268 * 1000)); // 0.268 TRX
      expect(fee.isFree, isFalse);
      expect(fee.bandwidthCovered, isFalse);
    });

    test('带宽刚好够 → 仍然免费（边界取 >=）', () {
      expect(_estimate(needed: 268, available: 268).feeSun, BigInt.zero);
      expect(_estimate(needed: 268, available: 267).feeSun, isNot(BigInt.zero));
    });

    test('收款方未激活且有足够质押带宽 → 只收 1 TRX 创建费', () {
      final fee = _estimate(staked: 600, activated: false);
      expect(fee.feeSun, BigInt.from(1000000)); // 1 TRX
      expect(fee.activatesRecipient, isTrue);
    });

    // java-tron 的 consumeBandwidthForCreateNewAccount 只走 useAccountNet，
    // 不走 useFreeNet——每日免费额度**不能**用于创建账户。普通账户没质押过，
    // 所以「转给未激活地址」在现实中几乎总是 1.1 TRX 而非 1 TRX。
    test('免费带宽不能用于激活账户，仍要付 0.1 TRX 带宽费', () {
      final fee = _estimate(available: 600, staked: 0, activated: false);
      expect(fee.feeSun, BigInt.from(1100000)); // 1 + 0.1
      expect(fee.bandwidthFeeSun, BigInt.from(100000));
      expect(fee.bandwidthCovered, isFalse);
    });

    // 但对**已激活**的收款方，免费额度照常可用。
    test('普通转账时免费带宽照常可用', () {
      final fee = _estimate(available: 600, staked: 0);
      expect(fee.feeSun, BigInt.zero);
      expect(fee.bandwidthCovered, isTrue);
    });

    // 激活场景下带宽那部分是固定的 0.1 TRX，而**不是**按字节算——
    // 这是 Tron 的特殊规则，容易想当然写成 needed × 1000。
    test('收款方未激活且带宽不足 → 1 TRX + 固定 0.1 TRX', () {
      final fee = _estimate(available: 0, staked: 0, activated: false);
      expect(fee.feeSun, BigInt.from(1100000)); // 1.1 TRX
    });

    // 确认页要单独说「激活费是多少」，不能拿总额去说——带宽也不足时总额里还
    // 混着 0.1 TRX 带宽欠费，说成「1.1 TRX 为其激活」就把这笔说大了。
    test('费用可拆分：激活费与带宽欠费各归各的', () {
      final fee = _estimate(needed: 268, available: 0, staked: 0, activated: false);
      expect(fee.activationFeeSun, BigInt.from(1000000)); // 只有激活那 1 TRX
      expect(fee.bandwidthFeeSun, BigInt.from(100000)); // 激活场景下带宽欠费是固定 0.1
      expect(fee.feeSun, fee.activationFeeSun + fee.bandwidthFeeSun);
    });

    test('已激活账户的带宽欠费按字节算，且激活费为 0', () {
      final fee = _estimate(needed: 268, available: 0);
      expect(fee.activationFeeSun, BigInt.zero);
      expect(fee.bandwidthFeeSun, BigInt.from(268 * 1000));
    });

    test('全免费时两个分量都是 0', () {
      final fee = _estimate(available: 600);
      expect(fee.activationFeeSun, BigInt.zero);
      expect(fee.bandwidthFeeSun, BigInt.zero);
      expect(fee.isFree, isTrue);
    });

    // 三个费率都是链参数，可由委员会提案改动，绝不能写死。
    test('费率取自链参数：sunPerBandwidthByte 翻倍则费用翻倍', () {
      final normal = _estimate(needed: 268, available: 0);
      final doubled = _estimate(needed: 268, available: 0, rates: const TronFeeRates(sunPerBandwidthByte: 2000));
      expect(doubled.feeSun, normal.feeSun * BigInt.two);
    });

    test('费率取自链参数：账户创建费可被改动', () {
      final fee = _estimate(
        staked: 600,
        activated: false,
        rates: const TronFeeRates(createNewAccountFeeSun: 5000000),
      );
      expect(fee.feeSun, BigInt.from(5000000));
    });
  });

  group('TronFeeRates.fromChainParameters', () {
    test('字段缺失时回落到主网默认值', () {
      final rates = TronFeeRates.fromChainParameters(TronChainParameters.fromJson(const {}));
      expect(rates.sunPerBandwidthByte, 1000);
      expect(rates.createAccountFeeSun, 100000);
      expect(rates.createNewAccountFeeSun, 1000000);
    });

    test('节点给了值就用节点的', () {
      final rates = TronFeeRates.fromChainParameters(
        TronChainParameters.fromJson(const {
          'getTransactionFee': 2000,
          'getCreateAccountFee': 200000,
          'getCreateNewAccountFeeInSystemContract': 3000000,
        }),
      );
      expect(rates.sunPerBandwidthByte, 2000);
      expect(rates.createAccountFeeSun, 200000);
      expect(rates.createNewAccountFeeSun, 3000000);
    });
  });
}
