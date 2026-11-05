// Finds user-facing string literals in app code.
//
//   fvm dart run tool/l10n/strings.dart inventory
//       Per-feature counts of literals that still need translation.
//   fvm dart run tool/l10n/strings.dart list <dir-or-file>...
//       Every finding as `file:line: kind: "text"`, for extraction work.
//   fvm dart run tool/l10n/strings.dart check
//       Fails when a directory listed in tool/l10n/migrated_dirs.txt has a
//       user-facing literal. A literal that must stay put carries a trailing
//       `// l10n-ignore: <reason>` comment on its line.
//
// The scan is syntactic, so "likely" literals include some false positives;
// "slot" literals sit in a widget text slot and are user-facing.
import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';

const _roots = ['lib/src', 'lib/app.dart'];
const _skipDirs = ['lib/src/rust/', 'lib/src/generated/'];
const _migratedDirsFile = 'tool/l10n/migrated_dirs.txt';
const _ignoreMarker = 'l10n-ignore';

/// Named arguments that render their value as text.
const _textSlots = {
  'actionLabel',
  'body',
  'buttonLabel',
  'cancelLabel',
  'caption',
  'confirmLabel',
  'description',
  'emptyLabel',
  'errorText',
  'heading',
  'helperText',
  'hintText',
  'label',
  'labelText',
  'message',
  'placeholder',
  'semanticLabel',
  'semanticsLabel',
  'subtitle',
  'text',
  'title',
  'tooltip',
};

const _textWidgets = {'Text', 'SelectableText', 'TextSpan'};

/// Calls whose string arguments are never shown to users.
const _devCalls = {
  'assert',
  'contains',
  'debugPrint',
  'endsWith',
  'indexOf',
  'log',
  'parse',
  'print',
  'replaceAll',
  'replaceFirst',
  'split',
  'startsWith',
  'tryParse',
};

const _devTypes = {
  'ArgumentError',
  'AssertionError',
  'Exception',
  'FlutterError',
  'FormatException',
  'GlobalKey',
  'Key',
  'MethodChannel',
  'EventChannel',
  'ObjectKey',
  'RegExp',
  'StateError',
  'UnimplementedError',
  'UnsupportedError',
  'ValueKey',
};

/// Named arguments that carry identifiers, not copy.
const _devNamedArgs = {
  'debugLabel',
  'family',
  'fontFamily',
  'package',
  'name',
  'path',
  'restorationId',
  'route',
  'routeName',
  'scenarioId',
  'semanticsIdentifier',
};

enum Kind { slot, likely }

class Finding {
  Finding(this.file, this.line, this.text, this.kind);
  final String file;
  final int line;
  final String text;
  final Kind kind;
}

class _Visitor extends RecursiveAstVisitor<void> {
  _Visitor(this.file, this.lineInfo, this.source);

  final String file;
  final LineInfo lineInfo;
  final String source;
  final findings = <Finding>[];

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) {
    if (node.parent is! AdjacentStrings) _consider(node, node.value);
  }

  @override
  void visitStringInterpolation(StringInterpolation node) {
    if (node.parent is! AdjacentStrings) {
      final text = node.elements
          .map((e) => e is InterpolationString ? e.value : '{}')
          .join();
      _consider(node, text);
    }
    super.visitStringInterpolation(node);
  }

  @override
  void visitAdjacentStrings(AdjacentStrings node) {
    _consider(node, node.stringValue ?? node.toSource());
    super.visitAdjacentStrings(node);
  }

  void _consider(StringLiteral node, String text) {
    if (!RegExp(r'[A-Za-z]{2}').hasMatch(text)) return;
    final location = lineInfo.getLocation(node.offset);
    final lineText = _line(location.lineNumber);
    if (lineText.contains(_ignoreMarker)) return;
    final kind = _classify(node, text);
    if (kind == null) return;
    findings.add(Finding(file, location.lineNumber, text, kind));
  }

  String _line(int number) {
    final start = lineInfo.getOffsetOfLine(number - 1);
    final end = number < lineInfo.lineCount
        ? lineInfo.getOffsetOfLine(number)
        : source.length;
    return source.substring(start, end);
  }

  Kind? _classify(StringLiteral node, String text) {
    AstNode child = node;
    AstNode? parent = node.parent;
    var slot = false;
    while (parent != null) {
      if (parent is Directive || parent is Annotation) return null;
      if (parent is AssertStatement || parent is AssertInitializer) return null;
      if (parent is MapLiteralEntry && parent.key == child) return null;
      if (parent is IndexExpression) return null;
      if (parent is SwitchCase || parent is SwitchPatternCase) return null;
      if (parent is ConstantPattern || parent is GuardedPattern) return null;
      if (parent is BinaryExpression &&
          (parent.operator.lexeme == '==' || parent.operator.lexeme == '!=')) {
        return null;
      }
      if (parent is NamedExpression) {
        final name = parent.name.label.name;
        if (_devNamedArgs.contains(name)) return null;
        if (_textSlots.contains(name)) slot = true;
      }
      if (parent is MethodInvocation) {
        final name = parent.methodName.name;
        if (_devCalls.contains(name) ||
            _devTypes.contains(name) ||
            RegExp(r'^_?(log|debug|trace)|Log$').hasMatch(name)) {
          return null;
        }
        if (name == 'showAppToast') slot = true;
        if (_textWidgets.contains(name) && child is ArgumentList) slot = true;
      }
      if (parent is InstanceCreationExpression) {
        final type = parent.constructorName.type.name.lexeme;
        if (_devTypes.contains(type)) return null;
        if (_textWidgets.contains(type)) slot = true;
      }
      if (parent is VariableDeclaration) {
        final name = parent.name.lexeme;
        if (RegExp(
              r'(Key|Path|Url|Uri|Route|Id|Channel|Prefix)$',
            ).hasMatch(name) ||
            RegExp(r'^k[A-Z].*Key$').hasMatch(name)) {
          return null;
        }
      }
      if (parent is ThrowExpression) return null;
      if (parent is FunctionBody || parent is ClassMember) break;
      child = parent;
      parent = parent.parent;
    }
    if (slot) return Kind.slot;
    final looksLikeCopy =
        RegExp(r'^[A-Z]').hasMatch(text.trimLeft()) || text.contains(' ');
    final looksLikeId =
        (!text.contains(' ') &&
            (text.contains('_') ||
                text.contains('/') ||
                text.contains('://') ||
                RegExp(r'^[a-z]').hasMatch(text) ||
                RegExp(r'^[A-Z][a-z]+[A-Z]').hasMatch(text))) ||
        // Log tags such as `SendBroadcast(ledger-terminal)` or `k=v` dumps.
        RegExp(r'^[A-Za-z]+\(').hasMatch(text) ||
        RegExp(r'\b\w+=\{\}').hasMatch(text);
    if (!looksLikeCopy || looksLikeId) return null;
    return Kind.likely;
  }
}

