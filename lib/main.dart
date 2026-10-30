import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb, listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const CalculatorApp());
}

class CalculatorApp extends StatelessWidget {
  const CalculatorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Калькулятор',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFF9800),
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
  simple('Simple'),
  engineering('Engineering'),
  pace('Pace'),
  ultra('Ultra'),
  time('Time');

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

  _CalculatorMode _mode = _CalculatorMode.simple;
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

  static const List<String> _engineeringKeys = [
    'sin',
    'cos',
    'tan',
    'ln',
    'log',
    '÷',
    'π',
    'e',
    'x²',
    'n!',
    '%',
    '×',
    '7',
    '8',
    '9',
    'C',
    '⌫',
    '-',
    '4',
    '5',
    '6',
    '(',
    ')',
    '+',
    '1',
    '2',
    '3',
    '√',
    '^',
    'angle',
    '0',
    '.',
    '1/x',
    'Ans',
    '',
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
        _message = 'Введите выражение';
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
        _message = 'Не удалось вычислить';
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
        content: Text('История очищена'),
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
        _mode == _CalculatorMode.time) {
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
                child: IndexedStack(
                  index: _mode.index,
                  children: [
                    _buildExpressionMode(isEngineering: false),
                    _buildExpressionMode(isEngineering: true),
                    _PaceView(
                      active: _mode == _CalculatorMode.pace,
                      surface: _PaceSurface.pace,
                    ),
                    _PaceView(
                      active: _mode == _CalculatorMode.ultra,
                      surface: _PaceSurface.ultra,
                    ),
                    const _TimeView(),
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

  Widget _buildExpressionMode({required bool isEngineering}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > constraints.maxHeight;
        final display = _buildDisplayArea(_preview);
        final keypad = _buildKeypad(
          keys: isEngineering ? _engineeringKeys : _keys,
          columns: isEngineering ? 6 : 4,
          simpleMode: !isEngineering,
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
                  color: _message == null ? Colors.grey : Colors.red,
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
        child: const Material(color: Colors.black),
      );
    }

    final label = _keyLabel(key);
    final isEquals = key == '=';
    final isRed = _redKeys.contains(key);

    final Color buttonColor;
    if (isEquals) {
      buttonColor = const Color(0xFFFF9800);
    } else if (isRed) {
      buttonColor = Colors.red;
    } else {
      buttonColor = Colors.black;
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

  String _semanticLabel(String key) {
    return switch (key) {
      'C' => 'Очистить. Долгое нажатие — очистить историю',
      '⌫' => 'Удалить',
      '√' => 'Квадратный корень',
      '^' => 'Степень',
      '÷' => 'Разделить',
      '×' => 'Умножить',
      '%' => 'Процент',
      '=' => 'Равно',
      '(' => 'Открывающая скобка',
      ')' => 'Закрывающая скобка',
      '000' => 'Три нуля',
      '.' => 'Точка',
      'sin' => 'Синус',
      'cos' => 'Косинус',
      'tan' => 'Тангенс',
      'ln' => 'Натуральный логарифм',
      'log' => 'Десятичный логарифм',
      'π' => 'Число пи',
      'e' => 'Экспонента',
      'x²' => 'Квадрат',
      '1/x' => 'Обратное число',
      'n!' => 'Факториал',
      'angle' => 'Переключить градусы и радианы',
      'Ans' => 'Предыдущий результат',
      _ => key,
    };
  }
}

String _formatPaceSeconds(int totalSeconds) {
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

({int days, int hours, int minutes, int seconds}) _splitSeconds(
  int totalSeconds,
) {
  final days = totalSeconds ~/ 86400;
  final hours = (totalSeconds % 86400) ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  return (days: days, hours: hours, minutes: minutes, seconds: seconds);
}

int? _parseDurationParts(List<String> values) {
  if (values.every((value) => value.trim().isEmpty)) return null;

  int read(int index) {
    return int.tryParse(values[index].trim()) ?? 0;
  }

  return read(0) * 86400 + read(1) * 3600 + read(2) * 60 + read(3);
}

double? _parseDecimalValue(String text) {
  final normalized = text.trim().replaceAll(',', '.');
  if (normalized.isEmpty) return null;

  final value = double.tryParse(normalized);
  if (value == null || !value.isFinite) return null;
  return value;
}

class _PaceDistance {
  _PaceDistance(
    this.name,
    this.checkpoints, {
    this.defaultTimes = const [],
    this.defaultDistances = const [],
  });

  final String name;
  final int checkpoints;

  /// Значения, которыми заполняется новая таблица дистанции.
  final List<String> defaultTimes;
  final List<String> defaultDistances;
}

class _PaceEvent {
  _PaceEvent(this.name, this.distances);

  final String name;
  final List<_PaceDistance> distances;
}

enum _PaceCalc { pace, distance, time }

enum _PaceTopField {
  distance,
  paceMinutes,
  paceSeconds,
  days,
  hours,
  minutes,
  seconds,
}

enum _PlannedSummarySource { none, pace, time }

enum _PaceFocusKind {
  none,
  top,
  tableTime,
  tableDistance,
  tablePlanTime,
  tablePlanPace,
  summaryPlannedPace,
  summaryPlannedTime,
}

class _PaceFocus {
  const _PaceFocus.none()
    : kind = _PaceFocusKind.none,
      field = null,
      tableColumn = -1;

  const _PaceFocus.top(this.field)
    : kind = _PaceFocusKind.top,
      tableColumn = -1;

  const _PaceFocus.tableTime(this.tableColumn)
    : kind = _PaceFocusKind.tableTime,
      field = null;

  const _PaceFocus.tableDistance(this.tableColumn)
    : kind = _PaceFocusKind.tableDistance,
      field = null;

  const _PaceFocus.tablePlanTime(this.tableColumn)
    : kind = _PaceFocusKind.tablePlanTime,
      field = null;

  const _PaceFocus.tablePlanPace(this.tableColumn)
    : kind = _PaceFocusKind.tablePlanPace,
      field = null;

  const _PaceFocus.summaryPlannedPace()
    : kind = _PaceFocusKind.summaryPlannedPace,
      field = null,
      tableColumn = -1;

  const _PaceFocus.summaryPlannedTime()
    : kind = _PaceFocusKind.summaryPlannedTime,
      field = null,
      tableColumn = -1;

  final _PaceFocusKind kind;
  final _PaceTopField? field;
  final int tableColumn;
}

enum _PaceSurface { pace, ultra }

class _PaceView extends StatefulWidget {
  const _PaceView({required this.active, required this.surface});

  final bool active;
  final _PaceSurface surface;

  @override
  State<_PaceView> createState() => _PaceViewState();
}

class _UltraTableData {
  _UltraTableData({
    required this.columns,
    required this.fitTable,
    required this.times,
    required this.distances,
    required this.planTimes,
    required this.planPaces,
    required this.notes,
    required this.water,
    required this.food,
    this.locked = false,
    this.plannedPaceOverride = '',
    this.plannedTimeOverride = '',
    this.plannedSummarySource = _PlannedSummarySource.none,
    this.seeded = false,
    this.boldColumns = const [],
  });

  int columns;
  bool fitTable;
  List<String> times;
  List<String> distances;
  List<String> planTimes;
  List<String> planPaces;
  List<String> notes;
  List<String> water;
  List<String> food;
  bool locked;
  String plannedPaceOverride;
  String plannedTimeOverride;
  _PlannedSummarySource plannedSummarySource;

  /// Стартовые данные для этой таблицы уже применялись или проверялись.
  bool seeded;
  List<int> boldColumns;
}

class _PaceViewState extends State<_PaceView> {
  static const int _maxColumns = 20;
  static const int _baseColumns = 8;
  static const double _fixedCellWidth = 52;

  static const String _legacyStorageKey = 'pace_state_v1';
  static const String _paceStorageKey = 'pace_calc_state_v1';
  static const String _ultraStorageKey = 'ultra_state_v1';

  static const List<Color> _dayColors = [
    Color(0xFF1B5E20),
    Colors.blue,
    Colors.yellow,
    Colors.red,
    Colors.cyan,
    Colors.orange,
    Colors.white,
  ];

  _PaceCalc _calc = _PaceCalc.pace;
  _PaceFocus _focus = const _PaceFocus.top(_PaceTopField.distance);

  String _distance = '';
  String _paceMinutes = '';
  String _paceSeconds = '';
  String _days = '';
  String _hours = '';
  String _minutes = '';
  String _seconds = '';

  late List<_PaceEvent> _events;
  late String _selectedEvent;
  late String _selectedDistance;
  int _columns = _baseColumns;
  bool _fitTable = true;

  late List<String> _tableTimes;
  late List<String> _tableDistances;
  late List<String> _planTimes;
  late List<String> _planPaces;
  late List<String> _notes;
  late List<String> _water;
  late List<String> _food;

  late List<int> _limitDays;
  late List<int> _planDays;

  bool _locked = false;
  bool _lockedLimits = false;
  bool _keyboardVisible = false;

  String _plannedPaceOverride = '';
  String _plannedTimeOverride = '';
  _PlannedSummarySource _plannedSummarySource = _PlannedSummarySource.none;

  /// Стартовые данные этой таблицы уже применены или проверены.
  bool _seeded = false;

  /// Колонки, у которых долгим нажатием включены жирные границы.
  final Set<int> _boldColumns = {};

  final Map<String, _UltraTableData> _tables = {};
  final GlobalKey _focusAnchorKey = GlobalKey();

  Timer? _cursorTimer;
  bool _cursorVisible = true;
  bool _stateLoaded = false;
  bool _suppressPersist = false;
  Future<SharedPreferences>? _prefsFuture;

  bool get _isUltra => widget.surface == _PaceSurface.ultra;

  String get _storageKey => _isUltra ? _ultraStorageKey : _paceStorageKey;

  Future<SharedPreferences> get _prefs =>
      _prefsFuture ??= SharedPreferences.getInstance();

  @override
  void initState() {
    super.initState();
    _events = _defaultEvents();
    _selectedEvent = 'GRUT';
    _selectedDistance = 'T100';
    _resetTable(_columns);
    _loadPaceState();
    if (widget.active) _startCursorTimer();
  }

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    if (!_suppressPersist) _persist();
  }

  @override
  void didUpdateWidget(covariant _PaceView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      _startCursorTimer();
    } else if (!widget.active && oldWidget.active) {
      _cursorTimer?.cancel();
      if (_isUltra) {
        _limitDays = _computeDays(_tableTimes);
        _planDays = _computeDays(_planTimes);
        _keyboardVisible = false;
        _focus = const _PaceFocus.none();
      }
    }
  }

  @override
  void dispose() {
    _cursorTimer?.cancel();
    super.dispose();
  }

  void _startCursorTimer() {
    _cursorTimer?.cancel();
    _cursorVisible = true;
    _cursorTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted) return;
      _suppressPersist = true;
      setState(() {
        _cursorVisible = !_cursorVisible;
      });
      _suppressPersist = false;
    });
  }

  String _tableKey(String event, String distance) => '$event\u0001$distance';

  Map<String, dynamic> _tableToJson(_UltraTableData data) {
    return {
      'columns': data.columns,
      'fitTable': data.fitTable,
      'tableTimes': data.times,
      'tableDistances': data.distances,
      'planTimes': data.planTimes,
      'planPaces': data.planPaces,
      'notes': data.notes,
      'water': data.water,
      'food': data.food,
      'locked': data.locked,
      'plannedPaceOverride': data.plannedPaceOverride,
      'plannedTimeOverride': data.plannedTimeOverride,
      'plannedSummarySource': data.plannedSummarySource.name,
      'seeded': data.seeded,
      'boldColumns': data.boldColumns,
    };
  }

  Map<String, dynamic> _toJson() {
    if (!_isUltra) {
      return {
        'calc': _calc.name,
        'distance': _distance,
        'paceMinutes': _paceMinutes,
        'paceSeconds': _paceSeconds,
        'days': _days,
        'hours': _hours,
        'minutes': _minutes,
        'seconds': _seconds,
      };
    }

    _saveCurrentTable();
    final tables = <String, dynamic>{};
    for (final entry in _tables.entries) {
      final separator = entry.key.indexOf('\u0001');
      if (separator < 0) continue;
      final eventName = entry.key.substring(0, separator);
      final distanceName = entry.key.substring(separator + 1);
      final eventTables = tables.putIfAbsent(
        eventName,
        () => <String, dynamic>{},
      );
      if (eventTables is Map<String, dynamic>) {
        eventTables[distanceName] = _tableToJson(entry.value);
      }
    }

    return {
      'events': _events
          .map(
            (event) => {
              'name': event.name,
              'distances': event.distances
                  .map(
                    (distance) => {
                      'name': distance.name,
                      'checkpoints': distance.checkpoints,
                    },
                  )
                  .toList(),
            },
          )
          .toList(),
      'selectedEvent': _selectedEvent,
      'selectedDistance': _selectedDistance,
      'tables': tables,
    };
  }

  void _persist() {
    if (!_stateLoaded) return;

    final encoded = jsonEncode(_toJson());
    unawaited(
      _prefs
          .then((prefs) => prefs.setString(_storageKey, encoded))
          .catchError((Object _) => false),
    );
  }

