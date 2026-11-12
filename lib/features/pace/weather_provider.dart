/// Провайдер погоды: Open-Meteo forecast / archive / normals.
///
/// Сеть изолирована за [WeatherProvider], чтобы позже подставить прокси или
/// кэш без изменения расчёта (docs/environment-conditions.md §5.1).
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import 'environment_data.dart';
import 'environment_factors.dart';
import 'environment_sampling.dart';
import 'factor_profile.dart';

/// Горизонт прогноза Open-Meteo в днях. Дальше отдаём климатические нормы.
const int forecastHorizonDays = 16;

/// Дата [date] дальше окна прогноза?
///
/// Сравниваются календарные дни, а не точное время: прогноз задаётся датой,
/// поэтому «через 16 дней и 20 часов» — это уже 17-е сутки без прогноза.
bool beyondForecastWindow(DateTime date, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final today = DateTime(current.year, current.month, current.day);
  final day = DateTime(date.year, date.month, date.day);
  return day.difference(today).inDays > forecastHorizonDays;
}

/// Запрос погоды для одной точки трека.
class WeatherQuery {
  const WeatherQuery({required this.point, required this.timeUtc});

  final WeatherSamplePoint point;
  final DateTime timeUtc;
}

/// Результат запроса погоды.
class WeatherFetchResult {
  const WeatherFetchResult({
    required this.samples,
    required this.mode,
    required this.hasWeatherBand,
    this.warning,
  });

  final List<WeatherSample> samples;
  final WeatherMode mode;

  /// `false` — только нормы, погодную полосу не рисуем.
  final bool hasWeatherBand;
  final String? warning;
}

/// Контракт провайдера погоды.
abstract class WeatherProvider {
  Future<WeatherFetchResult> fetch({
    required List<WeatherQuery> queries,
    required FactorProfile profile,
  });
}

/// Open-Meteo: бесплатный для некоммерческого использования.
class OpenMeteoProvider implements WeatherProvider {
  OpenMeteoProvider({
    http.Client? client,
    DateTime Function()? now,
    this.forecastUrl = 'https://api.open-meteo.com/v1/forecast',
    this.archiveUrl = 'https://archive-api.open-meteo.com/v1/archive',
    this.chunkSize = 20,
  }) : _client = client ?? http.Client(),
       _now = now ?? DateTime.now;

  final http.Client _client;
  final DateTime Function() _now;
  final String forecastUrl;
  final String archiveUrl;
  final int chunkSize;

  static final String _hourlyVariables = [
    'temperature_2m',
    'apparent_temperature',
    'relative_humidity_2m',
    'precipitation',
    'rain',
    'snowfall',
    'wind_speed_10m',
    'snow_depth',
    'soil_moisture_0_to_7cm',
    'soil_moisture_7_to_28cm',
    'et0_fao_evapotranspiration',
    'freezing_level_height',
  ].join(',');

  @override
  Future<WeatherFetchResult> fetch({
    required List<WeatherQuery> queries,
    required FactorProfile profile,
  }) async {
    if (queries.isEmpty) {
      return const WeatherFetchResult(
        samples: [],
        mode: WeatherMode.historical,
        hasWeatherBand: false,
        warning: 'Нет точек для запроса погоды',
      );
    }

    final earliest = queries
        .map((q) => q.timeUtc)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    final latest = queries
        .map((q) => q.timeUtc)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    final mode = _modeFor(earliest);

    final samples = <WeatherSample>[];
    for (var from = 0; from < queries.length; from += chunkSize) {
      final chunk = queries.sublist(
        from,
        math.min(from + chunkSize, queries.length),
      );
      final chunkSamples = await _fetchChunk(
        chunk: chunk,
        mode: mode,
        earliest: earliest,
        latest: latest,
        profile: profile,
      );
      samples.addAll(chunkSamples);
    }

    return WeatherFetchResult(
      samples: samples,
      mode: mode,
      hasWeatherBand: mode != WeatherMode.normals,
      warning: switch (mode) {
        WeatherMode.normals => 'Прогноза нет: показаны климатические нормы',
        WeatherMode.historical => 'Историческая погода из архива',
        WeatherMode.forecast => null,
      },
    );
  }

  WeatherMode _modeFor(DateTime startUtc) {
    final now = _now().toUtc();
    if (startUtc.isBefore(now.subtract(const Duration(days: 1)))) {
      return WeatherMode.historical;
    }
    if (beyondForecastWindow(startUtc, now: now)) {
      return WeatherMode.normals;
    }
    return WeatherMode.forecast;
  }

