import 'package:flutter_test/flutter_test.dart';
import 'package:ultra_run_calc/features/pace/pace_split_print.dart';

PaceSplitPrintData _data(int points) {
  return PaceSplitPrintData(
    title: 'Раскладка по контрольным точкам',
    summary: const [
      'Расстояние: 42.195 км',
      'Темп: 5:00 мин/км',
      'Время: 3:30:59',
      'Старт: 00:00',
      'Раскладка на: 1 км',
    ],
    points: [
      for (var index = 1; index <= points; index++)
        PaceSplitPrintPoint(
          distance: '$index км',
          time: '${index ~/ 12}:${'${(index * 5) % 60}'.padLeft(2, '0')}:00',
        ),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('buildPaceSplitPdf produces a PDF document', () async {
    final bytes = await buildPaceSplitPdf(_data(50));

    expect(bytes.length, greaterThan(1000));
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });

  test('buildPaceSplitPdf fits at least 44 points on the first page', () async {
    final bytes = await buildPaceSplitPdf(_data(44));
    final text = String.fromCharCodes(bytes);

    expect(RegExp(r'/Type\s*/Page\b').allMatches(text), hasLength(1));
  });

  test('buildPaceSplitPdf paginates a long table', () async {
    final firstPage = String.fromCharCodes(await buildPaceSplitPdf(_data(54)));
    expect(RegExp(r'/Type\s*/Page\b').allMatches(firstPage), hasLength(1));

    final secondPage = String.fromCharCodes(await buildPaceSplitPdf(_data(80)));
    expect(
      RegExp(r'/Type\s*/Page\b').allMatches(secondPage).length,
      greaterThan(1),
    );
  });

  test('buildPaceSplitPdf continues on extra pages for long tables', () async {
    final bytes = await buildPaceSplitPdf(_data(120));
    final text = String.fromCharCodes(bytes);

    expect(RegExp(r'/Type\s*/Page\b').allMatches(text).length, greaterThan(1));
  });
}
