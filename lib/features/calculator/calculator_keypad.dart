import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/key_labels.dart';
import '../../theme/app_colors.dart';

/// Клавиатура простого калькулятора.
///
/// Виджет не хранит состояние: нажатия и подсветка клавиш передаются снаружи.
class CalculatorKeypad extends StatelessWidget {
  const CalculatorKeypad({
    super.key,
    required this.keys,
    required this.columns,
    required this.onPressed,
    required this.onClearHistory,
    this.simpleMode = false,
    this.redKeys = const <String>{},
    this.angleInDegrees = true,
  });

  final List<String> keys;
  final int columns;
  final ValueChanged<String> onPressed;
  final VoidCallback onClearHistory;
  final bool simpleMode;
  final Set<String> redKeys;
  final bool angleInDegrees;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final rows = (keys.length / columns).ceil();
        final cellWidth = math.max(
          1.0,
          (constraints.maxWidth - (columns - 1)) / columns,
        );
        final cellHeight = math.max(
          1.0,
          (constraints.maxHeight - (rows - 1)) / rows,
        );

        return GridView.count(
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          crossAxisCount: columns,
          mainAxisSpacing: 1,
          crossAxisSpacing: 1,
          childAspectRatio: cellWidth / cellHeight,
          children: keys
              .map((key) => _buildKey(key, fontBoost: simpleMode ? 2 : 0))
              .toList(),
        );
      },
    );
  }

  Widget _buildKey(String key, {double fontBoost = 0}) {
    if (key.isEmpty) {
      return Container(
        color: const Color(0xFF555555),
        padding: const EdgeInsets.all(0.5),
        child: const Material(color: AppColors.background),
      );
    }

    final label = _keyLabel(key);
    final isEquals = key == '=';
    final isRed = redKeys.contains(key);

    final Color buttonColor;
    if (isEquals) {
      buttonColor = AppColors.accent;
    } else if (isRed) {
      buttonColor = AppColors.danger;
    } else {
      buttonColor = AppColors.background;
    }

    final baseFontSize = label.length >= 3
        ? 17.0
        : key == '000'
        ? 22.0
        : 28.0;
    final fontSize = baseFontSize + fontBoost;

    return Container(
      color: const Color(0xFF555555),
      padding: const EdgeInsets.all(0.5),
      child: Material(
        color: buttonColor,
        child: Semantics(
          button: true,
          label: semanticKeyLabel(key),
          onTap: () => onPressed(key),
          excludeSemantics: true,
          child: InkWell(
            key: ValueKey('key_$key'),
            canRequestFocus: false,
            onTap: () => onPressed(key),
            onLongPress: key == 'C' ? onClearHistory : null,
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Text(
                    label,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: fontSize,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _keyLabel(String key) {
    if (key == 'angle') return angleInDegrees ? 'DEG' : 'RAD';
    return key;
  }
}
