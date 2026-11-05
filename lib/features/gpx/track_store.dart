import 'dart:io';

/// Хранилище GPX-файлов треков. Интерфейс отделён от `path_provider`,
/// чтобы логику можно было тестировать на временном каталоге.
abstract class TrackFileStore {
  /// Атомарно записывает файл слота. Прежний файл заменяется только после
  /// полной записи.
  Future<void> write({
    required String distanceKey,
    required String fileName,
    required String content,
  });

  Future<String?> read({required String distanceKey, required String fileName});

  /// Удаляет весь каталог дистанции. Отсутствующий каталог — не ошибка.
  Future<void> deleteDistance(String distanceKey);

  Future<bool> exists({required String distanceKey, required String fileName});
}

/// Файловая реализация. Корень — каталог поддержки приложения (`tracks/`).
class DirectoryTrackFileStore implements TrackFileStore {
  DirectoryTrackFileStore(this.root);

  /// Каталог `.../tracks`. Создаётся при первой записи.
  final Directory root;

  Directory _dir(String distanceKey) =>
      Directory('${root.path}${Platform.pathSeparator}$distanceKey');

  File _file(String distanceKey, String fileName) =>
      File('${_dir(distanceKey).path}${Platform.pathSeparator}$fileName');

  @override
  Future<void> write({
    required String distanceKey,
    required String fileName,
    required String content,
  }) async {
    final dir = _dir(distanceKey);
    await dir.create(recursive: true);
    final target = _file(distanceKey, fileName);
    final temp = File('${target.path}.tmp');
    await temp.writeAsString(content, flush: true);
    await temp.rename(target.path);
  }

  @override
  Future<String?> read({
    required String distanceKey,
    required String fileName,
  }) async {
    final file = _file(distanceKey, fileName);
    if (!await file.exists()) return null;
    return file.readAsString();
  }

  @override
  Future<bool> exists({
    required String distanceKey,
    required String fileName,
  }) => _file(distanceKey, fileName).exists();

  @override
  Future<void> deleteDistance(String distanceKey) async {
    final dir = _dir(distanceKey);
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}

/// Стабильный ключ дистанции: FNV-1a 64 от UTF-16 строки
/// `event + \u0000 + distance`, 16 hex-символов.
///
/// `String.hashCode` не используем: он не гарантирован между версиями Dart,
/// а ключ пишется на диск. Считаем через `BigInt`, чтобы не зависеть от
/// знаковой арифметики `int`.
String trackDistanceKey(String eventName, String distanceName) {
  final offsetBasis = BigInt.parse('cbf29ce484222325', radix: 16);
  final prime = BigInt.parse('100000001b3', radix: 16);
  final mask = BigInt.parse('ffffffffffffffff', radix: 16);

  var hash = offsetBasis;
  for (final unit in '$eventName\u0000$distanceName'.codeUnits) {
    // Каждый UTF-16 код — два байта (младший, старший).
    for (final byte in [unit & 0xff, (unit >> 8) & 0xff]) {
      hash = (hash ^ BigInt.from(byte)) & mask;
      hash = (hash * prime) & mask;
    }
  }
  return hash.toRadixString(16).padLeft(16, '0');
}
