part of 'pace_view.dart';

extension _PaceCalculatorPart on _PaceViewState {
  Widget _buildCalculator() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _calcButton(
              AppStrings.paceCalcPace,
              _PaceCalc.pace,
              'pace-calc-pace',
            ),
            const SizedBox(width: 4),
            _calcButton(
              AppStrings.paceCalcDistance,
              _PaceCalc.distance,
              'pace-calc-distance',
            ),
            const SizedBox(width: 4),
            _calcButton(
              AppStrings.paceCalcTime,
              _PaceCalc.time,
              'pace-calc-time',
            ),
          ],
        ),
        const SizedBox(height: 8),
        _buildPaceRow(),
        const SizedBox(height: 4),
        _buildDistanceRow(),
        const SizedBox(height: 4),
        _buildTimeRow(),
      ],
    );
  }

  Widget _calcButton(String label, _PaceCalc value, String key) {
    final selected = _calc == value;

    return Expanded(
      child: InkWell(
        key: ValueKey(key),
        onTap: () => _selectCalc(value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.accent : AppColors.background,
            border: Border.all(
              color: selected ? AppColors.accent : Colors.grey.shade700,
            ),
            borderRadius: BorderRadius.circular(7),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              style: TextStyle(
                color: selected ? AppColors.background : Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _cursor() => BlinkingCursor(active: widget.active);

  Widget _field({
    required String key,
    required String text,
    required bool editable,
    required bool focused,
    required VoidCallback onTap,
    String hint = '',
  }) {
    final borderColor = focused
        ? AppColors.focus
        : editable
        ? Colors.grey.shade700
        : const Color(0x66FF9800);

    return InkWell(
      key: ValueKey(key),
      onTap: editable ? onTap : null,
      child: Container(
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: editable ? AppColors.background : AppColors.surfaceRaised,
          border: Border.all(color: borderColor, width: focused ? 1.5 : 1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                text.isEmpty ? hint : text,
                maxLines: 1,
                style: TextStyle(
                  color: editable
                      ? (text.isEmpty ? Colors.grey : Colors.white)
                      : AppColors.result,
                  fontSize: 15,
                  fontWeight: FontWeight.w400,
                ),
              ),
              if (focused) _cursor(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPaceRow() {
    final result = _calc == _PaceCalc.pace;

    return Row(
      children: [
        const SizedBox(
          width: 94,
          child: Text(
            AppStrings.paceCalcPace,
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
        ),
        Expanded(
          child: _field(
            key: 'pace-pace-min',
            text: _topPaceMinutes(),
            editable: !result,
            focused: _isTopFocused(_PaceTopField.paceMinutes),
            onTap: () => _focusTop(_PaceTopField.paceMinutes),
            hint: AppStrings.paceHintMinutes,
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Text(':', style: TextStyle(color: Colors.grey, fontSize: 18)),
        ),
        Expanded(
          child: _field(
            key: 'pace-pace-sec',
            text: _topPaceSeconds(),
            editable: !result,
            focused: _isTopFocused(_PaceTopField.paceSeconds),
            onTap: () => _focusTop(_PaceTopField.paceSeconds),
            hint: AppStrings.paceHintSeconds,
          ),
        ),
        const SizedBox(
          width: 44,
          child: Padding(
            padding: EdgeInsets.only(left: 4),
            child: Text(
              AppStrings.paceHintPace,
              style: TextStyle(color: Colors.grey, fontSize: 10),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDistanceRow() {
    final result = _calc == _PaceCalc.distance;

    return Row(
      children: [
        const SizedBox(
          width: 94,
          child: Text(
            AppStrings.paceCalcDistance,
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
        ),
        Expanded(
          child: _field(
            key: 'pace-distance',
            text: _topDistance(),
            editable: !result,
            focused: _isTopFocused(_PaceTopField.distance),
            onTap: () => _focusTop(_PaceTopField.distance),
            hint: AppStrings.paceHintKm,
          ),
        ),
        const SizedBox(
          width: 44,
          child: Padding(
            padding: EdgeInsets.only(left: 4),
            child: Text(
              AppStrings.paceHintKm,
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTimeRow() {
    const fields = [
      _PaceTopField.days,
      _PaceTopField.hours,
      _PaceTopField.minutes,
      _PaceTopField.seconds,
    ];
    const labels = [
      AppStrings.timeDays,
      AppStrings.timeHours,
      AppStrings.timeMinutes,
      AppStrings.timeSeconds,
    ];
    final result = _calc == _PaceCalc.time;

    return Column(
      children: [
        Row(
          children: [
            const SizedBox(width: 94),
            for (final label in labels)
              Expanded(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey, fontSize: 10),
                ),
              ),
          ],
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            const SizedBox(
              width: 94,
              child: Text(
                AppStrings.paceCalcTime,
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ),
            for (final field in fields)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1),
                  child: _field(
                    key: 'pace-time-${field.name}',
                    text: _topTimePart(field),
                    editable: !result,
                    focused: _isTopFocused(field),
                    onTap: () => _focusTop(field),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
