import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_core/chains.dart';

/// 端点传输安全。
///
/// 这是「不做证书 pinning」这个决定的配套断言（理由见 SECURITY.md）。
/// 不 pin，就更不能允许任何一条端点悄悄退回明文——那才是真正会出事的情况：
/// pinning 失效顶多是连不上，明文失效是全程可被读改而无人察觉。
void main() {
  test('所有链的 RPC 与浏览器端点都是 https，且不是 IP 字面量', () {
    // IP 字面量单独拦一次：直连 IP 的证书校验形同虚设（没有域名可比对），
    // 而且这种写法通常是某次本地联调忘了改回来。
    final offenders = <String>[];

    void check(String label, String? url) {
      if (url == null || url.isEmpty) return;
      final uri = Uri.tryParse(url);
      if (uri == null) {
        offenders.add('$label：URL 解析失败（$url）');
        return;
      }
      if (uri.scheme != 'https') {
        offenders.add('$label：不是 https（${uri.scheme}）');
      }
      if (RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(uri.host)) {
        offenders.add('$label：直连 IP 字面量（${uri.host}），证书校验失去意义');
      }
    }

    for (final chain in SupportedChains.all) {
      check('${chain.symbol} endpoint', chain.endpoint);
      check('${chain.symbol} explorerTx', chain.explorerTxUrlTemplate);
    }

    expect(offenders, isEmpty, reason: '端点传输不安全：\n${offenders.join('\n')}');
  });

  test('链列表非空', () {
    // 上一条用例遍历 SupportedChains.all。列表一旦为空，它会无条件通过——
    // 这条断言是那个假绿的哨兵。
    expect(SupportedChains.all, isNotEmpty);
  });
}
