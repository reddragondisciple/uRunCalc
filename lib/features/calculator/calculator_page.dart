import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/app_strings.dart';
import '../../core/expression_parser.dart';
import '../../core/rational.dart';
import '../../core/value_format.dart';
import '../../widgets/lazy_indexed_stack.dart';
import '../info/info_view.dart';
import '../pace/pace_view.dart';
import '../simple/expression_view.dart';
import '../time/time_view.dart';
import 'calculator_display.dart';
import 'calculator_mode.dart';
import 'calculator_mode_bar.dart';
import 'calculator_keypad.dart';

part 'calculator_input_part.dart';

class CalculatorPage extends StatefulWidget {
  const CalculatorPage({super.key});

  @override
  State<CalculatorPage> createState() => _CalculatorPageState();
}

class _HistoryEntry {
  const _HistoryEntry({
    required this.expression,
    required this.value,
    required this.approximate,
    required this.text,
  });

  final String expression;
  final Rational value;
  final bool approximate;
  final String text;
}

class _CalculatorPageState extends State<CalculatorPage>
    with WidgetsBindingObserver {
  static const String _modeStorageKey = 'app_mode_v1';

  String _expression = '';
  String? _message;

  final List<_HistoryEntry> _history = [];
  final Set<String> _redKeys = {};

  Timer? _flashTimer;

  /// Перерисовка из part-файла: `setState` защищён и недоступен
  /// в extension на `State`.
  void _rebuild(VoidCallback fn) => setState(fn);

  Rational? _exactResult;
  bool _justEvaluated = false;
  bool _resultApproximate = false;
  bool _resultShowsFraction = false;

  CalculatorMode _mode = CalculatorMode.ultra;
  bool _angleInDegrees = true;
  bool _modeRestored = false;
  bool _modeTouched = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _restoreMode();
  }

  Future<void> _restoreMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_modeStorageKey);
      if (!mounted || _modeTouched || raw == null) return;
      for (final mode in CalculatorMode.values) {
        if (mode.name == raw) {
          setState(() => _mode = mode);
          return;
        }
      }
    } catch (_) {
      // Недоступное хранилище не должно мешать запуску.
    } finally {
      _modeRestored = true;
    }
  }

  void _rememberMode() {
    // До завершения восстановления режима не перезаписываем сохранённое
    // значение жизненным циклом приложения.
    if (!_modeRestored && !_modeTouched) return;
    unawaited(
      SharedPreferences.getInstance()
          .then((prefs) => prefs.setString(_modeStorageKey, _mode.name))
          .catchError((Object _) => false),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _rememberMode();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _flashTimer?.cancel();
    super.dispose();
  }

  static const List<String> _keys = [
    'C',
    '(',
    ')',
    '⌫',
    '√',
    '^',
    '%',
    '÷',
    '7',
    '8',
    '9',
    '×',
    '4',
    '5',
    '6',
    '-',
    '1',
    '2',
    '3',
    '+',
    '0',
    '.',
    '000',
    '=',
  ];

  String? get _preview {
    if (_expression.isEmpty) return null;

    if (_justEvaluated && _exactResult != null) {
      if (!_resultShowsFraction) return null;
      final value = _exactResult!;
      return '${decimalSymbol(value, _resultApproximate)} '
          '${formatDecimal(value.toDisplayString())}';
    }

    try {
      final result = ExpressionParser(
        _expression,
        degrees: _angleInDegrees,
      ).parseResult();
      final value = result.value;
      return '${decimalSymbol(value, result.approximate)} '
          '${formatDecimal(value.toDisplayString())}';
    } catch (_) {
      return null;
    }
  }

  String get _resultDecimalPrefix {
    final value = _exactResult;
    if (value == null) return '';
    return decimalSymbol(value, _resultApproximate) == '=' ? '' : '≈ ';
  }

  @override
  Widget build(BuildContext context) {
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final hideModeBar = landscape && _mode == CalculatorMode.ultra;

    return Focus(
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              if (!hideModeBar) _buildModeBar(),
              Expanded(
                child: LazyIndexedStack(
                  index: _mode.index,
                  children: [
                    PaceView(
                      active: _mode == CalculatorMode.ultra,
                      surface: PaceSurface.ultra,
                    ),
                    PaceView(
                      active: _mode == CalculatorMode.pace,
                      surface: PaceSurface.pace,
                    ),
                    const TimeView(),
                    _buildExpressionMode(),
                    const InfoView(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModeBar() {
    return CalculatorModeBar(
      current: _mode,
      onSelected: (mode) {
        setState(() {
          _mode = mode;
        });
        _modeTouched = true;
        _rememberMode();
      },
    );
  }

  Widget _buildExpressionMode() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > constraints.maxHeight;
        final display = CalculatorDisplay(
          history: [for (final entry in _history) entry.text],
          onHistorySelected: (index) => _reuseHistory(_history[index]),
          currentValue: _buildCurrentValue(),
          message: _message,
          preview: _preview,
        );
        final keypad = CalculatorKeypad(
          keys: _keys,
          columns: 4,
          simpleMode: true,
          onPressed: _press,
          onClearHistory: _clearHistory,
          redKeys: _redKeys,
          angleInDegrees: _angleInDegrees,
        );

        if (isWide) {
          return Row(
            children: [
              Expanded(flex: 5, child: display),
              Expanded(flex: 6, child: keypad),
            ],
          );
        }

        return Column(
          children: [
            Expanded(flex: 5, child: display),
            Expanded(flex: 7, child: keypad),
          ],
        );
      },
    );
  }

  double get _displayFontSize => _mode == CalculatorMode.simple ? 37 : 32;

  FontWeight get _displayWeight =>
      _mode == CalculatorMode.simple ? FontWeight.w600 : FontWeight.w300;

  Widget _buildCurrentValue() {
    if (_justEvaluated && _exactResult != null) {
      if (_resultShowsFraction) {
        return ExpressionView(
          expression: _expression,
          fontSize: _displayFontSize,
          fontWeight: _displayWeight,
        );
      }

      return Text(
        '$_resultDecimalPrefix'
        '${formatDecimal(_exactResult!.toDisplayString())}',
        style: expressionTextStyle(
          _displayFontSize,
          Colors.white,
          _displayWeight,
        ),
      );
    }

    if (_expression.isEmpty) {
      return Text(
        '0',
        style: expressionTextStyle(
          _displayFontSize,
          Colors.white,
          _displayWeight,
        ),
      );
    }

    return ExpressionView(
      expression: _expression,
      fontSize: _displayFontSize,
      fontWeight: _displayWeight,
    );
  }
}
