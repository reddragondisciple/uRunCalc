/// Резервный источник погоды: NASA POWER.
///
/// Open-Meteo отдаёт прогноз, архив и нормы одним набором переменных. NASA
/// POWER не умеет прогноз, зато бесплатно и без ключа отдаёт суточные данные
/// и климатологию. Поэтому провайдер используется только для исторической
/// погоды и норм; прогноз остаётся за Open-Meteo, чтобы не подменять
/// семантику «на завтра».
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'environment_data.dart';
import 'environment_factors.dart';
import 'environment_sampling.dart';
import 'factor_profile.dart';
import 'weather_provider.dart';

/// NASA POWER: суточная история и месячная климатология.
class NasaPowerProvider implements WeatherProvider {
  NasaPowerProvider({
    http.Client? client,
    DateTime Function()? now,
    this.dailyUrl = 'https://power.larc.nasa.gov/api/temporal/daily/point',
    this.climatologyUrl =
        'https://power.larc.nasa.gov/api/temporal/climatology/point',
    this.timeout = const Duration(seconds: 25),
    this.totalBudget = const Duration(seconds: 45),
    this.cellDegrees = 0.5,
  }) : _client = client ?? http.Client(),
       _now = now ?? DateTime.now;

  final http.Client _client;
  final DateTime Function() _now;
  final String dailyUrl;
  final String climatologyUrl;
  final Duration timeout;
  final Duration totalBudget;

  /// NASA POWER — сетка около 0,5°. Запросы группируются по ячейкам, чтобы
  /// трек на 100 км не порождал десятки одинаковых запросов.
  final double cellDegrees;

  static const String _parameters =
      'T2M,RH2M,WS2M,PRECTOTCORR,GWETTOP,GWETROOT';

  static const List<String> _months = [
    'JAN',
    'FEB',
    'MAR',
    'APR',
    'MAY',
    'JUN',
    'JUL',
    'AUG',
    'SEP',
    'OCT',
    'NOV',
    'DEC',
  ];

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
        .map((query) => query.timeUtc)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    final latest = queries
        .map((query) => query.timeUtc)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    final mode = _modeFor(earliest);
    if (mode == WeatherMode.forecast) {
      throw const WeatherException('NASA POWER не даёт прогноз погоды');
    }

    final cells = <String, List<WeatherQuery>>{};
    for (final query in queries) {
      cells.putIfAbsent(_cellKey(query.point), () => []).add(query);
    }