List<Finding> scanSource(String path, String source) {
  final unit = parseString(
    content: source,
    featureSet: FeatureSet.latestLanguageVersion(),
    throwIfDiagnostics: false,
  ).unit;
  final visitor = _Visitor(path, unit.lineInfo, source);
  unit.accept(visitor);
  return visitor.findings;
}

List<Finding> scan(Iterable<String> roots) {
  final findings = <Finding>[];
  for (final root in roots) {
    final entity = FileSystemEntity.typeSync(root) == FileSystemEntityType.file
        ? [File(root)]
        : Directory(root)
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart'));
    for (final file in entity) {
      if (_skipDirs.any(file.path.startsWith)) continue;
      findings.addAll(scanSource(file.path, file.readAsStringSync()));
    }
  }
  return findings;
}

/// Directories whose strings have moved to ARB files.
List<String> migratedDirs() {
  final file = File(_migratedDirsFile);
  if (!file.existsSync()) return const [];
  return file
      .readAsLinesSync()
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty && !l.startsWith('#'))
      .toList();
}

String _area(String path) {
  final feature = RegExp(r'^lib/src/features/([^/]+)/').firstMatch(path);
  if (feature != null) return 'features/${feature.group(1)}';
  final top = RegExp(r'^lib/src/([^/]+)/').firstMatch(path);
  if (top != null) return top.group(1)!;
  return path;
}

void inventory() {
  final findings = scan(_roots);
  final byArea = <String, List<Finding>>{};
  for (final f in findings) {
    byArea.putIfAbsent(_area(f.file), () => []).add(f);
  }
  final rows = byArea.entries.map((e) {
    Set<String> unique(Kind k) =>
        e.value.where((f) => f.kind == k).map((f) => f.text).toSet();
    return (e.key, unique(Kind.slot).length, unique(Kind.likely).length);
  }).toList()..sort((a, b) => (b.$2 + b.$3).compareTo(a.$2 + a.$3));
  final allSlot = findings
      .where((f) => f.kind == Kind.slot)
      .map((f) => f.text)
      .toSet();
  final allLikely =
      findings.where((f) => f.kind == Kind.likely).map((f) => f.text).toSet()
        ..removeAll(allSlot);
  stdout.writeln('| area | slot | likely | total |');
  stdout.writeln('|---|---:|---:|---:|');
  for (final (area, slot, likely) in rows) {
    stdout.writeln('| $area | $slot | $likely | ${slot + likely} |');
  }
  stdout.writeln(
    '| **unique overall** | ${allSlot.length} | ${allLikely.length} | '
    '${allSlot.length + allLikely.length} |',
  );
}

int check() {
  final dirs = migratedDirs();
  if (dirs.isEmpty) {
    stdout.writeln('No migrated directories listed in $_migratedDirsFile.');
    return 0;
  }
  final findings = scan(dirs);
  for (final f in findings) {
    stdout.writeln('${f.file}:${f.line}: ${f.kind.name}: "${f.text}"');
  }
  if (findings.isEmpty) {
    stdout.writeln('No untranslated literals in ${dirs.length} migrated dirs.');
    return 0;
  }
  stdout.writeln(
    '${findings.length} literal(s) need a l10n key or a trailing '
    '`// $_ignoreMarker: <reason>`.',
  );
  return 1;
}

void main(List<String> args) {
  switch (args.firstOrNull) {
    case 'inventory':
      inventory();
    case 'list':
      for (final f in scan(args.skip(1).isEmpty ? _roots : args.skip(1))) {
        stdout.writeln('${f.file}:${f.line}: ${f.kind.name}: "${f.text}"');
      }
    case 'check':
      exitCode = check();
    default:
      stderr.writeln('usage: dart run tool/l10n/strings.dart inventory|check');
      exitCode = 64;
  }
}
