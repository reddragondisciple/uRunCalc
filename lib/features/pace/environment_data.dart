/// Погода, покрытие, кроссовки и снег для таблицы Pace/Ultra.
///
/// Настройки хранятся вместе с таблицей; вычисленные данные (погодные
/// сэмплы, участки покрытия) живут в памяти и не сериализуются. Старые
/// таблицы без блока `environment` читаются как «всё выключено».
library;

/// Откуда взята погода.
enum WeatherMode { forecast, normals, historical }

/// Тип покрытия. `unknown` при расчёте заменяется на `dirt`.
enum SurfaceType {
  asphalt,
  concrete,
  pavingStones,
  compacted,
  dirt,
  ground,
  grass,
  sand,
  mud,
  snowPacked,
  snowDeep,
  unknown,
}

/// Состояние мокрости участка.
enum Wetness { dry, damp, wet, saturated, bog }

/// Тип обуви. `null` в настройках означает «не выбрано».
enum ShoeKind { road, trail, minimal }

/// Контекст населённого пункта для расчистки снега.
enum SettlementContext { urban, town, village, rural }

/// Класс дороги для расчистки снега.
enum RoadClass { pavedMajor, pavedLocal, footway, unpaved }

/// Состояние снега на участке.
enum SnowState { none, asphalt, packed, ice, loose, slush }

/// Настройки окружения одной таблицы.
class EnvironmentSettings {
  const EnvironmentSettings({
    this.surfaceEnabled = false,
    this.weatherEnabled = false,
    this.shoesEnabled = false,
    this.groomedSnow = false,
    this.startUtc,
    this.shoe,
  });

  static const EnvironmentSettings empty = EnvironmentSettings();

  final bool surfaceEnabled;
  final bool weatherEnabled;
  final bool shoesEnabled;

  /// Укатанный/натоптанный снег. По умолчанию выключено.
  final bool groomedSnow;

  /// Время старта в UTC. Нужно для прогноза/архива.
  final DateTime? startUtc;

  /// Выбранная обувь. `null` — множитель обуви 1.00.
  final ShoeKind? shoe;

  bool get anyEnabled => surfaceEnabled || weatherEnabled || shoesEnabled;

  EnvironmentSettings copyWith({
    bool? surfaceEnabled,
    bool? weatherEnabled,
    bool? shoesEnabled,
    bool? groomedSnow,
    DateTime? startUtc,
    ShoeKind? shoe,
    bool clearStart = false,
    bool clearShoe = false,
  }) {
    return EnvironmentSettings(
      surfaceEnabled: surfaceEnabled ?? this.surfaceEnabled,
      weatherEnabled: weatherEnabled ?? this.weatherEnabled,
      shoesEnabled: shoesEnabled ?? this.shoesEnabled,
      groomedSnow: groomedSnow ?? this.groomedSnow,
      startUtc: clearStart ? null : (startUtc ?? this.startUtc),
      shoe: clearShoe ? null : (shoe ?? this.shoe),
    );
  }

  Map<String, dynamic> toJson() => {
    'surfaceEnabled': surfaceEnabled,
    'weatherEnabled': weatherEnabled,
    'shoesEnabled': shoesEnabled,
    'groomedSnow': groomedSnow,
    if (startUtc != null) 'startUtcMs': startUtc!.millisecondsSinceEpoch,
    if (shoe != null) 'shoe': shoe!.name,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EnvironmentSettings &&
          surfaceEnabled == other.surfaceEnabled &&
          weatherEnabled == other.weatherEnabled &&
          shoesEnabled == other.shoesEnabled &&
          groomedSnow == other.groomedSnow &&
          startUtc == other.startUtc &&
          shoe == other.shoe;

  @override
  int get hashCode => Object.hash(
    surfaceEnabled,
    weatherEnabled,
    shoesEnabled,
    groomedSnow,
    startUtc,
    shoe,
  );

  static EnvironmentSettings tryFromJson(dynamic raw) {
    if (raw is! Map) return empty;
    return EnvironmentSettings(
      surfaceEnabled: raw['surfaceEnabled'] is bool
          ? raw['surfaceEnabled'] as bool
          : false,
      weatherEnabled: raw['weatherEnabled'] is bool
          ? raw['weatherEnabled'] as bool
          : false,
      shoesEnabled: raw['shoesEnabled'] is bool
          ? raw['shoesEnabled'] as bool
          : false,
      groomedSnow: raw['groomedSnow'] is bool
          ? raw['groomedSnow'] as bool
          : false,
      startUtc: _readDateTime(raw['startUtcMs']),
      shoe: _readShoe(raw['shoe']),
    );
  }

  static DateTime? _readDateTime(dynamic value) {
    if (value is! num || !value.isFinite) return null;
    return DateTime.fromMillisecondsSinceEpoch(value.round(), isUtc: true);
  }

  static ShoeKind? _readShoe(dynamic value) {
    if (value is! String) return null;
    for (final shoe in ShoeKind.values) {
      if (shoe.name == value) return shoe;
    }
    return null;
  }
}

/// Погодный сэмпл, привязанный к точке трека.
class WeatherSample {
  const WeatherSample({
    required this.distanceM,
    required this.timeUtc,
    required this.lat,
    required this.lon,
    required this.elevationM,
    required this.tempC,
    required this.apparentC,
    required this.humidityPct,
    required this.precipMm,
    required this.rainMm,
    required this.et0Mm,
    required this.windKmh,
    required this.snowfallCm,
    required this.snowDepthM,
    required this.soilMoistureTop,
    required this.soilMoistureDeep,
    required this.soilMoistureEff,
    required this.freezingLevelM,
    required this.mode,
    this.avgTemp5C = 0,
    this.frozenDays = 0,
  });

