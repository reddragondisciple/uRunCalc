import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb, listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/app_strings.dart';
import 'core/expression_parser.dart';
import 'core/key_labels.dart';
import 'core/persisted_json_store.dart';
import 'core/rational.dart';
import 'core/time_math.dart';
import 'features/pace/pace_calculations.dart';
import 'features/pace/pace_catalog.dart';
import 'features/pace/pace_state_codec.dart';
import 'features/pace/pace_state_controller.dart';
import 'features/pace/pace_table_data.dart';
import 'features/time/time_calculator.dart';
import 'print_table.dart';
import 'theme/app_colors.dart';
import 'widgets/blinking_cursor.dart';
import 'widgets/lazy_indexed_stack.dart';

part 'features/info/info_view.dart';
part 'features/pace/pace_view.dart';
part 'features/simple/expression_view.dart';
part 'features/time/time_view.dart';

void main() {
  runApp(const CalculatorApp());
}

class CalculatorApp extends StatelessWidget {
  const CalculatorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'uRunCalc',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.accent,
          brightness: Brightness.dark,
        ),
      ),
      home: const CalculatorPage(),
    );
  }
}

class CalculatorPage extends StatefulWidget {
  const CalculatorPage({super.key});

  @override
  State<CalculatorPage> createState() => _CalculatorPageState();
}

enum _CalculatorMode {
  ultra('Ultra'),
  pace('Pace'),
  time('Time'),
  simple('Simple'),
  info('Info');

  const _CalculatorMode(this.label);

  final String label;
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

  Rational? _exactResult;
  bool _justEvaluated = false;
  bool _resultApproximate = false;
  bool _resultShowsFraction = false;

  _CalculatorMode _mode = _CalculatorMode.ultra;
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
      for (final mode in _CalculatorMode.values) {
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
      return '${_decimalSymbol(value, _resultApproximate)} '
          '${_formatDecimal(value.toDisplayString())}';
    }

