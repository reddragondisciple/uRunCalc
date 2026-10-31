import 'package:ultra_run_calc/main.dart';
import 'package:flutter_test/flutter_test.dart';

String evaluate(String expression) {
  return ExpressionParser(expression).parse().toDisplayString();
}

void main() {
  group('ExpressionParser', () {
    test('respects operator precedence', () {
      expect(evaluate('2+3*4'), '14');
      expect(evaluate('(2+3)*4'), '20');
      expect(evaluate('2^3^2'), '512');
      expect(evaluate('-2^2'), '-4');
      expect(evaluate('2^-3'), '0.125');
    });

    test('keeps exact rational arithmetic', () {
      expect(evaluate('1/3+1/6'), '0.5');
      expect(evaluate('1/3*3'), '1');
      expect(evaluate('0.1+0.2'), '0.3');
    });

    test('supports exact markers', () {
      expect(evaluate('@1:3;+@1:6;'), '0.5');
      expect(evaluate('@-1:3;*3'), '-1');
    });

    test('treats standalone percent as division by 100', () {
      expect(evaluate('50%'), '0.5');
      expect(evaluate('200*10%'), '20');
      expect(evaluate('200/10%'), '2000');
    });

    test('treats percent in addition as a share of the left operand', () {
      expect(evaluate('200+10%'), '220');
      expect(evaluate('200-10%'), '180');
      expect(evaluate('100+10%+10%'), '121');
      expect(evaluate('200+(10+5)%'), '230');
    });

    test('computes exact square roots without approximation flag', () {
      final result = ExpressionParser('sqrt(4)').parseResult();

      expect(result.value.toFractionString(), '2');
      expect(result.approximate, isFalse);
    });

    test('marks irrational square roots as approximate', () {
      final result = ExpressionParser('sqrt(2)').parseResult();

      expect(result.value.toDisplayString(), startsWith('1.41421356237309'));
      expect(result.approximate, isTrue);
    });

    test('handles exact fractional powers', () {
      expect(evaluate('4^0.5'), '2');
      expect(evaluate('4^1.5'), '8');
      expect(evaluate('4^-0.5'), '0.5');
      expect(evaluate('(10^14)^0.5'), '10000000');
      expect(evaluate('(10^40)^0.5'), '100000000000000000000');
    });

    test('marks irrational fractional powers as approximate', () {
      final result = ExpressionParser('2^0.5').parseResult();

      expect(result.approximate, isTrue);
      expect(result.value.toDisplayString(), startsWith('1.41421356237309'));
    });

    test('evaluates engineering functions in degrees', () {
      expect(evaluate('sin(30)'), '0.5');
      expect(evaluate('cos(60)'), '0.5');
      expect(evaluate('tan(45)'), '1');
      expect(evaluate('log(100)'), '2');
      expect(evaluate('ln(1)'), '0');
    });

    test('snaps floating point noise in trigonometric functions', () {
      expect(evaluate('sin(180)'), '0');
      expect(evaluate('cos(90)'), '0');
      expect(evaluate('tan(180)'), '0');
      expect(() => ExpressionParser('tan(90)').parse(), throwsFormatException);
    });

    test('supports radians', () {
      final result = ExpressionParser('sin(π/2)', degrees: false).parseResult();

      expect(result.value.toDisplayString(), '1');
      expect(result.approximate, isTrue);
    });

    test('supports constants, reciprocal and factorial', () {
      expect(evaluate('inv(4)'), '0.25');
      expect(evaluate('5!'), '120');
      expect(evaluate('3!+2'), '8');

      final pi = ExpressionParser('π').parseResult();
      expect(pi.value.toDisplayString(), '3.141592653589793');
      expect(pi.approximate, isTrue);

      expect(evaluate('e'), '2.718281828459045');
    });

    test('reports errors', () {
      expect(() => ExpressionParser('1/0').parse(), throwsFormatException);
      expect(() => ExpressionParser('sqrt(-1)').parse(), throwsFormatException);
      expect(() => ExpressionParser('1+').parse(), throwsFormatException);
      expect(() => ExpressionParser('1.2.3').parse(), throwsFormatException);
    });

    test('rejects huge powers', () {
      expect(
        () => ExpressionParser('999999999^10000').parse(),
        throwsFormatException,
      );
      expect(() => ExpressionParser('2^10001').parse(), throwsFormatException);
    });
  });
}