  final double distanceM;
  final DateTime timeUtc;
  final double lat;
  final double lon;
  final double elevationM;
  final double tempC;
  final double apparentC;
  final double humidityPct;
  final double precipMm;
  final double rainMm;
  final double et0Mm;
  final double windKmh;
  final double snowfallCm;
  final double snowDepthM;
  final double soilMoistureTop;
  final double soilMoistureDeep;
  final double soilMoistureEff;
  final double? freezingLevelM;
  final WeatherMode mode;

  /// Средняя температура за 5 дней до сэмпла, °C (для зимней логики болот).
  final double avgTemp5C;

  /// Сколько из последних 7 дней имели среднюю температуру ≤ −10 °C.
  final int frozenDays;
}

/// Однородный участок покрытия.
class SurfaceRun {
  const SurfaceRun({
    required this.startM,
    required this.endM,
    required this.type,
    required this.wetness,
    required this.confidence,
    this.isBog = false,
    this.bogKind,
    this.bogFactor = 1.0,
    this.bogConfidence = 1.0,
    this.surfaceSource = 'default',
    this.urbanity = 0,
    this.roadClass = RoadClass.unpaved,
    this.isFord = false,
    this.factor = 1.0,
    this.heatFactor = 1.0,
    this.snowFactor = 1.0,
    this.shoeFactor = 1.0,
  });

  final double startM;
  final double endM;
  final SurfaceType type;
  final Wetness wetness;
  final double confidence;
  final bool isBog;
  final String? bogKind;
  final double bogFactor;

  /// Уверенность болотного признака: 1.0 — OSM, ниже — растровый fallback.
  final double bogConfidence;
  final String surfaceSource;

  /// 0..1: степень урбанизации для расчистки снега.
  final double urbanity;
  final RoadClass roadClass;
  final bool isFord;

  /// Итоговый множитель участка с учётом включённых галочек.
  final double factor;
  final double heatFactor;
  final double snowFactor;
  final double shoeFactor;
}

/// Участок с известной степенью урбанизации.
class SettlementRun {
  const SettlementRun({
    required this.startM,
    required this.endM,
    required this.context,
    required this.urbanity,
    required this.confidence,
  });

  final double startM;
  final double endM;
  final SettlementContext context;

  /// 0..1: 0 — поле, 1 — плотная городская застройка.
  final double urbanity;
  final double confidence;
}

/// Оценка снега на участке.
class SnowEstimate {
  const SnowEstimate({
    required this.startM,
    required this.endM,
    required this.effectiveDepthM,
    required this.probabilities,
  });

  final double startM;
  final double endM;

  /// Глубина после расчистки и укатки.
  final double effectiveDepthM;

  /// Вероятности состояний, сумма = 1.
  final Map<SnowState, double> probabilities;
}

/// Брод.
class Ford {
  const Ford({required this.distanceM, required this.confirmed, this.widthM});

  final double distanceM;

  /// `true` — OSM `ford=yes`/`highway=ford`; `false` — возможный брод.
  final bool confirmed;
  final double? widthM;
}

/// Полный результат расчёта окружения. В таблицу сохраняются только
/// [settings], остальное пересчитывается при загрузке.
class EnvironmentData {
  const EnvironmentData({
    required this.settings,
    this.weather = const [],
    this.surface = const [],
    this.settlements = const [],
    this.snow = const [],
    this.fords = const [],
    this.surfaceCoverage = 0,
    this.rasterCoverage = 0,
    this.hasForecast = false,
    this.warning,
  });

