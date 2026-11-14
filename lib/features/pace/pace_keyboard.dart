import 'package:flutter/material.dart';

import '../../core/app_strings.dart';
import '../../core/key_labels.dart';
import '../../theme/app_colors.dart';

/// Экранная клавиатура таблицы Pace.
class PaceKeyboard extends StatelessWidget {
  const PaceKeyboard({
    super.key,
    required this.compact,
    required this.tableLayout,
    required this.isUltra,
    required this.onKey,
    required this.onClear,
  });

  final bool compact;
  final bool tableLayout;
  final bool isUltra;
  final ValueChanged<String> onKey;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final extraKey = isUltra ? AppStrings.ok : '00';
    if (tableLayout) {
      return Container(
        height: compact ? null : 180,
        padding: EdgeInsets.fromLTRB(4, 4, 4, compact ? 4 : 6),
        color: AppColors.surface,
        child: Column(
          children: [
            _keyRow(['.', AppStrings.reset, '⌫'], compact),
            _keyRow(['1', '2', '3'], compact),
            _keyRow(['4', '5', '6'], compact),
            _keyRow(['7', '8', '9'], compact),
            Expanded(
              child: Row(
                children: [
                  Expanded(flex: 2, child: _padKey('0', compact)),
                  if (!isUltra) ...[
                    // `±` меняет полярность только в поле сплита.
                    Expanded(
                      flex: 1,
                      child: _padKey(AppStrings.signToggleKey, compact),
                    ),
                    Expanded(flex: 1, child: _padKey(extraKey, compact)),
                  ] else
                    Expanded(flex: 1, child: _padKey(extraKey, compact)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      height: compact ? null : 180,
      padding: EdgeInsets.fromLTRB(4, 4, 4, compact ? 4 : 6),
      color: AppColors.surface,
      child: Column(
        children: [
          _keyRow(['1', '2', '3', '⌫'], compact),
          _keyRow(['4', '5', '6', '.'], compact),
          _keyRow(['7', '8', '9', AppStrings.reset], compact),
          Expanded(
            child: Row(
              children: [
                Expanded(flex: 2, child: _padKey('0', compact)),
                if (!isUltra) ...[
                  Expanded(
                    flex: 1,
                    child: _padKey(AppStrings.signToggleKey, compact),
                  ),
                  Expanded(flex: 1, child: _padKey(extraKey, compact)),
                ] else
                  Expanded(flex: 2, child: _padKey(extraKey, compact)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _keyRow(List<String> keys, bool compact) {
    return Expanded(
      child: Row(
        children: [
          for (final key in keys) Expanded(child: _padKey(key, compact)),
        ],
      ),
    );
  }

  Widget _padKey(String key, bool compact) {
    return Padding(
      padding: const EdgeInsets.all(1.5),
      child: Semantics(
        button: true,
        label: semanticKeyLabel(key),
        hint: key == '⌫' ? AppStrings.longPressClear : null,
        onTap: () => onKey(key),
        onLongPress: key == '⌫' ? onClear : null,
        excludeSemantics: true,
        child: Material(
          color: AppColors.background,
          child: InkWell(
            key: ValueKey('pace-key-$key'),
            onTap: () => onKey(key),
            onLongPress: key == '⌫' ? onClear : null,
            child: Center(
              child: Text(
                key,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: compact ? 16 : 20,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
