import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wallet_core/wallet_core.dart';

import 'package:wallet/providers/core/prefs_provider.dart';
import 'package:wallet/providers/core/service_provider.dart';
import 'package:wallet/providers/core/storage_provider.dart';

import 'support/fake_secure_storage.dart';

/// 运行时守卫：跑完真实的创建 / 导入 / 安全码流程后，SharedPreferences 里
/// 不得出现任何密钥材料。
///
/// 为什么不能只靠静态扫描：静态规则（见 layering_test）限制的是「谁有资格写」，
/// 绕过它只需要多一层间接调用。这里换个问法——不管中间经过多少层，
/// 跑完之后把整份 prefs 倒出来，里面不许出现哨兵值。
///
/// 这类守卫最常见的失效模式是**假绿**：流程根本没跑到，prefs 是空的，
/// 搜不到哨兵当然通过。所以下面每个用例都先断言「密钥确实进了安全存储、
/// prefs 确实被写过」，再断言「prefs 里搜不到密钥」。缺了前半段，后半段毫无意义。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 真实的 BIP-39 助记词：派生流程会校验词表与校验和，随便编的词串走不完全程。
  const mnemonic = 'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
  const securityPassword = 'S3ntinel-P@ssw0rd';

  test('创建助记词钱包后，prefs 里没有助记词的任何一个词', () async {
    final (container, platform) = await _setUp();

    final wallet = Wallet(
      id: newWalletId(),
      name: '哨兵钱包',
      source: WalletSource.mnemonic,
      addresses: const {'ethereum': '0x0000000000000000000000000000000000000001'},
    );
    await container.read(walletCommitServiceProvider).commit(wallet: wallet, mnemonic: mnemonic);

    // 前置断言：流程真的跑完了。没有这两条，下面的"搜不到"可能只是因为什么都没发生。
    expect(platform.store.values, contains(mnemonic), reason: '助记词没进安全存储，说明流程没走完，后面的断言不成立');
    expect(_prefsDump(container), isNotEmpty, reason: 'prefs 一个键都没写过，说明流程没走完');

    _expectNoSecrets(container, secrets: [mnemonic, ...mnemonic.split(' ')]);
  });

  test('导入私钥钱包后，prefs 里没有私钥（hex / 去 0x / base64 三种形态都搜）', () async {
    final (container, platform) = await _setUp();

    // 固定值而非随机生成：失败时的报错要能直接指出是哪一串泄漏了。
    const privateKey = '0x4646464646464646464646464646464646464646464646464646464646464646';

    final wallet = Wallet(
      id: newWalletId(),
      name: '导入哨兵',
      source: WalletSource.importedPrivateKey,
      addresses: const {'ethereum': '0x0000000000000000000000000000000000000002'},
    );
    await container.read(walletCommitServiceProvider).commit(wallet: wallet, privateKey: privateKey);

    expect(platform.store.values, contains(privateKey), reason: '私钥没进安全存储，说明流程没走完');
    expect(_prefsDump(container), isNotEmpty);

    // 三种形态一起搜：只搜原串的话，"我做了个编码所以算脱敏了"这种改法能溜过去。
    final stripped = privateKey.substring(2);
    _expectNoSecrets(
      container,
      secrets: [privateKey, stripped, base64Encode(utf8.encode(privateKey)), base64Encode(utf8.encode(stripped))],
    );
  });

  test('设置并校验安全码后，prefs 里没有安全码明文', () async {
    final (container, platform) = await _setUp();

    final service = container.read(securityPasswordServiceProvider);
    await service.setPassword(securityPassword);
    expect(await service.verify(securityPassword), isTrue, reason: '校验都没过，说明安全码流程没走完');

    expect(platform.store, isNotEmpty, reason: '安全码记录没进安全存储');
    // 顺带守住另一件事：安全存储里存的也不能是明文，必须是 PBKDF2 记录。
    expect(platform.store.values.any((v) => v.contains(securityPassword)), isFalse, reason: '安全码以明文存进了 Keychain');

    _expectNoSecrets(container, secrets: [securityPassword, base64Encode(utf8.encode(securityPassword))]);
  });

  test('守卫本身抓得住泄漏', () async {
    // 上面三条全绿，也可能是因为这个守卫根本没在起作用。这条用例故意把哨兵
    // 写进 prefs，断言守卫会失败——没有它，"全绿"说明不了任何事。
    final (container, _) = await _setUp();
    await container.read(sharedPrefsProvider).setString('leaky.key', '备份用：$mnemonic');

    expect(
      () => _expectNoSecrets(container, secrets: [mnemonic]),
      throwsA(isA<TestFailure>()),
      reason: '哨兵已经明文躺在 prefs 里，守卫却没报——它是失效的',
    );
  });

  test('Wallet.toJson 的字段集合是一份精确白名单', () {
    // 这是结构性的那一层：上面三条测的是"当前流程没泄漏"，这条测的是
    // "以后谁想往落盘结构里加字段，必须先改这个测试并在 review 里解释为什么"。
    final json = Wallet(
      id: 'w1',
      name: 'n',
      source: WalletSource.mnemonic,
      addresses: const {'ethereum': '0x1'},
    ).toJson();

    expect(json.keys.toSet(), {'id', 'name', 'source', 'addresses', 'createdAt', 'icon', 'backupMethods'});
  });
}

/// prefs 的全部内容，压成一个可搜索的字符串。
///
/// 刻意不做逐 key 白名单：那样新增的 key 默认是安全的，而这里新增的 key
/// 默认就在搜索范围内——守卫应该对没见过的东西更保守，而不是更宽松。
String _prefsDump(ProviderContainer container) {
  final prefs = container.read(sharedPrefsProvider);
  return jsonEncode({for (final key in prefs.getKeys()) key: prefs.get(key).toString()});
}

void _expectNoSecrets(ProviderContainer container, {required List<String> secrets}) {
  final dump = _prefsDump(container).toLowerCase();
  for (final secret in secrets) {
    if (secret.length < 4) continue; // 太短的片段会误报（助记词里的 "of"、"to" 之类）
    expect(dump, isNot(contains(secret.toLowerCase())), reason: '「$secret」出现在了 SharedPreferences 里');
  }
}

Future<(ProviderContainer, FakeSecureStoragePlatform)> _setUp() async {
  SharedPreferences.setMockInitialValues({});
  final sharedPreferences = await SharedPreferences.getInstance();

  final platform = FakeSecureStoragePlatform();
  FlutterSecureStoragePlatform.instance = platform;

  final container = ProviderContainer(
    overrides: [
      sharedPrefsProvider.overrideWithValue(sharedPreferences),
      secureWalletStorageProvider.overrideWithValue(SecureWalletStorage(const FlutterSecureStorage())),
      securityPasswordStorageProvider.overrideWithValue(SecurityPasswordStorage(const FlutterSecureStorage())),
    ],
  );
  addTearDown(container.dispose);
  return (container, platform);
}