  final EnvironmentSettings settings;
  final List<WeatherSample> weather;
  final List<SurfaceRun> surface;
  final List<SettlementRun> settlements;
  final List<SnowEstimate> snow;
  final List<Ford> fords;

  /// Доля точек, для которых нашёлся путь OSM.
  final double surfaceCoverage;

  /// Доля точек, где тип покрытия уточнён растром (WorldCover).
  final double rasterCoverage;

  /// `false` — прогноза нет, погодную полосу не рисуем.
  final bool hasForecast;
  final String? warning;

  /// Участок покрытия, содержащий [distanceM], или ближайший.
  SurfaceRun? runAt(double distanceM) {
    if (surface.isEmpty) return null;
    for (final run in surface) {
      if (distanceM >= run.startM && distanceM <= run.endM) return run;
    }
    SurfaceRun? best;
    var bestDelta = double.infinity;
    for (final run in surface) {
      final delta = distanceM < run.startM
          ? run.startM - distanceM
          : distanceM - run.endM;
      if (delta < bestDelta) {
        best = run;
        bestDelta = delta;
      }
    }
    return best;
  }

  /// Итоговый множитель окружения на расстоянии [distanceM].
  ///
  /// За пределами покрытого трека возвращается 1.00: неполный (DNF) трек
  /// не экстраполируется на оставшуюся дистанцию.
  double factorAt(double distanceM) {
    if (surface.isEmpty) return 1.0;
    if (distanceM < surface.first.startM || distanceM > surface.last.endM) {
      return 1.0;
    }
    return runAt(distanceM)?.factor ?? 1.0;
  }

  /// Средний множитель на отрезке `[startM, endM]`, взвешенный по длине.
  /// Если отрезок не пересекается с покрытым треком — 1.00.
  double factorBetween(double startM, double endM) {
    if (surface.isEmpty || endM <= startM) return 1.0;
    var weighted = 0.0;
    var covered = 0.0;
    for (final run in surface) {
      final from = run.startM > startM ? run.startM : startM;
      final to = run.endM < endM ? run.endM : endM;
      if (to <= from) continue;
      weighted += run.factor * (to - from);
      covered += to - from;
    }
    if (covered <= 0) return 1.0;
    return weighted / covered;
  }

  /// Есть ли что сохранять в кэш окружения. Пустой результат (например,
  /// ошибка сети без единого ответа) кэшировать нельзя: иначе экран будет
  /// считать, что сеть уже отвечала. Растр тоже считается результатом:
  /// при недоступном OSM он может дать покрытие.
  bool get hasContent =>
      weather.isNotEmpty || surfaceCoverage > 0 || rasterCoverage > 0;

  /// JSON для кэша между переключениями дистанций и перезапусками.
  Map<String, dynamic> toJson() => {
    'settings': settings.toJson(),
    'weather': [for (final sample in weather) _weatherToJson(sample)],
    'surface': [for (final run in surface) _runToJson(run)],
    'settlements': [
      for (final run in settlements)
        {
          'startM': run.startM,
          'endM': run.endM,
          'context': run.context.name,
          'urbanity': run.urbanity,
          'confidence': run.confidence,
        },
    ],
    'snow': [
      for (final estimate in snow)
        {
          'startM': estimate.startM,
          'endM': estimate.endM,
          'effectiveDepthM': estimate.effectiveDepthM,
          'probabilities': {
            for (final entry in estimate.probabilities.entries)
              entry.key.name: entry.value,
          },
        },
    ],
    'fords': [
      for (final ford in fords)
        {
          'distanceM': ford.distanceM,
          'confirmed': ford.confirmed,
          if (ford.widthM != null) 'widthM': ford.widthM,
        },
    ],
    'surfaceCoverage': surfaceCoverage,
    'rasterCoverage': rasterCoverage,
    'hasForecast': hasForecast,
    if (warning != null) 'warning': warning,
  };

