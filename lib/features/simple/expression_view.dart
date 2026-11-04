part of '../../main.dart';

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
