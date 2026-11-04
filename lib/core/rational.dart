import 'dart:math' as math;

import 'app_strings.dart';

/// Рациональное число: сокращённый числитель и положительный знаменатель.
class Rational {
  factory Rational(BigInt numerator, BigInt denominator) {
    if (denominator == BigInt.zero) {
      throw const FormatException(AppStrings.errorDivisionByZero);
    }

    var n = numerator;
    var d = denominator;

    if (d.isNegative) {
      n = -n;
      d = -d;
    }

    final divisor = _gcd(n.abs(), d);
    return Rational._(n ~/ divisor, d ~/ divisor);
  }

  Rational._(this.numerator, this.denominator);

  final BigInt numerator;
  final BigInt denominator;

  static final Rational zero = Rational._(BigInt.zero, BigInt.one);
  static final Rational one = Rational._(BigInt.one, BigInt.one);

  static BigInt _gcd(BigInt a, BigInt b) {
    var x = a;
    var y = b;

    while (y != BigInt.zero) {
      final remainder = x % y;
      x = y;
      y = remainder;
    }

    return x == BigInt.zero ? BigInt.one : x;
  }

  static BigInt _pow10(int exponent) {
    return BigInt.from(10).pow(exponent);
  }

  bool get isInteger => denominator == BigInt.one;

  /// Дробь стоит показывать, только если она не слишком громоздкая.
  bool get isDisplayableFraction {
    if (isInteger) return false;

    final digits =
        numerator.abs().toString().length + denominator.toString().length;
    return digits <= 24;
  }

  bool get hasTerminatingDecimal {
    var d = denominator;

    while (d % BigInt.two == BigInt.zero) {
      d = d ~/ BigInt.two;
    }
    while (d % BigInt.from(5) == BigInt.zero) {
      d = d ~/ BigInt.from(5);
    }

    return d == BigInt.one;
  }

  /// Совпадает ли отображаемая десятичная запись с точным значением.
  bool get decimalDisplayIsExact {
    final text = toDisplayString();

    if (text.contains('e')) return false;
    if (isInteger) return true;

    try {
      return Rational.fromDecimal(text) == this;
    } on FormatException {
      return false;
    }
  }

  static Rational fromDecimal(String text) {
    final negative = text.startsWith('-');
    final unsigned = negative ? text.substring(1) : text;
    final dotIndex = unsigned.indexOf('.');

    if (dotIndex == -1) {
      final value = BigInt.parse(unsigned);
      return Rational(negative ? -value : value, BigInt.one);
    }

    final whole = unsigned.substring(0, dotIndex);
    final fraction = unsigned.substring(dotIndex + 1);
    final digits = '${whole.isEmpty ? '0' : whole}$fraction';
    final denominator = _pow10(fraction.length);
    final numerator = BigInt.parse(digits.isEmpty ? '0' : digits);

    return Rational(negative ? -numerator : numerator, denominator);
  }

  Rational operator +(Rational other) {
    return Rational(
      numerator * other.denominator + other.numerator * denominator,
      denominator * other.denominator,
    );
  }

  Rational operator -(Rational other) {
    return Rational(
      numerator * other.denominator - other.numerator * denominator,
      denominator * other.denominator,
    );
  }

  Rational operator *(Rational other) {
    return Rational(
      numerator * other.numerator,
      denominator * other.denominator,
    );
  }

  Rational operator /(Rational other) {
    if (other.numerator == BigInt.zero) {
      throw const FormatException(AppStrings.errorDivisionByZero);
    }

    return Rational(
      numerator * other.denominator,
      denominator * other.numerator,
    );
  }

  Rational operator -() => Rational(-numerator, denominator);

  Rational percent() => Rational(numerator, denominator * BigInt.from(100));

  Rational powInteger(BigInt exponent) {
    if (exponent == BigInt.zero) {
      return one;
    }

    if (exponent.abs() > BigInt.from(10000)) {
      throw const FormatException(AppStrings.errorExponentTooLarge);
    }

    final power = exponent.abs().toInt();
    final estimatedNumeratorDigits = _estimatedPowerDigits(
      numerator.abs(),
      power,
    );
    final estimatedDenominatorDigits = _estimatedPowerDigits(
      denominator,
      power,
    );

    if (estimatedNumeratorDigits > 50000 ||
        estimatedDenominatorDigits > 50000) {
      throw const FormatException(AppStrings.errorNumberTooLarge);
    }

    final poweredNumerator = numerator.abs().pow(power);
    final signedNumerator = numerator.isNegative && power.isOdd
        ? -poweredNumerator
        : poweredNumerator;
    final poweredDenominator = denominator.pow(power);

    if (exponent.isNegative) {
      if (signedNumerator == BigInt.zero) {
        throw const FormatException(AppStrings.errorDivisionByZero);
      }
      return Rational(poweredDenominator, signedNumerator);
    }

    return Rational(signedNumerator, poweredDenominator);
  }

  static int _estimatedPowerDigits(BigInt value, int exponent) {
    if (value == BigInt.zero || value == BigInt.one) return 1;

    final double log10Value;
    if (value.bitLength <= 53) {
      log10Value = math.log(value.toDouble()) / math.ln10;
    } else {
      log10Value = (value.toString().length - 1).toDouble();
    }

    return (log10Value * exponent).ceil() + 1;
  }