  /// Восстанавливает сохранённое окружение. Повреждённые записи не роняют
  /// экран: возвращается `null`, и данные будут пересчитаны из сети.
  static EnvironmentData? tryFromJson(dynamic raw) {
    if (raw is! Map) return null;
    final rawSettings = raw['settings'];
    if (rawSettings is! Map) return null;

    final weather = <WeatherSample>[];
    final rawWeather = raw['weather'];
    if (rawWeather is List) {
      for (final item in rawWeather) {
        final sample = _weatherFromJson(item);
        if (sample != null) weather.add(sample);
      }
    }

    final surface = <SurfaceRun>[];
    final rawSurface = raw['surface'];
    if (rawSurface is List) {
      for (final item in rawSurface) {
        final run = _runFromJson(item);
        if (run != null) surface.add(run);
      }
    }

    final settlements = <SettlementRun>[];
    final rawSettlements = raw['settlements'];
    if (rawSettlements is List) {
      for (final item in rawSettlements) {
        final run = _settlementFromJson(item);
        if (run != null) settlements.add(run);
      }
    }

    final snow = <SnowEstimate>[];
    final rawSnow = raw['snow'];
    if (rawSnow is List) {
      for (final item in rawSnow) {
        final estimate = _snowFromJson(item);
        if (estimate != null) snow.add(estimate);
      }
    }

    final fords = <Ford>[];
    final rawFords = raw['fords'];
    if (rawFords is List) {
      for (final item in rawFords) {
        final ford = _fordFromJson(item);
        if (ford != null) fords.add(ford);
      }
    }

    return EnvironmentData(
      settings: EnvironmentSettings.tryFromJson(rawSettings),
      weather: weather,
      surface: surface,
      settlements: settlements,
      snow: snow,
      fords: fords,
      surfaceCoverage: _readDouble(raw['surfaceCoverage']),
      rasterCoverage: _readDouble(raw['rasterCoverage']),
      hasForecast: raw['hasForecast'] == true,
      warning: raw['warning'] is String ? raw['warning'] as String : null,
    );
  }

  static Map<String, dynamic> _weatherToJson(WeatherSample sample) => {
    'distanceM': sample.distanceM,
    'timeUtcMs': sample.timeUtc.millisecondsSinceEpoch,
    'lat': sample.lat,
    'lon': sample.lon,
    'elevationM': sample.elevationM,
    'tempC': sample.tempC,
    'apparentC': sample.apparentC,
    'humidityPct': sample.humidityPct,
    'precipMm': sample.precipMm,
    'rainMm': sample.rainMm,
    'et0Mm': sample.et0Mm,
    'windKmh': sample.windKmh,
    'snowfallCm': sample.snowfallCm,
    'snowDepthM': sample.snowDepthM,
    'soilMoistureTop': sample.soilMoistureTop,
    'soilMoistureDeep': sample.soilMoistureDeep,
    'soilMoistureEff': sample.soilMoistureEff,
    if (sample.freezingLevelM != null) 'freezingLevelM': sample.freezingLevelM,
    'mode': sample.mode.name,
    'avgTemp5C': sample.avgTemp5C,
    'frozenDays': sample.frozenDays,
  };

  static WeatherSample? _weatherFromJson(dynamic raw) {
    if (raw is! Map) return null;
    final timeMs = raw['timeUtcMs'];
    final mode = _readEnum(WeatherMode.values, raw['mode']);
    if (timeMs is! num || !timeMs.isFinite || mode == null) return null;
    return WeatherSample(
      distanceM: _readDouble(raw['distanceM']),
      timeUtc: DateTime.fromMillisecondsSinceEpoch(timeMs.round(), isUtc: true),
      lat: _readDouble(raw['lat']),
      lon: _readDouble(raw['lon']),
      elevationM: _readDouble(raw['elevationM']),
      tempC: _readDouble(raw['tempC']),
      apparentC: _readDouble(raw['apparentC']),
      humidityPct: _readDouble(raw['humidityPct']),
      precipMm: _readDouble(raw['precipMm']),
      rainMm: _readDouble(raw['rainMm']),
      et0Mm: _readDouble(raw['et0Mm']),
      windKmh: _readDouble(raw['windKmh']),
      snowfallCm: _readDouble(raw['snowfallCm']),
      snowDepthM: _readDouble(raw['snowDepthM']),
      soilMoistureTop: _readDouble(raw['soilMoistureTop']),
      soilMoistureDeep: _readDouble(raw['soilMoistureDeep']),
      soilMoistureEff: _readDouble(raw['soilMoistureEff']),
      freezingLevelM: raw['freezingLevelM'] is num
          ? _readDouble(raw['freezingLevelM'])
          : null,
      mode: mode,
      avgTemp5C: _readDouble(raw['avgTemp5C']),
      frozenDays: _readInt(raw['frozenDays']),
    );
  }

