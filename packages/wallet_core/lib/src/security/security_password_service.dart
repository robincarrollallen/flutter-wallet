import 'dart:convert';

import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:flutter/foundation.dart';

import '../storage/security_password_storage.dart';

/// 安全码的设置与校验。
///
/// 安全码是 App 全局唯一的口令，用于导出私钥 / 备份等敏感操作前的二次确认。
///
/// **它保护的不是钱包。** 能读到 Keychain 的攻击者，本来就能从同一个 Keychain 里
/// 读出助记词，那时安全码是什么已经无关紧要。这里改成 salt + PBKDF2 摘要，真正
/// 保护的是**用户这个口令本身**——它大概率在别处复用过，不该以明文躺在设备上。
/// 想清楚这一点才好判断该给它投多少成本：迭代次数值得拉高，但做失败锁定的收益有限。
class SecurityPasswordService {
  const SecurityPasswordService(this._storage);

  final SecurityPasswordStorage _storage;

  /// 当前编码格式的版本前缀。记录形如 `v1$<迭代次数>$<salt-base64>$<hash-base64>`。
  ///
  /// 带版本号是为了以后能换 KDF 而不锁死老用户：认不出的前缀一律当旧格式处理。
  static const _version = 'v1';
  static const _separator = r'$';

  /// PBKDF2 迭代次数。
  ///
  /// 取得高是因为安全码通常只有 6 位数字，搜索空间才 10^6——口令本身弱到无法补救，
  /// 迭代次数是唯一能拖慢离线爆破的手段。实测桌面 200000 次约 277ms，手机大约 1 秒，
  /// 是校验场景可接受的停顿上限。
  ///
  /// **迭代次数写进记录本身**，校验时按记录里的值重算，而不是读这个常量：
  /// 否则哪天把它调高，所有已存的记录都会验不过，等于把老用户全锁在门外。
  static const _iterations = 200000;
  static const _saltLength = 16;
  static const _keyLength = 32;

  /// 是否已设置过安全码。
  Future<bool> hasPassword() async {
    final record = await _storage.read();
    return record != null && record.isNotEmpty;
  }

  /// 设置 / 重置安全码。
  Future<void> setPassword(String password) async =>
      _storage.write(await _encode(password, QuickCrypto.generateRandom(_saltLength)));

  /// 校验安全码是否正确。
  ///
  /// 兼容两种记录：
  /// - `v1$…`：当前格式，重算摘要后常量时间比对；
  /// - 其它：本次改造之前写下的**明文**。比对通过后**就地升级**为 v1，
  ///   这样老用户无感迁移。少了这一步，所有已设置过安全码的用户会直接被锁死。
  Future<bool> verify(String password) async {
    final record = await _storage.read();
    if (record == null || record.isEmpty) return false;

    if (!record.startsWith('$_version$_separator')) {
      // 旧的明文记录。仍走常量时间比对——没有理由在这里留一个计时侧信道。
      final matched = BytesUtils.bytesEqualConst(utf8.encode(record), utf8.encode(password));
      if (matched) await setPassword(password);
      return matched;
    }

    final parts = record.split(_separator);
    // 格式不对说明记录被损坏或被外部篡改过，一律判为不通过，不去猜它想表达什么。
    if (parts.length != 4) return false;
    final iterations = int.tryParse(parts[1]);
    if (iterations == null || iterations <= 0) return false;
    final List<int> salt;
    final List<int> expected;
    try {
      salt = base64Decode(parts[2]);
      expected = base64Decode(parts[3]);
    } on FormatException {
      return false;
    }
    // 按记录里的迭代次数重算，而不是当前常量——这正是把它写进记录的意义。
    final actual = await compute(deriveSecurityPasswordHashInBackground, (password, salt, iterations));
    return BytesUtils.bytesEqualConst(actual, expected);
  }

  /// 把口令与 salt 编码成一条可落盘的记录。
  Future<String> _encode(String password, List<int> salt) async {
    final hash = await compute(deriveSecurityPasswordHashInBackground, (password, salt, _iterations));
    return [_version, '$_iterations', base64Encode(salt), base64Encode(hash)].join(_separator);
  }

  /// PBKDF2-HMAC-SHA256。与 BIP39 种子推导用的是同一套实现。
  ///
  /// **只能经 [deriveSecurityPasswordHashInBackground] 调用。** 20 万轮跑满约 1 秒
  /// （见 [_iterations]），直接调就是在 UI 线程上冻结这么久，而且不会有任何报错提醒你。
  static List<int> _derive(String password, List<int> salt, int iterations) => QuickCrypto.pbkdf2DeriveKey(
    password: utf8.encode(password),
    salt: salt,
    iterations: iterations,
    hash: () => SHA256(),
    dklen: _keyLength,
  );
}

/// compute() 顶层入口：在后台 isolate 跑 PBKDF2（20 万轮，手机约 1 秒）。
/// 入参为 (口令, salt, 迭代次数)——迭代次数随记录走，不读常量，理由见 [SecurityPasswordService._iterations]。
List<int> deriveSecurityPasswordHashInBackground((String, List<int>, int) args) =>
    SecurityPasswordService._derive(args.$1, args.$2, args.$3);
