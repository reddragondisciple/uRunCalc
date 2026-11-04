import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Мигающий курсор ввода.
///
/// Таймер живёт внутри виджета, поэтому мигание перерисовывает только курсор,
/// а не всю таблицу. Курсор декоративный и скрыт от screen reader.
class BlinkingCursor extends StatefulWidget {
  const BlinkingCursor({
    super.key,
    this.active = true,
    this.width = 2,
    this.height = 18,
    this.color = AppColors.focus,
  });

  /// Когда `false`, таймер не запускается: курсор остаётся видимым.
  final bool active;
  final double width;
  final double height;
  final Color color;

  @override
  State<BlinkingCursor> createState() => _BlinkingCursorState();
}

class _BlinkingCursorState extends State<BlinkingCursor> {
  static const Duration _interval = Duration(milliseconds: 500);

  Timer? _timer;
  bool _visible = true;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(covariant BlinkingCursor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active != oldWidget.active) _start();
  }

  void _start() {
    _timer?.cancel();
    _visible = true;
    if (!widget.active) return;

    _timer = Timer.periodic(_interval, (_) {
      if (!mounted) return;
      setState(() => _visible = !_visible);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Opacity(
        opacity: _visible ? 1 : 0,
        child: Container(
          width: widget.width,
          height: widget.height,
          margin: const EdgeInsets.only(left: 1),
          color: widget.color,
        ),
      ),
    );
  }
}
