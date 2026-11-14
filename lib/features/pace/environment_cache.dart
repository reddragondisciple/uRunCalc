import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'environment_data.dart';

/// Кэш посчитанного окружения по ключу трека.
///
/// Сеть может отвечать медленно или быть недоступной, поэтому результат
/// сохраняется между переключениями дистанций и перезапусками приложения.
/// Кэш не мешает обновлению: кнопка «Обновить» и смена трека/настроек
/// запускают новый расчёт.
class EnvironmentCacheStore {
  EnvironmentCacheStore({
    this.storageKey = defaultStorageKey,
    this.maxEntries = 12,
  });

  static const String defaultStorageKey = 'environment_cache_v3';
  static const int _schemaVersion = 1;

  final String storageKey;

  /// Сколько треков хранить. Старые записи вытесняются по времени записи.
  final int maxEntries;

  Map<String, _CachedEnvironment>? _entries;
  Future<void>? _loading;
  Future<void> _writeQueue = Future<void>.value();

  /// Загружает кэш один раз. Ошибки чтения не мешают расчёту.
  Future<void> ensureLoaded() async {
    if (_entries != null) return;
    _loading ??= _load();
    await _loading;
  }

  /// Окружение для [trackKey] или `null`, если его ещё не считали.
  Future<EnvironmentData?> read(String trackKey) async {
    await ensureLoaded();
    return _entries![trackKey]?.data;
  }

  /// Сохраняет результат. Пустые данные не кэшируются: иначе после
  /// неудачного запроса экран решил бы, что сеть уже ответила.
  Future<void> write(String trackKey, EnvironmentData data) async {
    if (!data.hasContent) return;
    await ensureLoaded();
    final entries = _entries!;
    entries.remove(trackKey);
    entries[trackKey] = _CachedEnvironment(
      data: data,
      savedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    while (entries.length > maxEntries) {
      var oldestKey = entries.keys.first;
      var oldestAt = entries[oldestKey]!.savedAtMs;
      for (final entry in entries.entries) {
        if (entry.value.savedAtMs < oldestAt) {
          oldestAt = entry.value.savedAtMs;
          oldestKey = entry.key;
        }
      }
      entries.remove(oldestKey);
    }
    await _flush();
  }

  /// Удаляет одну запись. Нужно после правки коэффициентов: старый результат
  /// посчитан по прежнему профилю.
  Future<void> remove(String trackKey) async {
    await ensureLoaded();
    if (_entries!.remove(trackKey) != null) await _flush();
  }

  /// Полная очистка — например, для тестов или будущей настройки.
  Future<void> clear() async {
    await ensureLoaded();
    _entries!.clear();
    await _flush();
  }

  Future<void> _load() async {
    final loaded = <String, _CachedEnvironment>{};
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(storageKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          final rawEntries = decoded['entries'];
          if (rawEntries is Map) {
            for (final entry in rawEntries.entries) {
              final key = entry.key;
              final value = entry.value;
              if (key is! String || value is! Map) continue;
              final data = EnvironmentData.tryFromJson(value['data']);
              if (data == null) continue;
              final savedAt = value['savedAtMs'];
              loaded[key] = _CachedEnvironment(
                data: data,
                savedAtMs: savedAt is num && savedAt.isFinite
                    ? savedAt.round()
                    : 0,
              );
            }
          }
        }
      }
    } catch (error) {
      debugPrint('uRunCalc: не удалось прочитать $storageKey: $error');
    }

    // JSON сохраняет порядок, но время записи надёжнее: оставляем самые
    // свежие записи, если файл пришёл из будущей версии с большим лимитом.
    final ordered = loaded.entries.toList()
      ..sort((a, b) => a.value.savedAtMs.compareTo(b.value.savedAtMs));
    for (final entry in ordered) {
      if (loaded.length <= maxEntries) break;
      loaded.remove(entry.key);
    }
    _entries = loaded;
  }

  Future<void> _flush() async {
    final String encoded;
    try {
      encoded = jsonEncode({
        'version': _schemaVersion,
        'entries': {
          for (final entry in _entries!.entries)
            entry.key: {
              'savedAtMs': entry.value.savedAtMs,
              'data': entry.value.data.toJson(),
            },
        },
      });
    } catch (error) {
      debugPrint('uRunCalc: не удалось собрать $storageKey: $error');
      return;
    }

    _writeQueue = _writeQueue
        .then((_) async {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(storageKey, encoded);
        })
        .catchError((Object error) {
          debugPrint('uRunCalc: ошибка сохранения $storageKey: $error');
        });
    await _writeQueue;
  }
}

class _CachedEnvironment {
  const _CachedEnvironment({required this.data, required this.savedAtMs});

  final EnvironmentData data;
  final int savedAtMs;
}
