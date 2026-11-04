import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef JsonSnapshotBuilder = Map<String, dynamic> Function();

/// Хранит JSON-состояние в `SharedPreferences`.
///
/// Запись откладывается на [debounce], поэтому сериализация выполняется один
/// раз после серии изменений, а не на каждый `setState`. Все записи идут
/// последовательно: более новая не может завершиться раньше старой.
class PersistedJsonStore {
  PersistedJsonStore({
    required this.storageKey,
    this.legacyStorageKey,
    this.schemaVersion = 1,
    this.debounce = const Duration(milliseconds: 400),
  });

  final String storageKey;
  final String? legacyStorageKey;
  final int schemaVersion;
  final Duration debounce;

  Future<SharedPreferences>? _prefs;
  Timer? _timer;
  JsonSnapshotBuilder? _pending;
  Future<void> _writeQueue = Future<void>.value();
  bool _disposed = false;

  Future<SharedPreferences> get _prefsInstance =>
      _prefs ??= SharedPreferences.getInstance();

  /// Читает состояние. Повреждённые данные не роняют приложение: возвращается
  /// `null`, а ошибка пишется в лог.
  Future<Map<String, dynamic>?> load() async {
    try {
      final prefs = await _prefsInstance;
      final data =
          _decode(prefs.getString(storageKey)) ??
          _decode(prefs.getString(legacyStorageKey ?? ''));
      if (data == null) return null;
      return _migrate(data);
    } catch (error) {
      debugPrint('uRunCalc: не удалось прочитать $storageKey: $error');
      return null;
    }
  }

  /// Планирует сохранение. Повторные вызовы в течение [debounce] заменяют
  /// предыдущий снимок, поэтому сериализация выполняется один раз.
  void schedule(JsonSnapshotBuilder build) {
    if (_disposed) return;
    _pending = build;
    _timer?.cancel();
    _timer = Timer(debounce, () => unawaited(_flushPending()));
  }

  /// Записывает отложенные изменения немедленно — например, при сворачивании
  /// приложения.
  Future<void> flush() async {
    _timer?.cancel();
    _timer = null;
    await _flushPending();
    await _writeQueue;
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    if (_pending != null) unawaited(_flushPending());
    _disposed = true;
  }

  Future<void> _flushPending() async {
    final build = _pending;
    _pending = null;
    if (build == null) return;

    final String encoded;
    try {
      final payload = <String, dynamic>{'version': schemaVersion, ...build()};
      encoded = jsonEncode(payload);
    } catch (error) {
      debugPrint('uRunCalc: не удалось собрать состояние $storageKey: $error');
      return;
    }

    _writeQueue = _writeQueue
        .then((_) async {
          final prefs = await _prefsInstance;
          final saved = await prefs.setString(storageKey, encoded);
          if (!saved) {
            debugPrint('uRunCalc: не удалось сохранить $storageKey');
          }
        })
        .catchError((Object error) {
          debugPrint('uRunCalc: ошибка сохранения $storageKey: $error');
        });

    await _writeQueue;
  }

  Map<String, dynamic>? _decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (error) {
      debugPrint('uRunCalc: повреждённые данные $storageKey: $error');
    }
    return null;
  }

  /// Точка расширения для будущих миграций схемы. Сейчас старые записи
  /// (без поля `version`) читаются как есть.
  Map<String, dynamic> _migrate(Map<String, dynamic> data) {
    final version = data['version'];
    if (version is int && version >= schemaVersion) return data;
    return data;
  }
}