  Map<String, dynamic>? _decodeState(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      // Повреждённые данные не должны мешать запуску.
    }
    return null;
  }

  Future<void> _loadPaceState() async {
    Map<String, dynamic>? data;
    try {
      final prefs = await _prefs;
      data = _decodeState(prefs.getString(_storageKey));
      data ??= _decodeState(prefs.getString(_legacyStorageKey));
    } catch (_) {
      // Недоступное хранилище не должно мешать запуску.
    }

    if (!mounted) return;
    setState(() {
      if (data != null) {
        _applyState(data);
      } else if (_isUltra) {
        _loadCurrentTable();
      }
      _stateLoaded = true;
    });
  }

  void _applyState(Map<String, dynamic> data) {
    if (_isUltra) {
      _applyUltraState(data);
    } else {
      _applyCalculatorState(data);
    }
    _focus = _isUltra
        ? const _PaceFocus.none()
        : const _PaceFocus.top(_PaceTopField.distance);
  }

  void _applyCalculatorState(Map<String, dynamic> data) {
    final calc = data['calc'];
    if (calc is String) {
      try {
        _calc = _PaceCalc.values.byName(calc);
      } catch (_) {
        // Неизвестный режим оставляем по умолчанию.
      }
    }

    _distance = _readString(data['distance']);
    _paceMinutes = _readString(data['paceMinutes']);
    _paceSeconds = _readString(data['paceSeconds']);
    _days = _readString(data['days']);
    _hours = _readString(data['hours']);
    _minutes = _readString(data['minutes']);
    _seconds = _readString(data['seconds']);
  }

  void _applyUltraState(Map<String, dynamic> data) {
    final rawEvents = data['events'];
    if (rawEvents is List) {
      final events = <_PaceEvent>[];
      for (final rawEvent in rawEvents) {
        if (rawEvent is! Map) continue;
        final name = rawEvent['name'];
        if (name is! String || name.isEmpty) continue;

        final distances = <_PaceDistance>[];
        final rawDistances = rawEvent['distances'];
        if (rawDistances is List) {
          for (final rawDistance in rawDistances) {
            if (rawDistance is! Map) continue;
            final distanceName = rawDistance['name'];
            final checkpoints = rawDistance['checkpoints'];
            if (distanceName is! String || distanceName.isEmpty) continue;
            if (checkpoints is! int) continue;
            distances.add(
              _PaceDistance(
                distanceName,
                checkpoints.clamp(1, _maxColumns - 2),
              ),
            );
          }
        }
        events.add(_PaceEvent(name, distances));
      }
      if (events.isNotEmpty) _events = events;
    }

    _prepareDistanceDefaults();

    final selectedEvent = data['selectedEvent'];
    if (selectedEvent is String &&
        _events.any((event) => event.name == selectedEvent)) {
      _selectedEvent = selectedEvent;
    }
    final event = _events.firstWhere(
      (event) => event.name == _selectedEvent,
      orElse: () => _events.first,
    );
    _selectedEvent = event.name;

    final selectedDistance = data['selectedDistance'];
    var requestedDistance = selectedDistance is String ? selectedDistance : '';
    if (event.name == 'Mad Fox Ultra' && requestedDistance == '100M') {
      requestedDistance = 'VR';
    }
    if (event.distances.any((distance) => distance.name == requestedDistance)) {
      _selectedDistance = requestedDistance;
    } else if (event.distances.isNotEmpty) {
      _selectedDistance = event.distances.first.name;
    } else {
      _selectedDistance = '—';
    }

    _tables.clear();
    final rawTables = data['tables'];
    if (rawTables is Map) {
      for (final eventEntry in rawTables.entries) {
        final eventName = eventEntry.key;
        final eventTables = eventEntry.value;
        if (eventName is! String || eventTables is! Map) continue;
        for (final distanceEntry in eventTables.entries) {
          var distanceName = distanceEntry.key;
          final rawTable = distanceEntry.value;
          if (distanceName is! String || rawTable is! Map) continue;
          if (eventName == 'Mad Fox Ultra' && distanceName == '100M') {
            distanceName = 'VR';
          }
          final table = _tableFromJson(rawTable);
          if (table != null) {
            _tables.putIfAbsent(
              _tableKey(eventName, distanceName),
              () => table,
            );
          }
        }
      }
    }

    // Данные старой версии хранились одной таблицей без разбивки по
    // мероприятиям и дистанциям.
    final legacyTable = _tableFromJson(data);
    if (legacyTable != null) {
      _tables.putIfAbsent(
        _tableKey(_selectedEvent, _selectedDistance),
        () => legacyTable,
      );
    }

    _loadCurrentTable();
  }

  _UltraTableData? _tableFromJson(Map<dynamic, dynamic> data) {
    final rawColumns = data['columns'];
    if (rawColumns is! int) return null;
    final columns = rawColumns.clamp(3, _maxColumns);

    // Read bold columns from saved data
    List<int> boldCols = [];
    final rawBold = data['boldColumns'];
    if (rawBold is List) {
      for (final item in rawBold) {
        if (item is int) boldCols.add(item);
      }
    }

    return _UltraTableData(
      columns: columns,
      fitTable: data['fitTable'] is bool ? data['fitTable'] as bool : true,
      times: _readStringList(data['tableTimes'], columns),
      distances: _readStringList(data['tableDistances'], columns),
      planTimes: _readStringList(data['planTimes'], columns),
      planPaces: _readStringList(data['planPaces'], columns),
      notes: _readStringList(data['notes'], columns),
      water: _readStringList(data['water'], columns),
      food: _readStringList(data['food'], columns),
      locked: data['locked'] is bool ? data['locked'] as bool : false,
      plannedPaceOverride: _readString(data['plannedPaceOverride']),
      plannedTimeOverride: _readString(data['plannedTimeOverride']),
      plannedSummarySource: _plannedSourceFromName(
        data['plannedSummarySource'],
      ),
      seeded: data['seeded'] is bool ? data['seeded'] as bool : false,
      boldColumns: boldCols,
    );
  }

  _PlannedSummarySource _plannedSourceFromName(dynamic value) {
    if (value is String) {
      try {
        return _PlannedSummarySource.values.byName(value);
      } catch (_) {
        // Неизвестный источник оставляем по умолчанию.
      }
    }
    return _PlannedSummarySource.none;
  }

  _UltraTableData _snapshotTable() {
    return _UltraTableData(
      columns: _columns,
      fitTable: _fitTable,
      times: List<String>.of(_tableTimes),
      distances: List<String>.of(_tableDistances),
      planTimes: List<String>.of(_planTimes),
      planPaces: List<String>.of(_planPaces),
      notes: List<String>.of(_notes),
      water: List<String>.of(_water),
      food: List<String>.of(_food),
      locked: _locked,
      plannedPaceOverride: _plannedPaceOverride,
      plannedTimeOverride: _plannedTimeOverride,
      plannedSummarySource: _plannedSummarySource,
      seeded: _seeded,
      boldColumns: List<int>.of(_boldColumns),
    );
  }

  void _saveCurrentTable() {
    if (_selectedDistance == '—') return;
    _tables[_tableKey(_selectedEvent, _selectedDistance)] = _snapshotTable();
  }

  void _loadCurrentTable() {
    // Жирные границы — временное оформление текущей таблицы, поэтому при
    // переключении мероприятия или дистанции они сбрасываются.
    _boldColumns.clear();
    final data = _tables[_tableKey(_selectedEvent, _selectedDistance)];
    if (data == null) {
      final event = _events.firstWhere(
        (event) => event.name == _selectedEvent,
        orElse: () => _events.first,
      );
      _PaceDistance? distance;
      for (final item in event.distances) {
        if (item.name == _selectedDistance) {
          distance = item;
          break;
        }
      }
      _resetTable(
        distance == null ? _baseColumns : distance.checkpoints + 2,
        distance,
      );
      if (_selectedDistance != '—') {
        _tables[_tableKey(_selectedEvent, _selectedDistance)] =
            _snapshotTable();
      }
      return;
    }

    _columns = data.columns.clamp(3, _maxColumns);
    _fitTable = data.fitTable;
    _tableTimes = _resizeList(data.times, _columns);
    _tableDistances = _resizeList(data.distances, _columns);
    _planTimes = _resizeList(data.planTimes, _columns);
    _planPaces = _resizeList(data.planPaces, _columns);
    _notes = _resizeList(data.notes, _columns);
    _water = _resizeList(data.water, _columns);
    _food = _resizeList(data.food, _columns);
    _tableDistances[0] = '0.00';
    _locked = data.locked;
    _keyboardVisible = false;
    _plannedPaceOverride = data.plannedPaceOverride;
    _plannedTimeOverride = data.plannedTimeOverride;
    _plannedSummarySource = data.plannedSummarySource;
    _seeded = data.seeded;
    _limitDays = _computeDays(_tableTimes);
    _planDays = _computeDays(_planTimes);

    if (!data.seeded) {
      // Старая таблица без флага: заполняем стартовыми данными только если
      // пользователь ещё ничего не ввёл, и больше не трогаем её при загрузке.
      _seeded = true;
      if (_isTableEmpty(data)) {
        final distance = _findDistance(_selectedEvent, _selectedDistance);
        if (distance != null) _applyDistanceDefaults(distance);
      }
      if (_selectedDistance != '—') {
        _tables[_tableKey(_selectedEvent, _selectedDistance)] =
            _snapshotTable();
      }
    }
  }

  _PaceDistance? _findDistance(String eventName, String distanceName) {
    for (final event in _events) {
      if (event.name != eventName) continue;
      for (final distance in event.distances) {
        if (distance.name == distanceName) return distance;
      }
    }
    return null;
  }

  bool _isTableEmpty(_UltraTableData data) {
    bool hasValue(List<String> values, {int skip = 0}) {
      for (var index = skip; index < values.length; index++) {
        if (values[index].trim().isNotEmpty) return true;
      }
      return false;
    }

    return !hasValue(data.times) &&
        !hasValue(data.distances, skip: 1) &&
        !hasValue(data.planTimes) &&
        !hasValue(data.planPaces) &&
        !hasValue(data.notes) &&
        !hasValue(data.water) &&
        !hasValue(data.food);
  }

  String _readString(dynamic value) => value is String ? value : '';

  List<String> _readStringList(dynamic value, int length) {
    final result = List<String>.filled(length, '');
    if (value is List) {
      for (var index = 0; index < length && index < value.length; index++) {
        final item = value[index];
        if (item is String) result[index] = item;
      }
    }
    return result;
  }

  static const List<String> _grutT100Times = [
    '0500',
    '0700',
    '0800',
    '1000',
    '1700',
    '2035',
    '2200',
    '2300',
  ];

  static const List<String> _grutT100Distances = [
    '',
    '11',
    '18.8',
    '30',
    '70.2',
    '94',
    '102.2',
    '109.5',
  ];

  static const List<String> _madFoxVrTimes = [
    '1600',
    '2100',
    '2350',
    '0300',
    '0640',
    '0930',
    '1245',
    '1500',
    '1730',
    '1900',
    '2200',
  ];

  static const List<String> _madFoxVrDistances = [
    '',
    '20.3',
    '32.2',
    '47.3',
    '72',
    '90.7',
    '111.2',
    '125.8',
    '139.6',
    '148.5',
    '165.2',
  ];

  /// Данные для дистанции K40 в Mad Fox Ultra (время)
  static const List<String> _madFoxK40Times = [
    '1030',
    '1330',
    '1530',
    '1830',
  ];

  /// Дистанции для K40 в Mad Fox Ultra (в км)
  static const List<String> _madFoxK40Distances = [
    '',
    '14.8',
    '24',
    '40.7',
  ];

  static List<_PaceEvent> _defaultEvents() => [
    _PaceEvent('GRUT', [
      _PaceDistance(
        'T100',
        6,
        defaultTimes: _grutT100Times,
        defaultDistances: _grutT100Distances,
      ),
      _PaceDistance('T80', 6),
      _PaceDistance('T50', 4),
    ]),
    _PaceEvent('Mad Fox Ultra', [
      _PaceDistance(
        'VR',
        9,
        defaultTimes: _madFoxVrTimes,
        defaultDistances: _madFoxVrDistances,
      ),
      _PaceDistance('50M', 5),
      _PaceDistance('K70', 4),
      _PaceDistance(
        'K40',
        2,
        defaultTimes: _madFoxK40Times,
        defaultDistances: _madFoxK40Distances,
      ),
    ]),
  ];

  /// Переименовывает старую дистанцию `100M` в `VR` и подключает стартовые
  /// данные к известным дистанциям, загруженным из старого хранилища.
  void _prepareDistanceDefaults() {
    for (final event in _events) {
      for (var index = 0; index < event.distances.length; index++) {
        final distance = event.distances[index];
        final isLegacyVr =
            event.name == 'Mad Fox Ultra' && distance.name == '100M';
        final name = isLegacyVr ? 'VR' : distance.name;
        if (!isLegacyVr &&
            (distance.defaultTimes.isNotEmpty ||
                distance.defaultDistances.isNotEmpty)) {
          continue;
        }

        List<String>? times;
        List<String>? distances;
        if (event.name == 'GRUT' && name == 'T100') {
          times = _grutT100Times;
          distances = _grutT100Distances;
        } else if (event.name == 'Mad Fox Ultra' && name == 'VR') {
          times = _madFoxVrTimes;
          distances = _madFoxVrDistances;
        }

        if (times == null || distances == null) {
          if (isLegacyVr) {
            event.distances[index] = _PaceDistance('VR', distance.checkpoints);
          }
          continue;
        }

        event.distances[index] = _PaceDistance(
          name,
          distance.checkpoints,
          defaultTimes: times,
          defaultDistances: distances,
        );
      }
    }
  }

  void _resetTable(int columns, [_PaceDistance? distance]) {
    final clamped = columns.clamp(3, _maxColumns).toInt();
    _columns = clamped;
    _fitTable = true;
    _tableTimes = List.filled(clamped, '');
    _tableDistances = List.filled(clamped, '');
    _planTimes = List.filled(clamped, '');
    _planPaces = List.filled(clamped, '');
    _notes = List.filled(clamped, '');
    _water = List.filled(clamped, '');
    _food = List.filled(clamped, '');
    _tableDistances[0] = '0.00';
    _seeded = true;

    if (distance != null) _applyDistanceDefaults(distance);

    _locked = false;
    _keyboardVisible = false;
    _boldColumns.clear();
    _plannedPaceOverride = '';
    _plannedTimeOverride = '';
    _plannedSummarySource = _PlannedSummarySource.none;
    _limitDays = _computeDays(_tableTimes);
    _planDays = _computeDays(_planTimes);
  }

  void _applyDistanceDefaults(_PaceDistance distance) {
    for (var index = 0; index < _columns; index++) {
      if (index < distance.defaultTimes.length) {
        _tableTimes[index] = distance.defaultTimes[index];
      }
      if (index > 0 && index < distance.defaultDistances.length) {
        _tableDistances[index] = distance.defaultDistances[index];
      }
    }
    _limitDays = _computeDays(_tableTimes);
    _planDays = _computeDays(_planTimes);
  }

  void _resizeTable(int columns) {
    final clamped = columns.clamp(3, _maxColumns).toInt();
    if (clamped == _columns) return;

    setState(() {
      _columns = clamped;
      if (clamped <= _baseColumns) _fitTable = true;
      _tableTimes = _resizeList(_tableTimes, clamped);
      _tableDistances = _resizeList(_tableDistances, clamped);
      _planTimes = _resizeList(_planTimes, clamped);
      _planPaces = _resizeList(_planPaces, clamped);
      _notes = _resizeList(_notes, clamped);
      _water = _resizeList(_water, clamped);
      _food = _resizeList(_food, clamped);
      _tableDistances[0] = '0.00';
      _boldColumns.removeWhere((index) => index >= clamped);
      _limitDays = _computeDays(_tableTimes);
      _planDays = _computeDays(_planTimes);

      if (_focus.tableColumn >= clamped) {
        _focus = const _PaceFocus.top(_PaceTopField.distance);
      }
    });
  }

  List<String> _resizeList(List<String> source, int length) {
    return List.generate(
      length,
      (index) => index < source.length ? source[index] : '',
    );
  }

  String get _eventLabel => '$_selectedEvent · $_selectedDistance';

  double? get _distanceValue => _parseDecimalValue(_distance);

  int? get _paceValue {
    if (_paceMinutes.trim().isEmpty && _paceSeconds.trim().isEmpty) {
      return null;
    }
    final minutes = int.tryParse(_paceMinutes.trim()) ?? 0;
    final seconds = int.tryParse(_paceSeconds.trim()) ?? 0;
    return minutes * 60 + seconds;
  }

  int? get _timeValue {
    return _parseDurationParts([_days, _hours, _minutes, _seconds]);
  }

  int? get _computedPace {
    final distance = _distanceValue;
    final time = _timeValue;
    if (distance == null || time == null || distance <= 0) return null;
    return (time / distance).round();
  }

  double? get _computedDistance {
    final time = _timeValue;
    final pace = _paceValue;
    if (time == null || pace == null || pace <= 0) return null;
    return time / pace;
  }

  int? get _computedTime {
    final distance = _distanceValue;
    final pace = _paceValue;
    if (distance == null || pace == null || distance <= 0) return null;
    return (distance * pace).round();
  }

  bool _isPaceField(_PaceTopField field) {
    return field == _PaceTopField.paceMinutes ||
        field == _PaceTopField.paceSeconds;
  }

  bool _isTimeField(_PaceTopField field) {
    return field == _PaceTopField.days ||
        field == _PaceTopField.hours ||
        field == _PaceTopField.minutes ||
        field == _PaceTopField.seconds;
  }

  bool _isTopEditable(_PaceTopField field) {
    return switch (_calc) {
      _PaceCalc.pace => field == _PaceTopField.distance || _isTimeField(field),
      _PaceCalc.distance => _isPaceField(field) || _isTimeField(field),
      _PaceCalc.time => field == _PaceTopField.distance || _isPaceField(field),
    };
  }

  bool _isTopFocused(_PaceTopField field) {
    return _focus.kind == _PaceFocusKind.top && _focus.field == field;
  }

  void _selectCalc(_PaceCalc calc) {
    setState(() {
      _calc = calc;
      _cursorVisible = true;
      _focus = switch (calc) {
        _PaceCalc.pace => const _PaceFocus.top(_PaceTopField.distance),
        _PaceCalc.distance => const _PaceFocus.top(_PaceTopField.paceMinutes),
        _PaceCalc.time => const _PaceFocus.top(_PaceTopField.distance),
      };
    });
  }

  void _focusTop(_PaceTopField field) {
    if (!_isTopEditable(field)) return;
    setState(() {
      _focus = _PaceFocus.top(field);
      _cursorVisible = true;
    });
  }

  String _topTimeValue(_PaceTopField field) {
    return switch (field) {
      _PaceTopField.days => _days,
      _PaceTopField.hours => _hours,
      _PaceTopField.minutes => _minutes,
      _PaceTopField.seconds => _seconds,
      _ => '',
    };
  }

  void _setTopTimeValue(_PaceTopField field, String value) {
    switch (field) {
      case _PaceTopField.days:
        _days = value;
      case _PaceTopField.hours:
        _hours = value;
      case _PaceTopField.minutes:
        _minutes = value;
      case _PaceTopField.seconds:
        _seconds = value;
      default:
        break;
    }
  }

  String _topPaceMinutes() {
    if (_calc == _PaceCalc.pace) {
      final pace = _computedPace;
      return pace == null ? '—' : '${pace ~/ 60}';
    }
    return _paceMinutes;
  }

  String _topPaceSeconds() {
    if (_calc == _PaceCalc.pace) {
      final pace = _computedPace;
      return pace == null ? '' : '${pace % 60}'.padLeft(2, '0');
    }
    return _paceSeconds;
  }

  String _topDistance() {
    if (_calc == _PaceCalc.distance) {
      final distance = _computedDistance;
      return distance == null ? '—' : distance.toStringAsFixed(2);
    }
    return _distance;
  }

  String _topTimePart(_PaceTopField field) {
    if (_calc != _PaceCalc.time) return _topTimeValue(field);

    final time = _computedTime;
    if (time == null) return field == _PaceTopField.days ? '—' : '';

    final parts = _splitSeconds(time);
    return switch (field) {
      _PaceTopField.days => '${parts.days}',
      _PaceTopField.hours => '${parts.hours}'.padLeft(2, '0'),
      _PaceTopField.minutes => '${parts.minutes}'.padLeft(2, '0'),
      _PaceTopField.seconds => '${parts.seconds}'.padLeft(2, '0'),
      _ => '',
    };
  }

  String _timeBufferText(String buffer) {
    if (buffer.isEmpty) return '00:00';
    final digits = buffer.padRight(4, '0');
    return '${digits.substring(0, 2)}:${digits.substring(2, 4)}';
  }

  int? _parseTimeBuffer(String buffer) {
    if (buffer.isEmpty) return null;
    final digits = buffer.padRight(4, '0');
    final hours = int.tryParse(digits.substring(0, 2));
    final minutes = int.tryParse(digits.substring(2, 4));
    if (hours == null || minutes == null || minutes > 59) return null;
    return hours * 60 + minutes;
  }

  String _paceBufferText(String buffer) {
    if (buffer.isEmpty) return '0:00';
    final digits = buffer.length < 4 ? buffer.padRight(4, '0') : buffer;
    final minutesStr = digits.substring(0, digits.length - 2);
    final minutes = int.tryParse(minutesStr) ?? 0;
    final seconds = int.tryParse(digits.substring(digits.length - 2)) ?? 0;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  int? _parsePaceBuffer(String buffer) {
    if (buffer.isEmpty) return null;
    final digits = buffer.length < 4 ? buffer.padRight(4, '0') : buffer;
    final minutes = int.tryParse(digits.substring(0, digits.length - 2));
    final seconds = int.tryParse(digits.substring(digits.length - 2));
    if (minutes == null || seconds == null || seconds > 59) return null;
    return minutes * 60 + seconds;
  }

  String _paceBufferFromSeconds(int totalSeconds) {
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}'
        '${seconds.toString().padLeft(2, '0')}';
  }

  String _timeBufferFromMinutes(int totalMinutes) {
    // Время суток циклично: план может пересекать несколько суток, поэтому
    // результат всегда приводится к 00:00–23:59.
    final minutesInDay = ((totalMinutes % (24 * 60)) + 24 * 60) % (24 * 60);
    final hours = minutesInDay ~/ 60;
    final minutes = minutesInDay % 60;
    return '${hours.toString().padLeft(2, '0')}'
        '${minutes.toString().padLeft(2, '0')}';
  }

  /// Определяет, находится ли текущая строка таблицы Ultra до или после ряда "План".
  /// Индексы строк таблицы: 0=Start/ПП, 1=Лимит, 2=Расстояние, 3=Темп сегмента (зеленый), 
  /// 4=Общее время, 5=Темп в лимит, 6=План, 7=Плановый темп (белый), 8=Итоговый плановый темп (белый), 9=Итоговое плановое время (белый)
  bool _isBeforePlanRow(int rowIndex) => rowIndex <= 5;

  String _columnLabel(int index) {
    if (index == 0) return 'Start';
    if (index == _columns - 1) return 'Finish';
    return '$index';
  }

  /// Форматирует время в формате чч:мм, убирая ведущий ноль (например, "07:00" -> "7:00").
  String _formatTimeWithoutLeadingZero(String timeBuffer) {
    if (timeBuffer.isEmpty) return '';
    final parts = timeBuffer.split(':');
    if (parts.length < 2) return timeBuffer;
    final hours = parts[0];
    final minutes = parts[1];
    // Убираем ведущий ноль у часов, если он есть
    final formattedHours = hours.replaceAllMapped(RegExp(r'^0+'), (match) => match.group(0)?.substring(1) ?? '');
    return '$formattedHours:$minutes';
  }

  String _tableTimeText(int column) {
    return _timeBufferText(_tableTimes[column]);
  }

  String _tableDistanceText(int column) {
    final focused =
        _focus.kind == _PaceFocusKind.tableDistance &&
        _focus.tableColumn == column;
    if (focused) return _tableDistances[column];
    return _formatDistanceInput(_tableDistances[column]);
  }

  /// Показывает столько знаков после запятой, сколько ввёл пользователь:
  /// целые значения остаются целыми, `20.3` — с одной десятой, `20.35` — с
  /// двумя.
  String _formatDistanceInput(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    final normalized = trimmed.replaceAll(',', '.');
    final dot = normalized.indexOf('.');
    final decimals = dot < 0 ? 0 : normalized.length - dot - 1;
    final value = _parseDecimalValue(trimmed);
    if (value == null) return '';
    if (decimals <= 0) return value.toStringAsFixed(0);
    if (decimals == 1) return value.toStringAsFixed(1);
    return value.toStringAsFixed(2);
  }

  String _planTimeText(int column) {
    return _timeBufferText(_planTimes[column]);
  }

  String _planPaceText(int column) {
    if (column == 0) return 'PACE';
    final focused =
        _focus.kind == _PaceFocusKind.tablePlanPace &&
        _focus.tableColumn == column;
    if (focused) return _paceBufferText(_planPaces[column]);
    if (_planPaces[column].isNotEmpty) {
      return _paceBufferText(_planPaces[column]);
    }

    final pace = _plannedPace(column);
    return pace == null ? '0:00' : _formatPaceSeconds(pace);
  }

  /// Определяет цвет текста для ячейки таблицы Ultra.
  /// Цвета от начала до ряда "Темп в лимит" (индексы 0-5): светло-коричневый
  /// План и ниже (индексы 6-9): белый
  Color? _cellTextColor(int rowIndex, {bool isPlanRow = false}) {
    if (rowIndex <= 5) {
      return const Color(0xFFD2B48C); // Светло-коричневый (tan)
    }
    if (isPlanRow || rowIndex >= 6) {
      return Colors.white;
    }
    return null;
  }

  /// Определяет цвет текста для ячейки в ряду Темп сегмента (зеленый по умолчанию).
  Color? _segmentPaceTextColor(int column, int rowIndex) {
    if (rowIndex != 3) return null; // Только для ряда Темп сегмента
    return const Color(0xFF4CAF50); // Зеленый
  }

  int? _segmentPace(int index) {
    if (index == 0) return null;

    final previousTime = _parseTimeBuffer(_tableTimes[index - 1]);
    final time = _parseTimeBuffer(_tableTimes[index]);
    final previousDistance = _parseDecimalValue(_tableDistances[index - 1]);
    final distance = _parseDecimalValue(_tableDistances[index]);

    if (previousTime == null ||
        time == null ||
        previousDistance == null ||
        distance == null) {
      return null;
    }

    var timeDelta = time - previousTime;
    if (timeDelta < 0) timeDelta += 24 * 60;

    final distanceDelta = distance - previousDistance;
    if (distanceDelta <= 0) return null;

    return (timeDelta * 60 / distanceDelta).round();
  }

  int? _plannedPace(int column) {
    if (column <= 0) return null;

    final previousTime = _parseTimeBuffer(_planTimes[column - 1]);
    final time = _parseTimeBuffer(_planTimes[column]);
    final previousDistance = _parseDecimalValue(_tableDistances[column - 1]);
    final distance = _parseDecimalValue(_tableDistances[column]);

    if (previousTime == null ||
        time == null ||
        previousDistance == null ||
        distance == null) {
      return null;
    }

    var timeDelta = time - previousTime;
    if (timeDelta < 0) timeDelta += 24 * 60;

    final distanceDelta = distance - previousDistance;
    if (distanceDelta <= 0) return null;

    return (timeDelta * 60 / distanceDelta).round();
  }

  int? get _overallPaceSeconds => _overallPaceFor(_tableTimes);

  int? _overallPaceFor(List<String> times) {
    final startTime = _parseTimeBuffer(times[0]);
    final startDistance = _parseDecimalValue(_tableDistances[0]) ?? 0;
    if (startTime == null) return null;

    var lastIndex = -1;
    for (var index = 1; index < _columns; index++) {
      if (_parseTimeBuffer(times[index]) != null &&
          _parseDecimalValue(_tableDistances[index]) != null) {
        lastIndex = index;
      }
    }
    if (lastIndex < 1) return null;

    var elapsedMinutes = 0;
    var previousTime = startTime;
    for (var index = 1; index <= lastIndex; index++) {
      final currentTime = _parseTimeBuffer(times[index]);
      if (currentTime == null) continue;

      var delta = currentTime - previousTime;
      if (delta < 0) delta += 24 * 60;
      elapsedMinutes += delta;
      previousTime = currentTime;
    }

    final endDistance = _parseDecimalValue(_tableDistances[lastIndex]);
    if (endDistance == null) return null;

    final distanceDelta = endDistance - startDistance;
    if (distanceDelta <= 0) return null;

    return (elapsedMinutes * 60 / distanceDelta).round();
  }

  Color? _paceHighlight(int column, List<int?> paces) {
    final values = <int>[];
    for (final pace in paces) {
      if (pace != null) values.add(pace);
    }
    if (values.isEmpty) return null;

    values.sort();
    final minimum = values.first;
    int? second;
    for (final value in values) {
      if (value > minimum) {
        second = value;
        break;
      }
    }

    final pace = paces[column];
    if (pace == null) return null;
    if (pace == minimum) return Colors.red;
    if (second != null && pace == second) return Colors.amber;
    return null;
  }

  List<int> _computeDays(List<String> times) {
    final days = List<int>.filled(_columns, 0);
    var day = 0;
    int? previous;
    for (var index = 0; index < _columns; index++) {
      final time = index < times.length ? _parseTimeBuffer(times[index]) : null;
      if (time != null) {
        if (previous != null && time < previous) day++;
        previous = time;
      }
      days[index] = day;
    }
    return days;
  }

  /// Returns true if the plan time at the given column exceeds the limit time.
  bool _planExceedsLimit(int column) {
    final planTime = _parseTimeBuffer(_planTimes[column]);
    final limitTime = _parseTimeBuffer(_tableTimes[column]);
    if (planTime == null || limitTime == null) return false;

    // Handle day rollover: compute the actual elapsed time from start
    final planStart = _parseTimeBuffer(_planTimes[0]);
    final limitStart = _parseTimeBuffer(_tableTimes[0]);
    if (planStart == null || limitStart == null) return false;

    // Calculate cumulative minutes from start for both plans
    var planElapsed = 0;
    var limitElapsed = 0;
    int? prevPlanTime;
    int? prevLimitTime;

    for (var i = 1; i <= column; i++) {
      final p = _parseTimeBuffer(_planTimes[i]);
      final l = _parseTimeBuffer(_tableTimes[i]);
      
      if (p != null && prevPlanTime != null) {
        var delta = p - prevPlanTime;
        if (delta < 0) delta += 24 * 60;
        planElapsed += delta;
      }
      if (l != null && prevLimitTime != null) {
        var delta = l - prevLimitTime;
        if (delta < 0) delta += 24 * 60;
        limitElapsed += delta;
      }
      
      prevPlanTime = p;
      prevLimitTime = l;
    }

    return planElapsed > limitElapsed;
  }

  /// Пересчитывает дни только по завершении ввода: при смене поля,
  /// нажатии «ОК», закрытии клавиатуры или тапе вне полей ввода.
  void _commitDays() {
    if (!_isUltra) return;
    final limitDays = _computeDays(_tableTimes);
    final planDays = _computeDays(_planTimes);
    if (listEquals(limitDays, _limitDays) && listEquals(planDays, _planDays)) {
      return;
    }
    setState(() {
      _limitDays = limitDays;
      _planDays = planDays;
    });
  }

  Color? _dayBorderColor(int column, List<int> days) {
    if (column < 0 || column >= days.length) return null;
    final day = days[column];
    if (day <= 0) return null;
    return _dayColors[(day - 1) % _dayColors.length];
  }

  int? get _totalLimitMinutes => _elapsedMinutesFor(_tableTimes);

  int? _elapsedMinutesFor(List<String> times) {
    if (times.isEmpty) return null;
    final start = _parseTimeBuffer(times[0]);
    if (start == null) return null;

    var total = 0;
    var found = false;
    var previous = start;
    for (var index = 1; index < _columns; index++) {
      final time = index < times.length ? _parseTimeBuffer(times[index]) : null;
      if (time == null) continue;

      var delta = time - previous;
      if (delta < 0) delta += 24 * 60;
      total += delta;
      previous = time;
      found = true;
    }
    return found ? total : null;
  }

  double? get _totalTableDistance {
    if (_tableDistances.isEmpty) return null;
    final start = _parseDecimalValue(_tableDistances[0]);
    double? end;
    for (var index = 1; index < _columns; index++) {
      final distance = _parseDecimalValue(_tableDistances[index]);
      if (distance != null) end = distance;
    }
    if (start == null || end == null) return null;
    final delta = end - start;
    return delta > 0 ? delta : null;
  }

  int? get _planStartMinutes {
    final plan = _parseTimeBuffer(_planTimes[0]);
    if (plan != null) return plan;
    return _parseTimeBuffer(_tableTimes[0]);
  }

  int? get _overallPlannedPaceSeconds {
    switch (_plannedSummarySource) {
      case _PlannedSummarySource.pace:
        return _parsePaceBuffer(_plannedPaceOverride) ??
            _overallPaceFor(_planTimes);
      case _PlannedSummarySource.time:
        final duration = _parseTimeBuffer(_plannedTimeOverride);
        final distance = _totalTableDistance;
        if (duration == null || distance == null || distance <= 0) {
          return _overallPaceFor(_planTimes);
        }
        return (duration * 60 / distance).round();
      case _PlannedSummarySource.none:
        return _overallPaceFor(_planTimes);
    }
  }

  /// Итоговое плановое время — это длительность от планового старта до
  /// планового финиша, а не время суток финиша.
  int? get _overallPlannedFinishMinutes {
    switch (_plannedSummarySource) {
      case _PlannedSummarySource.pace:
        final pace = _parsePaceBuffer(_plannedPaceOverride);
        final distance = _totalTableDistance;
        if (pace == null || distance == null || distance <= 0) {
          return _plannedDurationFromPlan;
        }
        return (pace * distance / 60).round();
      case _PlannedSummarySource.time:
        return _parseTimeBuffer(_plannedTimeOverride) ??
            _plannedDurationFromPlan;
      case _PlannedSummarySource.none:
        return _plannedDurationFromPlan;
    }
  }

  int? get _plannedDurationFromPlan {
    final start = _parseTimeBuffer(_planTimes[0]);
    if (start == null) return null;

    var total = 0;
    var previous = start;
    var found = false;
    for (var index = 1; index < _columns; index++) {
      final time = _parseTimeBuffer(_planTimes[index]);
      if (time == null) continue;

      var delta = time - previous;
      if (delta < 0) delta += 24 * 60;
      total += delta;
      previous = time;
      found = true;
    }
    return found ? total : null;
  }

  String _formatElapsedMinutes(int? minutes) {
    if (minutes == null) return '—';
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    return '${hours.toString().padLeft(2, '0')}:'
        '${rest.toString().padLeft(2, '0')}';
  }

  void _resetPlannedSummary() {
    _plannedPaceOverride = '';
    _plannedTimeOverride = '';
    _plannedSummarySource = _PlannedSummarySource.none;
  }

  void _beginTableFocus(_PaceFocus focus) {
    if (_locked) return;
    _commitDays();
    setState(() {
      _focus = focus;
      _cursorVisible = true;
      _keyboardVisible = true;
    });
    _ensureFocusVisible();
  }

  void _focusTableTime(int column) {
    _beginTableFocus(_PaceFocus.tableTime(column));
  }

  void _focusTableDistance(int column) {
    if (column == 0) return;
    _beginTableFocus(_PaceFocus.tableDistance(column));
  }

  void _focusPlanTime(int column) {
    _beginTableFocus(_PaceFocus.tablePlanTime(column));
  }

  void _focusPlanPace(int column) {
    if (column == 0) return;
    _beginTableFocus(_PaceFocus.tablePlanPace(column));
  }

  void _focusSummaryPlannedPace() {
    _beginTableFocus(const _PaceFocus.summaryPlannedPace());
  }

  void _focusSummaryPlannedTime() {
    _beginTableFocus(const _PaceFocus.summaryPlannedTime());
  }

  Future<void> _commitInput() async {
    final focus = _focus;
    var apply = true;
    switch (focus.kind) {
      case _PaceFocusKind.summaryPlannedTime:
        apply = await _confirmAndApplyPlannedTime();
      case _PaceFocusKind.summaryPlannedPace:
        apply = await _confirmAndApplyPlannedPace();
      default:
        break;
    }
    if (!mounted || !apply) return;
    _finishInput();
  }

  Future<bool> _confirmAndApplyPlannedTime() async {
    final duration = _parseTimeBuffer(_plannedTimeOverride);
    final distance = _totalTableDistance;
    final start = _planStartMinutes;
    if (duration == null || duration <= 0) {
      _showMessage('Введите итоговое плановое время');
      return false;
    }
    if (distance == null || distance <= 0) {
      _showMessage('Заполните расстояние в ряду «Расстояние, км»');
      return false;
    }
    if (start == null) {
      _showMessage('Заполните время старта');
      return false;
    }

    final planStartFilled = _parseTimeBuffer(_planTimes[0]) != null;
    final confirmed = await _confirmPlanRecalculation(
      planStartFilled
          ? 'Плановые данные будут переписаны, кроме времени старта. '
                'Средний темп рассчитается по введённому времени и расстоянию.'
          : 'Плановые данные будут переписаны. Время старта будет взято из '
                'ряда «Лимит». Средний темп рассчитается по введённому времени '
                'и расстоянию.',
    );
    if (!confirmed) return false;

    setState(() {
      if (!planStartFilled) _planTimes[0] = _tableTimes[0];
      final paceSeconds = (duration * 60 / distance).round();
      _applyPlanSchedule(paceSeconds, totalMinutes: duration);
      _resetPlannedSummary();
    });
    return true;
  }

  Future<bool> _confirmAndApplyPlannedPace() async {
    final pace = _parsePaceBuffer(_plannedPaceOverride);
    final distance = _totalTableDistance;
    final start = _planStartMinutes;
    if (pace == null || pace <= 0) {
      _showMessage('Введите итоговый плановый темп');
      return false;
    }
    if (distance == null || distance <= 0) {
      _showMessage('Заполните расстояние в ряду «Расстояние, км»');
      return false;
    }
    if (start == null) {
      _showMessage('Заполните время старта');
      return false;
    }

    final planStartFilled = _parseTimeBuffer(_planTimes[0]) != null;
    final confirmed = await _confirmPlanRecalculation(
      planStartFilled
          ? 'Плановые данные будут переписаны, кроме времени старта. '
                'Плановый темп будет заполнен введённым значением.'
          : 'Плановые данные будут переписаны. Время старта будет взято из '
                'ряда «Лимит». Плановый темп будет заполнен введённым '
                'значением.',
    );
    if (!confirmed) return false;

    setState(() {
      if (!planStartFilled) _planTimes[0] = _tableTimes[0];
      _applyPlanSchedule(pace);
      _resetPlannedSummary();
    });
    return true;
  }

  Future<bool> _confirmPlanRecalculation(String message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Пересчитать план?'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Пересчитать'),
            ),
          ],
        );
      },
    );
    return confirmed == true;
  }

  void _applyPlanSchedule(int paceSeconds, {int? totalMinutes}) {
    final start =
        _parseTimeBuffer(_planTimes[0]) ?? _parseTimeBuffer(_tableTimes[0]);
    if (start == null) return;

    final startDistance = _parseDecimalValue(_tableDistances[0]) ?? 0;
    final paceBuffer = _paceBufferFromSeconds(paceSeconds);
    var lastIndex = 0;

    for (var index = 1; index < _columns; index++) {
      _planPaces[index] = paceBuffer;
      final distance = _parseDecimalValue(_tableDistances[index]);
      if (distance == null) {
        _planTimes[index] = '';
        continue;
      }
      final delta = distance - startDistance;
      final minutes = (delta * paceSeconds / 60).round();
      _planTimes[index] = _timeBufferFromMinutes(start + minutes);
      lastIndex = index;
    }

    if (totalMinutes != null && lastIndex > 0) {
      _planTimes[lastIndex] = _timeBufferFromMinutes(start + totalMinutes);
    }
    _planPaces[0] = '';
    _planDays = _computeDays(_planTimes);

    // Recalculate subsequent checkpoint times based on their individual paces
    // if those paces have been manually entered
    for (var index = 1; index < _columns; index++) {
      final paced = _parsePaceBuffer(_planPaces[index]);
      if (paced == null || paced == 0) continue;

      final distance = _parseDecimalValue(_tableDistances[index]);
      final prevDistance = _parseDecimalValue(_tableDistances[index - 1]);
      if (distance == null || prevDistance == null) continue;

      final distanceDelta = distance - prevDistance;
      if (distanceDelta <= 0) continue;

      // Get the previous plan time
      final prevPlanTime = _parseTimeBuffer(_planTimes[index - 1]);
      if (prevPlanTime == null) continue;

      // Calculate time for this segment based on its pace
      final segmentMinutes = (paced * distanceDelta / 60).round();
      _planTimes[index] = _timeBufferFromMinutes(prevPlanTime + segmentMinutes);
    }
  }

  /// Завершает ввод: пересчитывает дни и убирает клавиатуру.
  void _finishInput() {
    _commitDays();
    if (!_keyboardVisible && _focus.kind == _PaceFocusKind.none) return;
    setState(() {
      _keyboardVisible = false;
      _focus = const _PaceFocus.none();
    });
  }

  void _hideKeyboard() {
    if (!_isUltra) return;
    _finishInput();
  }

  void _ensureFocusVisible() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureFocusVisibleNow();
    });
  }

  void _ensureFocusVisibleNow() {
    if (!mounted) return;
    final target = _focusAnchorKey.currentContext;
    if (target == null || !target.mounted) return;
    final targetBox = target.findRenderObject();
    if (targetBox is! RenderBox || !targetBox.hasSize) return;

    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final axis = landscape ? Axis.horizontal : Axis.vertical;

    ScrollableState? scrollable;
    target.visitAncestorElements((element) {
      final state = element is StatefulElement ? element.state : null;
      if (state is ScrollableState && state.position.axis == axis) {
        scrollable = state;
        return false;
      }
      return true;
    });
    final state = scrollable;
    if (state == null) return;

    final viewportBox = state.context.findRenderObject();
    if (viewportBox is! RenderBox || !viewportBox.hasSize) return;

    final position = state.position;
    final targetTopLeft = targetBox.localToGlobal(Offset.zero);
    final viewportTopLeft = viewportBox.localToGlobal(Offset.zero);

    double delta;
    if (axis == Axis.vertical) {
      final targetStart = targetTopLeft.dy;
      final targetEnd = targetStart + targetBox.size.height;
      final viewportStart = viewportTopLeft.dy;
      final viewportEnd = viewportStart + viewportBox.size.height;
      if (targetEnd > viewportEnd) {
        delta = targetEnd - viewportEnd;
      } else if (targetStart < viewportStart) {
        delta = targetStart - viewportStart;
      } else {
        return;
      }
    } else {
      final targetStart = targetTopLeft.dx;
      final targetEnd = targetStart + targetBox.size.width;
      final viewportStart = viewportTopLeft.dx;
      final viewportEnd = viewportStart + viewportBox.size.width;
      if (targetEnd > viewportEnd) {
        delta = targetEnd - viewportEnd;
      } else if (targetStart < viewportStart) {
        delta = targetStart - viewportStart;
      } else {
        return;
      }
    }

    position.animateTo(
      (position.pixels + delta).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  Future<void> _toggleLock() async {
    _hideKeyboard();
    final unlocking = _locked;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(
            unlocking ? 'Снять фиксацию?' : 'Зафиксировать введённые значения?',
          ),
          content: Text(
            unlocking
                ? 'Поля снова станут доступны для изменений.'
                : 'Все поля ввода станут недоступны для изменений. '
                      'Разблокировать таблицу можно этой же кнопкой.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(unlocking ? 'Снять' : 'Зафиксировать'),
            ),
          ],
        );
      },
    );

    if (!mounted || confirmed != true) return;
    setState(() {
      _locked = !unlocking;
      _keyboardVisible = false;
      _focus = const _PaceFocus.none();
    });
  }

  String _appendTimeBuffer(String current, String char) {
    if (char == ':') return current;

    if (!_isDigitChar(char) || current.length >= 4) return current;
    if (current.length == 2 && char.codeUnitAt(0) > 0x35) return current;
    return '$current$char';
  }

  String _appendPaceBuffer(String current, String char) {
    if (char == ':') return current;

    // Темп — это минуты и секунды; минуты могут быть больше 99
    // (например, 100:00), поэтому длина не ограничивается.
    if (!_isDigitChar(char)) return current;
    return '$current$char';
  }

  void _appendTableTime(int column, String char) {
    setState(() {
      _tableTimes[column] = _appendTimeBuffer(_tableTimes[column], char);
    });
  }

  void _appendPlanTime(int column, String char) {
    setState(() {
      _planTimes[column] = _appendTimeBuffer(_planTimes[column], char);
      _planPaces[column] = '';
      _resetPlannedSummary();
    });
  }

  void _applyPlanPace(int column) {
    if (column <= 0) return;

    final pace = _parsePaceBuffer(_planPaces[column]);
    if (pace == null) return;

    final previousTime = _parseTimeBuffer(_planTimes[column - 1]) ?? 0;
    final previousDistance = _parseDecimalValue(_tableDistances[column - 1]);
    final distance = _parseDecimalValue(_tableDistances[column]);
    if (previousDistance == null || distance == null) return;

    final distanceDelta = distance - previousDistance;
    if (distanceDelta <= 0) return;

    final minutes = (pace * distanceDelta / 60).round();
    _planTimes[column] = _timeBufferFromMinutes(previousTime + minutes);
  }

  void _appendPlanPace(int column, String char) {
    if (column == 0) return;
    setState(() {
      _planPaces[column] = _appendPaceBuffer(_planPaces[column], char);
      _applyPlanPace(column);
      _resetPlannedSummary();
    });
  }

  void _appendTableDistance(int column, String char) {
    if (column == 0) return;
    setState(() {
      _tableDistances[column] = _appendDecimal(_tableDistances[column], char);
      _resetPlannedSummary();
    });
  }

  void _appendTopField(_PaceTopField field, String char) {
    if (!_isTopEditable(field)) return;

    setState(() {
      switch (field) {
        case _PaceTopField.distance:
          _distance = _appendDecimal(_distance, char);
        case _PaceTopField.paceMinutes:
          _paceMinutes = _appendInteger(_paceMinutes, char, 3);
        case _PaceTopField.paceSeconds:
          _paceSeconds = _appendInteger(_paceSeconds, char, 2);
        case _PaceTopField.days:
          _days = _appendInteger(_days, char, 3);
        case _PaceTopField.hours:
        case _PaceTopField.minutes:
        case _PaceTopField.seconds:
          _setTopTimeValue(
            field,
            _appendInteger(_topTimeValue(field), char, 2),
          );
      }
    });
  }

  String _appendInteger(String current, String char, int maxLength) {
    if (!_isDigitChar(char) || current.length >= maxLength) return current;
    return '$current$char';
  }

  String _appendDecimal(String current, String char) {
    if (char == '.') {
      if (current.contains('.')) return current;
      return current.isEmpty ? '0.' : '$current.';
    }

    if (!_isDigitChar(char)) return current;

    final dot = current.indexOf('.');
    if (dot == -1) {
      if (current.length >= 5) return current;
      return '$current$char';
    }

    if (current.length - dot - 1 >= 2) return current;
    return '$current$char';
  }

  void _appendActive(String char) {
    switch (_focus.kind) {
      case _PaceFocusKind.none:
        break;
      case _PaceFocusKind.top:
        _appendTopField(_focus.field!, char);
      case _PaceFocusKind.tableTime:
        _appendTableTime(_focus.tableColumn, char);
      case _PaceFocusKind.tableDistance:
        _appendTableDistance(_focus.tableColumn, char);
      case _PaceFocusKind.tablePlanTime:
        _appendPlanTime(_focus.tableColumn, char);
      case _PaceFocusKind.tablePlanPace:
        _appendPlanPace(_focus.tableColumn, char);
      case _PaceFocusKind.summaryPlannedPace:
        setState(() {
          _plannedPaceOverride = _appendPaceBuffer(_plannedPaceOverride, char);
          _plannedSummarySource = _PlannedSummarySource.pace;
        });
      case _PaceFocusKind.summaryPlannedTime:
        setState(() {
          _plannedTimeOverride = _appendTimeBuffer(_plannedTimeOverride, char);
          _plannedSummarySource = _PlannedSummarySource.time;
        });
    }
  }

  void _backspaceActive() {
    setState(() {
      switch (_focus.kind) {
        case _PaceFocusKind.none:
          break;
        case _PaceFocusKind.top:
          final field = _focus.field!;
          switch (field) {
            case _PaceTopField.distance:
              _distance = _removeLast(_distance);
            case _PaceTopField.paceMinutes:
              _paceMinutes = _removeLast(_paceMinutes);
            case _PaceTopField.paceSeconds:
              _paceSeconds = _removeLast(_paceSeconds);
            case _PaceTopField.days:
            case _PaceTopField.hours:
            case _PaceTopField.minutes:
            case _PaceTopField.seconds:
              _setTopTimeValue(field, _removeLast(_topTimeValue(field)));
          }
        case _PaceFocusKind.tableTime:
          _tableTimes[_focus.tableColumn] = _removeLast(
            _tableTimes[_focus.tableColumn],
          );
        case _PaceFocusKind.tableDistance:
          if (_focus.tableColumn == 0) return;
          _tableDistances[_focus.tableColumn] = _removeLast(
            _tableDistances[_focus.tableColumn],
          );
          _resetPlannedSummary();
        case _PaceFocusKind.tablePlanTime:
          _planTimes[_focus.tableColumn] = _removeLast(
            _planTimes[_focus.tableColumn],
          );
          _planPaces[_focus.tableColumn] = '';
          _resetPlannedSummary();
        case _PaceFocusKind.tablePlanPace:
          final column = _focus.tableColumn;
          _planPaces[column] = _removeLast(_planPaces[column]);
          _applyPlanPace(column);
          _resetPlannedSummary();
        case _PaceFocusKind.summaryPlannedPace:
          _plannedPaceOverride = _removeLast(_plannedPaceOverride);
          _plannedSummarySource = _PlannedSummarySource.pace;
        case _PaceFocusKind.summaryPlannedTime:
          _plannedTimeOverride = _removeLast(_plannedTimeOverride);
          _plannedSummarySource = _PlannedSummarySource.time;
      }
    });
  }

  void _clearActive() {
    setState(() {
      switch (_focus.kind) {
        case _PaceFocusKind.none:
          break;
        case _PaceFocusKind.top:
          final field = _focus.field!;
          switch (field) {
            case _PaceTopField.distance:
              _distance = '';
            case _PaceTopField.paceMinutes:
              _paceMinutes = '';
            case _PaceTopField.paceSeconds:
              _paceSeconds = '';
            case _PaceTopField.days:
            case _PaceTopField.hours:
            case _PaceTopField.minutes:
            case _PaceTopField.seconds:
              _setTopTimeValue(field, '');
          }
        case _PaceFocusKind.tableTime:
          _tableTimes[_focus.tableColumn] = '';
        case _PaceFocusKind.tableDistance:
          if (_focus.tableColumn == 0) return;
          _tableDistances[_focus.tableColumn] = '';
          _resetPlannedSummary();
        case _PaceFocusKind.tablePlanTime:
          _planTimes[_focus.tableColumn] = '';
          _planPaces[_focus.tableColumn] = '';
          _resetPlannedSummary();
        case _PaceFocusKind.tablePlanPace:
          final column = _focus.tableColumn;
          _planPaces[column] = '';
          if (column > 0) _planTimes[column] = '';
          _resetPlannedSummary();
        case _PaceFocusKind.summaryPlannedPace:
          _plannedPaceOverride = '';
          _plannedSummarySource = _PlannedSummarySource.pace;
        case _PaceFocusKind.summaryPlannedTime:
          _plannedTimeOverride = '';
          _plannedSummarySource = _PlannedSummarySource.time;
      }
    });
  }

  String _removeLast(String value) {
    if (value.isEmpty) return value;
    return value.substring(0, value.length - 1);
  }

  bool _isDigitChar(String char) {
    final code = char.codeUnitAt(0);
    return code >= 0x30 && code <= 0x39;
  }

  Future<void> _editTextCell({
    required String title,
    required String value,
    required ValueChanged<String> onSaved,
    bool multiline = false,
  }) async {
    _hideKeyboard();
    var text = value;
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: TextFormField(
            initialValue: value,
            autofocus: true,
            keyboardType: multiline
                ? TextInputType.multiline
                : TextInputType.text,
            minLines: multiline ? 3 : 1,
            maxLines: multiline ? 6 : 1,
            textInputAction: multiline
                ? TextInputAction.newline
                : TextInputAction.done,
            onChanged: (value) => text = value,
            decoration: const InputDecoration(hintText: 'Введите текст'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, text),
              child: const Text('Сохранить'),
            ),
          ],
        );
      },
    );

    if (!mounted || result == null) return;
    setState(() {
      onSaved(result.trim());
    });
  }

  Future<void> _editNote(int index) async {
    await _editTextCell(
      title: 'Заметка: ${_columnLabel(index)}',
      value: _notes[index],
      onSaved: (text) {
        if (index < _notes.length) _notes[index] = text;
      },
    );
  }

  Future<void> _editListCell({
    required String title,
    required List<String> values,
    required int index,
  }) async {
    await _editTextCell(
      title: title,
      value: values[index],
      multiline: true,
      onSaved: (text) {
        if (index < values.length) values[index] = text;
      },
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showEventMenu() async {
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return SimpleDialog(
          title: const Text('Мероприятие'),
          children: [
            for (final event in _events)
              SimpleDialogOption(
                onPressed: () =>
                    Navigator.pop(dialogContext, 'event:${event.name}'),
                child: Row(
                  children: [
                    Expanded(child: Text(event.name)),
                    if (event.name == _selectedEvent)
                      const Icon(
                        Icons.check,
                        color: Color(0xFFFF9800),
                        size: 20,
                      ),
                  ],
                ),
              ),
            const Divider(),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, 'add'),
              child: const Text('+ Добавить мероприятие'),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, 'remove'),
              child: const Text('− Удалить мероприятие'),
            ),
          ],
        );
      },
    );

    if (!mounted || result == null) return;

    if (result == 'add') {
      await _addEvent();
    } else if (result == 'remove') {
      await _removeEvent();
    } else if (result.startsWith('event:')) {
      final name = result.substring('event:'.length);
      final event = _events.firstWhere(
        (event) => event.name == name,
        orElse: () => _events.first,
      );
      await _showDistanceMenu(event);
    }
  }

  Future<void> _showDistanceMenu(_PaceEvent event) async {
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return SimpleDialog(
          title: Text(event.name),
          children: [
            if (event.distances.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Нет дистанций'),
              ),
            for (final distance in event.distances)
              SimpleDialogOption(
                onPressed: () =>
                    Navigator.pop(dialogContext, 'distance:${distance.name}'),
                child: Row(
                  children: [
                    Expanded(child: Text(distance.name)),
                    Text(
                      '${distance.checkpoints} ПП',
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    if (event.name == _selectedEvent &&
                        distance.name == _selectedDistance)
                      const Padding(
                        padding: EdgeInsets.only(left: 6),
                        child: Icon(
                          Icons.check,
                          color: Color(0xFFFF9800),
                          size: 20,
                        ),
                      ),
                  ],
                ),
              ),
            const Divider(),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, 'add'),
              child: const Text('+ Добавить дистанцию'),
            ),
            if (event.distances.isNotEmpty)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(dialogContext, 'remove'),
                child: const Text('− Удалить дистанцию'),
              ),
          ],
        );
      },
    );

    if (!mounted || result == null) return;

    if (result == 'add') {
      await _addDistance(event);
    } else if (result == 'remove') {
      await _removeDistance(event);
    } else if (result.startsWith('distance:')) {
      final name = result.substring('distance:'.length);
      final distance = event.distances.firstWhere(
        (distance) => distance.name == name,
        orElse: () => event.distances.first,
      );
      _selectDistance(event, distance);
    }
  }

  void _selectDistance(_PaceEvent event, _PaceDistance distance) {
    _commitDays();
    setState(() {
      _saveCurrentTable();
      _selectedEvent = event.name;
      _selectedDistance = distance.name;
      _focus = const _PaceFocus.none();
      _cursorVisible = true;
      _keyboardVisible = false;
      _loadCurrentTable();
    });
  }

  Future<void> _addEvent() async {
    var name = '';
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Новое мероприятие'),
          content: TextFormField(
            autofocus: true,
            onChanged: (value) => name = value,
            decoration: const InputDecoration(hintText: 'Название'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, name.trim()),
              child: const Text('Добавить'),
            ),
          ],
        );
      },
    );

    if (!mounted || result == null || result.isEmpty) return;

    if (_events.any((event) => event.name == result)) {
      _showMessage('Такое мероприятие уже есть');
      return;
    }

    setState(() {
      _events.add(_PaceEvent(result, []));
    });
  }

  Future<void> _removeEvent() async {
    if (_events.length <= 1) {
      _showMessage('Нельзя удалить последнее мероприятие');
      return;
    }

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return SimpleDialog(
          title: const Text('Удалить мероприятие'),
          children: [
            for (final event in _events)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(dialogContext, event.name),
                child: Text(event.name),
              ),
          ],
        );
      },
    );

    if (!mounted || result == null) return;

    setState(() {
      _saveCurrentTable();
      _events.removeWhere((event) => event.name == result);
      _tables.removeWhere((key, _) => key.startsWith('$result\u0001'));

      if (_selectedEvent == result) {
        final first = _events.first;
        _selectedEvent = first.name;
        if (first.distances.isNotEmpty) {
          _selectedDistance = first.distances.first.name;
        } else {
          _selectedDistance = '—';
        }
        _loadCurrentTable();
      }
    });
  }

  Future<void> _addDistance(_PaceEvent event) async {
    var name = '';
    var checkpoints = '4';

    final result = await showDialog<({String name, int checkpoints})>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('Дистанция ${event.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                autofocus: true,
                onChanged: (value) => name = value,
                decoration: const InputDecoration(
                  labelText: 'Название',
                  hintText: 'T100',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: checkpoints,
                keyboardType: TextInputType.number,
                onChanged: (value) => checkpoints = value,
                decoration: const InputDecoration(labelText: 'Количество ПП'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, (
                name: name.trim(),
                checkpoints: int.tryParse(checkpoints) ?? 0,
              )),
              child: const Text('Добавить'),
            ),
          ],
        );
      },
    );

    if (!mounted || result == null || result.name.isEmpty) return;

    if (event.distances.any((distance) => distance.name == result.name)) {
      _showMessage('Такая дистанция уже есть');
      return;
    }

    if (result.checkpoints < 1 || result.checkpoints > _maxColumns - 2) {
      _showMessage('Количество ПП должно быть от 1 до ${_maxColumns - 2}');
      return;
    }

    setState(() {
      event.distances.add(_PaceDistance(result.name, result.checkpoints));
    });
  }

  Future<void> _removeDistance(_PaceEvent event) async {
    if (event.distances.length <= 1) {
      _showMessage('Нельзя удалить последнюю дистанцию');
      return;
    }

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return SimpleDialog(
          title: Text('Удалить дистанцию · ${event.name}'),
          children: [
            for (final distance in event.distances)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(dialogContext, distance.name),
                child: Text('${distance.name} (${distance.checkpoints} ПП)'),
              ),
          ],
        );
      },
    );

    if (!mounted || result == null) return;

    setState(() {
      _saveCurrentTable();
      event.distances.removeWhere((distance) => distance.name == result);
      _tables.remove(_tableKey(event.name, result));

      if (event.name == _selectedEvent && _selectedDistance == result) {
        final distance = event.distances.first;
        _selectedDistance = distance.name;
        _loadCurrentTable();
      }
    });
  }

  Future<void> _showColumnsDialog() async {
    var columns = _columns;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Колонки таблицы'),
              content: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    key: const ValueKey('pace-columns-minus'),
                    onPressed: columns > 3
                        ? () => setDialogState(() => columns--)
                        : null,
                    icon: const Icon(Icons.remove),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      '$columns',
                      style: const TextStyle(fontSize: 24),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('pace-columns-plus'),
                    onPressed: columns < _maxColumns
                        ? () => setDialogState(() => columns++)
                        : null,
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Отмена'),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                    _resizeTable(columns);
                  },
                  child: const Text('Применить'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _toggleScale() {
    _hideKeyboard();
    setState(() {
      _fitTable = !_fitTable;
    });
  }

  Widget _buildTableToolbar() {
    return Row(
      children: [
        Expanded(
          flex: 6,
          child: _toolbarButton(
            key: 'pace-event-button',
            label: _eventLabel,
            icon: Icons.flag_outlined,
            onTap: _locked
                ? null
                : () {
                    _hideKeyboard();
                    _showEventMenu();
                  },
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          flex: 2,
          child: _toolbarButton(
            key: 'pace-columns-button',
            label: '+−',
            icon: Icons.view_column_outlined,
            onTap: _locked
                ? null
                : () {
                    _hideKeyboard();
                    _showColumnsDialog();
                  },
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          flex: 2,
          child: _toolbarButton(
            key: 'pace-lock-button',
            icon: _locked || _lockedLimits ? Icons.lock : Icons.lock_open,
            onTap: _showLockMenu,
            active: _locked || _lockedLimits,
          ),
        ),
        if (_columns > _baseColumns) ...[
          const SizedBox(width: 4),
          Expanded(
            flex: 2,
            child: _toolbarButton(
              key: 'pace-scale-button',
              label: _fitTable ? 'Масштаб: вписать' : 'Масштаб: 1:1',
              icon: Icons.zoom_out_map,
              onTap: _toggleScale,
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _showLockMenu() async {
    _hideKeyboard();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return SimpleDialog(
          title: const Text('Фиксация'),
          children: [
            if (!_lockedLimits)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(dialogContext, 'lock_limits'),
                child: const Text('Зафиксировать лимиты'),
              )
            else
              SimpleDialogOption(
                onPressed: () => Navigator.pop(dialogContext, 'unlock_limits'),
                child: const Text('Разблокировать лимиты'),
              ),
            if (!_locked)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(dialogContext, 'lock_all'),
                child: const Text('Зафиксировать все'),
              )
            else
              SimpleDialogOption(
                onPressed: () => Navigator.pop(dialogContext, 'unlock_all'),
                child: const Text('Разблокировать все'),
              ),
            const Divider(),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, 'print'),
              child: const Text('Зафиксировать в бумаге'),
            ),
          ],
        );
      },
    );

    if (!mounted || result == null) return;

    switch (result) {
      case 'lock_limits':
        await _confirmAndApplyLock(true, false);
        break;
      case 'unlock_limits':
        await _confirmAndApplyUnlock(true, false);
        break;
      case 'lock_all':
        await _confirmAndApplyLock(true, true);
        break;
      case 'unlock_all':
        await _confirmAndApplyUnlock(true, true);
        break;
      case 'print':
        await _showPrintDialog();
        break;
    }
  }

  Future<void> _confirmAndApplyLock(bool lockLimits, bool lockAll) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Зафиксировать введённые значения?'),
          content: Text(
            lockAll
                ? 'Все поля ввода станут недоступны для изменений.'
                : 'Поля ПП, лимит и расстояние станут недоступны для изменений.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Зафиксировать'),
            ),
          ],
        );
      },
    );

    if (!mounted || confirmed != true) return;
    setState(() {
      if (lockAll) {
        _locked = true;
      } else {
        _lockedLimits = true;
        _locked = true;
      }
      _keyboardVisible = false;
      _focus = const _PaceFocus.none();
    });
  }

  Future<void> _confirmAndApplyUnlock(bool unlockLimits, bool unlockAll) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Снять фиксацию?'),
          content: const Text('Поля снова станут доступны для изменений.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Снять'),
            ),
          ],
        );
      },
    );

    if (!mounted || confirmed != true) return;
    setState(() {
      if (unlockAll) {
        _locked = false;
        _lockedLimits = false;
      } else {
        _lockedLimits = false;
        _locked = false;
      }
      _keyboardVisible = false;
      _focus = const _PaceFocus.none();
    });
  }

  Future<void> _showPrintDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Зафиксировать в бумаге?'),
          content: const Text(
            'Все поля ввода станут недоступны для изменений.\n'
            'Это эквивалентно "Зафиксировать все".',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Зафиксировать'),
            ),
          ],
        );
      },
    );

    if (!mounted || confirmed != true) return;
    setState(() {
      _locked = true;
      _keyboardVisible = false;
      _focus = const _PaceFocus.none();
    });
  }

  Widget _toolbarButton({
    required String key,
    String? label,
    required IconData icon,
    VoidCallback? onTap,
    bool active = false,
  }) {
    final enabled = onTap != null;
    final accent = active ? const Color(0xFFFF9800) : Colors.grey;
    final iconOnly = label == null;
    return InkWell(
      key: ValueKey(key),
      onTap: onTap,
      child: Container(
        height: 34,
        padding: EdgeInsets.symmetric(horizontal: iconOnly ? 0 : 6),
        decoration: BoxDecoration(
          color: Colors.black,
          border: Border.all(color: active ? accent : Colors.grey.shade700),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: iconOnly ? 20 : 15,
              color: enabled ? accent : Colors.grey.shade600,
            ),
            if (label != null) ...[
              const SizedBox(width: 4),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: TextStyle(
                      color: enabled ? Colors.white : Colors.grey.shade600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;

    if (!_isUltra) {
      final calculator = SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
        child: _buildCalculator(),
      );

      if (landscape) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: calculator),
            SizedBox(width: 190, child: _buildKeyboard(compact: true)),
          ],
        );
      }

      return Column(
        children: [
          Expanded(child: calculator),
          _buildKeyboard(compact: false),
        ],
      );
    }

    if (landscape) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final keyboardWidth = math.min(
            160.0,
            math.max(110.0, constraints.maxWidth * 0.2),
          );

          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: _hideKeyboard,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(4, 2, 4, 2),
                    child: _buildTable(compact: true),
                  ),
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                alignment: Alignment.centerRight,
                onEnd: _ensureFocusVisibleNow,
                child: _keyboardVisible
                    ? SizedBox(
                        width: keyboardWidth,
                        child: _buildKeyboard(compact: true, tableLayout: true),
                      )
                    : const SizedBox(width: 0),
              ),
            ],
          );
        },
      );
    }

    return Column(
      children: [
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _hideKeyboard,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildTableToolbar(),
                  const SizedBox(height: 8),
                  _buildTable(compact: false),
                ],
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          alignment: Alignment.bottomCenter,
          onEnd: _ensureFocusVisibleNow,
          child: _keyboardVisible
              ? _buildKeyboard(compact: false)
              : const SizedBox(width: double.infinity, height: 0),
        ),
      ],
    );
  }

  Widget _buildCalculator() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _calcButton('Темп', _PaceCalc.pace, 'pace-calc-pace'),
            const SizedBox(width: 4),
            _calcButton('Расстояние', _PaceCalc.distance, 'pace-calc-distance'),
            const SizedBox(width: 4),
            _calcButton('Время', _PaceCalc.time, 'pace-calc-time'),
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
            color: selected ? const Color(0xFFFF9800) : Colors.black,
            border: Border.all(
              color: selected ? const Color(0xFFFF9800) : Colors.grey.shade700,
            ),
            borderRadius: BorderRadius.circular(7),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              style: TextStyle(
                color: selected ? Colors.black : Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _cursor() {
    return Opacity(
      opacity: _cursorVisible ? 1 : 0,
      child: Container(
        width: 2,
        height: 18,
        margin: const EdgeInsets.only(left: 1),
        color: const Color(0xFF4CAF50),
      ),
    );
  }

  Widget _field({
    required String key,
    required String text,
    required bool editable,
    required bool focused,
    required VoidCallback onTap,
    String hint = '',
  }) {
    final borderColor = focused
        ? const Color(0xFF4CAF50)
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
          color: editable ? Colors.black : const Color(0xFF1B1B1B),
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
                      : const Color(0xFFFFB74D),
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
            'Темп',
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
            hint: 'мин',
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
            hint: 'сек',
          ),
        ),
        const SizedBox(
          width: 44,
          child: Padding(
            padding: EdgeInsets.only(left: 4),
            child: Text(
              'мин/км',
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
            'Расстояние',
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
            hint: 'км',
          ),
        ),
        const SizedBox(
          width: 44,
          child: Padding(
            padding: EdgeInsets.only(left: 4),
            child: Text(
              'км',
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
    const labels = ['дни', 'часы', 'мин', 'сек'];
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
                'Время',
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

  static const double _totalColumnWidth = 62;

  static const String _totalTimeDescription =
      'Общее время по данным строки «Лимит»: сумма переходов от старта '
      'до последнего заполненного пункта.';
  static const String _limitPaceDescription =
      'Итоговый темп всей дистанции по данным строки «Лимит».';
  static const String _plannedPaceDescription =
      'Итоговый плановый темп по данным строки «План».';
  static const String _plannedTimeDescription =
      'Длительность плана: разница между плановым стартом и плановым '
      'финишем.';

  void _showTotalDescription(String title, String description) {
    _hideKeyboard();
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: Text(description),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Закрыть'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTable({required bool compact}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final gap = compact ? 2.0 : 5.0;

        final compactLabels = <String>[
          '',
          'Лимит',
          'Расстояние, км',
          'Темп сегмента',
          'План',
          'Плановый темп',
          'Вода',
          'Еда',
        ];
        final portraitLabels = <String>[
          '',
          '',
          '',
          '',
          '',
          'План',
          '',
          '',
          '',
          '',
          '',
        ];
        final labels = compact ? compactLabels : portraitLabels;

        late List<double> heights;
        if (compact) {
          const weights = <double>[1.3, 1.3, 1.3, 1.3, 1.3, 1.3, 2.1, 2.1];
          final totalWeight = weights.fold<double>(0, (sum, w) => sum + w);
          final available = constraints.maxHeight.isFinite
              ? math.max(
                  0.0,
                  constraints.maxHeight - gap * (weights.length - 1),
                )
              : 30.0 * weights.length;
          final unit = available / totalWeight;
          heights = weights.map((w) => math.max(12.0, unit * w)).toList();
        } else {
          // Ряд заметок в два раза выше остальных, чтобы в нём помещался
          // крупный номер ПП и текст заметки. Вода и еда — максимально высокие.
          heights = <double>[60, 30, 30, 30, 30, 30, 30, 30, 30, 110, 110];
        }

        final rows = <Widget>[];
        if (compact) {
          rows.add(
            _tableRow(
              cells: _headerCells(true),
              height: heights[0],
              expanded: _fitTable,
              total: _totalHeaderCell(),
            ),
          );
          rows.add(
            _tableRow(
              cells: _timeCells(),
              height: heights[1],
              expanded: _fitTable,
              total: _totalValueCell(
                key: 'pace-total-time',
                text: _formatElapsedMinutes(_totalLimitMinutes),
                onTap: () =>
                    _showTotalDescription('Общее время', _totalTimeDescription),
              ),
            ),
          );
          rows.add(
            _tableRow(
              cells: _distanceCells(),
              height: heights[2],
              expanded: _fitTable,
              total: _totalBlankCell(),
            ),
          );
          rows.add(
            _tableRow(
              cells: _segmentPaceCells(),
              height: heights[3],
              expanded: _fitTable,
              total: _totalValueCell(
                key: 'pace-total-pace',
                text: _overallPaceSeconds == null
                    ? '—'
                    : _formatPaceSeconds(_overallPaceSeconds!),
                onTap: () => _showTotalDescription(
                  'Темп в лимит',
                  _limitPaceDescription,
                ),
              ),
            ),
          );
          rows.add(
            _tableRow(
              cells: _planTimeCells(),
              height: heights[4],
              expanded: _fitTable,
              total: _totalValueCell(
                key: 'pace-total-plan-time',
                text: _formatElapsedMinutes(_overallPlannedFinishMinutes),
                focused: _focus.kind == _PaceFocusKind.summaryPlannedTime,
                editable: true,
                onTap: _focusSummaryPlannedTime,
                onLongPress: () => _showTotalDescription(
                  'Итоговое плановое время',
                  _plannedTimeDescription,
                ),
              ),
            ),
          );
          rows.add(
            _tableRow(
              cells: _planPaceCells(),
              height: heights[5],
              expanded: _fitTable,
              total: _totalValueCell(
                key: 'pace-total-plan-pace',
                text: _overallPlannedPaceSeconds == null
                    ? '—'
                    : _formatPaceSeconds(_overallPlannedPaceSeconds!),
                focused: _focus.kind == _PaceFocusKind.summaryPlannedPace,
                editable: true,
                onTap: _focusSummaryPlannedPace,
                onLongPress: () => _showTotalDescription(
                  'Итоговый плановый темп',
                  _plannedPaceDescription,
                ),
              ),
            ),
          );
          rows.add(
            _wrappedTextRow(
              values: _water,
              keyPrefix: 'pace-water',
              title: 'Вода',
              height: heights[6],
              expanded: _fitTable,
              showFirstPlaceholder: false,
              total: _totalBlankCell(),
            ),
          );
          rows.add(
            _wrappedTextRow(
              values: _food,
              keyPrefix: 'pace-food',
              title: 'Еда',
              height: heights[7],
              expanded: _fitTable,
              showFirstPlaceholder: false,
              total: _totalBlankCell(),
            ),
          );
        } else {
          rows.add(
            _tableRow(
              cells: _headerCells(false),
              height: heights[0],
              expanded: _fitTable,
            ),
          );
          rows.add(
            _tableRow(
              cells: _timeCells(),
              height: heights[1],
              expanded: _fitTable,
            ),
          );
          rows.add(
            _tableRow(
              cells: _distanceCells(),
              height: heights[2],
              expanded: _fitTable,
            ),
          );
          rows.add(
            _tableRow(
              cells: _segmentPaceCells(),
              height: heights[3],
              expanded: _fitTable,
            ),
          );
          rows.add(
            _limitSummarySplitRow(height: heights[4], expanded: _fitTable),
          );
          rows.add(
            _tableRow(
              cells: _planTimeCells(),
              height: heights[5],
              expanded: _fitTable,
            ),
          );
          rows.add(
            _tableRow(
              cells: _planPaceCells(),
              height: heights[6],
              expanded: _fitTable,
            ),
          );
          rows.add(
            _plannedPaceSummaryRow(height: heights[7], expanded: _fitTable),
          );
          rows.add(
            _plannedTimeSummaryRow(height: heights[8], expanded: _fitTable),
          );
          rows.add(
            _wrappedTextRow(
              values: _water,
              keyPrefix: 'pace-water',
              title: 'Вода',
              height: heights[9],
              expanded: _fitTable,
              showFirstPlaceholder: true,
            ),
          );
          rows.add(
            _wrappedTextRow(
              values: _food,
              keyPrefix: 'pace-food',
              title: 'Еда',
              height: heights[10],
              expanded: _fitTable,
              showFirstPlaceholder: true,
            ),
          );
        }

        if (compact) {
          const labelWidth = 58.0;
          final availableWidth = math.max(
            1.0,
            constraints.maxWidth - labelWidth,
          );
          final tableWidth = _fitTable
              ? availableWidth
              : _columns * _fixedCellWidth + _totalColumnWidth;

          final table = SizedBox(
            width: tableWidth,
            child: Column(
              children: [
                for (var index = 0; index < rows.length; index++) ...[
                  if (index > 0) SizedBox(height: gap),
                  rows[index],
                ],
              ],
            ),
          );

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: labelWidth,
                child: Column(
                  children: [
                    for (var index = 0; index < labels.length; index++) ...[
                      if (index > 0) SizedBox(height: gap),
                      SizedBox(
                        height: heights[index],
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            labels[index],
                            maxLines: 1,
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 8,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Expanded(
                child: _fitTable
                    ? table
                    : SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: table,
                      ),
              ),
            ],
          );
        }

        final tableWidth = _fitTable
            ? constraints.maxWidth
            : _columns * _fixedCellWidth;
        final table = SizedBox(
          width: tableWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var index = 0; index < rows.length; index++) ...[
                if (index > 0) SizedBox(height: gap),
                if (labels[index].isNotEmpty) ...[
                  Text(
                    labels[index],
                    style: const TextStyle(color: Colors.grey, fontSize: 10),
                  ),
                  const SizedBox(height: 2),
                ],
                rows[index],
              ],
            ],
          ),
        );

        return _fitTable
            ? table
            : SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: table,
              );
      },
    );
  }

  Widget _tableRow({
    required List<Widget> cells,
    required double height,
    required bool expanded,
    Widget? total,
  }) {
    return SizedBox(
      height: height,
      child: Row(
        children: [
          for (final cell in cells)
            expanded
                ? Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 0.5),
                      child: SizedBox(height: height, child: cell),
                    ),
                  )
                : SizedBox(
                    width: _fixedCellWidth,
                    height: height,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 0.5),
                      child: cell,
                    ),
                  ),
          if (total != null)
            SizedBox(
              width: _totalColumnWidth,
              height: height,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 0.5),
                child: total,
              ),
            ),
        ],
      ),
    );
  }

  Widget _totalHeaderCell() {
    return _interactiveCell(
      key: 'pace-total-header',
      text: 'Total',
      result: true,
      bold: true,
      fontSize: 13,
    );
  }

  Widget _totalBlankCell() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        border: Border.all(color: Colors.grey.shade900),
      ),
    );
  }

  Widget _totalValueCell({
    required String key,
    required String text,
    bool focused = false,
    bool editable = false,
    VoidCallback? onTap,
    VoidCallback? onLongPress,
  }) {
    return _interactiveCell(
      key: key,
      text: text,
      focused: focused,
      editable: editable,
      result: true,
      bold: true,
      fontSize: 13,
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }

  Widget _limitSummarySplitRow({
    required double height,
    required bool expanded,
  }) {
    final pace = _overallPaceSeconds;
    final row = SizedBox(
      height: height,
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 0.5),
              child: _interactiveCell(
                key: 'pace-overall-time',
                text:
                    'Общее время - '
                    '${_formatElapsedMinutes(_totalLimitMinutes)}',
                result: true,
                fontSize: 14,
                onTap: _hideKeyboard,
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 0.5),
              child: _interactiveCell(
                key: 'pace-overall',
                text:
                    'Темп в лимит - '
                    '${pace == null ? '—' : _formatPaceSeconds(pace)}',
                result: true,
                fontSize: 14,
                onTap: _hideKeyboard,
              ),
            ),
          ),
        ],
      ),
    );

    return expanded
        ? row
        : SizedBox(width: _columns * _fixedCellWidth, child: row);
  }

  Widget _plannedPaceSummaryRow({
    required double height,
    required bool expanded,
  }) {
    final focused = _focus.kind == _PaceFocusKind.summaryPlannedPace;
    final seconds = _overallPlannedPaceSeconds;
    final cell = _interactiveCell(
      key: 'pace-overall-plan',
      text:
          'Итоговый плановый темп - '
          '${seconds == null ? '—' : _formatPaceSeconds(seconds)}',
      focused: focused,
      editable: true,
      result: true,
      fontSize: 14,
      onTap: () => _focusSummaryPlannedPace(),
    );

    return expanded
        ? SizedBox(height: height, child: cell)
        : SizedBox(
            width: _columns * _fixedCellWidth,
            child: SizedBox(height: height, child: cell),
          );
  }

  Widget _plannedTimeSummaryRow({
    required double height,
    required bool expanded,
  }) {
    final focused = _focus.kind == _PaceFocusKind.summaryPlannedTime;
    final cell = _interactiveCell(
      key: 'pace-overall-plan-time',
      text:
          'Итоговое плановое время - '
          '${_formatElapsedMinutes(_overallPlannedFinishMinutes)}',
      focused: focused,
      editable: true,
      result: true,
      fontSize: 14,
      onTap: () => _focusSummaryPlannedTime(),
    );

    return expanded
        ? SizedBox(height: height, child: cell)
        : SizedBox(
            width: _columns * _fixedCellWidth,
            child: SizedBox(height: height, child: cell),
          );
  }

  List<Widget> _headerCells(bool compact) {
    return List.generate(
      _columns,
      (index) => _noteCell(index, compact: compact),
    );
  }

  /// Определяет цвет текста для строки таблицы Ultra.
  /// Цвета: светло-коричневый (#D2B48C) - от начала до Плана, белый - План и ниже.
  Color? _textColorForRow(int rowIndex) {
    // Индексы строк: 0=Start/ПП, 1=Лимит, 2=Расстояние, 3=Темп сегмента, 4=Общее время, 5=Темп в лимит, 6=План, 7=Плановый темп, 8=Итоговый плановый темп, 9=Итоговое плановое время
    // Цвета от начала до Плана (индексы 0-3): светло-коричневый
    // План и ниже (индексы 6-9): белый
    if (rowIndex <= 3) {
      return const Color(0xFFD2B48C); // Светло-коричневый (tan)
    }
    if (rowIndex >= 6) {
      return Colors.white;
    }
    return null;
  }

  Widget _noteCell(int index, {required bool compact}) {
    final label = _columnLabel(index);
    final note = _notes[index];
    final dayBorder = _dayBorderColor(index, _limitDays);
    final bold = _boldColumns.contains(index);
    final textColor = _textColorForRow(index);

    if (compact) {
      final editable = !_locked;
      final borderColor =
          dayBorder ?? (editable ? Colors.grey.shade700 : Colors.grey.shade900);

      return InkWell(
        key: ValueKey('pace-note-$index'),
        onTap: editable ? () => _editNote(index) : null,
        onLongPress: () => _toggleBoldColumn(index),
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
          decoration: BoxDecoration(
            color: Colors.black,
            border: Border.all(color: borderColor, width: bold ? 2.5 : 1),
          ),
          child: Row(
            children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: TextStyle(
                      color: textColor ?? Colors.white,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
              if (note.isNotEmpty) ...[
                SizedBox(width: 2),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      note,
                      maxLines: 1,
                      style: TextStyle(
                        color: textColor ?? Colors.white,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    final editable = !_locked;
    final borderColor =
        dayBorder ?? (editable ? Colors.grey.shade700 : Colors.grey.shade900);
    return InkWell(
      key: ValueKey('pace-note-$index'),
      onTap: editable ? () => _editNote(index) : null,
      onLongPress: () => _toggleBoldColumn(index),
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.black,
          border: Border.all(color: borderColor, width: bold ? 2.5 : 1),
        ),
        child: Column(
          children: [
            Expanded(
              flex: note.isEmpty ? 1 : 2,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    color: textColor ?? Colors.white,
                    fontSize: 30,
                    height: 1,
                  ),
                ),
              ),
            ),
            if (note.isNotEmpty)
              Expanded(
                flex: 3,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // Reduce note font size by one step and decrease text color brightness
                    final fontSize = (_noteFontSize(note, constraints.maxWidth) - 1.0).clamp(8.0, 19.0);
                    final adjustedTextColor = textColor?.withOpacity(0.9) ?? Colors.white;
                    return FittedBox(
                      fit: BoxFit.scaleDown,
                      child: SizedBox(
                        width: constraints.maxWidth,
                        child: Text(
                          note,
                          maxLines: 3,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: adjustedTextColor,
                            fontSize: fontSize,
                            height: 1.05,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Подбирает размер заметки так, чтобы самое длинное слово помещалось в
  /// клетку целиком. Короткие заметки остаются крупными, длинные — мельче.
  double _noteFontSize(String note, double width) {
    var longest = 1;
    for (final word in note.split(RegExp(r'\s+'))) {
      if (word.length > longest) longest = word.length;
    }
    final byWidth = width / (longest * 0.58);
    return byWidth.clamp(9.0, 20.0);
  }

  void _toggleBoldColumn(int index) {
    setState(() {
      if (!_boldColumns.add(index)) _boldColumns.remove(index);
    });
  }

  List<Widget> _timeCells() {
    return List.generate(_columns, (index) {
      final focused =
          _focus.kind == _PaceFocusKind.tableTime &&
          _focus.tableColumn == index;
      // Check if plan time exceeds this limit - show red flash on limit cell
      final planExceeds = _planExceedsLimit(index);
      // Row 1 (index 0 in times row) has default tan color
      final textColor = _cellTextColor(1);
      
      return _interactiveCell(
        key: 'pace-table-time-$index',
        text: _tableTimeText(index),
        placeholder: _tableTimes[index].isEmpty,
        focused: focused,
        editable: true,
        dayBorder: _dayBorderColor(index, _limitDays),
        boldBorder: _boldColumns.contains(index),
        color: planExceeds ? Colors.red : textColor,
        onTap: () => _focusTableTime(index),
      );
    });
  }

  List<Widget> _distanceCells() {
    return List.generate(_columns, (index) {
      final focused =
          _focus.kind == _PaceFocusKind.tableDistance &&
          _focus.tableColumn == index;
      // Row 2 (index 1 in distances row) has default tan color
      final textColor = _cellTextColor(2);
      
      return _interactiveCell(
        key: 'pace-table-distance-$index',
        text: _tableDistanceText(index),
        placeholder: _tableDistances[index].isEmpty,
        focused: focused,
        editable: true,
        dayBorder: _dayBorderColor(index, _limitDays),
        boldBorder: _boldColumns.contains(index),
        color: textColor,
        onTap: () => _focusTableDistance(index),
      );
    });
  }

  List<Widget> _segmentPaceCells() {
    final paces = List<int?>.generate(_columns, _segmentPace);
    return List.generate(_columns, (index) {
      final pace = paces[index];
      // Row 3 has default green color for segment pace
      final baseColor = _segmentPaceTextColor(3, index);
      
      return _interactiveCell(
        key: 'pace-table-pace-$index',
        text: index == 0
            ? 'PACE'
            : pace == null
            ? '—'
            : _formatPaceSeconds(pace),
        result: true,
        color: _paceHighlight(index, paces) ?? baseColor,
        dayBorder: _dayBorderColor(index, _limitDays),
        boldBorder: _boldColumns.contains(index),
        onTap: _hideKeyboard,
      );
    });
  }

  List<Widget> _planTimeCells() {
    return List.generate(_columns, (index) {
      final focused =
          _focus.kind == _PaceFocusKind.tablePlanTime &&
          _focus.tableColumn == index;
      // Row 6 has white color for plan time
      final textColor = _cellTextColor(6, isPlanRow: true);
      final exceedsLimit = _planExceedsLimit(index);
      
      return _interactiveCell(
        key: 'pace-plan-time-$index',
        text: _planTimeText(index),
        placeholder: _planTimes[index].isEmpty,
        focused: focused,
        editable: true,
        dayBorder: _dayBorderColor(index, _planDays),
        boldBorder: _boldColumns.contains(index),
        color: exceedsLimit ? Colors.red : textColor,
        onTap: () => _focusPlanTime(index),
      );
    });
  }

  List<Widget> _planPaceCells() {
    final paces = List<int?>.generate(_columns, _plannedPace);
    return List.generate(_columns, (index) {
      if (index == 0) {
        return _interactiveCell(
          key: 'pace-plan-pace-0',
          text: 'PACE',
          result: true,
          dayBorder: _dayBorderColor(index, _planDays),
          boldBorder: _boldColumns.contains(index),
          onTap: _hideKeyboard,
        );
      }

      final focused =
          _focus.kind == _PaceFocusKind.tablePlanPace &&
          _focus.tableColumn == index;
      // Row 7 has white color for plan pace
      final textColor = _cellTextColor(7, isPlanRow: true);
      final planned = paces[index];
      
      return _interactiveCell(
        key: 'pace-plan-pace-$index',
        text: _planPaceText(index),
        placeholder: !focused && planned == null,
        focused: focused,
        editable: true,
        color: _paceHighlight(index, paces) ?? textColor,
        dayBorder: _dayBorderColor(index, _planDays),
        boldBorder: _boldColumns.contains(index),
        onTap: () => _focusPlanPace(index),
      );
    });
  }

  Widget _wrappedTextRow({
    required List<String> values,
    required String keyPrefix,
    required String title,
    required double height,
    required bool expanded,
    required bool showFirstPlaceholder,
    Widget? total,
  }) {
    final content = LayoutBuilder(
      builder: (context, constraints) {
        final width = expanded
            ? constraints.maxWidth
            : _columns * _fixedCellWidth;
        final cellWidth = width / _columns;
        final covered = List<bool>.filled(_columns, false);
        for (var index = 0; index < _columns; index++) {
          if (values[index].isEmpty) continue;
          for (
            var next = index + 1;
            next < _columns && values[next].isEmpty;
            next++
          ) {
            covered[next] = true;
          }
        }

        return SizedBox(
          width: width,
          height: height,
          child: Stack(
            children: [
              for (var index = 0; index < _columns; index++)
                Positioned(
                  left: index * cellWidth + 0.5,
                  top: 0,
                  width: cellWidth - 1,
                  height: height,
                  child: _wrappedTextCellBackground(
                    values: values,
                    keyPrefix: keyPrefix,
                    title: title,
                    index: index,
                    showPlaceholder:
                        showFirstPlaceholder &&
                        index == 0 &&
                        values[index].isEmpty,
                    showDash:
                        index != 0 && values[index].isEmpty && !covered[index],
                  ),
                ),
              for (var index = 0; index < _columns; index++)
                if (values[index].isNotEmpty)
                  Positioned(
                    left: index * cellWidth + 0.5,
                    top: 0,
                    width: cellWidth * _overflowSpan(values, index) - 1,
                    height: height,
                    child: IgnorePointer(
                      child: _wrappedTextContent(
                        value: values[index],
                        keyPrefix: keyPrefix,
                        keySuffix: '$keyPrefix-text-$index',
                        height: height,
                      ),
                    ),
                  ),
            ],
          ),
        );
      },
    );

    return SizedBox(
      height: height,
      child: Row(
        children: [
          if (expanded)
            Expanded(child: content)
          else
            SizedBox(width: _columns * _fixedCellWidth, child: content),
          if (total != null)
            SizedBox(
              width: _totalColumnWidth,
              height: height,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 0.5),
                child: total,
              ),
            ),
        ],
      ),
    );
  }

  int _overflowSpan(List<String> values, int index) {
    var span = 1;
    for (
      var next = index + 1;
      next < values.length && values[next].isEmpty;
      next++
    ) {
      span++;
    }
    return span;
  }

  Widget _wrappedTextCellBackground({
    required List<String> values,
    required String keyPrefix,
    required String title,
    required int index,
    required bool showPlaceholder,
    required bool showDash,
  }) {
    final editable = !_locked;
    final borderColor =
        _dayBorderColor(index, _limitDays) ??
        (editable ? Colors.grey.shade700 : Colors.grey.shade900);
    final bold = _boldColumns.contains(index);

    return InkWell(
      key: ValueKey('$keyPrefix-$index'),
      onTap: editable
          ? () => _editListCell(
              title: '$title ${_columnLabel(index)}',
              values: values,
              index: index,
            )
          : null,
      child: Container(
        alignment: Alignment.topLeft,
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
        decoration: BoxDecoration(
          color: Colors.black,
          border: Border.all(color: borderColor, width: bold ? 2.5 : 1),
        ),
        child: showPlaceholder
            ? Center(
                child: Text(
                  title,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                ),
              )
            : showDash
            ? Center(
                child: Text(
                  '—',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                ),
              )
            : const SizedBox.shrink(),
      ),
    );
  }

  Widget _wrappedTextContent({
    required String value,
    required String keyPrefix,
    required String keySuffix,
    required double height,
  }) {
    final maxLines = math.max(1, (height / 13).floor());
    return Container(
      key: ValueKey(keySuffix),
      alignment: Alignment.topLeft,
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
      child: Text.rich(
        TextSpan(
          children: keyPrefix == 'pace-water'
              ? _waterSpans(value)
              : [TextSpan(text: value)],
        ),
        maxLines: maxLines,
        overflow: TextOverflow.clip,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11.5,
          height: 1.15,
        ),
      ),
    );
  }

  List<InlineSpan> _waterSpans(String value) {
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

  Widget _interactiveCell({
    required String key,
    required String text,
    bool focused = false,
    bool editable = false,
    bool placeholder = false,
    bool result = false,
    bool bold = false,
    int maxLines = 1,
    double fontSize = 30,
    Color? color,
    Color? dayBorder,
    bool boldBorder = false,
    VoidCallback? onTap,
    VoidCallback? onLongPress,
  }) {
    if (editable && (_locked || _lockedLimits)) {
      editable = false;
      onTap = null;
    }

    final defaultBorder = editable
        ? Colors.grey.shade700
        : Colors.grey.shade900;
    final borderColor = focused
        ? const Color(0xFF4CAF50)
        : dayBorder ?? (boldBorder ? const Color(0xFFFF9800) : defaultBorder);
    final borderWidth = focused ? 1.5 : (boldBorder ? 3.0 : 1.0);

    final cell = InkWell(
      key: ValueKey(key),
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 1),
        decoration: BoxDecoration(
          color: result ? const Color(0xFF1B1B1B) : Colors.black,
          border: Border.all(color: borderColor, width: borderWidth),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                text,
                maxLines: maxLines,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: placeholder
                      ? Colors.grey.shade600
                      : color ??
                            (result ? const Color(0xFFFFB74D) : Colors.white),
                  fontSize: fontSize,
                  fontWeight: bold ? FontWeight.bold : null,
                ),
              ),
              if (focused) _cursor(),
            ],
          ),
        ),
      ),
    );

    return focused ? KeyedSubtree(key: _focusAnchorKey, child: cell) : cell;
  }

  Widget _buildKeyboard({required bool compact, bool tableLayout = false}) {
    final extraKey = _isUltra ? 'ОК' : '00';
    if (tableLayout) {
      return Container(
        height: compact ? null : 180,
        padding: EdgeInsets.fromLTRB(4, 4, 4, compact ? 4 : 6),
        color: const Color(0xFF111111),
        child: Column(
          children: [
            _keyRow(['.', 'Сброс', '⌫'], compact),
            _keyRow(['1', '2', '3'], compact),
            _keyRow(['4', '5', '6'], compact),
            _keyRow(['7', '8', '9'], compact),
            Expanded(
              child: Row(
                children: [
                  Expanded(flex: 2, child: _padKey('0', compact)),
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
      color: const Color(0xFF111111),
      child: Column(
        children: [
          _keyRow(['1', '2', '3', '⌫'], compact),
          _keyRow(['4', '5', '6', '.'], compact),
          _keyRow(['7', '8', '9', 'Сброс'], compact),
          Expanded(
            child: Row(
              children: [
                Expanded(flex: 2, child: _padKey('0', compact)),
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
      child: Material(
        color: Colors.black,
        child: InkWell(
          key: ValueKey('pace-key-$key'),
          onTap: () => _onPadKey(key),
          onLongPress: key == '⌫' ? _clearActive : null,
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
    );
  }

  void _onPadKey(String key) {
    if (key == 'ОК') {
      unawaited(_commitInput());
      return;
    }
    if (key == '⌫') {
      _backspaceActive();
      return;
    }
    if (key == 'Сброс') {
      _clearActive();
      return;
    }

    for (final char in key.split('')) {
      _appendActive(char);
    }
  }
}

enum _TimeTab { difference, addSubtract, converter }

enum _TimeField { date, days, hours, minutes, seconds }

class _TimeFocus {
  const _TimeFocus(this.group, this.field);

  final int group;
  final _TimeField field;
}

class _TimeView extends StatefulWidget {
  const _TimeView();

  @override
  State<_TimeView> createState() => _TimeViewState();
}

class _TimeViewState extends State<_TimeView> {
  _TimeTab _tab = _TimeTab.difference;
  bool _subtract = false;
  _TimeFocus _focus = const _TimeFocus(0, _TimeField.date);

  final List<Map<_TimeField, String>> _values = List.generate(
    3,
    (_) => {for (final field in _TimeField.values) field: ''},
  );

  String _raw(int group, _TimeField field) => _values[group][field] ?? '';

  String _dateText(String buffer) {
    if (buffer.isEmpty) return 'дд.мм.гггг';

    final text = StringBuffer();
    for (var index = 0; index < buffer.length; index++) {
      if (index == 2 || index == 4) text.write('.');
      text.write(buffer[index]);
    }
    return text.toString();
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}.'
        '${date.month.toString().padLeft(2, '0')}.'
        '${date.year.toString().padLeft(4, '0')}';
  }

  DateTime? _parseDate(String buffer) {
    if (buffer.length != 8) return null;

    final day = int.tryParse(buffer.substring(0, 2));
    final month = int.tryParse(buffer.substring(2, 4));
    final year = int.tryParse(buffer.substring(4, 8));
    if (day == null || month == null || year == null) return null;
    if (day < 1 || day > 31 || month < 1 || month > 12) return null;

    final date = DateTime.utc(year, month, day);
    if (date.year != year || date.month != month || date.day != day) {
      return null;
    }
    return date;
  }

  int? _parseClock(int group) {
    final hoursText = _raw(group, _TimeField.hours);
    final minutesText = _raw(group, _TimeField.minutes);
    if (hoursText.isEmpty && minutesText.isEmpty) return 0;

    final hours = int.tryParse(hoursText) ?? 0;
    final minutes = int.tryParse(minutesText) ?? 0;
    // Часы и минуты не ограничены: можно вводить 500 часов или 1000 минут.
    return hours * 3600 + minutes * 60;
  }

  DateTime? _dateTimeFor(int group) {
    final date = _parseDate(_raw(group, _TimeField.date));
    if (date == null) return null;

    final clock = _parseClock(group);
    if (clock == null) return null;

    return DateTime.utc(
      date.year,
      date.month,
      date.day,
    ).add(Duration(seconds: clock));
  }

  int? _durationSeconds(int group) {
    final parts = [
      _raw(group, _TimeField.days),
      _raw(group, _TimeField.hours),
      _raw(group, _TimeField.minutes),
      _raw(group, _TimeField.seconds),
    ];
    if (parts.every((value) => value.trim().isEmpty)) return null;
    return _parseDurationParts(parts);
  }

  int? get _differenceSeconds {
    if (_tab != _TimeTab.difference) return null;

    final start = _dateTimeFor(0);
    final end = _dateTimeFor(1);
    if (start == null || end == null) return null;
    return end.difference(start).inSeconds;
  }

  DateTime? get _resultDateTime {
    if (_tab != _TimeTab.addSubtract) return null;

    final base = _dateTimeFor(0);
    final duration = _durationSeconds(1);
    if (base == null || duration == null) return null;

    final delta = Duration(seconds: duration);
    return _subtract ? base.subtract(delta) : base.add(delta);
  }

  int? get _converterSeconds => _durationSeconds(0);

  bool get _resultNegative =>
      _tab == _TimeTab.difference && (_differenceSeconds ?? 0) < 0;

  bool _isFieldEditable(int group, _TimeField field) {
    return switch (_tab) {
      _TimeTab.difference =>
        (group == 0 || group == 1) &&
            (field == _TimeField.date ||
                field == _TimeField.hours ||
                field == _TimeField.minutes),
      _TimeTab.addSubtract =>
        group == 0
            ? (field == _TimeField.date ||
                  field == _TimeField.hours ||
                  field == _TimeField.minutes)
            : group == 1 &&
                  (field == _TimeField.days ||
                      field == _TimeField.hours ||
                      field == _TimeField.minutes ||
                      field == _TimeField.seconds),
      _TimeTab.converter =>
        group == 0 &&
            (field == _TimeField.days ||
                field == _TimeField.hours ||
                field == _TimeField.minutes ||
                field == _TimeField.seconds),
    };
  }

  bool _isFocused(int group, _TimeField field) {
    return _focus.group == group && _focus.field == field;
  }

  void _focusField(int group, _TimeField field) {
    if (!_isFieldEditable(group, field)) return;
    setState(() {
      _focus = _TimeFocus(group, field);
    });
  }

  void _selectTab(_TimeTab tab) {
    setState(() {
      _tab = tab;
      _focus = switch (tab) {
        _TimeTab.difference => const _TimeFocus(0, _TimeField.date),
        _TimeTab.addSubtract => const _TimeFocus(0, _TimeField.date),
        _TimeTab.converter => const _TimeFocus(0, _TimeField.days),
      };
    });
  }

  String _valueFor(int group, _TimeField field) {
    if (group == 2) {
      if (_tab == _TimeTab.difference) {
        final seconds = _differenceSeconds?.abs();
        if (seconds == null) {
          return field == _TimeField.days ? '—' : '';
        }

        final split = _splitSeconds(seconds);
        return switch (field) {
          _TimeField.days => '${split.days}',
          _TimeField.hours => '${split.hours}'.padLeft(2, '0'),
          _TimeField.minutes => '${split.minutes}'.padLeft(2, '0'),
          _TimeField.seconds => '${split.seconds}'.padLeft(2, '0'),
          _TimeField.date => '',
        };
      }

      if (_tab == _TimeTab.addSubtract) {
        final result = _resultDateTime;
        if (result == null) {
          return field == _TimeField.date ? '—' : '';
        }

        return switch (field) {
          _TimeField.date => _formatDate(result),
          _TimeField.hours => result.hour.toString().padLeft(2, '0'),
          _TimeField.minutes => result.minute.toString().padLeft(2, '0'),
          _TimeField.seconds => result.second.toString().padLeft(2, '0'),
          _TimeField.days => '',
        };
      }
    }

    final raw = _raw(group, field);
    if (field == _TimeField.date) return _dateText(raw);
    return raw;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildTabs(),
                const SizedBox(height: 10),
                ..._buildTabContent(),
              ],
            ),
          ),
        ),
        _buildKeyboard(),
      ],
    );
  }

  Widget _buildTabs() {
    return Row(
      children: [
        _tabButton('Разница', _TimeTab.difference, 'time-tab-difference'),
        const SizedBox(width: 4),
        _tabButton('Сложить/вычесть', _TimeTab.addSubtract, 'time-tab-add'),
        const SizedBox(width: 4),
        _tabButton('Конвертер', _TimeTab.converter, 'time-tab-converter'),
      ],
    );
  }

  Widget _tabButton(String label, _TimeTab value, String key) {
    final selected = _tab == value;

    return Expanded(
      child: InkWell(
        key: ValueKey(key),
        onTap: () => _selectTab(value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 3),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFFF9800) : Colors.black,
            border: Border.all(
              color: selected ? const Color(0xFFFF9800) : Colors.grey.shade700,
            ),
            borderRadius: BorderRadius.circular(7),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              style: TextStyle(
                color: selected ? Colors.black : Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildTabContent() {
    return switch (_tab) {
      _TimeTab.difference => [
        _dateTimeGroup(0, 'Начало'),
        const SizedBox(height: 10),
        _dateTimeGroup(1, 'Конец'),
        const SizedBox(height: 10),
        _resultDurationRow('Разница'),
      ],
      _TimeTab.addSubtract => [
        _dateTimeGroup(0, 'Дата и время'),
        const SizedBox(height: 10),
        _buildOperationToggle(),
        const SizedBox(height: 10),
        _durationRow(1, 'Длительность'),
        const SizedBox(height: 10),
        _resultDateTimeRow('Результат'),
      ],
      _TimeTab.converter => [
        _durationRow(0, 'Время'),
        const SizedBox(height: 12),
        _buildConverterOutput(),
      ],
    };
  }

  Widget _buildOperationToggle() {
    return Row(
      children: [
        _operationButton('+', false, 'time-op-add'),
        const SizedBox(width: 4),
        _operationButton('−', true, 'time-op-sub'),
      ],
    );
  }

  Widget _operationButton(String label, bool subtract, String key) {
    final selected = _subtract == subtract;

    return Expanded(
      child: InkWell(
        key: ValueKey(key),
        onTap: () {
          setState(() {
            _subtract = subtract;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 7),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFFF9800) : Colors.black,
            border: Border.all(
              color: selected ? const Color(0xFFFF9800) : Colors.grey.shade700,
            ),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.black : Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _dateTimeGroup(int group, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            SizedBox(
              width: 76,
              child: Text(
                label,
                style: const TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ),
            Expanded(child: _timeField(group, _TimeField.date)),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            const SizedBox(
              width: 76,
              child: Text(
                'Время',
                style: TextStyle(color: Colors.grey, fontSize: 11),
              ),
            ),
            Expanded(child: _timeField(group, _TimeField.hours)),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                ':',
                style: TextStyle(color: Colors.grey, fontSize: 18),
              ),
            ),
            Expanded(child: _timeField(group, _TimeField.minutes)),
          ],
        ),
      ],
    );
  }

  Widget _durationRow(int group, String label) {
    const parts = [
      _TimeField.days,
      _TimeField.hours,
      _TimeField.minutes,
      _TimeField.seconds,
    ];
    const partLabels = ['дни', 'часы', 'мин', 'сек'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const SizedBox(width: 76),
            for (final partLabel in partLabels)
              Expanded(
                child: Text(
                  partLabel,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey, fontSize: 10),
                ),
              ),
          ],
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            SizedBox(
              width: 76,
              child: Text(
                label,
                style: const TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ),
            for (final part in parts)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1),
                  child: _timeField(group, part),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _resultDurationRow(String label) {
    const parts = [
      _TimeField.days,
      _TimeField.hours,
      _TimeField.minutes,
      _TimeField.seconds,
    ];
    const partLabels = ['дни', 'часы', 'мин', 'сек'];
    final negative = _resultNegative;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const SizedBox(width: 76),
            for (final partLabel in partLabels)
              Expanded(
                child: Text(
                  partLabel,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey, fontSize: 10),
                ),
              ),
          ],
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            SizedBox(
              width: 76,
              child: Text(
                negative ? '− $label' : label,
                style: const TextStyle(color: Color(0xFFFFB74D), fontSize: 13),
              ),
            ),
            for (final part in parts)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1),
                  child: _timeField(2, part, result: true),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _resultDateTimeRow(String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            SizedBox(
              width: 76,
              child: Text(
                label,
                style: const TextStyle(color: Color(0xFFFFB74D), fontSize: 13),
              ),
            ),
            Expanded(child: _timeField(2, _TimeField.date, result: true)),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            const SizedBox(
              width: 76,
              child: Text(
                'Время',
                style: TextStyle(color: Colors.grey, fontSize: 11),
              ),
            ),
            Expanded(child: _timeField(2, _TimeField.hours, result: true)),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                ':',
                style: TextStyle(color: Colors.grey, fontSize: 18),
              ),
            ),
            Expanded(child: _timeField(2, _TimeField.minutes, result: true)),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                ':',
                style: TextStyle(color: Colors.grey, fontSize: 18),
              ),
            ),
            Expanded(child: _timeField(2, _TimeField.seconds, result: true)),
          ],
        ),
      ],
    );
  }

  Widget _timeField(int group, _TimeField field, {bool result = false}) {
    final editable = !result && _isFieldEditable(group, field);
    final focused = _isFocused(group, field);
    final text = _valueFor(group, field);
    final placeholder =
        !result && _raw(group, field).isEmpty && field != _TimeField.date;

    return InkWell(
      key: ValueKey('time-$group-${field.name}'),
      onTap: editable ? () => _focusField(group, field) : null,
      child: Container(
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: editable ? Colors.black : const Color(0xFF1B1B1B),
          border: Border.all(
            color: focused
                ? const Color(0xFF4CAF50)
                : editable
                ? Colors.grey.shade700
                : const Color(0x66FF9800),
            width: focused ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            text,
            maxLines: 1,
            style: TextStyle(
              color: editable
                  ? (placeholder ? Colors.grey : Colors.white)
                  : const Color(0xFFFFB74D),
              fontSize: 15,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildConverterOutput() {
    final seconds = _converterSeconds;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade800),
        borderRadius: BorderRadius.circular(8),
      ),
      child: seconds == null
          ? const Text(
              'Введите время',
              style: TextStyle(color: Colors.grey, fontSize: 14),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _converterLine('Всего дней', seconds / 86400, ''),
                _converterLine('Всего часов', seconds / 3600, ''),
                _converterLine('Всего минут', seconds / 60, ''),
                _converterLine('Всего секунд', seconds.toDouble(), ''),
              ],
            ),
    );
  }

  Widget _converterLine(String label, double value, String suffix) {
    final text = value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(2);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ),
          Text(
            '$text$suffix',
            style: const TextStyle(color: Colors.white, fontSize: 15),
          ),
        ],
      ),
    );
  }

  Widget _buildKeyboard() {
    return Container(
      height: 184,
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
      color: const Color(0xFF111111),
      child: Column(
        children: [
          _keyRow(['1', '2', '3']),
          _keyRow(['4', '5', '6']),
          _keyRow(['7', '8', '9']),
          _keyRow(['⌫', '0', '00']),
        ],
      ),
    );
  }

  Widget _keyRow(List<String> keys) {
    return Expanded(
      child: Row(
        children: [for (final key in keys) Expanded(child: _padKey(key))],
      ),
    );
  }

  Widget _padKey(String key) {
    return Padding(
      padding: const EdgeInsets.all(1.5),
      child: Material(
        color: Colors.black,
        child: InkWell(
          key: ValueKey('time-key-$key'),
          onTap: () => _onPadKey(key),
          onLongPress: key == '⌫' ? _clearActive : null,
          child: Center(
            child: Text(
              key,
              style: const TextStyle(color: Colors.white, fontSize: 20),
            ),
          ),
        ),
      ),
    );
  }

  void _onPadKey(String key) {
    if (key == '⌫') {
      _backspaceActive();
      return;
    }

    for (final char in key.split('')) {
      _appendActive(char);
    }
  }

  void _appendActive(String char) {
    if (!_isFieldEditable(_focus.group, _focus.field)) return;

    setState(() {
      final field = _focus.field;
      final group = _focus.group;
      final current = _raw(group, field);

      if (field == _TimeField.date) {
        if (!_isDigitChar(char) || current.length >= 8) return;
        _values[group][field] = '$current$char';
        return;
      }

      // Длина полей не ограничена: допускаются значения вроде 1000 минут
      // или 500 часов.
      if (!_isDigitChar(char)) return;

      _values[group][field] = '$current$char';
    });
  }

  void _backspaceActive() {
    if (!_isFieldEditable(_focus.group, _focus.field)) return;

    setState(() {
      final current = _raw(_focus.group, _focus.field);
      if (current.isEmpty) return;
      _values[_focus.group][_focus.field] = current.substring(
        0,
        current.length - 1,
      );
    });
  }

  void _clearActive() {
    if (!_isFieldEditable(_focus.group, _focus.field)) return;

    setState(() {
      _values[_focus.group][_focus.field] = '';
    });
  }

  bool _isDigitChar(String char) {
    final code = char.codeUnitAt(0);
    return code >= 0x30 && code <= 0x39;
  }
}

