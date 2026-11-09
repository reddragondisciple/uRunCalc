/// Один разряд и максимальное время для его получения.
class PaceNormativeCategory {
  const PaceNormativeCategory(this.name, this.maxSeconds);

  final String name;

  /// Верхняя граница времени в секундах: результат не медленнее этого
  /// значения соответствует разряду.
  final double maxSeconds;
}

/// Нормативы для одной дистанции отдельно для мужчин и женщин.
class PaceNormativeStandard {
  const PaceNormativeStandard({
    required this.distanceKm,
    required this.male,
    required this.female,
  });

  final double distanceKm;
  final List<PaceNormativeCategory> male;
  final List<PaceNormativeCategory> female;
}

/// Разряды, которые удалось выполнить на заданной дистанции.
class PaceNormativeResult {
  const PaceNormativeResult({this.male, this.female});

  final String? male;
  final String? female;

  bool get isEmpty => male == null && female == null;
}

/// Разрядные нормативы по бегу. Источник: таблицы «Бег по шоссе» и
/// «Бег на стадионе» (автохронометраж) с marathonec.ru, редакция 2026 года.
///
/// Для 5 и 10 км используются стадионные нормативы, для 15 км, полумарафона,
/// марафона и 100 км — шоссейные. Данные хранятся в коде, чтобы проверка
/// работала без сети и не зависела от доступности сайта.
class PaceNormatives {
  PaceNormatives._();

  /// Допуск при сопоставлении дистанции: 21.097 и 21.0975 должны считаться
  /// одной и той же дистанцией.
  static const double _distanceToleranceKm = 0.02;

