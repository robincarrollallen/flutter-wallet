import '../../services/mnemonic_service.dart';
import '../../services/private_key_service.dart';

/// 导入输入的类型：助记词 / 私钥 / 无法识别。
enum SecretType { mnemonic, privateKey, unknown }

/// 助记词或私钥校验失败的类型。文案在 UI 层按当前语言翻译，逻辑层只返回类型与数据。
enum MnemonicErrorKind {
  empty,
  nonEnglish,
  wordCount,
  invalidWords,
  checksum,
  invalidPrivateKey,
  deriveFailed,
}

/// 校验结果：类型 + 可选数据（词数 / 无效单词），供 UI 层组装本地化文案。
class MnemonicError {
  const MnemonicError(this.kind, {this.count, this.words});

  final MnemonicErrorKind kind;
  final int? count;
  final List<String>? words;
}

/// 导入助记词页面的纯逻辑：与状态/UI 无关，便于单测和复用。
class ImportMnemonicLogic {
  const ImportMnemonicLogic._();

  /// BIP39 允许的助记词长度。
  static const validWordCounts = {12, 15, 18, 21, 24};

  /// 单次最多展示的候选词数量。
  static const maxSuggestions = 6;

  /// 规整输入：去首尾空白、把连续空白/换行折叠成单个空格、转小写。
  static String normalize(String input) {
    return input.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  /// 自动判断输入“意图”是助记词还是私钥（用于分流与候选词屏蔽；
  /// 是否为**合法**私钥由 [validate] + [PrivateKeyService.detect] 严格判定）：
  /// - 空 → unknown；
  /// - 含空白（多词）→ 助记词；
  /// - 单 token 且呈现私钥特征（0x 前缀 / suiprivkey 前缀 / 长串非词）→ 私钥；
  /// - 其余（含正在输入的单个助记词）→ 助记词。
  static SecretType detectType(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return SecretType.unknown;
    if (RegExp(r'\s').hasMatch(trimmed)) return SecretType.mnemonic;

    final lower = trimmed.toLowerCase();
    // 私钥意图特征：明确前缀，或远超任何 BIP39 单词长度（≤8）的单 token。
    if (lower.startsWith('0x') ||
        lower.startsWith('suiprivkey') ||
        trimmed.length >= 40) {
      return SecretType.privateKey;
    }
    return SecretType.mnemonic;
  }

  /// 当前词数（空输入为 0）。
  static int wordCount(String input) {
    final n = normalize(input);
    if (n.isEmpty) return 0;
    return n.split(' ').length;
  }

  /// 取光标处正在输入的最后一个单词（用于自动补全前缀匹配）。
  static String currentWord(String text) {
    final match = RegExp(r'[a-zA-Z]*$').firstMatch(text);
    return (match?.group(0) ?? '').toLowerCase();
  }

  /// 根据正在输入的单词，从 BIP39 词表里前缀匹配候选词。
  /// 仅在输入被判定为助记词时提示，避免粘贴私钥时弹出无关候选。
  static List<String> suggestions(String text) {
    if (detectType(text) == SecretType.privateKey) return const [];
    final prefix = currentWord(text);
    if (prefix.isEmpty) return const [];
    // 已精确匹配某个完整词时不再提示，避免补全后还弹一条。
    final wordlist = MnemonicService.englishWordlist;
    if (wordlist.contains(prefix) &&
        !wordlist.any((w) => w != prefix && w.startsWith(prefix))) {
      return const [];
    }
    return wordlist
        .where((w) => w.startsWith(prefix))
        .take(maxSuggestions)
        .toList(growable: false);
  }

  /// 把输入末尾正在敲的单词替换为选中的完整单词，并补一个空格。
  static String applySuggestion(String text, String word) {
    final replaced = text.replaceFirst(RegExp(r'[a-zA-Z]*$'), word);
    return '$replaced ';
  }

  /// 校验输入（助记词或私钥），返回错误类型；为 null 表示通过。
  /// 先判类型：私钥走格式校验；助记词先长度/字符校验，再用 BIP39 校验和验证。
  static MnemonicError? validate(String input) {
    final type = detectType(input);
    if (type == SecretType.unknown) {
      return const MnemonicError(MnemonicErrorKind.empty);
    }
    if (type == SecretType.privateKey) {
      return PrivateKeyService.detect(input.trim()) == PrivateKeyKind.unknown
          ? const MnemonicError(MnemonicErrorKind.invalidPrivateKey)
          : null;
    }

    final n = normalize(input);
    if (n.isEmpty) return const MnemonicError(MnemonicErrorKind.empty);
    if (!RegExp(r'^[a-z ]+$').hasMatch(n)) {
      return const MnemonicError(MnemonicErrorKind.nonEnglish);
    }
    final words = n.split(' ');
    if (!validWordCounts.contains(words.length)) {
      return MnemonicError(MnemonicErrorKind.wordCount, count: words.length);
    }
    final unknown =
        words.where((w) => !MnemonicService.englishWordlist.contains(w)).toList();
    if (unknown.isNotEmpty) {
      return MnemonicError(
        MnemonicErrorKind.invalidWords,
        words: unknown.take(3).toList(),
      );
    }
    if (!MnemonicService.validate(n)) {
      return const MnemonicError(MnemonicErrorKind.checksum);
    }
    return null;
  }
}
