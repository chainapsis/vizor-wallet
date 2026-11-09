// Generates localization outputs on demand, or on translation saves with
// --watch. No build/run hook or editor task starts the watcher automatically.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'generated_output.dart';
import 'generation_watch.dart';
import 'korean_arb.dart'
    show buildKoreanArb, koreanOutputPath, koreanSourcePath;
import 'native_strings.dart' show buildNativeStringFiles;
import 'ui_font_characters.dart';

const generationStatePath = '.dart_tool/l10n_generation/flutter_outputs.json';
const generationInputs = [
  'lib/l10n/app_en.arb',
  'lib/l10n/source/app_ko.arb',
  'lib/l10n/app_zh.arb',
  'lib/src/core/l10n/app_language.dart',
  'tool/l10n/ui_fonts.py',
  'tool/l10n/ui_fonts.lock.json',
  'tool/l10n/ui_font_characters.dart',
  'tool/l10n/character_sets/tgh_2013.txt',
  'pubspec.lock',
  'pubspec.yaml',
  'l10n.yaml',
  '.fvmrc',
];

const restartInputs = [
  'tool/l10n/generate.dart',
  'tool/l10n/generation_watch.dart',
  'tool/l10n/generated_output.dart',
  'tool/l10n/korean_arb.dart',
  'tool/l10n/native_strings.dart',
  'tool/l10n/ui_font_characters.dart',
  'pubspec.lock',
  '.fvmrc',
];

List<String> arbInputs() =>
    Directory('lib/l10n')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.arb'))
        .map((f) => f.path.replaceAll('\\', '/'))
        .toList()
      ..sort();

String fileFingerprint(Iterable<String> paths) => sha256
    .convert(
      utf8.encode(
        jsonEncode({
          for (final path in paths)
            path: sha256.convert(File(path).readAsBytesSync()).toString(),
        }),
      ),
    )
    .toString();

Map<String, String> flutterOutputs() => {
  for (final file
      in Directory('lib/l10n')
          .listSync()
          .whereType<File>()
          .where(
            (f) =>
                f.uri.pathSegments.last.startsWith('app_localizations') &&
                f.path.endsWith('.dart'),
          )
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path)))
    file.path.replaceAll('\\', '/'): sha256
        .convert(file.readAsBytesSync())
        .toString(),
};

bool flutterOutputsAreCurrent(
  String inputHash, {
  String statePath = generationStatePath,
  Map<String, String> Function() readOutputs = flutterOutputs,
}) {
  try {
    final state = jsonDecode(File(statePath).readAsStringSync());
    if (state is! Map) return false;
    final outputs = readOutputs();
    return outputs.containsKey('lib/l10n/app_localizations.dart') &&
        state['inputs'] == inputHash &&
        jsonEncode(state['outputs']) == jsonEncode(outputs);
  } on FileSystemException {
    return false;
  } on FormatException {
    return false;
  }
}

Future<void> runTool(String executable, List<String> args) async {
  final process = await Process.start(
    executable,
    args,
    mode: ProcessStartMode.inheritStdio,
    runInShell: Platform.isWindows,
  );
  final code = await process.exitCode;
  if (code != 0) {
    throw ProcessException(executable, args, 'Generation failed', code);
  }
}