final RegExp _exactValuePattern = RegExp(r'@(-?\d+):(\d+);');
final RegExp _numberPattern = RegExp(r'\d+(?:\.\d*)?|\.\d+');
final RegExp _digitGroupPattern = RegExp(r'\B(?=(\d{3})+(?!\d))');

/// Текстовая версия выражения: дроби записываются как a/b, числа группируются.
String _displayText(String value) {
  var text = value.replaceAllMapped(_exactValuePattern, (match) {
    final numerator = BigInt.parse(match.group(1)!);
    final denominator = BigInt.parse(match.group(2)!);
    final rational = Rational(numerator, denominator);

    if (rational.isDisplayableFraction) {
      return rational.toFractionString();
    }

    return rational.toDisplayString();
  });

  text = text.replaceAll('sqrt(', '√(');
  text = text.replaceAll('inv(', '1/(');
  text = text.replaceAll('*', '×');
  text = text.replaceAll('-', '−');

  return _groupDigits(text);
}

String _groupDigits(String text) {
  return text.replaceAllMapped(_numberPattern, (match) {
    final number = match.group(0)!;
    final dotIndex = number.indexOf('.');
    final integerPart = dotIndex == -1 ? number : number.substring(0, dotIndex);
    final decimalPart = dotIndex == -1 ? '' : number.substring(dotIndex);

    final groupedInteger = integerPart.replaceAllMapped(
      _digitGroupPattern,
      (_) => '\u2009',
    );

    return '$groupedInteger$decimalPart';
  });
}

