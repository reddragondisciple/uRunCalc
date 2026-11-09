import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'core/app_strings.dart';
import 'features/gpx/elevation_profile.dart';

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
    this.activeTrack = '',
    this.elevationPairs = const [],
    this.totalAscent = '',
    this.totalDescent = '',
    this.profile = const [],
    this.elevationKms = const [],
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

  /// Подпись активного слота трека: «Основной» или «Резервный».
  final String activeTrack;

  /// D+/D− по колонкам. Индекс 0 — старт, значение пустое.
  final List<String> elevationPairs;

  /// Итоги набора и сброса по всей дистанции, метры.
  final String totalAscent;
  final String totalDescent;

  /// Профиль высот для карты. Пустой список — карту не печатаем.
  final List<ProfilePoint> profile;

  /// Километраж колонок от старта. Нужен для маркеров и диапазона страницы.
  final List<double> elevationKms;

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

/// Высота рядов «Вода» и «Еда»: примерно в три раза больше обычной строки.
const double _waterFoodRowHeight = 54;

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
    final range = _chartRange(data, chunks, pageIndex);
    document.addPage(
      pw.Page(
        pageFormat: format,
        margin: const pw.EdgeInsets.all(22),
        build: (context) {
          final chart = range == null
              ? null
              : _elevationChart(context, data, columns, range, regular);
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Text(
                data.event.isEmpty ? AppStrings.appName : data.event,
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                AppStrings.printPlanTitle,
                style: const pw.TextStyle(
                  fontSize: 9,
                  color: PdfColors.grey700,
                ),
              ),
              pw.SizedBox(height: 10),
              _summary(data),
              pw.SizedBox(height: 10),
              _table(data, columns),
              if (chart != null) ...[
                pw.SizedBox(height: 8),
                if (landscape)
                  pw.Expanded(child: chart)
                else
                  pw.SizedBox(height: 220, child: chart),
              ],
              pw.SizedBox(height: 4),
              pw.Text(
                AppStrings.printPage(pageIndex + 1, chunks.length),
                style: const pw.TextStyle(
                  fontSize: 8,
                  color: PdfColors.grey600,
                ),
              ),
            ],
          );
        },
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
        if (data.activeTrack.isNotEmpty) ...[
          pw.Text(
            AppStrings.printTrackSummary(data.activeTrack),
            style: const pw.TextStyle(fontSize: 9),
          ),
          pw.SizedBox(height: 3),
        ],
        pw.Text(
          AppStrings.printLimitSummary(data.limitTime, data.limitPace),
          style: const pw.TextStyle(fontSize: 9),
        ),
        pw.SizedBox(height: 3),
        pw.Text(
          AppStrings.printPlanSummary(data.plannedPace, data.plannedTime),
          style: const pw.TextStyle(fontSize: 9),
        ),
        if (data.totalAscent.isNotEmpty || data.totalDescent.isNotEmpty) ...[
          pw.SizedBox(height: 3),
          pw.Text(
            AppStrings.printElevationSummary(
              data.totalAscent,
              data.totalDescent,
            ),
            style: const pw.TextStyle(fontSize: 9),
          ),
        ],
      ],
    ),
  );
}

pw.Widget _table(PrintTableData data, List<int> columns) {
  final rows = <_PrintRow>[
    _PrintRow(label: AppStrings.printTimeLimit, values: data.times),
    _PrintRow(label: AppStrings.paceRowDistance, values: data.distances),
    _PrintRow(label: AppStrings.paceRowSegmentPace, values: data.segmentPaces),
    if (data.elevationPairs.isNotEmpty)
      _PrintRow(
        label: AppStrings.printElevationRow,
        values: data.elevationPairs,
      ),
    _PrintRow(label: AppStrings.paceRowPlan, values: data.planTimes),
    _PrintRow(label: AppStrings.paceRowPlanPace, values: data.planPaces),
    _PrintRow(
      label: AppStrings.paceRowWater,
      values: data.water,
      left: true,
      short: true,
      minHeight: _waterFoodRowHeight,
    ),
    _PrintRow(
      label: AppStrings.paceRowFood,
      values: data.food,
      left: true,
      short: true,
      minHeight: _waterFoodRowHeight,
    ),
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
      for (final row in rows)
        pw.TableRow(
          children: [
            _cell(row.label, bold: true, minHeight: row.minHeight),
            for (final column in columns)
              _cell(
                row.short
                    ? _short(data._at(row.values, column))
                    : data._at(row.values, column),
                align: row.left ? pw.TextAlign.left : pw.TextAlign.center,
                background: data._dayBackground(column),
                boldBorder: data.boldColumns.contains(column),
                minHeight: row.minHeight,
              ),
          ],
        ),
    ],
  );
}

