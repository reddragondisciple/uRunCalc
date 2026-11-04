import 'dart:math' as math;

import 'app_strings.dart';
import 'rational.dart';

class EvalResult {
  const EvalResult(this.value, {required this.approximate});

  final Rational value;
  final bool approximate;
}

/// Разбирает выражения с рациональной арифметикой, %, степенями, sqrt(...),
/// инженерными функциями и факториалом.
class ExpressionParser {
  ExpressionParser(this.input, {this.degrees = true});

  final String input;
  final bool degrees;
  int _position = 0;
  bool _approximate = false;

  static const List<String> _functionNames = [
    'sin',
    'cos',
    'tan',
    'ln',
    'log',
    'inv',
  ];

  Rational parse() => parseResult().value;

  EvalResult parseResult() {
    _approximate = false;
    final value = _parseAddSubtract();

    if (_position != input.length) {
      throw const FormatException(AppStrings.errorExtraCharacters);
    }

    return EvalResult(value, approximate: _approximate);
  }

  Rational _parseAddSubtract() {
    var value = _parseMultiplyDivide();

    while (_match('+') || _match('-')) {
      final operator = input[_position++];
      final rightStart = _position;
      var right = _parseMultiplyDivide();

      // Как в бытовом калькуляторе: 200 + 10% = 220, 200 - 10% = 180.
      // Относительный процент применяется, только если правый операнд —
      // самостоятельное процентное выражение (10%, (10)%, -10%).
      if (_isBarePercent(rightStart, _position)) {
        right = value * right;
      }

      value = operator == '+' ? value + right : value - right;
    }

    return value;
  }

  bool _isBarePercent(int start, int end) {
    if (end <= start || input[end - 1] != '%') return false;

    var depth = 0;

    for (var index = start; index < end; index++) {
      final char = input[index];

      if (char == '(') {
        depth++;
      } else if (char == ')') {
        depth--;
      } else if (depth == 0) {
        if (char == '*' || char == '/' || char == '^') {
          return false;
        }
        if ((char == '+' || char == '-') && index > start) {
          return false;
        }
      }
    }

    return true;
  }

  Rational _parseMultiplyDivide() {
    var value = _parseUnary();

    while (_match('*') || _match('/')) {
      final operator = input[_position++];
      final right = _parseUnary();

      value = operator == '*' ? value * right : value / right;
    }

    return value;
  }

  Rational _parseUnary() {
    if (_match('+')) {
      _position++;
      return _parseUnary();
    }

    if (_match('-')) {
      _position++;
      return -_parseUnary();
    }

    return _parsePower();
  }

  Rational _parsePower() {
    final base = _parsePostfix();

    if (_match('^')) {
      _position++;
      final exponent = _parseUnary();

      if (exponent.denominator == BigInt.one) {
        return base.powInteger(exponent.numerator);
      }

      // Для квадратного корня из рационального числа сохраняем точность.
      if (exponent.denominator == BigInt.two) {
        final exactRoot = base.trySqrtExact();
        if (exactRoot != null) {
          return exactRoot.powInteger(exponent.numerator);
        }
      }

      // Дробные степени в общем случае не являются рациональными.
      _approximate = true;
      final result = math.pow(base.toDouble(), exponent.toDouble()).toDouble();
      return Rational.fromDouble(result);
    }

    return base;
  }

  Rational _parsePostfix() {
    var value = _parsePrimary();

    while (_match('%') || _match('!')) {
      if (_match('%')) {
        _position++;
        value = value.percent();
      } else {
        _position++;
        value = _factorial(value);
      }
    }

    return value;
  }

  Rational _parsePrimary() {
    if (input.startsWith('sqrt(', _position)) {
      _position += 'sqrt('.length;
      final value = _parseAddSubtract();
      _expect(')');

      final exact = value.trySqrtExact();
      if (exact != null) return exact;

      _approximate = true;
      return value.sqrtApproximation();
    }

    for (final name in _functionNames) {
      final prefix = '$name(';

      if (input.startsWith(prefix, _position)) {
        _position += prefix.length;
        final value = _parseAddSubtract();
        _expect(')');
        return _applyFunction(name, value);
      }
    }

    if (_match('π')) {
      _position++;
      _approximate = true;
      return Rational.fromDouble(math.pi);
    }

    if (input.startsWith('pi', _position)) {
      _position += 2;
      _approximate = true;
      return Rational.fromDouble(math.pi);
    }

    if (_match('e')) {
      _position++;
      _approximate = true;
      return Rational.fromDouble(math.e);
    }

    if (_match('@')) {
      return _parseExactValue();
    }

    if (_match('(')) {
      _position++;
      final value = _parseAddSubtract();
      _expect(')');
      return value;
    }

    return _parseNumber();
  }

