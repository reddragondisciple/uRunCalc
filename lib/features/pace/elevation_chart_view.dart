import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/app_strings.dart';
import '../gpx/elevation_format.dart';
import '../gpx/elevation_profile.dart';
import 'environment_data.dart';

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

/// Цвет линии покрытия на графике. Легенды нет, цвет только различает типы.
Color surfaceOverlayColor(SurfaceType type) => switch (type) {
  SurfaceType.asphalt => const Color(0xFFB0BEC5),
  SurfaceType.concrete => const Color(0xFFCFD8DC),
  SurfaceType.pavingStones => const Color(0xFFD7B377),
  SurfaceType.compacted => const Color(0xFFC8A96B),
  SurfaceType.dirt => const Color(0xFF8D6E63),
  SurfaceType.ground => const Color(0xFF795548),
  SurfaceType.grass => const Color(0xFF66BB6A),
  SurfaceType.sand => const Color(0xFFE6C86E),
  SurfaceType.mud => const Color(0xFF4E342E),
  SurfaceType.snowPacked => const Color(0xFFB3E5FC),
  SurfaceType.snowDeep => const Color(0xFFE1F5FE),
  SurfaceType.unknown => const Color(0xFF8D6E63),
};

/// Прозрачность синей линии мокрости.
Color wetnessOverlayColor(Wetness wetness) => switch (wetness) {
  Wetness.dry => const Color(0x2664B5F6),
  Wetness.damp => const Color(0x6681D4FA),
  Wetness.wet => const Color(0xAA42A5F5),
  Wetness.saturated => const Color(0xDD29B6F6),
  Wetness.bog => const Color(0xEE26C6DA),
};

/// Цвет полупрозрачной полосы по «ощущается как». Без легенды.
Color apparentTemperatureColor(double apparentC) {
  if (apparentC <= -15) return const Color(0xFF3949AB);
  if (apparentC <= -5) return const Color(0xFF42A5F5);
  if (apparentC <= 5) return const Color(0xFF4DD0E1);
  if (apparentC <= 15) return const Color(0xFF81C784);
  if (apparentC <= 22) return const Color(0xFFFFF176);
  if (apparentC <= 28) return const Color(0xFFFFB74D);
  if (apparentC <= 35) return const Color(0xFFFF7043);
  return const Color(0xFFD32F2F);
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
    this.environment,
  });

  final List<ProfilePoint> profile;
  final double fromKm;
  final double toKm;
  final List<ElevationMarker> markers;
  final double? touchKm;

  /// Покрытие, мокрость, болота, броды и погода. `null` — слой не рисуется.
  final EnvironmentData? environment;

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

    canvas.save();
    canvas.clipRect(Offset.zero & size);

    // Погодная полоса — за сеткой и профилем, у верхнего края.
    _paintWeatherBand(canvas, size, xOf);

    _paintGrid(canvas, size, floorE, topE, altStep, xOf, yOf);

    // Низ графика: болото, мокрость и линия покрытия.
    _paintSurfaceOverlays(canvas, size, xOf);
    _paintFords(canvas, size, xOf);

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
    canvas.restore();
  }

  /// Полупрозрачная полоса по `apparent_temperature`. Нет прогноза — нет
  /// полосы: климатические нормы не выдаём за погоду.
  void _paintWeatherBand(
    Canvas canvas,
    Size size,
    double Function(double) xOf,
  ) {
    final env = environment;
    if (env == null || !env.hasForecast || env.weather.isEmpty) return;
    final samples = [...env.weather]
      ..sort((a, b) => a.distanceM.compareTo(b.distanceM));
    final bandHeight = math.min(18.0, size.height * 0.12);
    for (var i = 0; i < samples.length; i++) {
      final sample = samples[i];
      final km = sample.distanceM / 1000;
      final prevKm = i == 0 ? fromKm : samples[i - 1].distanceM / 1000;
      final nextKm = i == samples.length - 1
          ? toKm
          : samples[i + 1].distanceM / 1000;
      final left = math.max(fromKm, (prevKm + km) / 2);
      final right = math.min(toKm, (km + nextKm) / 2);
      if (right <= left) continue;
      final paint = Paint()
        ..color = apparentTemperatureColor(
          sample.apparentC,
        ).withValues(alpha: 0.35);
      canvas.drawRect(
        Rect.fromLTRB(xOf(left), 0, xOf(right), bandHeight),
        paint,
      );
    }
  }

  /// Низ графика: широкая полоса болота, синяя линия мокрости и линия
  /// покрытия. Высота фиксированная, чтобы не отнимать место у профиля.
  void _paintSurfaceOverlays(
    Canvas canvas,
    Size size,
    double Function(double) xOf,
  ) {
    final env = environment;
    if (env == null || env.surface.isEmpty) return;

    final bottom = size.height;
    const bogTop = 13.0;
    const bogBottom = 7.0;
    const wetnessY = 5.0;
    const surfaceY = 1.5;

    for (final run in env.surface) {
      final startKm = run.startM / 1000;
      final endKm = run.endM / 1000;
      if (endKm < fromKm || startKm > toKm) continue;
      final left = xOf(math.max(fromKm, startKm));
      final right = xOf(math.min(toKm, endKm));
      if (right <= left) continue;

      if (run.isBog) {
        canvas.drawRect(
          Rect.fromLTRB(left, bottom - bogTop, right, bottom - bogBottom),
          Paint()..color = const Color(0xFF6D4C41).withValues(alpha: 0.55),
        );
      }

      canvas.drawLine(
        Offset(left, bottom - wetnessY),
        Offset(right, bottom - wetnessY),
        Paint()
          ..color = wetnessOverlayColor(run.wetness)
          ..strokeWidth = 1.6,
      );
      canvas.drawLine(
        Offset(left, bottom - surfaceY),
        Offset(right, bottom - surfaceY),
        Paint()
          ..color = surfaceOverlayColor(run.type)
          ..strokeWidth = 2.4,
      );
    }
  }

  /// Броды: сплошная синяя линия — подтверждённый, пунктир — возможный.
  void _paintFords(Canvas canvas, Size size, double Function(double) xOf) {
    final env = environment;
    if (env == null || env.fords.isEmpty) return;
    for (final ford in env.fords) {
      final km = ford.distanceM / 1000;
      if (km < fromKm || km > toKm) continue;
      final x = xOf(km);
      final paint = Paint()
        ..color = const Color(0xFF40C4FF)
        ..strokeWidth = 2;
      final from = Offset(x, 0);
      final to = Offset(x, size.height);
      if (ford.confirmed) {
        canvas.drawLine(from, to, paint);
      } else {
        _drawDashedLine(canvas, from, to, paint);
      }
    }
  }

  void _drawDashedLine(
    Canvas canvas,
    Offset from,
    Offset to,
    Paint paint, {
    double dash = 4,
    double gap = 4,
  }) {
    final delta = to - from;
    final length = delta.distance;
    if (length <= 0) return;
    final direction = delta / length;
    var travelled = 0.0;
    while (travelled < length) {
      final end = math.min(travelled + dash, length);
      canvas.drawLine(
        from + direction * travelled,
        from + direction * end,
        paint,
      );
      travelled = end + gap;
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
      if (m.label.isNotEmpty) {
        _text(canvas, m.label, Offset(x + 2, 2), 10, color: Colors.amberAccent);
      }
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
      !identical(old.environment, environment) ||
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
    this.environment,
  });

  final List<ProfilePoint> profile;
  final List<ElevationMarker> markers;
  final double totalAscentM;
  final double totalDescentM;

  /// Километраж колонок ПП от старта, по возрастанию. Используется для
  /// фокуса на сегменте «ПП i → ПП i+1».
  final List<double> boundariesKm;

  /// Покрытие, мокрость, болота, броды и погода. `null` — слои не рисуются.
  final EnvironmentData? environment;
}

