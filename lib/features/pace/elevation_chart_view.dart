import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/app_strings.dart';
import '../gpx/elevation_format.dart';
import '../gpx/elevation_profile.dart';

/// Маркер ПП на профиле: километраж и подпись.
class ElevationMarker {
  const ElevationMarker({required this.km, required this.label});

  final double km;
  final String label;
}

/// Цвет по классу крутизны (§8.3: зелёный → жёлтый → оранжевый → красный).
Color gradeColor(GradeBand band) => switch (band) {
  GradeBand.flat => const Color(0xFF4CAF50),
  GradeBand.gentle => const Color(0xFFCDDC39),
  GradeBand.moderate => const Color(0xFFFF9800),
  GradeBand.steep => const Color(0xFFF44336),
  GradeBand.extreme => const Color(0xFFB71C1C),
};

/// Шаг сетки по вертикали (м) по диапазону высот: 100/250/500.
double altitudeGridStep(double rangeM) {
  if (rangeM <= 400) return 100;
  if (rangeM <= 1200) return 250;
  return 500;
}

/// Шаг сетки по горизонтали (км) по диапазону: 1/2/5/10/20.
double distanceGridStep(double rangeKm) {
  if (rangeKm <= 10) return 1;
  if (rangeKm <= 30) return 2;
  if (rangeKm <= 60) return 5;
  if (rangeKm <= 120) return 10;
  return 20;
}

/// Рисует профиль: сетку, линию с цветом по крутизне, маркеры ПП и
/// подсветку тапа. Путь строится один раз на данные и диапазон.
class ElevationProfilePainter extends CustomPainter {
  ElevationProfilePainter({
    required this.profile,
    required this.fromKm,
    required this.toKm,
    required this.markers,
    this.touchKm,
  });

  final List<ProfilePoint> profile;
  final double fromKm;
  final double toKm;
  final List<ElevationMarker> markers;
  final double? touchKm;

  @override
  void paint(Canvas canvas, Size size) {
    if (profile.isEmpty || toKm <= fromKm) return;
    final visible = profileBetween(profile, fromKm, toKm);
    if (visible.isEmpty) return;

    var minE = visible.first.eleM;
    var maxE = visible.first.eleM;
    for (final p in visible) {
      minE = math.min(minE, p.eleM);
      maxE = math.max(maxE, p.eleM);
    }
    final altStep = altitudeGridStep(maxE - minE);
    final floorE = (minE / altStep).floor() * altStep;
    final topE = (maxE / altStep).ceil() * altStep;
    final rangeE = math.max(1.0, topE - floorE);

    double xOf(double km) => (km - fromKm) / (toKm - fromKm) * size.width;
    double yOf(double ele) =>
        size.height - (ele - floorE) / rangeE * size.height;

    _paintGrid(canvas, size, floorE, topE, altStep, xOf, yOf);

    // Линия по сегментам с цветом класса крутизны.
    final paint = Paint()
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (var i = 1; i < visible.length; i++) {
      final a = visible[i - 1];
      final b = visible[i];
      paint.color = gradeColor(gradeBand(b.gradeFraction));
      canvas.drawLine(
        Offset(xOf(a.km), yOf(a.eleM)),
        Offset(xOf(b.km), yOf(b.eleM)),
        paint,
      );
    }

    _paintMarkers(canvas, size, xOf);

    final touch = touchKm;
    if (touch != null && touch >= fromKm && touch <= toKm) {
      final x = xOf(touch);
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        Paint()
          ..color = Colors.white70
          ..strokeWidth = 1,
      );
    }
  }

  void _paintGrid(
    Canvas canvas,
    Size size,
    double floorE,
    double topE,
    double altStep,
    double Function(double) xOf,
    double Function(double) yOf,
  ) {
    final grid = Paint()
      ..color = Colors.white24
      ..strokeWidth = 1;
    for (var e = floorE; e <= topE + 0.001; e += altStep) {
      final y = yOf(e);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
      _text(canvas, '${e.round()}', Offset(2, y - 12), 10);
    }
    final kmStep = distanceGridStep(toKm - fromKm);
    final firstKm = (fromKm / kmStep).ceil() * kmStep;
    for (var km = firstKm; km <= toKm + 0.001; km += kmStep) {
      final x = xOf(km);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
      _text(
        canvas,
        AppStrings.elevationChartAxisKm(
          km.toStringAsFixed(km % 1 == 0 ? 0 : 1),
        ),
        Offset(x + 2, size.height - 14),
        10,
      );
    }
  }

  void _paintMarkers(Canvas canvas, Size size, double Function(double) xOf) {
    for (final m in markers) {
      if (m.km < fromKm || m.km > toKm) continue;
      final x = xOf(m.km);
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        Paint()
          ..color = Colors.amberAccent.withValues(alpha: 0.7)
          ..strokeWidth = 1,
      );
      _text(canvas, m.label, Offset(x + 2, 2), 10, color: Colors.amberAccent);
    }
  }

  void _text(
    Canvas canvas,
    String text,
    Offset at,
    double size, {
    Color color = Colors.white70,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: size),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at);
  }

  @override
  bool shouldRepaint(ElevationProfilePainter old) =>
      old.fromKm != fromKm ||
      old.toKm != toKm ||
      old.touchKm != touchKm ||
      !identical(old.profile, profile) ||
      old.markers.length != markers.length;
}

/// Данные для карты, собранные экраном таблицы.
class ElevationChartData {
  const ElevationChartData({
    required this.profile,
    required this.markers,
    required this.totalAscentM,
    required this.totalDescentM,
    required this.boundariesKm,
  });

  final List<ProfilePoint> profile;
  final List<ElevationMarker> markers;
  final double totalAscentM;
  final double totalDescentM;

