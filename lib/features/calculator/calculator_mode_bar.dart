import 'package:flutter/material.dart';

import 'calculator_mode.dart';

/// Кнопка выбора режима в левом верхнем углу.
class CalculatorModeBar extends StatelessWidget {
  const CalculatorModeBar({
    super.key,
    required this.current,
    required this.onSelected,
  });

  final CalculatorMode current;
  final ValueChanged<CalculatorMode> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Align(
          alignment: Alignment.centerLeft,
          child: PopupMenuButton<CalculatorMode>(
            key: const ValueKey('mode-button'),
            initialValue: current,
            onSelected: onSelected,
            itemBuilder: (context) {
              return CalculatorMode.values.map((mode) {
                return PopupMenuItem<CalculatorMode>(
                  value: mode,
                  child: Row(
                    children: [
                      SizedBox(
                        width: 22,
                        child: mode == current
                            ? const Icon(Icons.check, size: 18)
                            : null,
                      ),
                      Text(mode.label),
                    ],
                  ),
                );
              }).toList();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade700),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.grid_view_rounded,
                    size: 17,
                    color: Colors.grey,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    current.label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Icon(
                    Icons.arrow_drop_down,
                    size: 18,
                    color: Colors.grey,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
