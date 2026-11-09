import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/app_strings.dart';

/// Одна строка таблицы раскладки для печати.
class PaceSplitPrintPoint {
  const PaceSplitPrintPoint({required this.distance, required this.time});

  final String distance;
  final String time;
}

/// Данные для печати раскладки по контрольным точкам.
class PaceSplitPrintData {
  const PaceSplitPrintData({
    required this.title,
    required this.summary,
    required this.points,
  });

  final String title;

  /// Сводка (расстояние, темп, время, старт, шаг). Печатается в начале
  /// первого столбца.
  final List<String> summary;

  final List<PaceSplitPrintPoint> points;
}

/// Сколько строк помещается в один столбец.
const int _rowsPerColumn = 28;

/// Сколько столбцов на странице.
const int _columnsPerPage = 3;

/// Высота строки таблицы.
const double _rowHeight = 25;

/// Ширина ячейки с расстоянием.
const double _distanceWidth = 74;

/// Ширина ячейки со временем.
const double _timeWidth = 58;

/// Расстояние между чекпойнтом и его временем: 1 см.
const double _pairGap = PdfPageFormat.cm;

/// Отступ сверху: 2 см.
const double _topMargin = 2 * PdfPageFormat.cm;

/// Собирает вертикальный PDF с раскладкой. Сводка идёт в начале первого
/// столбца, таблица продолжается во втором столбце и на следующих страницах.
Future<Uint8List> buildPaceSplitPdf(PaceSplitPrintData data) async {
  final regular = pw.Font.ttf(
    await rootBundle.load('assets/fonts/DejaVuSans.ttf'),
  );
  final bold = pw.Font.ttf(
    await rootBundle.load('assets/fonts/DejaVuSans-Bold.ttf'),
  );

  final document = pw.Document(
    theme: pw.ThemeData.withFont(base: regular, bold: bold),
  );

  final pages = _paginate(data);
  for (var pageIndex = 0; pageIndex < pages.length; pageIndex++) {
    final columns = pages[pageIndex];
    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(12, _topMargin, 12, 12),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Text(
                data.title,
                style: pw.TextStyle(
                  fontSize: 15,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Expanded(
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    for (
                      var column = 0;
                      column < _columnsPerPage;
                      column++
                    ) ...[
                      if (column > 0) pw.SizedBox(width: 10),
                      pw.Expanded(child: _buildColumn(columns[column])),
                    ],
                  ],
                ),
              ),
              if (pages.length > 1) ...[
                pw.SizedBox(height: 3),
                pw.Text(
                  '${pageIndex + 1} / ${pages.length}',
                  style: const pw.TextStyle(
                    fontSize: 9,
                    color: PdfColors.grey600,
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  return document.save();
}

/// Делит строки на страницы и столбцы. Сводка занимает первые строки
/// первого столбца, поэтому на первой странице остаётся место для
/// `2 * 28 - summary.length` контрольных точек.
List<List<List<_PrintRow>>> _paginate(PaceSplitPrintData data) {
  final rows = <_PrintRow>[
    for (final line in data.summary) _PrintRow.summary(line),
    for (final point in data.points) _PrintRow.point(point),
  ];

  final pages = <List<List<_PrintRow>>>[];
  final perPage = _rowsPerColumn * _columnsPerPage;
  for (var start = 0; start < rows.length; start += perPage) {
    final pageRows = rows.sublist(
      start,
      math.min(start + perPage, rows.length),
    );
    final columns = <List<_PrintRow>>[];
    for (var offset = 0; offset < pageRows.length; offset += _rowsPerColumn) {
      columns.add(
        pageRows.sublist(
          offset,
          math.min(offset + _rowsPerColumn, pageRows.length),
        ),
      );
    }
    while (columns.length < _columnsPerPage) {
      columns.add(const <_PrintRow>[]);
    }
    pages.add(columns);
  }

  if (pages.isEmpty) {
    pages.add(const <List<_PrintRow>>[
      <_PrintRow>[],
      <_PrintRow>[],
      <_PrintRow>[],
    ]);
  }

  return pages;
}

pw.Widget _buildColumn(List<_PrintRow> rows) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      pw.Container(
        height: 22,
        padding: const pw.EdgeInsets.symmetric(horizontal: 4),
        decoration: const pw.BoxDecoration(color: PdfColors.grey300),
        child: pw.Center(
          child: pw.Row(
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              pw.SizedBox(
                width: _distanceWidth,
                child: pw.Text(
                  AppStrings.paceSplitTableDistance,
                  style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.grey800,
                  ),
                ),
              ),
              pw.SizedBox(width: _pairGap),
              pw.SizedBox(
                width: _timeWidth,
                child: pw.Text(
                  AppStrings.paceSplitTableTime,
                  style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.grey800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      for (final row in rows) _buildRow(row),
    ],
  );
}

pw.Widget _buildRow(_PrintRow row) {
  final summary = row.summary;
  final point = row.point;
  return pw.Container(
    height: _rowHeight,
    padding: const pw.EdgeInsets.symmetric(horizontal: 4),
    decoration: const pw.BoxDecoration(
      border: pw.Border(
        bottom: pw.BorderSide(color: PdfColors.grey400, width: 0.4),
      ),
    ),
    child: summary != null
        ? pw.Align(
            alignment: pw.Alignment.centerLeft,
            child: pw.Text(
              summary,
              maxLines: 1,
              overflow: pw.TextOverflow.clip,
              style: pw.TextStyle(
                fontSize: 12.5,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          )
        : pw.Center(
            child: pw.Row(
              mainAxisSize: pw.MainAxisSize.min,
              children: [
                pw.SizedBox(
                  width: _distanceWidth,
                  child: pw.Text(
                    point?.distance ?? '',
                    style: const pw.TextStyle(fontSize: 13),
                  ),
                ),
                pw.SizedBox(width: _pairGap),
                pw.SizedBox(
                  width: _timeWidth,
                  child: pw.Text(
                    point?.time ?? '',
                    style: const pw.TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
  );
}

/// Строка печатной раскладки: либо строка сводки, либо контрольная точка.
class _PrintRow {
  const _PrintRow.summary(this.summary) : point = null;

  const _PrintRow.point(this.point) : summary = null;

  final String? summary;
  final PaceSplitPrintPoint? point;
}
