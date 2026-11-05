/// Горные данные таблицы (docs/gpx-mountain-mode.md §2).
///
/// Объекты неизменяемые, сериализуются в JSON. Старые таблицы без этих полей
/// читаются через [MountainData.empty].
library;

/// Опора плана: от чего считать сегменты при пересчёте.
enum PlanAnchorKind { flat, targetTime, targetPace, manual }

class PlanAnchor {
  const PlanAnchor._(
    this.kind, {
    this.flatPaceSec,
    this.targetTotalSec,
    this.targetPaceSec,
  });

  /// Плоский темп (сек/км) — данные введены «плоскими».
  const PlanAnchor.flat(double paceSecPerKm)
    : this._(PlanAnchorKind.flat, flatPaceSec: paceSecPerKm);

  /// Итоговое время с учётом стоянок, сек.
  const PlanAnchor.targetTime(int totalSec)
    : this._(PlanAnchorKind.targetTime, targetTotalSec: totalSec);

  /// Целевой ходовой темп (сек/км) — уже с поправкой на высоты.
  const PlanAnchor.targetPace(double paceSecPerKm)
    : this._(PlanAnchorKind.targetPace, targetPaceSec: paceSecPerKm);

  const PlanAnchor.manual() : this._(PlanAnchorKind.manual);

  final PlanAnchorKind kind;
  final double? flatPaceSec;
  final int? targetTotalSec;
  final double? targetPaceSec;

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    if (flatPaceSec != null) 'flatPaceSec': flatPaceSec,
    if (targetTotalSec != null) 'targetTotalSec': targetTotalSec,
    if (targetPaceSec != null) 'targetPaceSec': targetPaceSec,
  };

  static PlanAnchor? tryFromJson(dynamic raw) {
    if (raw is! Map) return null;
    final kindName = raw['kind'];
    for (final kind in PlanAnchorKind.values) {
      if (kind.name != kindName) continue;
      switch (kind) {
        case PlanAnchorKind.flat:
          final pace = _readDouble(raw['flatPaceSec']);
          return pace == null ? null : PlanAnchor.flat(pace);
        case PlanAnchorKind.targetTime:
          final total = _readDouble(raw['targetTotalSec']);
          return total == null ? null : PlanAnchor.targetTime(total.round());
        case PlanAnchorKind.targetPace:
          final pace = _readDouble(raw['targetPaceSec']);
          return pace == null ? null : PlanAnchor.targetPace(pace);
        case PlanAnchorKind.manual:
          return const PlanAnchor.manual();
      }
    }
    return null;
  }
}

/// Метаданные одного трека (основной или резервный). Сам GPX лежит файлом.
class TrackMeta {
  const TrackMeta({
    required this.relativePath,
    required this.originalName,
    required this.importedAtMs,
    required this.points,
    required this.lengthM,
    required this.ascentM,
    required this.descentM,
    required this.hasElevation,
    this.offsetM = 0,
  });

  /// Относительно каталога треков дистанции: `primary.gpx` или `backup.gpx`.
  /// Абсолютный путь на iOS меняется между запусками, поэтому не храним.
  final String relativePath;
  final String originalName;
  final int importedAtMs;
  final int points;
  final double lengthM;
  final double ascentM;
  final double descentM;
  final bool hasElevation;

  /// Сдвиг начала трека относительно старта, м. По умолчанию 0.
  final double offsetM;

  Map<String, dynamic> toJson() => {
    'relativePath': relativePath,
    'originalName': originalName,
    'importedAtMs': importedAtMs,
    'points': points,
    'lengthM': lengthM,
    'ascentM': ascentM,
    'descentM': descentM,
    'hasElevation': hasElevation,
    'offsetM': offsetM,
  };

