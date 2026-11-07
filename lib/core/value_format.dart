import 'rational.dart';

final RegExp _exactValuePattern = RegExp(r'@(-?\d+):(\d+);');
final RegExp _numberPattern = RegExp(r'\d+(?:\.\d*)?|\.\d+');
final RegExp _digitGroupPattern = RegExp(r'\B(?=(\d{3})+(?!\d))');

/// Текстовая версия выражения: дроби записываются как a/b, числа группируются.
String displayText(String value) {
  var text = value.replaceAllMapped(_exactValuePattern, (match) {
    final numerator = BigInt.parse(match.group(1)!);
    final denominator = BigInt.parse(match.group(2)!);
    final rational = Rational(numerator, denominator);

    if (rational.isDisplayableFraction) {
      return rational.toFractionString();
    }

    return rational.toDisplayString();
  });

  text = text.replaceAll('sqrt(', '√(');
  text = text.replaceAll('inv(', '1/(');
  text = text.replaceAll('*', '×');
  text = text.replaceAll('-', '−');

  return groupDigits(text);
}

String groupDigits(String text) {
  return text.replaceAllMapped(_numberPattern, (match) {
    final number = match.group(0)!;
    final dotIndex = number.indexOf('.');
    final integerPart = dotIndex == -1 ? number : number.substring(0, dotIndex);
    final decimalPart = dotIndex == -1 ? '' : number.substring(dotIndex);

    final groupedInteger = integerPart.replaceAllMapped(
      _digitGroupPattern,
      (_) => '\u2009',
    );

    return '$groupedInteger$decimalPart';
  });
}

String formatDecimal(String text) {
  final formatted = text.replaceAll('-', '−');
  if (formatted.contains('e')) return formatted;
  return groupDigits(formatted);
}

String decimalSymbol(Rational value, bool approximate) {
  if (!value.decimalDisplayIsExact) return '≈';
  if (approximate && !value.isInteger) return '≈';
  return '=';
}

String historyText(String expression, Rational value, bool approximate) {
  final left = displayText(expression);
  final decimal = formatDecimal(value.toDisplayString());
  final symbol = decimalSymbol(value, approximate);
  final showsFraction = !approximate && value.isDisplayableFraction;

  if (showsFraction) {
    final fraction = value.toFractionString();
    if (left == fraction) {
      return '$left $symbol $decimal';
    }
    if (left == decimal) {
      return '$left = $fraction';
    }
    return '$left = $fraction $symbol $decimal';
  }

  if (value.isInteger && symbol == '=') {
    return '$left = $decimal';
  }

  return '$left $symbol $decimal';
}
