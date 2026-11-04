import 'package:flutter_test/flutter_test.dart';
import 'package:ultra_run_calc/core/app_strings.dart';
import 'package:ultra_run_calc/core/key_labels.dart';

void main() {
  test('describes symbol keys for screen readers', () {
    expect(semanticKeyLabel('⌫'), AppStrings.keyDelete);
    expect(semanticKeyLabel('√'), AppStrings.keySquareRoot);
    expect(semanticKeyLabel('÷'), AppStrings.keyDivide);
    expect(semanticKeyLabel('×'), AppStrings.keyMultiply);
    expect(semanticKeyLabel('ОК'), AppStrings.keyDone);
    expect(semanticKeyLabel(':'), AppStrings.keyColon);
  });

  test('keeps digits and unknown keys as is', () {
    expect(semanticKeyLabel('0'), '0');
    expect(semanticKeyLabel('7'), '7');
    expect(semanticKeyLabel('+'), '+');
  });

  test('mentions long press for clear keys', () {
    expect(semanticKeyLabel('C'), AppStrings.keyClearHistory);
    expect(semanticKeyLabel('angle'), AppStrings.keyAngleToggle);
  });
}