class _PrintRow {
  const _PrintRow({
    required this.label,
    required this.values,
    this.left = false,
    this.short = false,
    this.minHeight,
  });

  final String label;
  final List<String> values;
  final bool left;
  final bool short;
  final double? minHeight;
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
  double? minHeight,
}) {
  final content = pw.Container(
    color: background,
    padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 3),
    constraints: minHeight == null
        ? null
        : pw.BoxConstraints(minHeight: minHeight),
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

/// Диапазон карты для страницы. Первая страница — от старта до последней
/// колонки страницы, следующие — от последней колонки предыдущей страницы.
({double fromKm, double toKm})? _chartRange(
  PrintTableData data,
  List<List<int>> chunks,
  int pageIndex,
) {
  if (data.profile.isEmpty) return null;
  final profileStart = data.profile.first.km;
  final profileEnd = data.profile.last.km;
  if (profileEnd <= profileStart) return null;

  double? kmAt(int index) {
    if (index < 0 || index >= data.elevationKms.length) return null;
    final km = data.elevationKms[index];
    return km.isFinite ? km : null;
  }

  final columns = chunks[pageIndex];
  final from = pageIndex == 0
      ? kmAt(columns.first)
      : kmAt(chunks[pageIndex - 1].last);
  final to = kmAt(columns.last);
  var start = (from ?? profileStart).clamp(profileStart, profileEnd).toDouble();
  var end = (to ?? profileEnd).clamp(profileStart, profileEnd).toDouble();
  if (end <= start) {
    start = profileStart;
    end = profileEnd;
  }
  return (fromKm: start, toKm: end);
}

pw.Widget _elevationChart(
  pw.Context context,
  PrintTableData data,
  List<int> columns,
  ({double fromKm, double toKm}) range,
  pw.Font font,
) {
  final visible = profileBetween(data.profile, range.fromKm, range.toKm);
  if (visible.isEmpty) {
    return pw.Container(
      alignment: pw.Alignment.center,
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey500, width: 0.6),
      ),
      child: pw.Text(
        AppStrings.elevationChartNoData,
        style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
      ),
    );
  }

  final markers = <_ChartMarker>[
    for (final column in columns)
      if (column < data.elevationKms.length)
        _ChartMarker(
          km: data.elevationKms[column],
          label: _markerLabel(data, column),
        ),
  ].where((m) => m.km >= range.fromKm && m.km <= range.toKm).toList();

  final pdfFont = font.getFont(context);
  return pw.Container(
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: PdfColors.grey500, width: 0.6),
    ),
    child: pw.CustomPaint(
      painter: (canvas, size) => _paintElevationChart(
        canvas: canvas,
        size: size,
        profile: visible,
        fromKm: range.fromKm,
        toKm: range.toKm,
        markers: markers,
        font: pdfFont,
      ),
    ),
  );
}

String _markerLabel(PrintTableData data, int column) {
  final label = data._at(data.columns, column).split('\n').first.trim();
  return label;
}

class _ChartMarker {
  const _ChartMarker({required this.km, required this.label});

  final double km;
  final String label;
}