Future<void> generate({bool force = false}) async {
  final timer = Stopwatch()..start();
  // Parse all translation sources first. An incomplete editor save must not
  // rewrite native/ARB outputs before its JSON error is discovered.
  final native = buildNativeStringFiles();
  final korean = buildKoreanArb(File(koreanSourcePath).readAsStringSync());
  writeGeneratedTextIfChanged(koreanOutputPath, korean);
  await writeUiFormattingCharacters();
  await runTool(Platform.isWindows ? 'python' : 'python3', [
    'tool/l10n/ui_fonts.py',
  ]);

  final inputHash = fileFingerprint([
    ...arbInputs(),
    'l10n.yaml',
    'pubspec.yaml',
    'pubspec.lock',
    '.fvmrc',
  ]);
  final generateFlutter = force || !flutterOutputsAreCurrent(inputHash);
  if (generateFlutter) await runTool('fvm', ['flutter', 'gen-l10n']);
  for (final entry in native.entries) {
    writeGeneratedTextIfChanged(entry.key, entry.value);
  }
  if (generateFlutter) {
    writeGeneratedTextIfChanged(
      generationStatePath,
      jsonEncode({'inputs': inputHash, 'outputs': flutterOutputs()}),
    );
  }
  exitCode = 0;
  stdout.writeln(
    'Localizations and UI fonts are up to date. '
    '(${(timer.elapsedMilliseconds / 1000).toStringAsFixed(2)}s; '
    'Flutter ${generateFlutter ? 'generated' : 'unchanged'})',
  );
}

String _normalized(String path) =>
    File(path).absolute.uri.normalizePath().toString();

Future<void> watch() async {
  final lockPath = '.dart_tool/l10n_generation/watch.lock';
  if (symbolicLinkOnPath(lockPath) != null) {
    throw StateError('Unsafe watch lock path');
  }
  final lockFile = File(lockPath)..parent.createSync(recursive: true);
  final lock = lockFile.openSync(mode: FileMode.append);
  try {
    lock.lockSync(FileLock.exclusive);
  } on FileSystemException {
    lock.closeSync();
    throw StateError(
      'A localization watcher is already running in this worktree.',
    );
  }

  var previous = '';
  final scheduler = GenerationWatch(
    generate: () async {
      final next = fileFingerprint({
        ...generationInputs,
        ...arbInputs().where((p) => p != koreanOutputPath),
      });
      if (next == previous) return;
      previous = next;
      await generate();
    },
    onError: (error, stack) => stderr.writeln(error),
  );
  final sources = generationInputs.map(_normalized).toSet();
  final restarts = restartInputs.map(_normalized).toSet();
  final arbDirectory = Directory('lib/l10n').absolute.uri.normalizePath();
  bool sourceArb(String path) {
    final uri = File(path).absolute.uri.normalizePath();
    return uri.resolve('.').toString() == arbDirectory.toString() &&
        uri.path.endsWith('.arb') &&
        _normalized(path) != _normalized(koreanOutputPath);
  }

  final subscriptions = <StreamSubscription<FileSystemEvent>>[];
  final stopped = Completer<void>();
  StreamSubscription<ProcessSignal>? signal;
  try {
    for (final directory in {
      ...generationInputs,
      ...restartInputs,
    }.map((p) => File(p).parent.path).toSet()) {
      subscriptions.add(
        Directory(directory).watch().listen((event) {
          final destination = event is FileSystemMoveEvent
              ? event.destination
              : null;
          if (restarts.contains(_normalized(event.path)) ||
              (destination != null &&
                  restarts.contains(_normalized(destination)))) {
            stderr.writeln(
              'Localization tooling or dependencies changed; restart the watcher.',
            );
            if (!stopped.isCompleted) stopped.complete();
            return;
          }
          if (sources.contains(_normalized(event.path)) ||
              sourceArb(event.path) ||
              (destination != null && sourceArb(destination)) ||
              (destination != null &&
                  sources.contains(_normalized(destination)))) {
            scheduler.schedule();
          }
        }, onError: (Object error) => stderr.writeln(error)),
      );
    }
    signal = ProcessSignal.sigint.watch().listen((_) {
      if (!stopped.isCompleted) stopped.complete();
    });
    stdout.writeln(
      'Watching localization inputs (500ms debounce; Ctrl+C to stop).',
    );
    scheduler.schedule(immediate: true);
    await stopped.future;
  } finally {
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    await signal?.cancel();
    await scheduler.close();
    lock.unlockSync();
    lock.closeSync();
  }
}

Future<void> main(List<String> args) async {
  try {
    if (args.contains('--watch')) {
      await watch();
    } else {
      await generate(force: args.contains('--force'));
    }
  } catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  }
}