  static TrackMeta? tryFromJson(dynamic raw) {
    if (raw is! Map) return null;
    final path = raw['relativePath'];
    if (path is! String || path.isEmpty) return null;
    return TrackMeta(
      relativePath: path,
      originalName: raw['originalName'] is String
          ? raw['originalName'] as String
          : '',
      importedAtMs: _readInt(raw['importedAtMs']) ?? 0,
      points: _readInt(raw['points']) ?? 0,
      lengthM: _readDouble(raw['lengthM']) ?? 0,
      ascentM: _readDouble(raw['ascentM']) ?? 0,
      descentM: _readDouble(raw['descentM']) ?? 0,
      hasElevation: raw['hasElevation'] is bool
          ? raw['hasElevation'] as bool
          : false,
      offsetM: _readDouble(raw['offsetM']) ?? 0,
    );
  }
}

/// Два слота треков и активный выбор.
class TrackSlots {
  const TrackSlots({this.active = 'primary', this.primary, this.backup});

  static const TrackSlots empty = TrackSlots();

  /// `primary` или `backup`.
  final String active;
  final TrackMeta? primary;
  final TrackMeta? backup;

  TrackMeta? get activeTrack => active == 'backup' ? backup : primary;

  Map<String, dynamic> toJson() => {
    'active': active,
    'primary': primary?.toJson(),
    'backup': backup?.toJson(),
  };

  static TrackSlots tryFromJson(dynamic raw) {
    if (raw is! Map) return empty;
    final active = raw['active'] == 'backup' ? 'backup' : 'primary';
    return TrackSlots(
      active: active,
      primary: TrackMeta.tryFromJson(raw['primary']),
      backup: TrackMeta.tryFromJson(raw['backup']),
    );
  }
}

/// Горная часть таблицы. Пустой объект означает обычный режим.
class MountainData {
  const MountainData({
    this.enabled = false,
    this.stopsSec = const <int>[],
    this.anchor,
    this.tracks = TrackSlots.empty,
    this.manualAscent = const <int?>[],
    this.manualDescent = const <int?>[],
    this.showStopsInPace = false,
  });

  static const MountainData empty = MountainData();

  final bool enabled;

  /// Стоянки по колонкам, сек. Длина совпадает с числом колонок.
  final List<int> stopsSec;
  final PlanAnchor? anchor;
  final TrackSlots tracks;

  /// Ручные D+/D−, м, по сегментам. `null` — брать из трека.
  final List<int?> manualAscent;
  final List<int?> manualDescent;

  /// Глобальный переключатель: «темп сегмента с учётом стоянок».
  final bool showStopsInPace;

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'stopsSec': stopsSec,
    'anchor': anchor?.toJson(),
    'tracks': tracks.toJson(),
    'manualAscent': manualAscent,
    'manualDescent': manualDescent,
    'showStopsInPace': showStopsInPace,
  };

  static MountainData tryFromJson(dynamic raw, {required int columns}) {
    if (raw is! Map) return empty;
    return MountainData(
      enabled: raw['enabled'] is bool ? raw['enabled'] as bool : false,
      stopsSec: _readIntList(raw['stopsSec'], columns),
      anchor: PlanAnchor.tryFromJson(raw['anchor']),
      tracks: TrackSlots.tryFromJson(raw['tracks']),
      manualAscent: _readNullableIntList(raw['manualAscent'], columns),
      manualDescent: _readNullableIntList(raw['manualDescent'], columns),
      showStopsInPace: raw['showStopsInPace'] is bool
          ? raw['showStopsInPace'] as bool
          : false,
    );
  }
}

double? _readDouble(dynamic value) {
  if (value is num && value.isFinite) return value.toDouble();
  return null;
}

int? _readInt(dynamic value) {
  if (value is int) return value;
  if (value is num && value.isFinite) return value.round();
  return null;
}

List<int> _readIntList(dynamic value, int length) {
  final result = List<int>.filled(length, 0);
  if (value is List) {
    for (var i = 0; i < length && i < value.length; i++) {
      result[i] = _readInt(value[i]) ?? 0;
    }
  }
  return result;
}

List<int?> _readNullableIntList(dynamic value, int length) {
  final result = List<int?>.filled(length, null);
  if (value is List) {
    for (var i = 0; i < length && i < value.length; i++) {
      result[i] = _readInt(value[i]);
    }
  }
  return result;
}
