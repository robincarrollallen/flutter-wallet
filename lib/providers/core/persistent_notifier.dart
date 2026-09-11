import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../enums/prefs_key.dart';
import 'prefs_provider.dart';

/// 给任意 Notifier 复用的持久化能力——**写时过滤、读时全量**。
///
/// 设计取舍：
/// - 整个 state 序列化成一份 JSON 存在 [persistKey] 下。
/// - 写：[toJson] 里**只放要持久化的字段**——不想存的字段不 put 进 map，即被过滤掉。
/// - 读：[fromJson] 直接把存下来的 JSON 全量还原成 state，**不做任何「要不要恢复」的判定**；
///   没存进去的字段，自然落到 [fromJson] 给的默认值上。
///
/// 这样「哪些字段持久化」只在 [toJson] 一处声明，读端无需关心，杜绝读写不同步。
///
/// 用法：
/// ```dart
/// class SettingsNotifier extends Notifier<Settings>
///     with PersistentNotifier<Settings> {
///   @override
///   PrefsKey get persistKey => PrefsKey.appearance;
///
///   @override
///   Map<String, dynamic> toJson(Settings s) => {
///         'themeMode': s.themeMode.name, // 要持久化
///         'locale': s.locale.languageTag,
///         // s.isEditing 不放进来 => 不持久化
///       };
///
///   @override
///   Settings fromJson(Map<String, dynamic> json, Settings fallback) => fallback.copyWith(
///         themeMode: ThemeMode.values.asNameMap()[json['themeMode']],
///         locale: json['locale'] != null ? AppLocaleUtils.parse(json['locale']) : null,
///       );
///
///   @override
///   Settings build() => restore(const Settings());
///
///   void setThemeMode(ThemeMode m) => state = state.copyWith(themeMode: m); // 自动落盘
/// }
/// ```
mixin PersistentNotifier<T> on Notifier<T> {
  SharedPreferences get _prefs => ref.read(sharedPrefsProvider);

  /// 整份 state 在 SharedPreferences 中的存储键，必须来自 [PrefsKey] 清单。
  PrefsKey get persistKey;

  /// 写：把 state 转成 JSON——**只放要持久化的字段**，省略的字段即被过滤。
  Map<String, dynamic> toJson(T state);

  /// 读：把存下来的 JSON 全量还原成 state。[fallback] 是默认值，
  /// 用来兜底 JSON 里缺失的字段（建议用 copyWith，缺啥就保留 fallback 的）。
  T fromJson(Map<String, dynamic> json, T fallback);

  /// [restore] 执行时，本 Notifier 的持久化键是否已经存在。
  ///
  /// 用来区分「从没存过 / 数据容器被清」与「存过一份空值」——两者在 [restore] 的
  /// 返回值上都是 initial，但对调用方含义天差地别：前者是「不知道」，后者才是
  /// 「确实是空的」。拿它当删除依据的调用方（如启动对账）必须分清。
  ///
  /// 取的是 [restore] 当时的快照而不是现读：[restore] 挂的自动写回在 build 之后
  /// 立刻就会把键建出来，现读永远是 true，问不出「原本有没有」。
  bool get hasPersistedValue => _hadPersistedValue;
  bool _hadPersistedValue = false;

  /// [restore] 读到的存储值是否已损坏（JSON 解析失败或不是 Map）。
  ///
  /// 损坏与「没存过」一样，恢复结果都是 initial，同样不能当成「确实是空的」。
  bool get persistedValueCorrupted => _corrupted;
  bool _corrupted = false;

  /// 在 build() 里调用：用存储值全量恢复，并挂上「state 变化自动写回」的监听。
  /// 返回恢复后的初始 state；[initial] 同时充当缺失字段的默认值。
  T restore(T initial) {
    var s = initial;
    _corrupted = false;
    _hadPersistedValue = _prefs.containsKey(persistKey.value);
    final raw = _prefs.getString(persistKey.value);
    if (raw != null) {
      try {
        final json = jsonDecode(raw);
        if (json is Map<String, dynamic>) {
          s = fromJson(json, initial);
        } else {
          _corrupted = true; // 存着，但不是我们写下的结构。
        }
      } catch (_) {
        // 脏数据：当作没存过，用默认值，但记下来——调用方可能需要区分。
        _corrupted = true;
      }
    }
    /// 监听 state 变化，自动落盘
    listenSelf((_, next) {
      _prefs.setString(persistKey.value, jsonEncode(toJson(next)));
    });
    return s;
  }

  /// 清空本 Notifier 的持久化数据（下次重启回到默认值）。
  Future<void> clearPersisted() => _prefs.remove(persistKey.value);
}