/// Открывает карту: bottom sheet в портрете, полупрозрачный экран на весь
/// размер в ландшафте. Закрывается крестиком, свайпом вниз (sheet) и
/// системной кнопкой «назад».
Future<void> showElevationChart(
  BuildContext context,
  ElevationChartData data, {
  double? initialFromKm,
  double? initialToKm,
}) {
  final landscape = MediaQuery.orientationOf(context) == Orientation.landscape;
  if (landscape) {
    return Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierDismissible: true,
        barrierColor: Colors.black54,
        pageBuilder: (_, _, _) => _ElevationChartScaffold(
          data: data,
          landscape: true,
          initialFromKm: initialFromKm,
          initialToKm: initialToKm,
        ),
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
      child: _ElevationChartScaffold(
        data: data,
        landscape: false,
        initialFromKm: initialFromKm,
        initialToKm: initialToKm,
      ),
    ),
  );
}

class _ElevationChartScaffold extends StatefulWidget {
  const _ElevationChartScaffold({
    required this.data,
    required this.landscape,
    this.initialFromKm,
    this.initialToKm,
  });

  final ElevationChartData data;
  final bool landscape;

  /// Начальный фокус: сегмент, по клетке которого открыли окно.
  final double? initialFromKm;
  final double? initialToKm;

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
    final wholeFrom = _wholeFrom;
    final wholeTo = _wholeTo;
    final from = widget.initialFromKm;
    final to = widget.initialToKm;
    if (from != null && to != null && to > from && wholeTo > wholeFrom) {
      final clampedFrom = math.max(wholeFrom, from);
      final clampedTo = math.min(wholeTo, to);
      if (clampedTo > clampedFrom) {
        _fromKm = clampedFrom;
        _toKm = clampedTo;
        return;
      }
    }
    _fromKm = wholeFrom;
    _toKm = wholeTo;
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
                            environment: data.environment,
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
