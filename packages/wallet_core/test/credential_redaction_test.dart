import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_core/rpc.dart';

/// 凭据不得随错误信息外流。
///
/// 背景：区块浏览器的 key 是以 `?apikey=` 拼在 URL 里的，而 URL 会随异常
/// 流向日志、崩溃上报、甚至 UI 上的错误提示。只要线上出现一次 429 或 5xx，
/// key 就跟着出去了——这比"key 被打进安装包"更隐蔽，因为它只在出错时发生，
/// 平时测不出来。
void main() {
  test('查询串里的 apikey 被替换成 REDACTED，其余部分保留', () {
    final uri = Uri.parse('https://api.etherscan.io/v2/api?chainid=1&module=account&apikey=SECRET123');

    final redacted = redactCredentials(uri).toString();

    expect(redacted, isNot(contains('SECRET123')));
    expect(redacted, contains('apikey=REDACTED'));
    // 路径和其他参数必须留着：脱敏脱到只剩 host，排查问题时没人会看，
    // 最后大家又会绕过它去打印原始 uri。
    expect(redacted, contains('module=account'));
    expect(redacted, contains('/v2/api'));
  });

  test('参数名大小写不同也照样脱敏', () {
    // 第三方接口的参数名不受我们控制，ApiKey / API_KEY 都出现过。
    expect(redactCredentials(Uri.parse('https://x.test/a?ApiKey=S3CRET')).toString(), isNot(contains('S3CRET')));
    expect(redactCredentials(Uri.parse('https://x.test/a?ACCESS_TOKEN=S3CRET')).toString(), isNot(contains('S3CRET')));
  });

  test('没有凭据参数的 URI 原样返回', () {
    final uri = Uri.parse('https://api.test/v1/blocks?height=100');
    expect(redactCredentials(uri), uri);
  });

  test('HttpStatusException 的文本里不含 key', () {
    // 这条才是真正要守的东西：脱敏函数写对了，但异常忘了调用它，一样会泄漏。
    final exception = HttpStatusException(
      429,
      Uri.parse('https://api.etherscan.io/v2/api?apikey=SECRET123'),
      'rate limited',
    );

    expect(exception.toString(), isNot(contains('SECRET123')));
    expect(exception.toString(), contains('429'));
  });
}
