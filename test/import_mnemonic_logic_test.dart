import 'package:flutter_test/flutter_test.dart';
import 'package:wallet/features/wallet/screens/import_mnemonic/import_mnemonic_logic.dart';

void main() {
  const validMnemonic =
      'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';

  group('normalize', () {
    test('去首尾空白、折叠空白、转小写', () {
      expect(ImportMnemonicLogic.normalize('  Abandon   ABOUT \n test '),
          'abandon about test');
    });
  });

  group('wordCount', () {
    test('空输入为 0', () {
      expect(ImportMnemonicLogic.wordCount('   '), 0);
    });

    test('按规整后的词数统计', () {
      expect(ImportMnemonicLogic.wordCount('abandon  about'), 2);
    });
  });

  group('currentWord', () {
    test('取末尾正在输入的单词', () {
      expect(ImportMnemonicLogic.currentWord('abandon abo'), 'abo');
    });

    test('以空格结尾时为空', () {
      expect(ImportMnemonicLogic.currentWord('abandon '), '');
    });
  });

  group('suggestions', () {
    test('按前缀给出候选且不超过上限', () {
      final s = ImportMnemonicLogic.suggestions('aban');
      expect(s, contains('abandon'));
      expect(s.length, lessThanOrEqualTo(ImportMnemonicLogic.maxSuggestions));
      expect(s.every((w) => w.startsWith('aban')), isTrue);
    });

    test('已唯一精确匹配时不再提示', () {
      // “zoo” 是词表中唯一以 zoo 开头的词。
      expect(ImportMnemonicLogic.suggestions('zoo'), isEmpty);
    });

    test('空前缀无候选', () {
      expect(ImportMnemonicLogic.suggestions('abandon '), isEmpty);
    });
  });

  group('applySuggestion', () {
    test('替换末尾单词并补空格', () {
      expect(ImportMnemonicLogic.applySuggestion('aba ab', 'abandon'),
          'aba abandon ');
    });
  });

  group('validate', () {
    MnemonicErrorKind? kind(String input) =>
        ImportMnemonicLogic.validate(input)?.kind;

    test('合法助记词返回 null', () {
      expect(ImportMnemonicLogic.validate(validMnemonic), isNull);
    });

    test('空输入提示', () {
      expect(kind(''), MnemonicErrorKind.empty);
    });

    test('词数非法', () {
      expect(kind('abandon about'), MnemonicErrorKind.wordCount);
    });

    test('含无效单词', () {
      const input =
          'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon zzzz';
      expect(kind(input), MnemonicErrorKind.invalidWords);
    });

    test('词数与字符合法但校验和错误', () {
      const input =
          'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon';
      expect(kind(input), MnemonicErrorKind.checksum);
    });

    test('合法 EVM 私钥返回 null', () {
      expect(
        ImportMnemonicLogic.validate(
          '0x0000000000000000000000000000000000000000000000000000000000000001',
        ),
        isNull,
      );
    });

    test('残缺/非法私钥提示 invalidPrivateKey', () {
      // 64 位 hex 但其一为非 hex 字符 → 不被判为私钥而走助记词分支；
      // 这里用一个明显的私钥前缀格式（suiprivkey 开头但内容非法）触发私钥错误。
      expect(kind('suiprivkey1qzzzzzz'), MnemonicErrorKind.invalidPrivateKey);
    });
  });

  group('detectType', () {
    test('多词 → mnemonic', () {
      expect(ImportMnemonicLogic.detectType('abandon about test'),
          SecretType.mnemonic);
    });
    test('64 位 hex → privateKey', () {
      expect(
        ImportMnemonicLogic.detectType(
          '0x0000000000000000000000000000000000000000000000000000000000000001',
        ),
        SecretType.privateKey,
      );
    });
    test('正在输入的单个助记词 → mnemonic', () {
      expect(ImportMnemonicLogic.detectType('aban'), SecretType.mnemonic);
    });
    test('空 → unknown', () {
      expect(ImportMnemonicLogic.detectType('  '), SecretType.unknown);
    });
  });

  group('suggestions 私钥屏蔽', () {
    test('输入私钥时不返回 BIP39 候选', () {
      expect(
        ImportMnemonicLogic.suggestions(
          '0x0000000000000000000000000000000000000000000000000000000000000001',
        ),
        isEmpty,
      );
    });
  });
}
