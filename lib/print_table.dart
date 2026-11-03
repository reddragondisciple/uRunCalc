import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Данные, необходимые для печати таблицы Ultra.
class PrintTableData {
  const PrintTableData({
    required this.event,
    required this.columns,
    required this.times,
    required this.distances,
    required this.segmentPaces,
    required this.planTimes,
    required this.planPaces,
    required this.water,
    required this.food,
    required this.limitTime,
    required this.limitPace,
    required this.plannedPace,
    required this.plannedTime,
    this.boldColumns = const [],
    this.dayIndexes = const [],
  });

  final String event;
  final List<String> columns;
  final List<String> times;
  final List<String> distances;
  final List<String> segmentPaces;
  final List<String> planTimes;
  final List<String> planPaces;
  final List<String> water;
  final List<String> food;
  final String limitTime;
  final String limitPace;
  final String plannedPace;
  final String plannedTime;

  /// Колонки с толстой чёрной рамкой.
  final List<int> boldColumns;

  /// Номер дня для каждой колонки. Второй день получает слабый серый фон.
  final List<int> dayIndexes;

  int get columnCount => columns.length;

  String _at(List<String> values, int index) =>
      index < values.length ? values[index] : '';

  /// День 1 (индекс 0) без фона, день 2 — слабый серый, день 3 снова без
  /// фона и так далее.
  PdfColor? _dayBackground(int index) {
    if (index >= dayIndexes.length) return null;
    final day = dayIndexes[index];
    return day.isOdd ? PdfColors.grey200 : null;
  }
}

/// Собирает PDF с таблицей. При большом количестве колонок таблица
/// разбивается на несколько страниц, при этом стартовая колонка повторяется
/// на каждой странице для удобства чтения.
Future<Uint8List> buildTablePdf(
  PrintTableData data, {
  required bool landscape,
}) async {
  final regular = pw.Font.ttf(
    await rootBundle.load('assets/fonts/DejaVuSans.ttf'),
  );
  final bold = pw.Font.ttf(
    await rootBundle.load('assets/fonts/DejaVuSans-Bold.ttf'),
  );

  final document = pw.Document(
    theme: pw.ThemeData.withFont(base: regular, bold: bold),
  );
  final format = landscape ? PdfPageFormat.a4.landscape : PdfPageFormat.a4;
  final chunks = _columnChunks(data.columnCount, landscape);

  for (var pageIndex = 0; pageIndex < chunks.length; pageIndex++) {
    final columns = chunks[pageIndex];
    document.addPage(
      pw.MultiPage(
        pageFormat: format,
        margin: const pw.EdgeInsets.all(22),
        build: (context) => [
          pw.Text(
            data.event.isEmpty ? 'uRunCalc' : data.event,
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            'uRunCalc — таблица плана',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 10),
          _summary(data),
          pw.SizedBox(height: 10),
          _table(data, columns),
          pw.SizedBox(height: 8),
          pw.Text(
            'Страница ${pageIndex + 1} из ${chunks.length}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
        ],
      ),
    );
  }

  return document.save();
}

pw.Widget _summary(PrintTableData data) {
  return pw.Container(
    padding: const pw.EdgeInsets.all(7),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: PdfColors.grey400, width: 0.6),
      borderRadius: pw.BorderRadius.circular(3),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Общее время: ${data.limitTime}    '
          'Темп в лимит: ${data.limitPace}',
          style: const pw.TextStyle(fontSize: 9),
        ),
        pw.SizedBox(height: 3),
        pw.Text(
          'Итоговый плановый темп: ${data.plannedPace}    '
          'Итоговое плановое время: ${data.plannedTime}',
          style: const pw.TextStyle(fontSize: 9),
        ),
      ],
    ),
  );
}

pw.Widget _table(PrintTableData data, List<int> columns) {
  final labels = <String>[
    'Время (лимит)',
    'Расстояние, км',
    'Темп сегмента',
    'План',
    'Плановый темп',
    'Вода',
    'Еда',
  ];

  final widths = <int, pw.TableColumnWidth>{
    0: const pw.FixedColumnWidth(74),
    for (var index = 1; index <= columns.length; index++)
      index: const pw.FlexColumnWidth(),
  };

  return pw.Table(
    border: pw.TableBorder.all(color: PdfColors.grey500, width: 0.5),
    columnWidths: widths,
    children: [
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey300),
        children: [
          _cell('', bold: true),
          for (final column in columns)
            _cell(
              data._at(data.columns, column),
              bold: true,
              boldBorder: data.boldColumns.contains(column),
            ),
        ],
      ),
      for (var row = 0; row < labels.length; row++)
        pw.TableRow(
          children: [
            _cell(labels[row], bold: true),
            for (final column in columns)
              _cell(
                _value(data, column, row),
                align: row >= 5 ? pw.TextAlign.left : pw.TextAlign.center,
                background: data._dayBackground(column),
                boldBorder: data.boldColumns.contains(column),
              ),
          ],
        ),
    ],
  );
}

String _value(PrintTableData data, int column, int row) {
  return switch (row) {
    0 => data._at(data.times, column),
    1 => data._at(data.distances, column),
    2 => data._at(data.segmentPaces, column),
    3 => data._at(data.planTimes, column),
    4 => data._at(data.planPaces, column),
    5 => _short(data._at(data.water, column)),
    _ => _short(data._at(data.food, column)),
  };
}

String _short(String value) {
  final normalized = value.replaceAll('\n', ' ').trim();
  if (normalized.length <= 120) return normalized;
  return '${normalized.substring(0, 117)}...';
}

pw.Widget _cell(
  String text, {
  bool bold = false,
  pw.TextAlign align = pw.TextAlign.center,
  PdfColor? background,
  bool boldBorder = false,
}) {
  final content = pw.Container(
    color: background,
    padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 3),
    child: pw.Text(
      text.isEmpty ? '—' : text,
      textAlign: align,
      style: pw.TextStyle(
        fontSize: 11,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      ),
    ),
  );

  if (!boldBorder) return content;

  return pw.Container(
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: PdfColors.black, width: 1.6),
    ),
    child: content,
  );
}

List<List<int>> _columnChunks(int columnCount, bool landscape) {
  final perPage = landscape ? 11 : 7;
  final chunks = <List<int>>[];
  for (var start = 1; start < columnCount; start += perPage) {
    final end = math.min(start + perPage, columnCount);
    chunks.add([0, for (var index = start; index < end; index++) index]);
  }
  if (chunks.isEmpty) chunks.add([0]);
  return chunks;
}
