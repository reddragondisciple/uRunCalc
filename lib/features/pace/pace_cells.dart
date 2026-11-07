import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../widgets/blinking_cursor.dart';

/// Универсальная ячейка таблицы Pace: значение, фокус, границы, подсказки.
///
/// Не зависит от состояния экрана — все параметры передаются снаружи.
class PaceInteractiveCell extends StatelessWidget {
  const PaceInteractiveCell({
    super.key,
    required this.cellKey,
    required this.text,
    required this.focusAnchorKey,
    this.focused = false,
    this.editable = false,
    this.placeholder = false,
    this.result = false,
    this.bold = false,
    this.cursorFirst = false,
    this.cursorActive = false,
    this.maxLines = 1,
    this.fontSize = 30,
    this.color,
    this.dayBorder,
    this.boldBorder = false,
    this.onTap,
    this.onLongPress,
    this.semanticLabel,
    this.semanticHint,
    this.spans,
  });

  final String cellKey;
  final String text;
  final GlobalKey focusAnchorKey;
  final bool focused;
  final bool editable;
  final bool placeholder;
  final bool result;
  final bool bold;
  final bool cursorFirst;
  final bool cursorActive;
  final int maxLines;
  final double fontSize;
  final Color? color;
  final Color? dayBorder;
  final bool boldBorder;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String? semanticLabel;
  final String? semanticHint;
  final List<TextSpan>? spans;

  @override
  Widget build(BuildContext context) {
    final defaultBorder = editable
        ? Colors.grey.shade700
        : Colors.grey.shade900;
    final borderColor = focused
        ? AppColors.focus
        : boldBorder
        ? Colors.grey.shade500
        : dayBorder ?? defaultBorder;
    final borderWidth = focused ? 1.5 : (boldBorder ? 3.0 : 1.0);

    final cell = InkWell(
      key: ValueKey(cellKey),
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 1),
        decoration: BoxDecoration(
          color: result ? AppColors.surfaceRaised : AppColors.background,
          border: Border.all(color: borderColor, width: borderWidth),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (focused && cursorFirst) _cursor(),
              if (spans != null && !placeholder)
                Text.rich(
                  TextSpan(
                    children: spans,
                    style: TextStyle(
                      fontSize: fontSize,
                      fontWeight: bold ? FontWeight.bold : null,
                    ),
                  ),
                  maxLines: maxLines,
                  textAlign: TextAlign.center,
                )
              else
                Text(
                  text,
                  maxLines: maxLines,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: placeholder
                        ? Colors.grey.shade600
                        : color ?? (result ? AppColors.result : Colors.white),
                    fontSize: fontSize,
                    fontWeight: bold ? FontWeight.bold : null,
                  ),
                ),
              if (focused && !cursorFirst) _cursor(),
            ],
          ),
        ),
      ),
    );

    final content = focused
        ? KeyedSubtree(key: focusAnchorKey, child: cell)
        : cell;
    if (semanticLabel == null && semanticHint == null) return content;

    // Цвет клетки передаёт статус плана, но скринридер его не видит — поэтому
    // для таких клеток задаём текстовую подпись и подсказку.
    return Semantics(
      label: semanticLabel,
      hint: semanticHint,
      button: onTap != null,
      excludeSemantics: true,
      onTap: onTap,
      onLongPress: onLongPress,
      child: content,
    );
  }

  Widget _cursor() => BlinkingCursor(active: cursorActive);
}

/// Текст заметки/воды/еды, который растягивается на пустые соседние клетки.
class PaceWrappedTextContent extends StatelessWidget {
  const PaceWrappedTextContent({
    super.key,
    required this.value,
    required this.cellKeySuffix,
    required this.height,
    this.fontSize = 11.5,
    this.water = false,
  });

  final String value;
  final String cellKeySuffix;
  final double height;
  final double fontSize;
  final bool water;

  @override
  Widget build(BuildContext context) {
    final maxLines = math.max(1, (height / 13).floor());
    return Container(
      key: ValueKey(cellKeySuffix),
      alignment: Alignment.topLeft,
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
      child: Text.rich(
        TextSpan(children: water ? waterSpans(value) : [TextSpan(text: value)]),
        maxLines: maxLines,
        overflow: TextOverflow.clip,
        style: TextStyle(color: Colors.white, fontSize: fontSize, height: 1.15),
      ),
    );
  }
}

/// Раскрашивает слова в заметке «Вода» по известным напиткам.
List<InlineSpan> waterSpans(String value) {
  final spans = <InlineSpan>[];
  for (final match in RegExp(r'\S+|\s+').allMatches(value)) {
    final part = match.group(0)!;
    if (part.trim().isEmpty) {
      spans.add(TextSpan(text: part));
      continue;
    }

    final normalized = part.toLowerCase().replaceAll(
      RegExp(r'[^а-яёa-z0-9]'),
      '',
    );
    final color = switch (normalized) {
      'кола' => const Color(0xFFD2A679),
      'вода' => const Color(0xFF64B5F6),
      'пиво' => const Color(0xFFFFEB3B),
      'ягер' => const Color(0xFF81C784),
      _ => Colors.white,
    };
    spans.add(
      TextSpan(
        text: part,
        style: TextStyle(color: color),
      ),
    );
  }
  return spans;
}