    final deadline = DateTime.now().add(totalBudget);
    final samples = <WeatherSample>[];
    String? warning;
    for (final entry in cells.entries) {
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        warning = samples.isEmpty
            ? 'NASA POWER: превышен лимит времени'
            : 'NASA POWER: часть точек без данных (лимит времени)';
        break;
      }
      try {
        final point = entry.value.first.point;
        final data = mode == WeatherMode.normals
            ? await _fetchClimatology(point, remaining)
            : await _fetchDaily(point, earliest, latest, remaining);
        for (final query in entry.value) {
          samples.add(_sample(query, data, mode));
        }
      } catch (error) {
        // Первая ячейка не загрузилась — пусть сервис покажет ошибку.
        // Если часть данных уже есть, отдаём её с предупреждением.
        if (samples.isEmpty) rethrow;
        warning = 'NASA POWER: часть точек без данных';
        break;
      }
    }

    if (samples.isEmpty) {
      throw const WeatherException('NASA POWER не вернул погоду');
    }

    return WeatherFetchResult(
      samples: samples,
      mode: mode,
      hasWeatherBand: mode != WeatherMode.normals,
      warning:
          warning ??
          (mode == WeatherMode.normals
              ? 'Прогноза нет: климатические нормы NASA POWER'
              : 'Историческая погода NASA POWER'),
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

  String _cellKey(WeatherSamplePoint point) {
    final lat = (point.lat / cellDegrees).floor();
    final lon = (point.lon / cellDegrees).floor();
    return '$lat:$lon';
  }

  Future<_NasaCellData> _fetchDaily(
    WeatherSamplePoint point,
    DateTime earliest,
    DateTime latest,
    Duration budget,
  ) async {
    final from = earliest.subtract(const Duration(days: 6));
    final uri = Uri.parse(dailyUrl).replace(
      queryParameters: {
        'parameters': _parameters,
        'community': 'RE',
        'longitude': point.lon.toStringAsFixed(5),
        'latitude': point.lat.toStringAsFixed(5),
        'start': _date(from),
        'end': _date(latest),
        'format': 'JSON',
      },
    );
    return _request(uri, budget);
  }

  Future<_NasaCellData> _fetchClimatology(
    WeatherSamplePoint point,
    Duration budget,
  ) async {
    final uri = Uri.parse(climatologyUrl).replace(
      queryParameters: {
        'parameters': _parameters,
        'community': 'RE',
        'longitude': point.lon.toStringAsFixed(5),
        'latitude': point.lat.toStringAsFixed(5),
        'format': 'JSON',
      },
    );
    return _request(uri, budget);
  }

  Future<_NasaCellData> _request(Uri uri, Duration budget) async {
    final response = await _client
        .get(uri)
        .timeout(budget < timeout ? budget : timeout);
    if (response.statusCode != 200) {
      throw WeatherException(
        'NASA POWER вернул ${response.statusCode}: ${response.body}',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw const WeatherException('NASA POWER вернул не JSON');
    }
    final properties = decoded['properties'];
    final parameters = properties is Map ? properties['parameter'] : null;
    if (parameters is! Map) {
      throw const WeatherException('В ответе NASA POWER нет parameter');
    }
    double? elevation;
    final geometry = decoded['geometry'];
    if (geometry is Map) {
      final coordinates = geometry['coordinates'];
      if (coordinates is List && coordinates.length >= 3) {
        final value = coordinates[2];
        if (value is num && value.isFinite) elevation = value.toDouble();
      }
    }
    return _NasaCellData(parameters: parameters, elevationM: elevation);
  }

  WeatherSample _sample(
    WeatherQuery query,
    _NasaCellData data,
    WeatherMode mode,
  ) {
    final temp = _valueAt(
      data.parameters['T2M'],
      query.timeUtc,
      mode,
      fallback: 0,
    );
    final humidity = _valueAt(
      data.parameters['RH2M'],
      query.timeUtc,
      mode,
      fallback: 70,
    );
    final windMs = _valueAt(
      data.parameters['WS2M'],
      query.timeUtc,
      mode,
      fallback: 0,
    );
    final precip = _valueAt(
      data.parameters['PRECTOTCORR'],
      query.timeUtc,
      mode,
      fallback: 0,
    );
    final soilTop = _valueAt(
      data.parameters['GWETTOP'],
      query.timeUtc,
      mode,
      fallback: 0.3,
    );
    final soilDeep = _valueAt(
      data.parameters['GWETROOT'],
      query.timeUtc,
      mode,
      fallback: soilTop,
    );
    final avgTemp5 = mode == WeatherMode.normals
        ? temp
        : _averageBefore(
            data.parameters['T2M'],
            query.timeUtc,
            days: 5,
            fallback: temp,
          );
    final frozenDays = mode == WeatherMode.normals
        ? (temp < 0 ? 7 : 0)
        : _frozenDaysBefore(data.parameters['T2M'], query.timeUtc, days: 7);

    return WeatherSample(
      distanceM: query.point.distanceM,
      timeUtc: query.timeUtc,
      lat: query.point.lat,
      lon: query.point.lon,
      elevationM: query.point.elevationM,
      tempC: temp,
      // NASA POWER не отдаёт «ощущается как»; суточная T2M — единственная
      // сопоставимая величина, поэтому heatFactor считаем по ней.
      apparentC: temp,
      humidityPct: humidity,
      precipMm: precip,
      rainMm: temp > 0 ? precip : 0,
      et0Mm: 0,
      windKmh: windMs * 3.6,
      snowfallCm: 0,
      snowDepthM: 0,
      soilMoistureTop: soilTop,
      soilMoistureDeep: soilDeep,
      soilMoistureEff: (soilTop + soilDeep) / 2,
      freezingLevelM: estimateFreezingLevelM(
        elevationM: query.point.elevationM,
        tempC: temp,
      ),
      mode: mode,
      avgTemp5C: avgTemp5,
      frozenDays: frozenDays,
    );
  }

  /// Значение для даты (история) или месяца (нормы).
  static double _valueAt(
    dynamic raw,
    DateTime date,
    WeatherMode mode, {
    required double fallback,
  }) {
    if (raw is! Map) return fallback;
    if (mode == WeatherMode.normals) {
      return _read(raw[_months[date.month - 1]], fallback);
    }
    final exact = _read(raw[_date(date)], double.nan);
    if (exact.isFinite) return exact;

    // Суточные данные могут отставать на 1–2 дня. Берём ближайшую дату,
    // чтобы исторический расчёт не остался без температуры.
    final target = DateTime.utc(date.year, date.month, date.day);
    DateTime? bestDate;
    var bestDelta = 1 << 30;
    double? bestValue;
    for (final entry in raw.entries) {
      final key = entry.key;
      if (key is! String) continue;
      final parsed = _parseDate(key);
      if (parsed == null) continue;
      final value = _read(entry.value, double.nan);
      if (!value.isFinite) continue;
      final delta = parsed.difference(target).inDays.abs();
      if (delta < bestDelta) {
        bestDelta = delta;
        bestDate = parsed;
        bestValue = value;
      }
    }
    if (bestDate == null || bestValue == null || bestDelta > 3) {
      return fallback;
    }
    return bestValue;
  }

  static double _averageBefore(
    dynamic raw,
    DateTime date, {
    required int days,
    required double fallback,
  }) {
    if (raw is! Map) return fallback;
    final target = DateTime.utc(date.year, date.month, date.day);
    var sum = 0.0;
    var count = 0;
    for (final entry in raw.entries) {
      final key = entry.key;
      if (key is! String) continue;
      final parsed = _parseDate(key);
      if (parsed == null) continue;
      final delta = target.difference(parsed).inDays;
      if (delta < 0 || delta >= days) continue;
      final value = _read(entry.value, double.nan);
      if (!value.isFinite) continue;
      sum += value;
      count++;
    }
    return count == 0 ? fallback : sum / count;
  }

  static int _frozenDaysBefore(
    dynamic raw,
    DateTime date, {
    required int days,
  }) {
    if (raw is! Map) return 0;
    final target = DateTime.utc(date.year, date.month, date.day);
    var count = 0;
    for (final entry in raw.entries) {
      final key = entry.key;
      if (key is! String) continue;
      final parsed = _parseDate(key);
      if (parsed == null) continue;
      final delta = target.difference(parsed).inDays;
      if (delta < 0 || delta >= days) continue;
      final value = _read(entry.value, double.nan);
      if (value.isFinite && value < 0) count++;
    }
    return count;
  }

  static double _read(dynamic raw, double fallback) {
    if (raw is! num || !raw.isFinite) return fallback;
    final value = raw.toDouble();
    // NASA POWER помечает пропуски большими отрицательными числами.
    if (value <= -900) return fallback;
    return value;
  }

  static String _date(DateTime date) {
    final utc = date.toUtc();
    final month = utc.month.toString().padLeft(2, '0');
    final day = utc.day.toString().padLeft(2, '0');
    return '${utc.year}$month$day';
  }

  static DateTime? _parseDate(String value) {
    if (value.length != 8) return null;
    final year = int.tryParse(value.substring(0, 4));
    final month = int.tryParse(value.substring(4, 6));
    final day = int.tryParse(value.substring(6, 8));
    if (year == null || month == null || day == null) return null;
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    return DateTime.utc(year, month, day);
  }
}

class _NasaCellData {
  const _NasaCellData({required this.parameters, this.elevationM});

  final Map<dynamic, dynamic> parameters;
  final double? elevationM;
}
