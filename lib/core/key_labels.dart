import 'app_strings.dart';

/// Подписи клавиш экранных клавиатур для screen reader.
///
/// Символы вроде `⌫`, `√` и `×` читаются плохо или не читаются совсем,
/// поэтому для них заданы словесные подписи. Неизвестные клавиши (цифры и
/// буквы) возвращаются как есть.
String semanticKeyLabel(String key) {
  return switch (key) {
    'C' => AppStrings.keyClearHistory,
    'Сброс' => AppStrings.keyResetField,
    '⌫' => AppStrings.keyDelete,
    '00' => AppStrings.keyDoubleZero,
    '000' => AppStrings.keyTripleZero,
    'ОК' => AppStrings.keyDone,
    ':' => AppStrings.keyColon,
    '.' => AppStrings.keyDot,
    '/' => AppStrings.keyFractionSlash,
    '√' => AppStrings.keySquareRoot,
    '^' => AppStrings.keyPower,
    '÷' => AppStrings.keyDivide,
    '×' => AppStrings.keyMultiply,
    '%' => AppStrings.keyPercent,
    '=' => AppStrings.keyEquals,
    '(' => AppStrings.keyOpenParen,
    ')' => AppStrings.keyCloseParen,
    'sin' => AppStrings.keySine,
    'cos' => AppStrings.keyCosine,
    'tan' => AppStrings.keyTangent,
    'ln' => AppStrings.keyNaturalLog,
    'log' => AppStrings.keyDecimalLog,
    'π' => AppStrings.keyPi,
    'e' => AppStrings.keyExponent,
    'x²' => AppStrings.keySquare,
    '1/x' => AppStrings.keyReciprocal,
    'n!' => AppStrings.keyFactorial,
    'angle' => AppStrings.keyAngleToggle,
    'Ans' => AppStrings.keyPreviousResult,
    _ => key,
  };
}
