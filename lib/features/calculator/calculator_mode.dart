/// Режимы приложения. Порядок значений задаёт индекс экрана в стеке.
enum CalculatorMode {
  ultra('Ultra'),
  pace('Pace'),
  time('Time'),
  simple('Simple'),
  info('Info');

  const CalculatorMode(this.label);

  final String label;
}