String _formatDecimal(String text) {
  final formatted = text.replaceAll('-', '−');
  if (formatted.contains('e')) return formatted;
  return _groupDigits(formatted);
}

String _decimalSymbol(Rational value, bool approximate) {
  if (!value.decimalDisplayIsExact) return '≈';
  if (approximate && !value.isInteger) return '≈';
  return '=';
}

String _historyText(String expression, Rational value, bool approximate) {
  final left = _displayText(expression);
  final decimal = _formatDecimal(value.toDisplayString());
  final symbol = _decimalSymbol(value, approximate);
  final showsFraction = !approximate && value.isDisplayableFraction;

  if (showsFraction) {
    final fraction = value.toFractionString();
    if (left == fraction) {
      return '$left $symbol $decimal';
    }
    if (left == decimal) {
      return '$left = $fraction';
    }
    return '$left = $fraction $symbol $decimal';
  }

  if (value.isInteger && symbol == '=') {
    return '$left = $decimal';
  }

  return '$left $symbol $decimal';
}

/// Рисует выражение как набор inline-виджетов с настоящими вертикальными дробями.
class _ExpressionView extends StatelessWidget {
  const _ExpressionView({
    required this.expression,
    this.fontSize = 32,
    this.fontWeight = FontWeight.w300,
  });