  /// Километраж колонок ПП от старта, по возрастанию. Используется для
  /// фокуса на сегменте «ПП i → ПП i+1».
  final List<double> boundariesKm;
}

/// Открывает карту: bottom sheet в портрете, полупрозрачный экран на весь
/// размер в ландшафте. Закрывается крестиком, свайпом вниз (sheet) и
/// системной кнопкой «назад».
Future<void> showElevationChart(BuildContext context, ElevationChartData data) {
  final landscape = MediaQuery.orientationOf(context) == Orientation.landscape;
  if (landscape) {
    return Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierDismissible: true,
        barrierColor: Colors.black54,
        pageBuilder: (_, _, _) =>
            _ElevationChartScaffold(data: data, landscape: true),
      ),
    );
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.5,
      child: _ElevationChartScaffold(data: data, landscape: false),
    ),
  );
}

class _ElevationChartScaffold extends StatefulWidget {
  const _ElevationChartScaffold({required this.data, required this.landscape});

  final ElevationChartData data;
  final bool landscape;

  @override
  State<_ElevationChartScaffold> createState() =>
      _ElevationChartScaffoldState();
}

class _ElevationChartScaffoldState extends State<_ElevationChartScaffold> {
  static final ButtonStyle _compactButton = TextButton.styleFrom(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    minimumSize: const Size(0, 36),
  );

  /// Текущее окно по километрам. По умолчанию — весь трек.
  late double _fromKm;
  late double _toKm;
  double? _touchKm;

  double get _wholeFrom =>
      widget.data.profile.isEmpty ? 0 : widget.data.profile.first.km;
  double get _wholeTo =>
      widget.data.profile.isEmpty ? 0 : widget.data.profile.last.km;

  bool get _focused => _fromKm > _wholeFrom || _toKm < _wholeTo;

  @override
  void initState() {
    super.initState();
    _fromKm = _wholeFrom;
    _toKm = _wholeTo;
  }

  void _focusSegment(double km) {
    final bounds = widget.data.boundariesKm;
    if (bounds.length < 2) return;
    // Сегмент, в который попал тап: между соседними колонками ПП.
    for (var i = 0; i + 1 < bounds.length; i++) {
      if (km >= bounds[i] && km <= bounds[i + 1]) {
        setState(() {
          _fromKm = bounds[i];
          _toKm = bounds[i + 1];
          _touchKm = null;
        });
        return;
      }
    }
  }

  void _resetFocus() {
    setState(() {
      _fromKm = _wholeFrom;
      _toKm = _wholeTo;
      _touchKm = null;
    });
  }

  double _kmAt(Offset local, double width) {
    final ratio = (local.dx / width).clamp(0.0, 1.0);
    return _fromKm + ratio * (_toKm - _fromKm);
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final theme = Theme.of(context);
    final hasData = data.profile.isNotEmpty;

    final touch = _touchKm == null
        ? null
        : nearestProfilePoint(data.profile, _touchKm!);

    final content = Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  AppStrings.elevationChartTitle,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              if (hasData && data.boundariesKm.length >= 2)
                Flexible(
                  child: TextButton(
                    key: const ValueKey('elevation-chart-segment'),
                    style: _compactButton,
                    onPressed: _touchKm == null
                        ? null
                        : () => _focusSegment(_touchKm!),
                    child: const Text(
                      AppStrings.elevationChartSegmentFocus,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              if (_focused)
                Flexible(
                  child: TextButton(
                    key: const ValueKey('elevation-chart-reset'),
                    style: _compactButton,
                    onPressed: _resetFocus,
                    child: const Text(
                      AppStrings.elevationChartWholeDistance,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              IconButton(
                key: const ValueKey('elevation-chart-close'),
                tooltip: AppStrings.elevationChartClose,
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              AppStrings.elevationChartSummary(
                ascent: formatElevationValue(data.totalAscentM),
                descent: formatElevationValue(data.totalDescentM),
              ),
              style: theme.textTheme.bodySmall,
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: !hasData
                ? Center(child: Text(AppStrings.elevationChartNoData))
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final size = Size(
                        constraints.maxWidth,
                        constraints.maxHeight,
                      );
                      return GestureDetector(
                        key: const ValueKey('elevation-chart-canvas'),
                        behavior: HitTestBehavior.opaque,
                        onTapDown: (d) => setState(
                          () => _touchKm = _kmAt(d.localPosition, size.width),
                        ),
                        onDoubleTapDown: (d) {
                          final km = _kmAt(d.localPosition, size.width);
                          setState(() => _touchKm = km);
                          _focusSegment(km);
                        },
                        child: CustomPaint(
                          size: size,
                          painter: ElevationProfilePainter(
                            profile: data.profile,
                            fromKm: _fromKm,
                            toKm: _toKm,
                            markers: data.markers,
                            touchKm: _touchKm,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ),
        if (touch != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                AppStrings.elevationChartPoint(
                  km: touch.km.toStringAsFixed(2),
                  ele: touch.eleM.round().toString(),
                  grade: '${(touch.gradeFraction * 100).toStringAsFixed(1)}%',
                ),
                key: const ValueKey('elevation-chart-touch'),
              ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              AppStrings.elevationChartHint,
              style: theme.textTheme.bodySmall,
            ),
          ),
      ],
    );

    return PopScope(
      canPop: true,
      child: widget.landscape
          ? Material(
              color: Colors.black.withValues(alpha: 0.85),
              child: SafeArea(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onVerticalDragEnd: (d) {
                    if ((d.primaryVelocity ?? 0) > 300) {
                      Navigator.of(context).maybePop();
                    }
                  },
                  child: content,
                ),
              ),
            )
          : Material(child: content),
    );
  }
}
