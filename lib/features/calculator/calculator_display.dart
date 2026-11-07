import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// Область отображения простого калькулятора: история, текущий ввод и
/// предпросмотр/сообщение об ошибке.
class CalculatorDisplay extends StatelessWidget {
  const CalculatorDisplay({
    super.key,
    required this.history,
    required this.onHistorySelected,
    required this.currentValue,
    this.message,
    this.preview,
  });

  /// История в хронологическом порядке: последний элемент — самый новый.
  final List<String> history;

  /// Индекс элемента в [history] (не в перевёрнутом списке).
  final ValueChanged<int> onHistorySelected;

  final Widget currentValue;
  final String? message;
  final String? preview;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
      child: Column(
        children: [
          // История занимает свободное место и прокручивается отдельно.
          Expanded(
            child: history.isEmpty
                ? const SizedBox.shrink()
                : ListView.builder(
                    key: const ValueKey('history'),
                    reverse: true,
                    itemCount: history.length,
                    itemBuilder: (context, index) {
                      final entryIndex = history.length - 1 - index;

                      return InkWell(
                        key: ValueKey('history-$index'),
                        onTap: () => onHistorySelected(entryIndex),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              history[entryIndex],
                              textAlign: TextAlign.right,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 18,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),

          const SizedBox(height: 6),

          // Текущий ввод всегда остаётся внизу поля.
          SizedBox(
            key: const ValueKey('current-display'),
            height: 100,
            width: double.infinity,
            child: Align(
              alignment: Alignment.centerRight,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                reverse: true,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: currentValue,
                ),
              ),
            ),
          ),

          const SizedBox(height: 4),

          // Здесь показывается предпросмотр, десятичное значение или ошибка.
          SizedBox(
            key: const ValueKey('preview'),
            height: 28,
            width: double.infinity,
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                message ?? preview ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: message == null ? Colors.grey : AppColors.danger,
                  fontSize: 20,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