  Rational _applyFunction(String name, Rational value) {
    switch (name) {
      case 'inv':
        if (value == Rational.zero) {
          throw const FormatException(AppStrings.errorDivisionByZero);
        }
        return Rational.one / value;
      case 'ln':
        if (value.toDouble() <= 0) {
          throw const FormatException(AppStrings.errorLogUndefined);
        }
        _approximate = true;
        return Rational.fromDouble(math.log(value.toDouble()));
      case 'log':
        if (value.toDouble() <= 0) {
          throw const FormatException(AppStrings.errorLogUndefined);
        }
        _approximate = true;
        return Rational.fromDouble(math.log(value.toDouble()) / math.ln10);
      case 'sin':
        _approximate = true;
        return Rational.fromDouble(
          _snapTrig(math.sin(_toRadians(value.toDouble()))),
        );
      case 'cos':
        _approximate = true;
        return Rational.fromDouble(
          _snapTrig(math.cos(_toRadians(value.toDouble()))),
        );
      case 'tan':
        final radians = _toRadians(value.toDouble());
        if (math.cos(radians).abs() < 1e-12) {
          throw const FormatException(AppStrings.errorTanUndefined);
        }
        _approximate = true;
        return Rational.fromDouble(_snapTrig(math.tan(radians)));
      default:
        throw const FormatException(AppStrings.errorUnknownFunction);
    }
  }

  double _snapTrig(double value) {
    // Убираем шум плавающей точки: sin(180°) должен быть ровно 0.
    return value.abs() < 1e-12 ? 0 : value;
  }

  double _toRadians(double value) {
    return degrees ? value * math.pi / 180 : value;
  }

  Rational _factorial(Rational value) {
    if (!value.isInteger || value.numerator.isNegative) {
      throw const FormatException(AppStrings.errorFactorialIntegers);
    }

    if (value.numerator > BigInt.from(1000)) {
      throw const FormatException(AppStrings.errorNumberTooLarge);
    }

    var result = BigInt.one;
    final limit = value.numerator.toInt();

    for (var number = 2; number <= limit; number++) {
      result *= BigInt.from(number);
    }

    return Rational(result, BigInt.one);
  }

  Rational _parseExactValue() {
    _position++; // @

    final colon = input.indexOf(':', _position);
    if (colon == -1) {
      throw const FormatException(AppStrings.errorInvalidExactNumber);
    }

    final semicolon = input.indexOf(';', colon + 1);
    if (semicolon == -1) {
      throw const FormatException(AppStrings.errorInvalidExactNumber);
    }

    final numeratorText = input.substring(_position, colon);
    final denominatorText = input.substring(colon + 1, semicolon);

    _position = semicolon + 1;

    return Rational(BigInt.parse(numeratorText), BigInt.parse(denominatorText));
  }

  Rational _parseNumber() {
    final start = _position;
    var hasDigit = false;

    while (_position < input.length && _isDigit(input[_position])) {
      hasDigit = true;
      _position++;
    }

    if (_match('.')) {
      _position++;

      while (_position < input.length && _isDigit(input[_position])) {
        hasDigit = true;
        _position++;
      }
    }

    if (!hasDigit) {
      throw const FormatException(AppStrings.errorNumberExpected);
    }

    return Rational.fromDecimal(input.substring(start, _position));
  }

  bool _match(String char) {
    return _position < input.length && input[_position] == char;
  }

  void _expect(String char) {
    if (!_match(char)) {
      throw const FormatException(AppStrings.errorMissingClosingParen);
    }

    _position++;
  }

  static bool _isDigit(String char) {
    final code = char.codeUnitAt(0);
    return code >= 0x30 && code <= 0x39;
  }
}