  /// Точный квадратный корень, если он рационален.
  Rational? trySqrtExact() {
    if (numerator.isNegative) return null;

    final rootNumerator = _integerSqrt(numerator);
    final rootDenominator = _integerSqrt(denominator);

    if (rootNumerator * rootNumerator == numerator &&
        rootDenominator * rootDenominator == denominator) {
      return Rational(rootNumerator, rootDenominator);
    }

    return null;
  }

  Rational sqrtApproximation() {
    if (numerator.isNegative) {
      throw const FormatException(AppStrings.errorNegativeSquareRoot);
    }

    const places = 24;
    final scale = _pow10(places);
    final scaledRadicand = numerator * scale * scale ~/ denominator;
    final root = _integerSqrt(scaledRadicand);

    return Rational(root, scale);
  }

  static BigInt _integerSqrt(BigInt value) {
    if (value < BigInt.zero) {
      throw const FormatException(AppStrings.errorNegativeSquareRoot);
    }
    if (value < BigInt.two) return value;

    var x = value;
    var y = (x + BigInt.one) ~/ BigInt.two;

    while (y < x) {
      x = y;
      y = (x + value ~/ x) ~/ BigInt.two;
    }

    return x;
  }

  double toDouble() {
    return numerator.toDouble() / denominator.toDouble();
  }

  static Rational fromDouble(double value) {
    if (value.isNaN) {
      throw const FormatException(AppStrings.errorInvalidResult);
    }
    if (!value.isFinite) {
      throw const FormatException(AppStrings.errorResultTooLarge);
    }
    if (value == 0) return zero;

    final text = value.toStringAsExponential();
    final eIndex = text.indexOf('e');
    final mantissaText = text.substring(0, eIndex);
    final exponent = int.parse(text.substring(eIndex + 1));

    final negative = mantissaText.startsWith('-');
    final unsigned = negative ? mantissaText.substring(1) : mantissaText;
    final dotIndex = unsigned.indexOf('.');
    final whole = dotIndex == -1 ? unsigned : unsigned.substring(0, dotIndex);
    final fraction = dotIndex == -1 ? '' : unsigned.substring(dotIndex + 1);
    final digits = '$whole$fraction';

    var numerator = BigInt.parse(digits);
    if (negative) numerator = -numerator;

    final denominatorExponent = fraction.length - exponent;
    if (denominatorExponent >= 0) {
      return Rational(numerator, _pow10(denominatorExponent));
    }

    return Rational(numerator * _pow10(-denominatorExponent), BigInt.one);
  }

  static Rational fromDoubleApproximation(double value) => fromDouble(value);

  int _decimalExponent() {
    final nDigits = numerator.abs().toString().length;
    final dDigits = denominator.toString().length;
    var exponent = nDigits - dDigits;

    while (_compareWithPowerOfTen(exponent) < 0) {
      exponent--;
    }
    while (_compareWithPowerOfTen(exponent + 1) >= 0) {
      exponent++;
    }

    return exponent;
  }

  int _compareWithPowerOfTen(int exponent) {
    final n = numerator.abs();
    final d = denominator;

    if (exponent >= 0) {
      return n.compareTo(d * _pow10(exponent));
    }

    return (n * _pow10(-exponent)).compareTo(d);
  }

  String _toScientificString(int exponent) {
    const significantDigits = 12;
    final n = numerator.abs();
    final d = denominator;

    var scaledNumerator = n * _pow10(significantDigits - 1);
    var scaledDenominator = d;

    if (exponent >= 0) {
      scaledDenominator *= _pow10(exponent);
    } else {
      scaledNumerator *= _pow10(-exponent);
    }

    var mantissa =
        (scaledNumerator + scaledDenominator ~/ BigInt.two) ~/
        scaledDenominator;

    final limit = _pow10(significantDigits);
    if (mantissa >= limit) {
      mantissa = mantissa ~/ BigInt.from(10);
      exponent++;
    }

    final digits = mantissa.toString().padLeft(significantDigits, '0');
    final whole = digits.substring(0, 1);
    final fraction = digits.substring(1).replaceFirst(RegExp(r'0+$'), '');
    final sign = numerator.isNegative ? '-' : '';
    final mantissaText = fraction.isEmpty ? whole : '$whole.$fraction';

    return '$sign${mantissaText}e${exponent >= 0 ? '+' : ''}$exponent';
  }

  String toDisplayString() {
    if (numerator == BigInt.zero) return '0';

    final exponent = _decimalExponent();
    if (exponent >= 21 || exponent <= -16) {
      return _toScientificString(exponent);
    }

    const places = 15;
    final scale = _pow10(places);
    final absoluteNumerator = numerator.abs();
    final scaled = absoluteNumerator * scale;
    var rounded = scaled ~/ denominator;
    final remainder = scaled % denominator;

    if (remainder * BigInt.two >= denominator) {
      rounded += BigInt.one;
    }

    if (rounded == BigInt.zero) return '0';

    final whole = rounded ~/ scale;
    final fraction = (rounded % scale).toString().padLeft(places, '0');
    final trimmedFraction = fraction.replaceFirst(RegExp(r'0+$'), '');
    final sign = numerator.isNegative ? '-' : '';

    if (trimmedFraction.isEmpty) {
      return '$sign$whole';
    }

    return '$sign$whole.$trimmedFraction';
  }

  String toFractionString() {
    if (isInteger) return numerator.toString();
    return '$numerator/$denominator';
  }

  @override
  bool operator ==(Object other) {
    return other is Rational &&
        numerator == other.numerator &&
        denominator == other.denominator;
  }

  @override
  int get hashCode => Object.hash(numerator, denominator);

  @override
  String toString() => toFractionString();
}
