import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/app_strings.dart';

/// Одна строка таблицы раскладки для печати.
class PaceSplitPrintPoint {
  const PaceSplitPrintPoint({
    required this.distance,
    required this.time,
    this.left = '',
    this.right = '',
  });

  final String distance;
  final String time;

  /// Метки строки: `пп, био`.
  final String left;

  /// Питание строки: `гель, фрукты, вода`.
  final String right;
}

/// Данные для печати раскладки по контрольным точкам.
class PaceSplitPrintData {
  const PaceSplitPrintData({
    required this.title,
    required this.summary,
    required this.points,
  });

  final String title;

  /// Сводка (расстояние, темп, время, старт, шаг, гели и статистика).
  /// Печатается в начале первого столбца.
  final List<String> summary;

  final List<PaceSplitPrintPoint> points;
}

/// Макет печатной раскладки: две или три колонки на странице.
enum PaceSplitPrintLayout { twoColumns, threeColumns }

/// Сколько столбцов на странице и ширины клеток выбранного макета.
class _PrintLayout {
  const _PrintLayout({
    required this.columnsPerPage,
    required this.distanceWidth,
    required this.leftWidth,
    required this.rightWidth,
    required this.timeWidth,
    required this.cellGap,
    required this.distanceHeader,
  });

  final int columnsPerPage;
  final double distanceWidth;
  final double leftWidth;
  final double rightWidth;
  final double timeWidth;
  final double cellGap;
  final String distanceHeader;

  double get innerWidth =>
      distanceWidth + leftWidth + rightWidth + timeWidth + cellGap * 3;

  /// Две широкие колонки: прежний макет.
  static const twoColumns = _PrintLayout(
    columnsPerPage: 2,
    distanceWidth: 46,
    leftWidth: 58,
    rightWidth: 104,
    timeWidth: 42,
    cellGap: 4,
    distanceHeader: AppStrings.paceSplitTableDistance,
  );

  /// Три узкие колонки. Клетки переносятся, поэтому строки растут по высоте.
  static const threeColumns = _PrintLayout(
    columnsPerPage: 3,
    distanceWidth: 34,
    leftWidth: 36,
    rightWidth: 56,
    timeWidth: 38,
    cellGap: 3,
    distanceHeader: AppStrings.paceSplitTableDistanceShort,
  );
}

_PrintLayout _layoutFor(PaceSplitPrintLayout layout) {
  return switch (layout) {
    PaceSplitPrintLayout.twoColumns => _PrintLayout.twoColumns,
    PaceSplitPrintLayout.threeColumns => _PrintLayout.threeColumns,
  };
}

/// Высота строки таблицы без переноса.
const double _rowMinHeight = 22;

/// Высота заголовка столбца.
const double _headerHeight = 24;

/// Доступная высота одного столбца.
const double _columnBodyHeight = 690;

const double _pointFontSize = 8.5;
const double _lineHeight = 10.2;

/// Отступ сверху: 2 см.
const double _topMargin = 2 * PdfPageFormat.cm;

