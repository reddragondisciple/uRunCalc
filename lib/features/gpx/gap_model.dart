/// Поправка темпа на уклон по Minetti et al. (2002), см. docs/gpx-mountain-mode.md §6.
///
/// Все константы — в одном месте, покрыты тестами.
library;

/// Уклон обрезаем: за пределами ±25% полином экстраполируется.
const double minGrade = -0.25;
const double maxGrade = 0.25;

/// Спуск не быстрее 30% от плоского темпа (иначе −10% даёт 3:35/км).
const double minFactor = 0.70;

/// Энергозатраты на плоском: Cr(0), Дж/(кг·м).
const double _crFlat = 3.6;

/// Cr(i) — полином Minetti, `i` — уклон в долях (0.05 = 5%).
double minettiCr(double grade) {
  final i = grade;
  return 155.4 * i * i * i * i * i -
      30.4 * i * i * i * i -
      43.3 * i * i * i +
      46.3 * i * i +
      19.5 * i +
      _crFlat;
}

/// Множитель времени к плоскому темпу для уклона `grade`.
///
/// `k = Cr(i) / Cr(0)`: при подъёме больше 1 (медленнее), при спуске меньше 1.
/// Уклон и результат ограничены, см. константы выше.
double gapFactor(double grade) {
  final clamped = grade.clamp(minGrade, maxGrade).toDouble();
  final k = minettiCr(clamped) / _crFlat;
  return k < minFactor ? minFactor : k;
}
