import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 安全边界守卫。
///
/// 安全敏感代码已经抽到 `packages/wallet_core`，目的是让第三方审计只需要看
/// 那一个目录。这个目录能不能守住，靠的不是约定而是下面这几条断言——
/// 它们放在 app 的测试里，因为只有这一侧能同时看到边界的两边。
///
/// 每加一条规则都写清楚「违反了会怎样」，否则后来者只会用 ignore 绕过去。
void main() {
  final packageLib = Directory('packages/wallet_core/lib');
  final packageTest = Directory('packages/wallet_core/test');
  final appLib = Directory('lib');

  test('wallet_core 不认识状态管理、非敏感持久化与本机配置', () {
    // 违反的后果：审计范围被撑大。要确认密钥何时被读写，就得连带看一遍
    // Riverpod 的生命周期；而 shared_preferences 出现在包里，等于给
    // 「密钥被明文落盘」开了一条编译器不再拦截的路。
    const forbidden = {
      'flutter_riverpod': '状态管理必须留在 app：包内只提供纯类，谁持有、持有多久由 app 决定',
      'shared_preferences': '非敏感持久化留在 app：包内没有任何理由碰明文键值存储',
      'flutter_dotenv': '本机配置留在 app：包内不读环境，也就没有"配置里混进密钥"这一说',
    };

    final offenders = <String>[];
    for (final file in _dartFilesIn(packageLib)) {
      for (final directive in _directivesOf(file)) {
        for (final entry in forbidden.entries) {
          if (directive.contains(entry.key)) {
            offenders.add('${file.path}：出现 ${entry.key}——${entry.value}');
          }
        }
        // 反向依赖：包一旦 import 回 app，边界就只剩形式了。
        if (directive.contains('package:wallet/')) {
          offenders.add('${file.path}：import 了 app（package:wallet/），安全包不能反向依赖宿主');
        }
      }
    }

    expect(offenders, isEmpty, reason: '违反安全边界：\n${offenders.join('\n')}');
  });

  test('app 不得穿透 wallet_core 的 src/', () {
    // src/ 下的东西默认不是公开面。绕过 lib/*.dart 直接 import 具体实现，
    // 等于让「app 能碰到哪些安全能力」重新变成一个需要逐文件排查的问题。
    final offenders = [
      for (final file in [..._dartFilesIn(appLib), ..._dartFilesIn(Directory('test'))])
        if (_directivesOf(file).any((d) => d.contains('package:wallet_core/src/')))
          '${file.path}：直接 import 了 src/，应改用 wallet_core.dart / chains.dart / rpc.dart',
    ];

    expect(offenders, isEmpty, reason: '穿透了包的公开面：\n${offenders.join('\n')}');
  });

  test('包内实现不 import 自己的安全门面', () {
    // wallet_core.dart 导出的正是 src/ 里的文件，src/ 再反过来 import 它就是循环；
    // 更实际的问题是，哪天某个类型不再对外公开，包内实现会跟着编译失败。
    // chains.dart / rpc.dart 不导出安全核心，不成环，允许包内使用。
    final offenders = [
      for (final file in _dartFilesIn(packageLib))
        if (file.path.contains('/src/') && _directivesOf(file).any((d) => d.endsWith("wallet_core.dart';")))
          '${file.path}：import 了 wallet_core.dart 门面，应改成指向具体文件的相对 import',
    ];

    expect(offenders, isEmpty, reason: '包内出现门面循环：\n${offenders.join('\n')}');
  });

  test('派生与存储层不依赖签名与钱包管理', () {
    // 保持派生层在最底下。私钥怎么算出来，不应该取决于它之后被拿去做什么；
    // 反过来依赖会让「只审派生」这件事变得不可能。
    final offenders = <String>[];
    for (final dir in ['crypto', 'storage']) {
      for (final file in _dartFilesIn(Directory('${packageLib.path}/src/$dir'))) {
        final directives = _directivesOf(file);
        for (final upper in ['../transaction/', '../wallet/']) {
          if (directives.any((d) => d.contains("'$upper"))) {
            offenders.add('${file.path}：import 了 $upper，派生/存储层必须留在依赖链底部');
          }
        }
      }
    }

    expect(offenders, isEmpty, reason: '违反包内分层：\n${offenders.join('\n')}');
  });

  test('能碰 SharedPreferences 的文件是一份固定的短名单', () {
    // 明文键值存储是「密钥意外落盘」最可能的出口。守住它的前提是这份名单足够短、
    // 且改动必须是显式的：新增一个文件直接读写 prefs，这条断言就会拦下来，
    // 迫使改动者说明为什么它需要绕过 PersistentNotifier。
    //
    // 这和运行时的 no_plaintext_secret_in_prefs_test 是两层防线：
    // 那一层证明「跑完全流程后 prefs 里没有密钥」，这一层限制「谁有资格写进去」。
    const allowed = {
      'lib/main.dart', // 唯一 await getInstance() 的地方，拿到后立即注入 provider
      'lib/providers/core/prefs_provider.dart', // 实例的全局入口
      'lib/providers/core/persistent_notifier.dart', // 所有落盘都经由它 + PrefsKey
    };

    final offenders = [
      for (final file in _dartFilesIn(appLib))
        if (_directivesOf(file).any((d) => d.contains('shared_preferences')) && !allowed.contains(file.path))
          '${file.path}：直接依赖 shared_preferences，落盘应经由 PersistentNotifier + PrefsKey',
    ];

    expect(offenders, isEmpty, reason: '绕过了统一的落盘入口：\n${offenders.join('\n')}');
  });

  test('services 层不认识状态管理', () {
    // `lib/providers/core/service_provider.dart` 的文档注释一直声称这条由本文件守着，
    // 但在补上这条断言之前它并不存在——约定只是被自觉遵守着。而一旦某个 service
    // 自己去 watch provider，「谁跟谁组装」就从装配处散回各个 service，
    // 单测也得先搭一个 ProviderContainer 才跑得起来。
    final services = _dartFilesIn(Directory('${appLib.path}/services'));
    // 目录改名或挪走时，上面那个循环会扫出空集合，断言随之变成一句空话——
    // 仍然全绿，却不再守住任何东西。先钉死「确实扫到了文件」。
    expect(services, isNotEmpty, reason: 'lib/services/ 扫不到文件，这条守卫已经失效');

    final offenders = [
      for (final file in services)
        if (_directivesOf(file).any((directive) => directive.contains('flutter_riverpod')))
          '${file.path}：service 不得认识 Riverpod，依赖一律走构造注入',
    ];

    expect(offenders, isEmpty, reason: '违反分层：\n${offenders.join('\n')}');
  });

  test('包内测试确实存在', () {
    // CI 要分别在两个目录跑 flutter test。少写一条命令，包内测试会静默不执行，
    // 而"全绿"看起来毫无异常——这条断言是那个失效模式的唯一哨兵。
    expect(_dartFilesIn(packageTest).where((f) => f.path.endsWith('_test.dart')), isNotEmpty);
  });
}

/// 文件里的 import / export 指令行。
///
/// 只看指令而不是全文，是因为这些规则的文档注释里必然要提到被禁的包名
/// （"不得出现 flutter_riverpod"这句话本身就含有 flutter_riverpod），
/// 全文匹配会让守卫把自己的解释当成违规。
List<String> _directivesOf(File file) => [
  for (final line in file.readAsLinesSync())
    if (line.startsWith('import ') || line.startsWith('export ')) line.trim(),
];

List<File> _dartFilesIn(Directory dir) => [
  if (dir.existsSync())
    for (final entity in dir.listSync(recursive: true))
      if (entity is File && entity.path.endsWith('.dart')) entity,
];