/// Собирает вертикальный PDF с раскладкой. Сводка идёт в начале первого
/// столбца, таблица продолжается в следующих столбцах и на новых страницах.
Future<Uint8List> buildPaceSplitPdf(
  PaceSplitPrintData data, {
  PaceSplitPrintLayout layout = PaceSplitPrintLayout.twoColumns,
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

  final printLayout = _layoutFor(layout);
  final pages = _paginate(data, printLayout);
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
                      column < printLayout.columnsPerPage;
                      column++
                    ) ...[
                      if (column > 0) pw.SizedBox(width: 10),
                      pw.Expanded(
                        child: _buildColumn(columns[column], printLayout),
                      ),
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

/// Делит строки на страницы и столбцы с учётом высоты переноса.
List<List<List<_PrintRow>>> _paginate(
  PaceSplitPrintData data,
  _PrintLayout layout,
) {
  final rows = <_PrintRow>[
    for (final line in data.summary) _PrintRow.summary(line),
    for (final point in data.points) _PrintRow.point(point),
  ];

  final pages = <List<List<_PrintRow>>>[];
  var columns = <List<_PrintRow>>[];
  var column = <_PrintRow>[];
  var height = 0.0;

  void finishColumn() {
    columns.add(column);
    column = <_PrintRow>[];
    height = 0;
  }

  void finishPage() {
    if (column.isNotEmpty || columns.isEmpty) finishColumn();
    while (columns.length < layout.columnsPerPage) {
      columns.add(<_PrintRow>[]);
    }
    pages.add(columns);
    columns = <List<_PrintRow>>[];
    column = <_PrintRow>[];
    height = 0;
  }

  for (final row in rows) {
    final rowHeight = row.height(layout);
    if (column.isNotEmpty && height + rowHeight > _columnBodyHeight) {
      finishColumn();
      if (columns.length >= layout.columnsPerPage) finishPage();
    }
    column.add(row);
    height += rowHeight;
  }

  if (column.isNotEmpty || columns.isNotEmpty || pages.isEmpty) {
    finishPage();
  }

  if (pages.isEmpty) {
    pages.add(<List<_PrintRow>>[
      for (var index = 0; index < layout.columnsPerPage; index++) <_PrintRow>[],
    ]);
  }

  return pages;
}

pw.Widget _buildColumn(List<_PrintRow> rows, _PrintLayout layout) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      pw.Container(
        height: _headerHeight,
        padding: const pw.EdgeInsets.symmetric(horizontal: 4),
        decoration: const pw.BoxDecoration(color: PdfColors.grey300),
        child: pw.Center(
          child: pw.Row(
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              pw.SizedBox(
                width: layout.distanceWidth,
                child: _headerText(layout.distanceHeader),
              ),
              pw.SizedBox(width: layout.cellGap),
              pw.SizedBox(
                width: layout.leftWidth,
                child: _headerText(AppStrings.paceGelLeftHeader),
              ),
              pw.SizedBox(width: layout.cellGap),
              pw.SizedBox(
                width: layout.rightWidth,
                child: _headerText(AppStrings.paceGelRightHeader),
              ),
              pw.SizedBox(width: layout.cellGap),
              pw.SizedBox(
                width: layout.timeWidth,
                child: _headerText(AppStrings.paceSplitTableTime),
              ),
            ],
          ),
        ),
      ),
      for (final row in rows) _buildRow(row, layout),
    ],
  );
}

pw.Widget _headerText(String text) {
  return pw.Text(
    text,
    maxLines: 1,
    overflow: pw.TextOverflow.clip,
    style: pw.TextStyle(
      fontSize: 8,
      fontWeight: pw.FontWeight.bold,
      color: PdfColors.grey800,
    ),
  );
}

pw.Widget _buildRow(_PrintRow row, _PrintLayout layout) {
  final summary = row.summary;
  final point = row.point;
  return pw.Container(
    height: row.height(layout),
    padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
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
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
            ),
          )
        : pw.Row(
            mainAxisSize: pw.MainAxisSize.min,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(
                width: layout.distanceWidth,
                child: pw.Text(
                  point?.distance ?? '',
                  style: const pw.TextStyle(fontSize: 9),
                ),
              ),
              pw.SizedBox(width: layout.cellGap),
              pw.SizedBox(
                width: layout.leftWidth,
                child: pw.Text(
                  point?.left ?? '',
                  style: const pw.TextStyle(fontSize: _pointFontSize),
                ),
              ),
              pw.SizedBox(width: layout.cellGap),
              pw.SizedBox(
                width: layout.rightWidth,
                child: pw.Text(
                  point?.right ?? '',
                  style: const pw.TextStyle(fontSize: _pointFontSize),
                ),
              ),
              pw.SizedBox(width: layout.cellGap),
              pw.SizedBox(
                width: layout.timeWidth,
                child: pw.Text(
                  point?.time ?? '',
                  style: const pw.TextStyle(fontSize: _pointFontSize),
                ),
              ),
            ],
          ),
  );
}

int _lineCount(String text, double width, double fontSize) {
  if (text.isEmpty) return 1;
  final charsPerLine = math.max(1, (width / (fontSize * 0.55)).floor());
  var lines = 0;
  for (final part in text.split('\n')) {
    lines += math.max(1, (part.length / charsPerLine).ceil());
  }
  return math.max(1, lines);
}

/// Строка печатной раскладки: либо строка сводки, либо контрольная точка.
class _PrintRow {
  const _PrintRow.summary(this.summary) : point = null;

  const _PrintRow.point(this.point) : summary = null;

  final String? summary;
  final PaceSplitPrintPoint? point;

  double height(_PrintLayout layout) {
    final summary = this.summary;
    if (summary != null) {
      final lines = _lineCount(summary, layout.innerWidth, 11);
      return math.max(_rowMinHeight, lines * 13.0 + 6);
    }
    final point = this.point!;
    final lines = [
      _lineCount(point.distance, layout.distanceWidth, 9),
      _lineCount(point.left, layout.leftWidth, _pointFontSize),
      _lineCount(point.right, layout.rightWidth, _pointFontSize),
      _lineCount(point.time, layout.timeWidth, _pointFontSize),
    ].reduce(math.max);
    return math.max(_rowMinHeight, lines * _lineHeight + 6);
  }
}
