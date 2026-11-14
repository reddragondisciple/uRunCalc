/// Погодный провайдер с резервным источником.
///
/// Основной источник — Open-Meteo. Если он недоступен и речь идёт об
/// исторической погоде или климатических нормах, пробуем NASA POWER.
/// Прогноз намеренно не подменяем: «завтра» должно оставаться прогнозом,
/// а не климатологией.
library;

import 'environment_data.dart';
import 'factor_profile.dart';
import 'weather_provider.dart';

class FallbackWeatherProvider implements WeatherProvider {
  FallbackWeatherProvider({
    required this.primary,
    required this.fallback,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final WeatherProvider primary;
  final WeatherProvider fallback;
  final DateTime Function() _now;

  @override
  Future<WeatherFetchResult> fetch({
    required List<WeatherQuery> queries,
    required FactorProfile profile,
  }) async {
    if (queries.isEmpty) {
      return primary.fetch(queries: queries, profile: profile);
    }

    final earliest = queries
        .map((query) => query.timeUtc)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    final mode = _modeFor(earliest);

    WeatherFetchResult? primaryResult;
    Object? primaryError;
    try {
      primaryResult = await primary.fetch(queries: queries, profile: profile);
    } catch (error) {
      primaryError = error;
    }

    // Для прогноза резерва нет: NASA POWER прогноз не отдаёт.
    if (mode == WeatherMode.forecast) {
      if (primaryError != null) throw primaryError;
      return primaryResult!;
    }
    // Основной источник ответил непустыми данными — резерв не нужен.
    if (primaryResult != null && primaryResult.samples.isNotEmpty) {
      return primaryResult;
    }

    try {
      final result = await fallback.fetch(queries: queries, profile: profile);
      final prefix = primaryError == null
          ? 'Open-Meteo не вернул данные, использован NASA POWER'
          : 'Open-Meteo недоступен, использован NASA POWER';
      return WeatherFetchResult(
        samples: result.samples,
        mode: result.mode,
        hasWeatherBand: result.hasWeatherBand,
        warning: result.warning == null ? prefix : '$prefix: ${result.warning}',
      );
    } catch (fallbackError) {
      if (primaryError != null) {
        throw WeatherException(
          'Open-Meteo и NASA POWER недоступны: $primaryError; $fallbackError',
        );
      }
      throw WeatherException('NASA POWER недоступен: $fallbackError');
    }
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
}