void _paintElevationChart({
  required PdfGraphics canvas,
  required PdfPoint size,
  required List<ProfilePoint> profile,
  required double fromKm,
  required double toKm,
  required List<_ChartMarker> markers,
  required PdfFont font,
}) {
  if (profile.isEmpty || toKm <= fromKm || size.x <= 0 || size.y <= 0) {
    return;
  }

  var minE = profile.first.eleM;
  var maxE = profile.first.eleM;
  for (final point in profile) {
    minE = math.min(minE, point.eleM);
    maxE = math.max(maxE, point.eleM);
  }
  final altStep = _altitudeStep(maxE - minE);
  final floorE = (minE / altStep).floor() * altStep;
  final topE = (maxE / altStep).ceil() * altStep;
  final rangeE = math.max(1.0, topE - floorE);

  double xOf(double km) => (km - fromKm) / (toKm - fromKm) * size.x;
  double yOf(double ele) => (ele - floorE) / rangeE * size.y;

  // Сетка: светлее графика, чтобы не конкурировать с линией высот.
  const gridColor = PdfColorGrey(0.82);
  canvas.setFillColor(const PdfColorGrey(0.35));
  for (
    var elevation = floorE;
    elevation <= topE + 0.001;
    elevation += altStep
  ) {
    final y = yOf(elevation);
    _strokeLine(canvas, gridColor, 0.4, 0, y, size.x, y);
    canvas.drawString(font, 6, '${elevation.round()}', 2, y + 1);
  }

  final kmStep = _distanceStep(toKm - fromKm);
  final firstKm = (fromKm / kmStep).ceil() * kmStep;
  for (var km = firstKm; km <= toKm + 0.001; km += kmStep) {
    final x = xOf(km);
    _strokeLine(canvas, gridColor, 0.4, x, 0, x, size.y);
    final label = km % 1 == 0 ? km.toStringAsFixed(0) : km.toStringAsFixed(1);
    canvas.drawString(font, 6, label, x + 2, 2);
  }

  // Линия профиля: ровные участки светлее, крутые — темнее и толще.
  for (var index = 1; index < profile.length; index++) {
    final a = profile[index - 1];
    final b = profile[index];
    final band = gradeBand(b.gradeFraction);
    _strokeLine(
      canvas,
      _gradeGrey(band),
      _gradeWidth(band),
      xOf(a.km),
      yOf(a.eleM),
      xOf(b.km),
      yOf(b.eleM),
    );
  }

  // Маркеры ПП: тонкая линия и подпись сверху.
  for (final marker in markers) {
    final x = xOf(marker.km);
    _strokeLine(canvas, const PdfColorGrey(0.55), 0.5, x, 0, x, size.y);
    if (marker.label.isNotEmpty) {
      canvas.setFillColor(const PdfColorGrey(0.2));
      canvas.drawString(font, 7, marker.label, x + 2, size.y - 8);
    }
  }
}

void _strokeLine(
  PdfGraphics canvas,
  PdfColor color,
  double width,
  double x1,
  double y1,
  double x2,
  double y2,
) {
  canvas
    ..setStrokeColor(color)
    ..setLineWidth(width)
    ..drawLine(x1, y1, x2, y2)
    ..strokePath();
}

PdfColor _gradeGrey(GradeBand band) => switch (band) {
  GradeBand.flat => const PdfColorGrey(0.76),
  GradeBand.gentle => const PdfColorGrey(0.62),
  GradeBand.moderate => const PdfColorGrey(0.44),
  GradeBand.steep => const PdfColorGrey(0.22),
  GradeBand.extreme => PdfColors.black,
};

double _gradeWidth(GradeBand band) => switch (band) {
  GradeBand.flat => 0.6,
  GradeBand.gentle => 0.8,
  GradeBand.moderate => 1.0,
  GradeBand.steep => 1.2,
  GradeBand.extreme => 1.4,
};

double _altitudeStep(double rangeM) {
  if (rangeM <= 400) return 100;
  if (rangeM <= 1200) return 250;
  return 500;
}

double _distanceStep(double rangeKm) {
  if (rangeKm <= 10) return 1;
  if (rangeKm <= 30) return 2;
  if (rangeKm <= 60) return 5;
  if (rangeKm <= 120) return 10;
  return 20;
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