  static const List<PaceNormativeStandard> _standards = [
    PaceNormativeStandard(
      distanceKm: 5,
      male: [
        PaceNormativeCategory('МСМК', 13 * 60 + 27.0),
        PaceNormativeCategory('МС', 14 * 60 + 6.0),
        PaceNormativeCategory('КМС', 14 * 60 + 50.24),
        PaceNormativeCategory('I', 15 * 60 + 55.24),
        PaceNormativeCategory('II', 17 * 60 + 0.24),
        PaceNormativeCategory('III', 18 * 60 + 5.24),
      ],
      female: [
        PaceNormativeCategory('МСМК', 15 * 60 + 20.24),
        PaceNormativeCategory('МС', 16 * 60 + 5.24),
        PaceNormativeCategory('КМС', 17 * 60 + 20.24),
        PaceNormativeCategory('I', 18 * 60 + 45.24),
        PaceNormativeCategory('II', 20 * 60 + 20.24),
        PaceNormativeCategory('III', 22 * 60 + 5.24),
      ],
    ),
    PaceNormativeStandard(
      distanceKm: 10,
      male: [
        PaceNormativeCategory('МСМК', 28 * 60 + 0.0),
        PaceNormativeCategory('МС', 29 * 60 + 20.0),
        PaceNormativeCategory('КМС', 31 * 60 + 10.24),
        PaceNormativeCategory('I', 33 * 60 + 20.24),
        PaceNormativeCategory('II', 35 * 60 + 50.24),
        PaceNormativeCategory('III', 38 * 60 + 40.24),
      ],
      female: [
        PaceNormativeCategory('МСМК', 31 * 60 + 50.24),
        PaceNormativeCategory('МС', 33 * 60 + 48.24),
        PaceNormativeCategory('КМС', 37 * 60 + 0.24),
        PaceNormativeCategory('I', 40 * 60 + 0.24),
        PaceNormativeCategory('II', 43 * 60 + 40.24),
        PaceNormativeCategory('III', 47 * 60 + 50.24),
      ],
    ),
    PaceNormativeStandard(
      distanceKm: 15,
      male: [
        PaceNormativeCategory('КМС', 49 * 60.0),
        PaceNormativeCategory('I', 52 * 60.0),
        PaceNormativeCategory('II', 56 * 60.0),
        PaceNormativeCategory('III', 60 * 60.0),
      ],
      female: [
        PaceNormativeCategory('КМС', 59 * 60.0),
        PaceNormativeCategory('I', 62 * 60.0),
        PaceNormativeCategory('II', 67 * 60.0),
        PaceNormativeCategory('III', 73 * 60.0),
      ],
    ),
    PaceNormativeStandard(
      distanceKm: 21.0975,
      male: [
        PaceNormativeCategory('МСМК', 61 * 60 + 30.0),
        PaceNormativeCategory('МС', 65 * 60.0),
        PaceNormativeCategory('КМС', 70 * 60 + 30.0),
        PaceNormativeCategory('I', 76 * 60.0),
        PaceNormativeCategory('II', 81 * 60 + 30.0),
        PaceNormativeCategory('III', 88 * 60.0),
      ],
      female: [
        PaceNormativeCategory('МСМК', 71 * 60.0),
        PaceNormativeCategory('МС', 75 * 60 + 40.0),
        PaceNormativeCategory('КМС', 85 * 60.0),
        PaceNormativeCategory('I', 94 * 60 + 30.0),
        PaceNormativeCategory('II', 104 * 60 + 30.0),
        PaceNormativeCategory('III', 115 * 60.0),
      ],
    ),
    PaceNormativeStandard(
      distanceKm: 42.195,
      male: [
        PaceNormativeCategory('МСМК', 132 * 60.0),
        PaceNormativeCategory('МС', 140 * 60.0),
        PaceNormativeCategory('КМС', 150 * 60.0),
        PaceNormativeCategory('I', 160 * 60.0),
        PaceNormativeCategory('II', 170 * 60.0),
        PaceNormativeCategory('III', 190 * 60.0),
      ],
      female: [
        PaceNormativeCategory('МСМК', 150 * 60.0),
        PaceNormativeCategory('МС', 160 * 60.0),
        PaceNormativeCategory('КМС', 180 * 60.0),
        PaceNormativeCategory('I', 202 * 60.0),
        PaceNormativeCategory('II', 228 * 60.0),
        PaceNormativeCategory('III', 250 * 60.0),
      ],
    ),
    PaceNormativeStandard(
      distanceKm: 100,
      male: [
        PaceNormativeCategory('МСМК', 399 * 60.0),
        PaceNormativeCategory('МС', 416 * 60.0),
        PaceNormativeCategory('КМС', 435 * 60.0),
        PaceNormativeCategory('I', 460 * 60.0),
        PaceNormativeCategory('II', 490 * 60.0),
        PaceNormativeCategory('III', 525 * 60.0),
      ],
      female: [
        PaceNormativeCategory('МСМК', 460 * 60.0),
        PaceNormativeCategory('МС', 480 * 60.0),
        PaceNormativeCategory('КМС', 505 * 60.0),
        PaceNormativeCategory('I', 535 * 60.0),
        PaceNormativeCategory('II', 570 * 60.0),
        PaceNormativeCategory('III', 610 * 60.0),
      ],
    ),
  ];

  /// Возвращает выполненные разряды или `null`, если дистанция не входит в
  /// таблицу либо время не соответствует даже III разряду.
  static PaceNormativeResult? lookup({
    required double distanceKm,
    required int timeSeconds,
  }) {
    if (!distanceKm.isFinite || distanceKm <= 0 || timeSeconds <= 0) {
      return null;
    }

    PaceNormativeStandard? standard;
    for (final item in _standards) {
      if ((item.distanceKm - distanceKm).abs() <= _distanceToleranceKm) {
        standard = item;
        break;
      }
    }
    if (standard == null) return null;

    final male = _categoryFor(standard.male, timeSeconds);
    final female = _categoryFor(standard.female, timeSeconds);
    if (male == null && female == null) return null;

    return PaceNormativeResult(male: male, female: female);
  }

  static String? _categoryFor(
    List<PaceNormativeCategory> categories,
    int timeSeconds,
  ) {
    for (final category in categories) {
      if (timeSeconds <= category.maxSeconds) return category.name;
    }
    return null;
  }
}
