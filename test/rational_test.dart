import 'package:ultra_run_calc/core/rational.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Rational', () {
    test('normalizes numerator and denominator', () {
      final value = Rational(BigInt.from(2), BigInt.from(4));

      expect(value.numerator, BigInt.one);
      expect(value.denominator, BigInt.two);
    });

    test('moves sign to numerator', () {
      final value = Rational(BigInt.one, BigInt.from(-3));

      expect(value.numerator, BigInt.from(-1));
      expect(value.denominator, BigInt.from(3));
    });

    test('normalizes zero', () {
      final value = Rational(BigInt.zero, BigInt.from(5));

      expect(value.numerator, BigInt.zero);
      expect(value.denominator, BigInt.one);
    });

    test('rejects zero denominator', () {
      expect(() => Rational(BigInt.one, BigInt.zero), throwsFormatException);
    });

    test('adds, subtracts, multiplies and divides exactly', () {
      final third = Rational(BigInt.one, BigInt.from(3));
      final sixth = Rational(BigInt.one, BigInt.from(6));

      expect((third + sixth).toFractionString(), '1/2');
      expect((third - sixth).toFractionString(), '1/6');
      expect((third * sixth).toFractionString(), '1/18');
      expect((third / sixth).toFractionString(), '2');
    });

    test('percent divides by 100', () {
      final value = Rational(BigInt.from(50), BigInt.one).percent();

      expect(value.toFractionString(), '1/2');
    });

    test('displays fractions', () {
      final value = Rational(BigInt.from(-3), BigInt.from(4));

      expect(value.toFractionString(), '-3/4');
      expect(value.isDisplayableFraction, isTrue);
      expect(value.toString(), '-3/4');
    });

    test('never displays negative zero', () {
      final value = Rational(BigInt.from(-1), BigInt.from(10000000000000000));

      expect(value.toDisplayString(), '-1e-16');
      expect(value.toDisplayString(), isNot('-0'));
    });

    test('rounds repeating decimals', () {
      final value = Rational(BigInt.one, BigInt.from(3));

      expect(value.toDisplayString(), '0.333333333333333');
      expect(value.decimalDisplayIsExact, isFalse);
    });

    test('detects exact decimal display', () {
      final half = Rational(BigInt.one, BigInt.two);
      final third = Rational(BigInt.one, BigInt.from(3));

      expect(half.decimalDisplayIsExact, isTrue);
      expect(third.decimalDisplayIsExact, isFalse);
      expect(half.hasTerminatingDecimal, isTrue);
      expect(third.hasTerminatingDecimal, isFalse);
    });

    test('uses scientific notation for huge values', () {
      final value = Rational(BigInt.from(2).pow(10000), BigInt.one);
      final text = value.toDisplayString();

      expect(text, contains('e+'));
      expect(text.length, lessThan(30));
    });

    test('uses scientific notation for tiny values', () {
      final value = Rational(BigInt.one, BigInt.from(10).pow(20));

      expect(value.toDisplayString(), '1e-20');
    });

    test('fromDouble keeps large and tiny values', () {
      expect(
        Rational.fromDouble(1e20).toFractionString(),
        '100000000000000000000',
      );
      expect(
        Rational.fromDouble(1e-20).toFractionString(),
        '1/100000000000000000000',
      );
    });

    test('fromDouble rejects non-finite values', () {
      expect(() => Rational.fromDouble(double.infinity), throwsFormatException);
      expect(() => Rational.fromDouble(double.nan), throwsFormatException);
    });

    test('computes exact square roots', () {
      final root = Rational(BigInt.from(4), BigInt.one).trySqrtExact();

      expect(root, isNotNull);
      expect(root!.toFractionString(), '2');
    });

    test('computes approximate square roots', () {
      final two = Rational(BigInt.two, BigInt.one);
      final root = two.sqrtApproximation();

      expect(root.toDisplayString(), startsWith('1.41421356237309'));
      expect(two.trySqrtExact(), isNull);
    });

    test('limits huge powers', () {
      expect(
        () => Rational(
          BigInt.from(999999999),
          BigInt.one,
        ).powInteger(BigInt.from(10000)),
        throwsFormatException,
      );
    });
  });
}