  final String expression;
  final double fontSize;
  final FontWeight fontWeight;

  @override
  Widget build(BuildContext context) {
    try {
      final nodes = _DisplayParser(expression).parse();

      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: nodes
            .map(
              (node) => _renderNode(node, fontSize, Colors.white, fontWeight),
            )
            .toList(),
      );
    } catch (_) {
      return Text(
        _displayText(expression),
        style: _textStyle(fontSize, Colors.white, fontWeight),
      );
    }
  }
}

abstract class _DisplayNode {
  const _DisplayNode();

  bool get isEmpty => false;
}

class _EmptyNode extends _DisplayNode {
  const _EmptyNode();

  @override
  bool get isEmpty => true;
}

class _TextNode extends _DisplayNode {
  const _TextNode(this.text, {this.isOperator = false});

  final String text;
  final bool isOperator;
}

class _NumberNode extends _DisplayNode {
  const _NumberNode(this.text);

  final String text;
}

class _SequenceNode extends _DisplayNode {
  const _SequenceNode(this.children);

  final List<_DisplayNode> children;
}

class _FractionNode extends _DisplayNode {
  const _FractionNode(this.numerator, this.denominator);

  final _DisplayNode numerator;
  final _DisplayNode denominator;
}

class _GroupNode extends _DisplayNode {
  const _GroupNode(this.children, {required this.closed});

