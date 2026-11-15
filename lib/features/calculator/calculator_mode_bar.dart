import 'package:flutter/material.dart';

import '../../core/app_strings.dart';
import '../pace/environment_status.dart';
import '../pace/pace_options_controller.dart';
import '../pace/pace_split_print_controller.dart';
import 'calculator_mode.dart';

/// Кнопка выбора режима в левом верхнем углу и строка состояния окружения
/// в свободном месте справа от неё.
class CalculatorModeBar extends StatelessWidget {
  const CalculatorModeBar({
    super.key,
    required this.current,
    required this.onSelected,
    this.environmentStatus,
    this.splitPrintController,
    this.optionsController,
  });

  final CalculatorMode current;
  final ValueChanged<CalculatorMode> onSelected;

  /// Статус покрытия и погоды. `null` — места не занимает.
  final EnvironmentStatusController? environmentStatus;

  /// Кнопка печати раскладки. `null` — кнопки нет.
  final PaceSplitPrintController? splitPrintController;

  /// Кнопка с шестерёнкой опций Pace. `null` — кнопки нет.
  final PaceOptionsController? optionsController;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            PopupMenuButton<CalculatorMode>(
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
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
            if (environmentStatus != null) ...[
              const SizedBox(width: 10),
              Expanded(
                child: AnimatedBuilder(
                  animation: environmentStatus!,
                  builder: (context, _) {
                    final status = environmentStatus!;
                    if (status.isEmpty) return const SizedBox.shrink();
                    return Row(
                      children: [
                        if (status.loading) ...[
                          const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Expanded(
                          child: Text(
                            status.loading
                                ? AppStrings.environmentLoading
                                : status.text!,
                            key: const ValueKey('environment-status'),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
            if (optionsController != null)
              AnimatedBuilder(
                animation: optionsController!,
                builder: (context, _) {
                  if (!optionsController!.available) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: IconButton(
                      key: const ValueKey('pace-options-button'),
                      tooltip: AppStrings.paceOptionsTitle,
                      onPressed: () => optionsController!.open(),
                      icon: const Icon(Icons.settings_outlined, size: 20),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 36,
                        minHeight: 36,
                      ),
                    ),
                  );
                },
              ),
            if (splitPrintController != null)
              AnimatedBuilder(
                animation: splitPrintController!,
                builder: (context, _) {
                  if (!splitPrintController!.available) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: IconButton(
                      key: const ValueKey('pace-split-print'),
                      tooltip: AppStrings.paceSplitPrintButton,
                      onPressed: () => splitPrintController!.print(),
                      icon: const Icon(Icons.print, size: 20),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 36,
                        minHeight: 36,
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