  static Map<String, dynamic> _runToJson(SurfaceRun run) => {
    'startM': run.startM,
    'endM': run.endM,
    'type': run.type.name,
    'wetness': run.wetness.name,
    'confidence': run.confidence,
    'isBog': run.isBog,
    if (run.bogKind != null) 'bogKind': run.bogKind,
    'bogFactor': run.bogFactor,
    'bogConfidence': run.bogConfidence,
    'surfaceSource': run.surfaceSource,
    'urbanity': run.urbanity,
    'roadClass': run.roadClass.name,
    'isFord': run.isFord,
    'factor': run.factor,
    'heatFactor': run.heatFactor,
    'snowFactor': run.snowFactor,
    'shoeFactor': run.shoeFactor,
  };

  static SurfaceRun? _runFromJson(dynamic raw) {
    if (raw is! Map) return null;
    final start = _readDouble(raw['startM'], double.nan);
    final end = _readDouble(raw['endM'], double.nan);
    if (!start.isFinite || !end.isFinite || end < start) return null;
    return SurfaceRun(
      startM: start,
      endM: end,
      type: _readEnum(SurfaceType.values, raw['type']) ?? SurfaceType.unknown,
      wetness: _readEnum(Wetness.values, raw['wetness']) ?? Wetness.dry,
      confidence: _readDouble(raw['confidence']),
      isBog: raw['isBog'] == true,
      bogKind: raw['bogKind'] is String ? raw['bogKind'] as String : null,
      bogFactor: _readDouble(raw['bogFactor'], 1),
      bogConfidence: _readDouble(raw['bogConfidence'], 1),
      surfaceSource: raw['surfaceSource'] is String
          ? raw['surfaceSource'] as String
          : 'default',
      urbanity: _readDouble(raw['urbanity']),
      roadClass:
          _readEnum(RoadClass.values, raw['roadClass']) ?? RoadClass.unpaved,
      isFord: raw['isFord'] == true,
      factor: _readDouble(raw['factor'], 1),
      heatFactor: _readDouble(raw['heatFactor'], 1),
      snowFactor: _readDouble(raw['snowFactor'], 1),
      shoeFactor: _readDouble(raw['shoeFactor'], 1),
    );
  }

  static SettlementRun? _settlementFromJson(dynamic raw) {
    if (raw is! Map) return null;
    final start = _readDouble(raw['startM'], double.nan);
    final end = _readDouble(raw['endM'], double.nan);
    final context = _readEnum(SettlementContext.values, raw['context']);
    if (!start.isFinite || !end.isFinite || end < start || context == null) {
      return null;
    }
    return SettlementRun(
      startM: start,
      endM: end,
      context: context,
      urbanity: _readDouble(raw['urbanity']),
      confidence: _readDouble(raw['confidence']),
    );
  }

  static SnowEstimate? _snowFromJson(dynamic raw) {
    if (raw is! Map) return null;
    final start = _readDouble(raw['startM'], double.nan);
    final end = _readDouble(raw['endM'], double.nan);
    if (!start.isFinite || !end.isFinite || end < start) return null;
    final probabilities = <SnowState, double>{};
    final rawProbabilities = raw['probabilities'];
    if (rawProbabilities is Map) {
      for (final entry in rawProbabilities.entries) {
        final state = _readEnum(SnowState.values, entry.key);
        if (state == null || entry.value is! num) continue;
        probabilities[state] = _readDouble(entry.value);
      }
    }
    if (probabilities.isEmpty) return null;
    return SnowEstimate(
      startM: start,
      endM: end,
      effectiveDepthM: _readDouble(raw['effectiveDepthM']),
      probabilities: probabilities,
    );
  }

  static Ford? _fordFromJson(dynamic raw) {
    if (raw is! Map) return null;
    final distance = _readDouble(raw['distanceM'], double.nan);
    if (!distance.isFinite) return null;
    return Ford(
      distanceM: distance,
      confirmed: raw['confirmed'] == true,
      widthM: raw['widthM'] is num ? _readDouble(raw['widthM']) : null,
    );
  }

  static double _readDouble(dynamic value, [double fallback = 0]) =>
      value is num && value.isFinite ? value.toDouble() : fallback;

  static int _readInt(dynamic value, [int fallback = 0]) =>
      value is num && value.isFinite ? value.round() : fallback;

  static T? _readEnum<T extends Enum>(List<T> values, dynamic raw) {
    if (raw is! String) return null;
    for (final value in values) {
      if (value.name == raw) return value;
    }
    return null;
  }
}