  final List<_DisplayNode> children;
  final bool closed;
}

class _SqrtNode extends _DisplayNode {
  const _SqrtNode(this.children, {required this.closed});

  final List<_DisplayNode> children;
  final bool closed;
}

class _FunctionNode extends _DisplayNode {
  const _FunctionNode(this.name, this.children, {required this.closed});

  final String name;
  final List<_DisplayNode> children;
  final bool closed;
}

class _PowerNode extends _DisplayNode {
  const _PowerNode(this.base, this.exponent);

  final _DisplayNode base;
  final _DisplayNode exponent;
}

/// Толерантный парсер для отображения: понимает недописанные выражения.
class _DisplayParser {
  _DisplayParser(this.input);

  final String input;
  int _position = 0;

  static const List<String> _functionNames = [
    'sin',
    'cos',
    'tan',
    'ln',
    'log',
    'inv',
  ];

  List<_DisplayNode> parse() {
    final nodes = _parseExpression();

    if (_position < input.length) {
      nodes.add(_TextNode(_symbols(input.substring(_position))));
      _position = input.length;
    }

    return nodes;
  }

  List<_DisplayNode> _parseExpression() {
    final nodes = <_DisplayNode>[];
    final first = _parseTerm();

    if (!first.isEmpty) nodes.add(first);

    while (_position < input.length) {
      if (_peek(')')) break;

      if (_peek('+') || _peek('-')) {
        final operator = input[_position++];
        final right = _parseTerm();
        nodes.add(_TextNode(operator == '-' ? '−' : '+', isOperator: true));
        if (!right.isEmpty) nodes.add(right);
      } else {
        break;
      }
    }

    return nodes;
  }