  Future<List<WeatherSample>> _fetchChunk({
    required List<WeatherQuery> chunk,
    required WeatherMode mode,
    required DateTime earliest,
    required DateTime latest,
    required FactorProfile profile,
  }) async {
    // Для норм сдвигаем даты на год назад: архив не знает будущее.
    final shiftYears = mode == WeatherMode.normals ? 1 : 0;
    final from = _shiftYears(
      earliest.subtract(const Duration(days: 4)),
      shiftYears,
    );
    final to = _shiftYears(latest.add(const Duration(days: 1)), shiftYears);

    final url = mode == WeatherMode.forecast ? forecastUrl : archiveUrl;
    final uri = Uri.parse(url).replace(
      queryParameters: {
        'latitude': chunk.map((q) => q.point.lat.toStringAsFixed(5)).join(','),
        'longitude': chunk.map((q) => q.point.lon.toStringAsFixed(5)).join(','),
        'elevation': chunk
            .map((q) => q.point.elevationM.round().toString())
            .join(','),
        'start_date': _date(from),
        'end_date': _date(to),
        'hourly': _hourlyVariables,
        'timezone': 'UTC',
        'wind_speed_unit': 'kmh',
      },
    );

    final response = await _client.get(uri);
    if (response.statusCode != 200) {
      throw WeatherException(
        'Open-Meteo вернул ${response.statusCode}: ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    final items = decoded is List ? decoded : [decoded];
    if (items.length < chunk.length) {
      throw const WeatherException('Open-Meteo вернул меньше точек, чем нужно');
    }

    final result = <WeatherSample>[];
    for (var i = 0; i < chunk.length; i++) {
      final item = items[i];
      if (item is! Map) continue;
      final query = chunk[i];
      // Время сэмпла — запрошенная дата гонки. В архив уходит дата,
      // сдвинутая на год назад, но пользователю показываем его год.
      result.add(
        _sampleFromJson(item, query.point, query.timeUtc, mode, profile),
      );
    }
    return result;
  }

  WeatherSample _sampleFromJson(
    Map<dynamic, dynamic> item,
    WeatherSamplePoint point,
    DateTime timeUtc,
    WeatherMode mode,
    FactorProfile profile,
  ) {
    final hourly = item['hourly'];
    if (hourly is! Map) {
      throw const WeatherException('В ответе нет почасовых данных');
    }
    final times = _list(hourly['time']);
    if (times.isEmpty) {
      throw const WeatherException('В ответе нет времени');
    }
    final parsedTimes = [for (final raw in times) _parseUtc('$raw')];
    final index = _nearestHourIndex(parsedTimes, timeUtc);

    double value(String key) => _valueAt(hourly[key], index);
    double sum(String key, int hours) {
      final values = _list(hourly[key]);
      var total = 0.0;
      for (var i = math.max(0, index - hours); i < index; i++) {
        total += _valueAt(values, i);
      }
      return total;
    }

    final temp = value('temperature_2m');
    final rain12 = sum('rain', 12);
    final et012 = sum('et0_fao_evapotranspiration', 12);
    final rain72 = sum('rain', 72);
    final et072 = sum('et0_fao_evapotranspiration', 72);
    final net72 = rain72 - 0.6 * et072;
    final meltwater72 = _meltwater(hourly, index, temp);

    final smTop = value('soil_moisture_0_to_7cm');
    final smDeep = value('soil_moisture_7_to_28cm');
    final soilMissing =
        _isMissing(_list(hourly['soil_moisture_0_to_7cm']), index) ||
        _isMissing(_list(hourly['soil_moisture_7_to_28cm']), index);
    final fallbackSoil = _fallbackSoilFromRain(rain72);
    final smEff = soilMissing
        ? fallbackSoil
        : soilMoistureEffective(
            smTop: smTop,
            smDeep: smDeep,
            rain12: rain12,
            et012: et012,
            net72: net72,
            meltwater72: meltwater72,
            profile: profile,
          );

    final temps = _list(hourly['temperature_2m']);
    final avgTemp5 = _average(temps, index, 120);
    final frozenDays = _frozenDays(temps, index, 168);

    final freezingRaw = _list(hourly['freezing_level_height']);
    final freezingValue = _valueAt(freezingRaw, index);
    final freezingLevel = _isMissing(freezingRaw, index)
        ? estimateFreezingLevelM(elevationM: point.elevationM, tempC: temp)
        : freezingValue;

    return WeatherSample(
      distanceM: point.distanceM,
      timeUtc: timeUtc,
      lat: point.lat,
      lon: point.lon,
      elevationM: point.elevationM,
      tempC: temp,
      apparentC: value('apparent_temperature'),
      humidityPct: value('relative_humidity_2m'),
      precipMm: value('precipitation'),
      rainMm: value('rain'),
      et0Mm: value('et0_fao_evapotranspiration'),
      windKmh: value('wind_speed_10m'),
      snowfallCm: value('snowfall'),
      snowDepthM: value('snow_depth'),
      soilMoistureTop: smTop,
      soilMoistureDeep: smDeep,
      soilMoistureEff: smEff,
      freezingLevelM: freezingLevel,
      mode: mode,
      avgTemp5C: avgTemp5,
      frozenDays: frozenDays,
    );
  }

  /// Fallback влажности почвы по осадкам за 72 ч, §5.4.
  static double _fallbackSoilFromRain(double rain72) {
    if (rain72 < 2) return 0.20;
    if (rain72 < 10) return 0.28;
    if (rain72 < 25) return 0.36;
    return 0.45;
  }

  static double _average(List<dynamic> values, int endIndex, int hours) {
    if (values.isEmpty) return 0;
    final from = math.max(0, endIndex - hours);
    var sum = 0.0;
    var count = 0;
    for (var i = from; i < endIndex && i < values.length; i++) {
      final value = values[i];
      if (value is num && value.isFinite) {
        sum += value;
        count++;
      }
    }
    return count == 0 ? 0 : sum / count;
  }

  /// Сколько суток из последних [hours] имели среднюю температуру ≤ −10 °C.
  static int _frozenDays(List<dynamic> temps, int endIndex, int hours) {
    if (temps.isEmpty) return 0;
    final from = math.max(0, endIndex - hours);
    var frozen = 0;
    for (var dayStart = from; dayStart < endIndex; dayStart += 24) {
      final dayEnd = math.min(dayStart + 24, endIndex);
      var sum = 0.0;
      var count = 0;
      for (var i = dayStart; i < dayEnd && i < temps.length; i++) {
        final value = temps[i];
        if (value is num && value.isFinite) {
          sum += value;
          count++;
        }
      }
      if (count > 0 && sum / count <= -10) frozen++;
    }
    return frozen;
  }

  /// Талая вода за 72 ч: падение глубины снега при плюсовой температуре.
  double _meltwater(HourlyMap hourly, int index, double tempC) {
    final depths = _list(hourly['snow_depth']);
    if (depths.isEmpty) return 0;
    var melt = 0.0;
    for (var i = math.max(1, index - 72); i <= index; i++) {
      final t = _valueAt(_list(hourly['temperature_2m']), i);
      if (t <= 0) continue;
      final before = _valueAt(depths, i - 1);
      final after = _valueAt(depths, i);
      final drop = before - after;
      if (drop > 0) melt += drop * 1000 * 0.3;
    }
    return melt;
  }

  static int _nearestHourIndex(List<DateTime> times, DateTime target) {
    var best = 0;
    var bestDelta = times[0].difference(target).inSeconds.abs();
    for (var i = 1; i < times.length; i++) {
      final delta = times[i].difference(target).inSeconds.abs();
      if (delta < bestDelta) {
        best = i;
        bestDelta = delta;
      }
    }
    return best;
  }

  static bool _isMissing(List<dynamic> values, int index) {
    if (values.isEmpty) return true;
    final value = values[math.min(index, values.length - 1)];
    return value == null;
  }

  static double _valueAt(dynamic raw, int index) {
    final values = _list(raw);
    if (values.isEmpty) return 0;
    final value = values[math.min(index, values.length - 1)];
    if (value is num && value.isFinite) return value.toDouble();
    return 0;
  }

  static List<dynamic> _list(dynamic raw) => raw is List ? raw : const [];

  static DateTime _shiftYears(DateTime time, int years) {
    if (years == 0) return time;
    final year = time.year - years;
    final day = math.min(time.day, _daysInMonth(year, time.month));
    return DateTime.utc(
      year,
      time.month,
      day,
      time.hour,
      time.minute,
      time.second,
    );
  }

  static int _daysInMonth(int year, int month) {
    return DateTime.utc(year, month + 1, 0).day;
  }

  static String _date(DateTime time) {
    final month = time.month.toString().padLeft(2, '0');
    final day = time.day.toString().padLeft(2, '0');
    return '${time.year}-$month-$day';
  }

  /// Open-Meteo с `timezone=UTC` отдаёт время без суффикса `Z`.
  static DateTime _parseUtc(String raw) {
    final hasZone = raw.endsWith('Z') || raw.contains('+');
    final parsed = DateTime.tryParse(hasZone ? raw : '${raw}Z');
    return (parsed ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true))
        .toUtc();
  }
}

/// Тип для читаемости `hourly` в разборе.
typedef HourlyMap = Map<dynamic, dynamic>;

/// Ошибка провайдера погоды.
class WeatherException implements Exception {
  const WeatherException(this.message);

  final String message;

  @override
  String toString() => message;
}
