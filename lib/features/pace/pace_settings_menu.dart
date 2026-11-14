import 'package:flutter/material.dart';

import '../../core/app_strings.dart';

/// Меню-шестерёнка над таблицей Pace/Ultra (docs/gpx-mountain-mode.md §8.1).
///
/// Виджет не знает о состоянии таблицы: состояние приходит флагами, действия —
/// колбэками. Так меню тестируется отдельно от `pace_view.dart`.
class PaceSettingsMenu {
  PaceSettingsMenu._();

  /// Показывает диалог и вызывает действие выбранного пункта.
  static Future<void> show(
    BuildContext context, {
    required PaceSettingsState state,
    required PaceSettingsActions actions,
  }) async {
    final choice = await showDialog<PaceSettingsChoice>(
      context: context,
      builder: (dialogContext) {
        return SimpleDialog(
          title: const Text(AppStrings.paceSettingsTitle),
          children: [
            SimpleDialogOption(
              key: const ValueKey('pace-settings-columns'),
              onPressed: () =>
                  Navigator.pop(dialogContext, PaceSettingsChoice.columns),
              child: const Text(AppStrings.paceSettingsColumns),
            ),
            const Divider(),
            SimpleDialogOption(
              key: const ValueKey('pace-settings-mountain'),
              onPressed: () => Navigator.pop(
                dialogContext,
                state.mountainMode
                    ? PaceSettingsChoice.mountainOff
                    : PaceSettingsChoice.mountainOn,
              ),
              child: Row(
                children: [
                  Icon(
                    state.mountainMode
                        ? Icons.check_box
                        : Icons.check_box_outline_blank,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(child: Text(AppStrings.paceSettingsMountain)),
                ],
              ),
            ),
            if (state.mountainMode) ...[
              SimpleDialogOption(
                key: const ValueKey('pace-settings-import-gpx'),
                onPressed: () =>
                    Navigator.pop(dialogContext, PaceSettingsChoice.importGpx),
                child: const Text(AppStrings.paceSettingsImportGpx),
              ),
              SimpleDialogOption(
                key: const ValueKey('pace-settings-track-slot'),
                onPressed: () =>
                    Navigator.pop(dialogContext, PaceSettingsChoice.trackSlot),
                child: Text(
                  '${AppStrings.paceSettingsTrackSlot}: '
                  '${state.activeSlotLabel}',
                ),
              ),
            ],
            // Отложено: режим «темп с учётом стоянок» не входит в текущий план.
            // Пункт виден серым, без реакции на нажатие.
            const SimpleDialogOption(
              key: ValueKey('pace-settings-stops-mode'),
              onPressed: null,
              child: Row(
                children: [
                  Icon(Icons.check_box_outline_blank, color: Colors.grey),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      AppStrings.paceSettingsStopsModeDeferred,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(),
            _environmentOption(
              dialogContext,
              key: const ValueKey('pace-settings-surface'),
              label: AppStrings.paceSettingsSurface,
              checked: state.surfaceEnabled,
              choice: PaceSettingsChoice.surface,
            ),
            _environmentOption(
              dialogContext,
              key: const ValueKey('pace-settings-weather'),
              label: AppStrings.paceSettingsWeather,
              checked: state.weatherEnabled,
              choice: PaceSettingsChoice.weather,
            ),
            _environmentOption(
              dialogContext,
              key: const ValueKey('pace-settings-shoes'),
              label: AppStrings.paceSettingsShoes,
              checked: state.shoesEnabled,
              choice: PaceSettingsChoice.shoes,
            ),
            SimpleDialogOption(
              key: const ValueKey('pace-settings-factors'),
              onPressed: () =>
                  Navigator.pop(dialogContext, PaceSettingsChoice.factors),
              child: const Text(AppStrings.paceSettingsFactors),
            ),
            const Divider(),
            SimpleDialogOption(
              key: const ValueKey('pace-settings-export-tcx'),
              onPressed: null,
              child: Text(
                '${AppStrings.paceSettingsExportTcx} '
                '(${AppStrings.paceSettingsExportTcxHint})',
              ),
            ),
          ],
        );
      },
    );

    if (choice == null || !context.mounted) return;
    switch (choice) {
      case PaceSettingsChoice.columns:
        await actions.onColumns();
      case PaceSettingsChoice.mountainOn:
        actions.onMountainChanged(true);
      case PaceSettingsChoice.mountainOff:
        actions.onMountainChanged(false);
      case PaceSettingsChoice.importGpx:
        await actions.onImportGpx();
      case PaceSettingsChoice.trackSlot:
        await actions.onTrackSlot();
      case PaceSettingsChoice.surface:
        await actions.onSurface();
      case PaceSettingsChoice.weather:
        await actions.onWeather();
      case PaceSettingsChoice.shoes:
        await actions.onShoes();
      case PaceSettingsChoice.factors:
        await actions.onFactors();
    }
  }

  /// Пункт с чекбоксом. Нажатие всегда открывает диалог: галочка появляется
  /// только после «Применить», поэтому здесь нет переключения флага.
  static Widget _environmentOption(
    BuildContext dialogContext, {
    required Key key,
    required String label,
    required bool checked,
    required PaceSettingsChoice choice,
  }) {
    return SimpleDialogOption(
      key: key,
      onPressed: () => Navigator.pop(dialogContext, choice),
      child: Row(
        children: [
          Icon(checked ? Icons.check_box : Icons.check_box_outline_blank),
          const SizedBox(width: 8),
          Expanded(child: Text(label)),
        ],
      ),
    );
  }
}

enum PaceSettingsChoice {
  columns,
  mountainOn,
  mountainOff,
  importGpx,
  trackSlot,
  surface,
  weather,
  shoes,
  factors,
}

/// Состояние, которое меню показывает.
class PaceSettingsState {
  const PaceSettingsState({
    required this.mountainMode,
    required this.showStopsInPace,
    required this.activeSlotLabel,
    this.surfaceEnabled = false,
    this.weatherEnabled = false,
    this.shoesEnabled = false,
  });

  final bool mountainMode;
  final bool showStopsInPace;
  final String activeSlotLabel;
  final bool surfaceEnabled;
  final bool weatherEnabled;
  final bool shoesEnabled;
}

/// Действия меню. Все асинхронные — экран ждёт завершения диалогов.
class PaceSettingsActions {
  const PaceSettingsActions({
    required this.onColumns,
    required this.onMountainChanged,
    required this.onImportGpx,
    required this.onTrackSlot,
    required this.onStopsModeChanged,
    required this.onSurface,
    required this.onWeather,
    required this.onShoes,
    required this.onFactors,
  });

  final Future<void> Function() onColumns;
  final void Function(bool enabled) onMountainChanged;
  final Future<void> Function() onImportGpx;
  final Future<void> Function() onTrackSlot;
  final void Function(bool enabled) onStopsModeChanged;
  final Future<void> Function() onSurface;
  final Future<void> Function() onWeather;
  final Future<void> Function() onShoes;
  final Future<void> Function() onFactors;
}