  _DisplayNode _parseTerm() {
    var left = _parsePower();

    while (_position < input.length) {
      if (_peek('*')) {
        _position++;
        final right = _parsePower();
        if (right.isEmpty) {
          return _SequenceNode([left, const _TextNode('×', isOperator: true)]);
        }
        left = _SequenceNode([
          left,
          const _TextNode('×', isOperator: true),
          right,
        ]);
      } else if (_peek('/')) {
        _position++;
        final right = _parsePower();
        if (right.isEmpty) {
          return _SequenceNode([left, const _TextNode('÷', isOperator: true)]);
        }
        left = _FractionNode(left, right);
      } else {
        break;
      }
    }

    return left;
  }

  _DisplayNode _parsePower() {
    if (_peek('-') || _peek('+')) {
      final operator = input[_position++];
      final operand = _parsePower();

      return _SequenceNode([
        _TextNode(operator == '-' ? '−' : '+', isOperator: true),
        operand,
      ]);
    }

    var base = _parsePostfix();

    if (_peek('^')) {
      _position++;
      final exponent = _parsePower();

      if (exponent.isEmpty) {
        base = _SequenceNode([base, const _TextNode('^', isOperator: true)]);
      } else {
        base = _PowerNode(base, exponent);
      }
    }

    return base;
  }

  _DisplayNode _parsePostfix() {
    var value = _parsePrimary();

    while (_peek('%') || _peek('!')) {
      final symbol = input[_position++];
      value = _SequenceNode([value, _TextNode(symbol, isOperator: true)]);
    }

    return value;
  }

  _DisplayNode _parsePrimary() {
    if (_position >= input.length) return const _EmptyNode();

    if (input.startsWith('sqrt(', _position)) {
      _position += 'sqrt('.length;
      final children = _parseExpression();
      final closed = _peek(')');
      if (closed) _position++;

      return _SqrtNode(children, closed: closed);
    }

    for (final name in _functionNames) {
      final prefix = '$name(';

      if (input.startsWith(prefix, _position)) {
        _position += prefix.length;
        final children = _parseExpression();
        final closed = _peek(')');
        if (closed) _position++;

        return _FunctionNode(name, children, closed: closed);
      }
    }

    if (_peek('π')) {
      _position++;
      return const _TextNode('π');
    }

    if (input.startsWith('pi', _position)) {
      _position += 2;
      return const _TextNode('π');
    }

    if (_peek('e')) {
      _position++;
      return const _TextNode('e');
    }

    if (_peek('@')) {
      return _parseExact();
    }

    if (_peek('(')) {
      _position++;
      final children = _parseExpression();
      final closed = _peek(')');
      if (closed) _position++;

      return _GroupNode(children, closed: closed);
    }

    if (_peek(')')) return const _EmptyNode();

    if (_isDigit(input[_position]) || _peek('.')) {
      return _parseNumber();
    }

    final char = input[_position++];
    return _TextNode(_symbols(char), isOperator: true);
  }

  _DisplayNode _parseExact() {
    final start = _position;
    _position++;

    final colon = input.indexOf(':', _position);
    final semicolon = colon == -1 ? -1 : input.indexOf(';', colon + 1);

    if (colon == -1 || semicolon == -1) {
      _position = start + 1;
      return const _TextNode('@');
    }

    final numeratorText = input.substring(_position, colon);
    final denominatorText = input.substring(colon + 1, semicolon);
    _position = semicolon + 1;

    try {
      final value = Rational(
        BigInt.parse(numeratorText),
        BigInt.parse(denominatorText),
      );

      if (value.isDisplayableFraction) {
        return _FractionNode(
          _NumberNode(value.numerator.toString()),
          _NumberNode(value.denominator.toString()),
        );
      }

      if (value.isInteger) {
        return _NumberNode(value.numerator.toString());
      }

      return _TextNode(value.toDisplayString());
    } on FormatException {
      return const _TextNode('@');
    }
  }

  _DisplayNode _parseNumber() {
    final start = _position;
    var hasDot = false;

    while (_position < input.length) {
      final char = input[_position];

      if (_isDigit(char)) {
        _position++;
      } else if (char == '.' && !hasDot) {
        hasDot = true;
        _position++;
      } else {
        break;
      }
    }

    if (start == _position) {
      _position++;
      return const _EmptyNode();
    }

    return _NumberNode(input.substring(start, _position));
  }

  bool _peek(String char) {
    return _position < input.length && input[_position] == char;
  }

  static bool _isDigit(String char) {
    final code = char.codeUnitAt(0);
    return code >= 0x30 && code <= 0x39;
  }

  static String _symbols(String text) {
    return text
        .replaceAll('sqrt(', '√(')
        .replaceAll('*', '×')
        .replaceAll('/', '÷')
        .replaceAll('-', '−');
  }
}

Widget _renderNode(
  _DisplayNode node,
  double fontSize,
  Color color, [
  FontWeight fontWeight = FontWeight.w300,
]) {
  if (node is _EmptyNode) return const SizedBox.shrink();

  if (node is _TextNode) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: node.isOperator ? 3 : 0),
      child: Text(node.text, style: _textStyle(fontSize, color, fontWeight)),
    );
  }

  if (node is _NumberNode) {
    return Text(
      _groupDigits(node.text),
      style: _textStyle(fontSize, color, fontWeight),
    );
  }

  if (node is _SequenceNode) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: node.children
          .map((child) => _renderNode(child, fontSize, color, fontWeight))
          .toList(),
    );
  }

  if (node is _FractionNode) {
    final childSize = fontSize * 0.78;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: IntrinsicWidth(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.center,
              child: _renderNode(node.numerator, childSize, color, fontWeight),
            ),
            Container(
              height: 1.5,
              margin: const EdgeInsets.symmetric(vertical: 1),
              color: color,
            ),
            Align(
              alignment: Alignment.center,
              child: _renderNode(
                node.denominator,
                childSize,
                color,
                fontWeight,
              ),
            ),
          ],
        ),
      ),
    );
  }

  if (node is _GroupNode) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text('(', style: _textStyle(fontSize, color, fontWeight)),
        ...node.children.map(
          (child) => _renderNode(child, fontSize, color, fontWeight),
        ),
        if (node.closed)
          Text(')', style: _textStyle(fontSize, color, fontWeight)),
      ],
    );
  }

  if (node is _SqrtNode) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text('√', style: _textStyle(fontSize, color, fontWeight)),
        Text('(', style: _textStyle(fontSize, color, fontWeight)),
        ...node.children.map(
          (child) => _renderNode(child, fontSize, color, fontWeight),
        ),
        if (node.closed)
          Text(')', style: _textStyle(fontSize, color, fontWeight)),
      ],
    );
  }

  if (node is _FunctionNode) {
    final name = node.name == 'inv' ? '1/' : node.name;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(name, style: _textStyle(fontSize, color, fontWeight)),
        Text('(', style: _textStyle(fontSize, color, fontWeight)),
        ...node.children.map(
          (child) => _renderNode(child, fontSize, color, fontWeight),
        ),
        if (node.closed)
          Text(')', style: _textStyle(fontSize, color, fontWeight)),
      ],
    );
  }

  if (node is _PowerNode) {
    final baseNeedsParentheses = node.base is _FractionNode;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (baseNeedsParentheses)
          Text('(', style: _textStyle(fontSize, color, fontWeight)),
        _renderNode(node.base, fontSize, color, fontWeight),
        if (baseNeedsParentheses)
          Text(')', style: _textStyle(fontSize, color, fontWeight)),
        Transform.translate(
          offset: Offset(0, -fontSize * 0.3),
          child: _renderNode(node.exponent, fontSize * 0.7, color, fontWeight),
        ),
      ],
    );
  }

  return const SizedBox.shrink();
}