    try {
      final result = ExpressionParser(
        _expression,
        degrees: _angleInDegrees,
      ).parseResult();
      final value = result.value;
      return '${_decimalSymbol(value, result.approximate)} '
          '${_formatDecimal(value.toDisplayString())}';
    } catch (_) {
      return null;
    }
  }

  static bool _isDigit(String char) {
    final code = char.codeUnitAt(0);
    return code >= 0x30 && code <= 0x39;
  }

  static bool _isOperator(String char) {
    return char == '+' ||
        char == '-' ||
        char == '*' ||
        char == '/' ||
        char == '^';
  }

  bool get _endsWithOperand {
    if (_expression.isEmpty) return false;

    final last = _expression[_expression.length - 1];
    return _isDigit(last) ||
        last == '.' ||
        last == ')' ||
        last == '%' ||
        last == ';' ||
        last == 'π' ||
        last == 'e' ||
        last == '!';
  }

  bool get _needsMultiplicationAfterValue {
    if (_expression.isEmpty) return false;

    final last = _expression[_expression.length - 1];
    return last == ')' ||
        last == '%' ||
        last == ';' ||
        last == 'π' ||
        last == 'e' ||
        last == '!';
  }

  String _encodeRational(Rational value) {
    return '@${value.numerator}:${value.denominator};';
  }

  String get _resultDecimalPrefix {
    final value = _exactResult;
    if (value == null) return '';
    return _decimalSymbol(value, _resultApproximate) == '=' ? '' : '≈ ';
  }

  void _haptic() {
    if (kIsWeb) return;
    if (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS) {
      unawaited(HapticFeedback.selectionClick());
    }
  }

  void _flash(String key) {
    _flashTimer?.cancel();

    setState(() {
      _redKeys
        ..clear()
        ..add(key);
    });

    _flashTimer = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;

      setState(() {
        _redKeys.clear();
      });
    });
  }

  void _press(String key) {
    _haptic();

    if (key == 'C') {
      setState(() {
        _expression = '';
        _message = null;
        _exactResult = null;
        _justEvaluated = false;
        _resultApproximate = false;
        _resultShowsFraction = false;
      });
      return;
    }

    if (key == '⌫') {
      setState(() {
        _message = null;

        if (_justEvaluated) {
          _expression = '';
          _exactResult = null;
          _justEvaluated = false;
          _resultApproximate = false;
          _resultShowsFraction = false;
          return;
        }

        if (_expression.endsWith('sqrt(')) {
          // Корень удаляется одним нажатием, не оставляя "sqrt".
          _expression = _expression.substring(
            0,
            _expression.length - 'sqrt('.length,
          );
        } else if (_expression.endsWith(';')) {
          // Внутренний маркер точного результата удаляется целиком.
          final markerStart = _expression.lastIndexOf('@');
          if (markerStart >= 0) {
            _expression = _expression.substring(0, markerStart);
          } else if (_expression.isNotEmpty) {
            _expression = _expression.substring(0, _expression.length - 1);
          }
        } else if (_expression.isNotEmpty) {
          _expression = _expression.substring(0, _expression.length - 1);
        }
      });
      return;
    }

    if (key == '=') {
      _calculate();
      return;
    }

    if (_justEvaluated) {
      final startsNewExpression =
          _isDigit(key) || key == '.' || key == '(' || key == '√';

      setState(() {
        if (startsNewExpression) {
          _expression = '';
        } else if (_exactResult != null) {
          // Не теряем точность результата при продолжении вычисления.
          _expression = _encodeRational(_exactResult!);
        }

        _justEvaluated = false;
        _exactResult = null;
        _resultApproximate = false;
        _resultShowsFraction = false;
      });
    }

    final accepted = switch (key) {
      '0' ||
      '1' ||
      '2' ||
      '3' ||
      '4' ||
      '5' ||
      '6' ||
      '7' ||
      '8' ||
      '9' => _insertDigit(key),
      '.' => _insertDecimalPoint(),
      '+' || '-' || '×' || '÷' || '^' => _insertOperator(key),
      '(' => _insertOpenParenthesis(),
      ')' => _insertCloseParenthesis(),
      '%' => _insertPercent(),
      '√' => _insertSquareRoot(),
      '000' => _insertTripleZeros(),
      'sin' || 'cos' || 'tan' || 'ln' || 'log' => _insertFunction(key),
      'π' || 'e' => _insertConstant(key),
      'x²' => _insertSquare(),
      '1/x' => _insertReciprocal(),
      'n!' => _insertFactorial(),
      'angle' => _toggleAngle(),
      'Ans' => _insertAnswer(),
      _ => false,
    };

    if (!accepted) {
      _flash(key);
    }
  }

  bool _insertDigit(String digit) {
    var addition = digit;

    if (_needsMultiplicationAfterValue) {
      addition = '*$digit';
    }

    setState(() {
      _expression += addition;
      _message = null;
    });

    return true;
  }

  bool _insertDecimalPoint() {
    if (_needsMultiplicationAfterValue) {
      return false;
    }

    var index = _expression.length - 1;

    while (index >= 0 &&
        (_isDigit(_expression[index]) || _expression[index] == '.')) {
      if (_expression[index] == '.') return false;
      index--;
    }

    setState(() {
      if (_expression.isEmpty ||
          _isOperator(_expression[_expression.length - 1]) ||
          _expression.endsWith('(')) {
        _expression += '0.';
      } else {
        _expression += '.';
      }
      _message = null;
    });

    return true;
  }

  bool _insertOperator(String key) {
    final operator = switch (key) {
      '×' => '*',
      '÷' => '/',
      _ => key,
    };

    if (_expression.isEmpty) {
      if (operator != '-') return false;
    } else {
      final last = _expression[_expression.length - 1];

      // Унарный минус разрешён в начале, после оператора и после "(",
      // но только один: 1+-2 можно, 1+--2 — нет.
      if (operator == '-' && (_isOperator(last) || last == '(')) {
        if (last == '-') return false;

        setState(() {
          _expression += '-';
          _message = null;
        });
        return true;
      }

      if (!_endsWithOperand) return false;
    }

    setState(() {
      if (operator == '^') {
        // Дробь в основании степени показываем в скобках: (1/2)^2.
        _expression = _parenthesizeTrailingFraction(_expression);
      }
      _expression += operator;
      _message = null;
    });

    return true;
  }

  String _parenthesizeTrailingFraction(String expression) {
    final start = _lastAdditiveTermStart(expression);
    final term = expression.substring(start);

    if (!_isFractionTerm(term)) return expression;

    return '${expression.substring(0, start)}($term)';
  }

  int _lastAdditiveTermStart(String expression) {
    var depth = 0;

    for (var index = expression.length - 1; index >= 0; index--) {
      final char = expression[index];

      if (char == ')') {
        depth++;
      } else if (char == '(') {
        depth--;
      } else if (depth == 0 && (char == '+' || char == '-')) {
        final previous = index == 0 ? null : expression[index - 1];
        final unary =
            previous == null || _isOperator(previous) || previous == '(';

        if (!unary) return index + 1;
      }
    }

    return 0;
  }

  bool _isFractionTerm(String term) {
    if (term.isEmpty) return false;

    if (term.startsWith('@') && term.endsWith(';')) {
      try {
        return !ExpressionParser(term).parse().isInteger;
      } on FormatException {
        return true;
      }
    }

    var depth = 0;

    for (var index = 0; index < term.length; index++) {
      final char = term[index];

      if (char == '(') {
        depth++;
      } else if (char == ')') {
        depth--;
      } else if (depth == 0 && char == '/') {
        return true;
      }
    }

    return false;
  }

  bool _insertOpenParenthesis() {
    setState(() {
      if (_endsWithOperand) {
        _expression += '*';
      }
      _expression += '(';
      _message = null;
    });

    return true;
  }

  bool _insertCloseParenthesis() {
    if (!_endsWithOperand) return false;

    var openCount = 0;
    var closeCount = 0;

    for (final char in _expression.split('')) {
      if (char == '(') openCount++;
      if (char == ')') closeCount++;
    }

    if (closeCount >= openCount) return false;

    setState(() {
      _expression += ')';
      _message = null;
    });

    return true;
  }

  bool _insertPercent() {
    if (!_endsWithOperand || _expression.endsWith('%')) {
      return false;
    }

    setState(() {
      _expression += '%';
      _message = null;
    });

    return true;
  }

  bool _insertSquareRoot() {
    setState(() {
      if (_endsWithOperand) {
        _expression += '*';
      }
      _expression += 'sqrt(';
      _message = null;
    });

    return true;
  }

  bool _insertTripleZeros() {
    if (!_endsWithOperand) return false;

    setState(() {
      if (_needsMultiplicationAfterValue) {
        _expression += '*1000';
      } else {
        _expression += '000';
      }
      _message = null;
    });

    return true;
  }

  bool _insertFunction(String name) {
    setState(() {
      if (_endsWithOperand) {
        _expression += '*';
      }
      _expression += '$name(';
      _message = null;
    });

    return true;
  }

  bool _insertConstant(String symbol) {
    setState(() {
      if (_endsWithOperand) {
        _expression += '*';
      }
      _expression += symbol;
      _message = null;
    });

    return true;
  }

  bool _insertSquare() {
    if (!_endsWithOperand) return false;

    setState(() {
      _expression = _parenthesizeTrailingFraction(_expression);
      _expression += '^2';
      _message = null;
    });

    return true;
  }

  bool _insertFactorial() {
    if (!_endsWithOperand || _expression.endsWith('!')) return false;

    setState(() {
      _expression += '!';
      _message = null;
    });

    return true;
  }

  bool _insertReciprocal() {
    if (!_endsWithOperand) {
      setState(() {
        if (_expression.isNotEmpty &&
            !_isOperator(_expression[_expression.length - 1]) &&
            !_expression.endsWith('(')) {
          _expression += '*';
        }
        _expression += '1/(';
        _message = null;
      });

      return true;
    }

    final start = _lastAdditiveTermStart(_expression);
    final term = _expression.substring(start);
    final wrapped = term.startsWith('(') && term.endsWith(')')
        ? term
        : '($term)';

    setState(() {
      _expression = '${_expression.substring(0, start)}1/$wrapped';
      _message = null;
    });

    return true;
  }

  bool _insertAnswer() {
    if (_history.isEmpty) return false;

    setState(() {
      if (_endsWithOperand) {
        _expression += '*';
      }
      _expression += _encodeRational(_history.last.value);
      _message = null;
    });

    return true;
  }

  bool _toggleAngle() {
    setState(() {
      _angleInDegrees = !_angleInDegrees;
      _message = null;
    });

    return true;
  }

  void _calculate() {
    if (_expression.isEmpty) {
      setState(() {
        _message = AppStrings.simpleEnterExpression;
      });
      return;
    }

    if (_justEvaluated) return;

    try {
      final result = ExpressionParser(
        _expression,
        degrees: _angleInDegrees,
      ).parseResult();
      final value = result.value;
      final showsFraction = !result.approximate && value.isDisplayableFraction;
      final entry = _HistoryEntry(
        expression: _expression,
        value: value,
        approximate: result.approximate,
        text: _historyText(_expression, value, result.approximate),
      );

      setState(() {
        _history.add(entry);

        // Храним последние восемь вычислений.
        if (_history.length > 8) {
          _history.removeAt(0);
        }

        _expression = _encodeRational(value);
        _exactResult = value;
        _justEvaluated = true;
        _resultApproximate = result.approximate;
        _resultShowsFraction = showsFraction;
        _message = null;
      });
    } on FormatException catch (error) {
      setState(() {
        _message = error.message.toString();
      });
    } catch (_) {
      setState(() {
        _message = AppStrings.simpleEvaluationFailed;
      });
    }
  }

  void _clearHistory() {
    if (_history.isEmpty) return;

    setState(() {
      _history.clear();
    });

    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(
        content: Text(AppStrings.simpleHistoryCleared),
        duration: Duration(seconds: 1),
      ),
    );
  }

  void _reuseHistory(_HistoryEntry entry) {
    // После результата поле визуально занято, но нового ввода ещё нет:
    // в этом случае подставляем выражение из истории. Если пользователь
    // уже что-то набрал, не затираем ввод, а дописываем итоговое значение.
    final replaceExpression = _expression.isEmpty || _justEvaluated;

    setState(() {
      if (replaceExpression) {
        _expression = entry.expression;
      } else {
        if (_endsWithOperand) {
          _expression += '*';
        }
        _expression += _encodeRational(entry.value);
      }

      _message = null;
      _exactResult = null;
      _justEvaluated = false;
      _resultApproximate = false;
      _resultShowsFraction = false;
    });
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (_mode == _CalculatorMode.pace ||
        _mode == _CalculatorMode.ultra ||
        _mode == _CalculatorMode.time ||
        _mode == _CalculatorMode.info) {
      return KeyEventResult.ignored;
    }

    final logicalKey = event.logicalKey;
    if (logicalKey == LogicalKeyboardKey.enter ||
        logicalKey == LogicalKeyboardKey.numpadEnter) {
      _press('=');
      return KeyEventResult.handled;
    }
    if (logicalKey == LogicalKeyboardKey.backspace ||
        logicalKey == LogicalKeyboardKey.delete) {
      _press('⌫');
      return KeyEventResult.handled;
    }
    if (logicalKey == LogicalKeyboardKey.escape) {
      _press('C');
      return KeyEventResult.handled;
    }

    final character = event.character ?? logicalKey.keyLabel;
    if (character.length != 1) return KeyEventResult.ignored;

    final key = switch (character) {
      '0' ||
      '1' ||
      '2' ||
      '3' ||
      '4' ||
      '5' ||
      '6' ||
      '7' ||
      '8' ||
      '9' => character,
      '+' => '+',
      '-' => '-',
      '*' || 'x' || 'X' => '×',
      '/' => '÷',
      '^' => '^',
      '%' => '%',
      '(' => '(',
      ')' => ')',
      '.' || ',' => '.',
      '=' => '=',
      'r' || 'R' => '√',
      'c' || 'C' => 'C',
      _ => null,
    };

    if (key == null) return KeyEventResult.ignored;

    _press(key);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final hideModeBar = landscape && _mode == _CalculatorMode.ultra;

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
                    _PaceView(
                      active: _mode == _CalculatorMode.ultra,
                      surface: _PaceSurface.ultra,
                    ),
                    _PaceView(
                      active: _mode == _CalculatorMode.pace,
                      surface: _PaceSurface.pace,
                    ),
                    const _TimeView(),
                    _buildExpressionMode(),
                    const _InfoView(),
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
    return SizedBox(
      height: 44,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Align(
          alignment: Alignment.centerLeft,
          child: PopupMenuButton<_CalculatorMode>(
            key: const ValueKey('mode-button'),
            initialValue: _mode,
            onSelected: (mode) {
              setState(() {
                _mode = mode;
              });
              _modeTouched = true;
              _rememberMode();
            },
            itemBuilder: (context) {
              return _CalculatorMode.values.map((mode) {
                return PopupMenuItem<_CalculatorMode>(
                  value: mode,
                  child: Row(
                    children: [
                      SizedBox(
                        width: 22,
                        child: mode == _mode
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
                    _mode.label,
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

  Widget _buildExpressionMode() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > constraints.maxHeight;
        final display = _buildDisplayArea(_preview);
        final keypad = _buildKeypad(keys: _keys, columns: 4, simpleMode: true);

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

  Widget _buildDisplayArea(String? preview) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
      child: Column(
        children: [
          // История занимает свободное место и прокручивается отдельно.
          Expanded(
            child: _history.isEmpty
                ? const SizedBox.shrink()
                : ListView.builder(
                    key: const ValueKey('history'),
                    reverse: true,
                    itemCount: _history.length,
                    itemBuilder: (context, index) {
                      final entry = _history[_history.length - 1 - index];

                      return InkWell(
                        key: ValueKey('history-$index'),
                        onTap: () => _reuseHistory(entry),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              entry.text,
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
                  child: _buildCurrentValue(),
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
                _message ?? preview ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _message == null ? Colors.grey : AppColors.danger,
                  fontSize: 20,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  double get _displayFontSize => _mode == _CalculatorMode.simple ? 37 : 32;

  FontWeight get _displayWeight =>
      _mode == _CalculatorMode.simple ? FontWeight.w600 : FontWeight.w300;

  Widget _buildCurrentValue() {
    if (_justEvaluated && _exactResult != null) {
      if (_resultShowsFraction) {
        return _ExpressionView(
          expression: _expression,
          fontSize: _displayFontSize,
          fontWeight: _displayWeight,
        );
      }

      return Text(
        '$_resultDecimalPrefix'
        '${_formatDecimal(_exactResult!.toDisplayString())}',
        style: _textStyle(_displayFontSize, Colors.white, _displayWeight),
      );
    }

    if (_expression.isEmpty) {
      return Text(
        '0',
        style: _textStyle(_displayFontSize, Colors.white, _displayWeight),
      );
    }

    return _ExpressionView(
      expression: _expression,
      fontSize: _displayFontSize,
      fontWeight: _displayWeight,
    );
  }

  Widget _buildKeypad({
    required List<String> keys,
    required int columns,
    bool simpleMode = false,
  }) {
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
    final isRed = _redKeys.contains(key);

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
          label: _semanticLabel(key),
          onTap: () => _press(key),
          excludeSemantics: true,
          child: InkWell(
            key: ValueKey('key_$key'),
            canRequestFocus: false,
            onTap: () => _press(key),
            onLongPress: key == 'C' ? _clearHistory : null,
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
    if (key == 'angle') return _angleInDegrees ? 'DEG' : 'RAD';
    return key;
  }

  String _semanticLabel(String key) => semanticKeyLabel(key);
}