TextStyle _textStyle(
  double fontSize,
  Color color, [
  FontWeight fontWeight = FontWeight.w300,
]) {
  return TextStyle(
    color: color,
    fontSize: fontSize,
    fontWeight: fontWeight,
    fontFeatures: const [FontFeature.tabularFigures()],
  );
}

/// Рациональное число: сокращённый числитель и положительный знаменатель.
class Rational {
  factory Rational(BigInt numerator, BigInt denominator) {
    if (denominator == BigInt.zero) {
      throw const FormatException('Деление на ноль');
    }

    var n = numerator;
    var d = denominator;

    if (d.isNegative) {
      n = -n;
      d = -d;
    }

    final divisor = _gcd(n.abs(), d);
    return Rational._(n ~/ divisor, d ~/ divisor);
  }

  Rational._(this.numerator, this.denominator);

  final BigInt numerator;
  final BigInt denominator;

  static final Rational zero = Rational._(BigInt.zero, BigInt.one);
  static final Rational one = Rational._(BigInt.one, BigInt.one);

  static BigInt _gcd(BigInt a, BigInt b) {
    var x = a;
    var y = b;

    while (y != BigInt.zero) {
      final remainder = x % y;
      x = y;
      y = remainder;
    }

    return x == BigInt.zero ? BigInt.one : x;
  }

  static BigInt _pow10(int exponent) {
    return BigInt.from(10).pow(exponent);
  }

  bool get isInteger => denominator == BigInt.one;

  /// Дробь стоит показывать, только если она не слишком громоздкая.
  bool get isDisplayableFraction {
    if (isInteger) return false;

    final digits =
        numerator.abs().toString().length + denominator.toString().length;
    return digits <= 24;
  }

  bool get hasTerminatingDecimal {
    var d = denominator;

    while (d % BigInt.two == BigInt.zero) {
      d = d ~/ BigInt.two;
    }
    while (d % BigInt.from(5) == BigInt.zero) {
      d = d ~/ BigInt.from(5);
    }

    return d == BigInt.one;
  }

  /// Совпадает ли отображаемая десятичная запись с точным значением.
  bool get decimalDisplayIsExact {
    final text = toDisplayString();

    if (text.contains('e')) return false;
    if (isInteger) return true;

    try {
      return Rational.fromDecimal(text) == this;
    } on FormatException {
      return false;
    }
  }

  static Rational fromDecimal(String text) {
    final negative = text.startsWith('-');
    final unsigned = negative ? text.substring(1) : text;
    final dotIndex = unsigned.indexOf('.');

    if (dotIndex == -1) {
      final value = BigInt.parse(unsigned);
      return Rational(negative ? -value : value, BigInt.one);
    }

    final whole = unsigned.substring(0, dotIndex);
    final fraction = unsigned.substring(dotIndex + 1);
    final digits = '${whole.isEmpty ? '0' : whole}$fraction';
    final denominator = _pow10(fraction.length);
    final numerator = BigInt.parse(digits.isEmpty ? '0' : digits);

    return Rational(negative ? -numerator : numerator, denominator);
  }

  Rational operator +(Rational other) {
    return Rational(
      numerator * other.denominator + other.numerator * denominator,
      denominator * other.denominator,
    );
  }

  Rational operator -(Rational other) {
    return Rational(
      numerator * other.denominator - other.numerator * denominator,
      denominator * other.denominator,
    );
  }

  Rational operator *(Rational other) {
    return Rational(
      numerator * other.numerator,
      denominator * other.denominator,
    );
  }

  Rational operator /(Rational other) {
    if (other.numerator == BigInt.zero) {
      throw const FormatException('Деление на ноль');
    }

    return Rational(
      numerator * other.denominator,
      denominator * other.numerator,
    );
  }

  Rational operator -() => Rational(-numerator, denominator);

  Rational percent() => Rational(numerator, denominator * BigInt.from(100));

  Rational powInteger(BigInt exponent) {
    if (exponent == BigInt.zero) {
      return one;
    }

    if (exponent.abs() > BigInt.from(10000)) {
      throw const FormatException('Слишком большая степень');
    }

    final power = exponent.abs().toInt();
    final estimatedNumeratorDigits = _estimatedPowerDigits(
      numerator.abs(),
      power,
    );
    final estimatedDenominatorDigits = _estimatedPowerDigits(
      denominator,
      power,
    );

    if (estimatedNumeratorDigits > 50000 ||
        estimatedDenominatorDigits > 50000) {
      throw const FormatException('Слишком большое число');
    }

    final poweredNumerator = numerator.abs().pow(power);
    final signedNumerator = numerator.isNegative && power.isOdd
        ? -poweredNumerator
        : poweredNumerator;
    final poweredDenominator = denominator.pow(power);

    if (exponent.isNegative) {
      if (signedNumerator == BigInt.zero) {
        throw const FormatException('Деление на ноль');
      }
      return Rational(poweredDenominator, signedNumerator);
    }

    return Rational(signedNumerator, poweredDenominator);
  }

  static int _estimatedPowerDigits(BigInt value, int exponent) {
    if (value == BigInt.zero || value == BigInt.one) return 1;

    final double log10Value;
    if (value.bitLength <= 53) {
      log10Value = math.log(value.toDouble()) / math.ln10;
    } else {
      log10Value = (value.toString().length - 1).toDouble();
    }

    return (log10Value * exponent).ceil() + 1;
  }

  /// Точный квадратный корень, если он рационален.
  Rational? trySqrtExact() {
    if (numerator.isNegative) return null;

    final rootNumerator = _integerSqrt(numerator);
    final rootDenominator = _integerSqrt(denominator);

    if (rootNumerator * rootNumerator == numerator &&
        rootDenominator * rootDenominator == denominator) {
      return Rational(rootNumerator, rootDenominator);
    }

    return null;
  }

  Rational sqrtApproximation() {
    if (numerator.isNegative) {
      throw const FormatException('Корень из отрицательного числа');
    }

    const places = 24;
    final scale = _pow10(places);
    final scaledRadicand = numerator * scale * scale ~/ denominator;
    final root = _integerSqrt(scaledRadicand);

    return Rational(root, scale);
  }

  static BigInt _integerSqrt(BigInt value) {
    if (value < BigInt.zero) {
      throw const FormatException('Корень из отрицательного числа');
    }
    if (value < BigInt.two) return value;

    var x = value;
    var y = (x + BigInt.one) ~/ BigInt.two;

    while (y < x) {
      x = y;
      y = (x + value ~/ x) ~/ BigInt.two;
    }

    return x;
  }

  double toDouble() {
    return numerator.toDouble() / denominator.toDouble();
  }

  static Rational fromDouble(double value) {
    if (value.isNaN) {
      throw const FormatException('Некорректный результат');
    }
    if (!value.isFinite) {
      throw const FormatException('Результат слишком велик');
    }
    if (value == 0) return zero;

    final text = value.toStringAsExponential();
    final eIndex = text.indexOf('e');
    final mantissaText = text.substring(0, eIndex);
    final exponent = int.parse(text.substring(eIndex + 1));

    final negative = mantissaText.startsWith('-');
    final unsigned = negative ? mantissaText.substring(1) : mantissaText;
    final dotIndex = unsigned.indexOf('.');
    final whole = dotIndex == -1 ? unsigned : unsigned.substring(0, dotIndex);
    final fraction = dotIndex == -1 ? '' : unsigned.substring(dotIndex + 1);
    final digits = '$whole$fraction';

    var numerator = BigInt.parse(digits);
    if (negative) numerator = -numerator;

    final denominatorExponent = fraction.length - exponent;
    if (denominatorExponent >= 0) {
      return Rational(numerator, _pow10(denominatorExponent));
    }

    return Rational(numerator * _pow10(-denominatorExponent), BigInt.one);
  }

  static Rational fromDoubleApproximation(double value) => fromDouble(value);

  int _decimalExponent() {
    final nDigits = numerator.abs().toString().length;
    final dDigits = denominator.toString().length;
    var exponent = nDigits - dDigits;

    while (_compareWithPowerOfTen(exponent) < 0) {
      exponent--;
    }
    while (_compareWithPowerOfTen(exponent + 1) >= 0) {
      exponent++;
    }

    return exponent;
  }

  int _compareWithPowerOfTen(int exponent) {
    final n = numerator.abs();
    final d = denominator;

    if (exponent >= 0) {
      return n.compareTo(d * _pow10(exponent));
    }

    return (n * _pow10(-exponent)).compareTo(d);
  }

  String _toScientificString(int exponent) {
    const significantDigits = 12;
    final n = numerator.abs();
    final d = denominator;

    var scaledNumerator = n * _pow10(significantDigits - 1);
    var scaledDenominator = d;

    if (exponent >= 0) {
      scaledDenominator *= _pow10(exponent);
    } else {
      scaledNumerator *= _pow10(-exponent);
    }

    var mantissa =
        (scaledNumerator + scaledDenominator ~/ BigInt.two) ~/
        scaledDenominator;

    final limit = _pow10(significantDigits);
    if (mantissa >= limit) {
      mantissa = mantissa ~/ BigInt.from(10);
      exponent++;
    }

    final digits = mantissa.toString().padLeft(significantDigits, '0');
    final whole = digits.substring(0, 1);
    final fraction = digits.substring(1).replaceFirst(RegExp(r'0+$'), '');
    final sign = numerator.isNegative ? '-' : '';
    final mantissaText = fraction.isEmpty ? whole : '$whole.$fraction';

    return '$sign${mantissaText}e${exponent >= 0 ? '+' : ''}$exponent';
  }

  String toDisplayString() {
    if (numerator == BigInt.zero) return '0';

    final exponent = _decimalExponent();
    if (exponent >= 21 || exponent <= -16) {
      return _toScientificString(exponent);
    }

    const places = 15;
    final scale = _pow10(places);
    final absoluteNumerator = numerator.abs();
    final scaled = absoluteNumerator * scale;
    var rounded = scaled ~/ denominator;
    final remainder = scaled % denominator;

    if (remainder * BigInt.two >= denominator) {
      rounded += BigInt.one;
    }

    if (rounded == BigInt.zero) return '0';

    final whole = rounded ~/ scale;
    final fraction = (rounded % scale).toString().padLeft(places, '0');
    final trimmedFraction = fraction.replaceFirst(RegExp(r'0+$'), '');
    final sign = numerator.isNegative ? '-' : '';

    if (trimmedFraction.isEmpty) {
      return '$sign$whole';
    }

    return '$sign$whole.$trimmedFraction';
  }

  String toFractionString() {
    if (isInteger) return numerator.toString();
    return '$numerator/$denominator';
  }

  @override
  bool operator ==(Object other) {
    return other is Rational &&
        numerator == other.numerator &&
        denominator == other.denominator;
  }

  @override
  int get hashCode => Object.hash(numerator, denominator);

  @override
  String toString() => toFractionString();
}

class EvalResult {
  const EvalResult(this.value, {required this.approximate});

  final Rational value;
  final bool approximate;
}

/// Разбирает выражения с рациональной арифметикой, %, степенями, sqrt(...),
/// инженерными функциями и факториалом.
class ExpressionParser {
  ExpressionParser(this.input, {this.degrees = true});

  final String input;
  final bool degrees;
  int _position = 0;
  bool _approximate = false;

  static const List<String> _functionNames = [
    'sin',
    'cos',
    'tan',
    'ln',
    'log',
    'inv',
  ];

  Rational parse() => parseResult().value;

  EvalResult parseResult() {
    _approximate = false;
    final value = _parseAddSubtract();

    if (_position != input.length) {
      throw const FormatException('Лишние символы');
    }

    return EvalResult(value, approximate: _approximate);
  }

  Rational _parseAddSubtract() {
    var value = _parseMultiplyDivide();

    while (_match('+') || _match('-')) {
      final operator = input[_position++];
      final rightStart = _position;
      var right = _parseMultiplyDivide();

      // Как в бытовом калькуляторе: 200 + 10% = 220, 200 - 10% = 180.
      // Относительный процент применяется, только если правый операнд —
      // самостоятельное процентное выражение (10%, (10)%, -10%).
      if (_isBarePercent(rightStart, _position)) {
        right = value * right;
      }

      value = operator == '+' ? value + right : value - right;
    }

    return value;
  }

  bool _isBarePercent(int start, int end) {
    if (end <= start || input[end - 1] != '%') return false;

    var depth = 0;

    for (var index = start; index < end; index++) {
      final char = input[index];

      if (char == '(') {
        depth++;
      } else if (char == ')') {
        depth--;
      } else if (depth == 0) {
        if (char == '*' || char == '/' || char == '^') {
          return false;
        }
        if ((char == '+' || char == '-') && index > start) {
          return false;
        }
      }
    }

    return true;
  }

  Rational _parseMultiplyDivide() {
    var value = _parseUnary();

    while (_match('*') || _match('/')) {
      final operator = input[_position++];
      final right = _parseUnary();

      value = operator == '*' ? value * right : value / right;
    }

    return value;
  }

  Rational _parseUnary() {
    if (_match('+')) {
      _position++;
      return _parseUnary();
    }

    if (_match('-')) {
      _position++;
      return -_parseUnary();
    }

    return _parsePower();
  }

  Rational _parsePower() {
    final base = _parsePostfix();

    if (_match('^')) {
      _position++;
      final exponent = _parseUnary();

      if (exponent.denominator == BigInt.one) {
        return base.powInteger(exponent.numerator);
      }

      // Для квадратного корня из рационального числа сохраняем точность.
      if (exponent.denominator == BigInt.two) {
        final exactRoot = base.trySqrtExact();
        if (exactRoot != null) {
          return exactRoot.powInteger(exponent.numerator);
        }
      }

      // Дробные степени в общем случае не являются рациональными.
      _approximate = true;
      final result = math.pow(base.toDouble(), exponent.toDouble()).toDouble();
      return Rational.fromDouble(result);
    }

    return base;
  }

  Rational _parsePostfix() {
    var value = _parsePrimary();

    while (_match('%') || _match('!')) {
      if (_match('%')) {
        _position++;
        value = value.percent();
      } else {
        _position++;
        value = _factorial(value);
      }
    }

    return value;
  }

  Rational _parsePrimary() {
    if (input.startsWith('sqrt(', _position)) {
      _position += 'sqrt('.length;
      final value = _parseAddSubtract();
      _expect(')');

      final exact = value.trySqrtExact();
      if (exact != null) return exact;

      _approximate = true;
      return value.sqrtApproximation();
    }

    for (final name in _functionNames) {
      final prefix = '$name(';

      if (input.startsWith(prefix, _position)) {
        _position += prefix.length;
        final value = _parseAddSubtract();
        _expect(')');
        return _applyFunction(name, value);
      }
    }

    if (_match('π')) {
      _position++;
      _approximate = true;
      return Rational.fromDouble(math.pi);
    }

    if (input.startsWith('pi', _position)) {
      _position += 2;
      _approximate = true;
      return Rational.fromDouble(math.pi);
    }

    if (_match('e')) {
      _position++;
      _approximate = true;
      return Rational.fromDouble(math.e);
    }

    if (_match('@')) {
      return _parseExactValue();
    }

    if (_match('(')) {
      _position++;
      final value = _parseAddSubtract();
      _expect(')');
      return value;
    }

    return _parseNumber();
  }

  Rational _applyFunction(String name, Rational value) {
    switch (name) {
      case 'inv':
        if (value == Rational.zero) {
          throw const FormatException('Деление на ноль');
        }
        return Rational.one / value;
      case 'ln':
        if (value.toDouble() <= 0) {
          throw const FormatException('Логарифм не определён');
        }
        _approximate = true;
        return Rational.fromDouble(math.log(value.toDouble()));
      case 'log':
        if (value.toDouble() <= 0) {
          throw const FormatException('Логарифм не определён');
        }
        _approximate = true;
        return Rational.fromDouble(math.log(value.toDouble()) / math.ln10);
      case 'sin':
        _approximate = true;
        return Rational.fromDouble(
          _snapTrig(math.sin(_toRadians(value.toDouble()))),
        );
      case 'cos':
        _approximate = true;
        return Rational.fromDouble(
          _snapTrig(math.cos(_toRadians(value.toDouble()))),
        );
      case 'tan':
        final radians = _toRadians(value.toDouble());
        if (math.cos(radians).abs() < 1e-12) {
          throw const FormatException('Тангенс не определён');
        }
        _approximate = true;
        return Rational.fromDouble(_snapTrig(math.tan(radians)));
      default:
        throw const FormatException('Неизвестная функция');
    }
  }

  double _snapTrig(double value) {
    // Убираем шум плавающей точки: sin(180°) должен быть ровно 0.
    return value.abs() < 1e-12 ? 0 : value;
  }

  double _toRadians(double value) {
    return degrees ? value * math.pi / 180 : value;
  }

  Rational _factorial(Rational value) {
    if (!value.isInteger || value.numerator.isNegative) {
      throw const FormatException(
        'Факториал только для целых неотрицательных чисел',
      );
    }

    if (value.numerator > BigInt.from(1000)) {
      throw const FormatException('Слишком большое число');
    }

    var result = BigInt.one;
    final limit = value.numerator.toInt();

    for (var number = 2; number <= limit; number++) {
      result *= BigInt.from(number);
    }

    return Rational(result, BigInt.one);
  }

  Rational _parseExactValue() {
    _position++; // @

    final colon = input.indexOf(':', _position);
    if (colon == -1) {
      throw const FormatException('Некорректное точное число');
    }

    final semicolon = input.indexOf(';', colon + 1);
    if (semicolon == -1) {
      throw const FormatException('Некорректное точное число');
    }

    final numeratorText = input.substring(_position, colon);
    final denominatorText = input.substring(colon + 1, semicolon);

    _position = semicolon + 1;

    return Rational(BigInt.parse(numeratorText), BigInt.parse(denominatorText));
  }

  Rational _parseNumber() {
    final start = _position;
    var hasDigit = false;

    while (_position < input.length && _isDigit(input[_position])) {
      hasDigit = true;
      _position++;
    }

    if (_match('.')) {
      _position++;

      while (_position < input.length && _isDigit(input[_position])) {
        hasDigit = true;
        _position++;
      }
    }

    if (!hasDigit) {
      throw const FormatException('Ожидалось число');
    }

    return Rational.fromDecimal(input.substring(start, _position));
  }

  bool _match(String char) {
    return _position < input.length && input[_position] == char;
  }

  void _expect(String char) {
    if (!_match(char)) {
      throw const FormatException('Не хватает закрывающей скобки');
    }

    _position++;
  }

  static bool _isDigit(String char) {
    final code = char.codeUnitAt(0);
    return code >= 0x30 && code <= 0x39;
  }
}
