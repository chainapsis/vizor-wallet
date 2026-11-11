import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/l10n/generate.dart';
import '../../tool/l10n/generation_watch.dart';

void main() {
  test('a save burst runs once and idle time does no work', () async {
    var runs = 0;
    final watcher = GenerationWatch(
      generate: () async {
        runs++;
      },
      onError: (error, _) => fail('$error'),
      debounce: const Duration(milliseconds: 20),
    );
    addTearDown(watcher.close);
    for (var i = 0; i < 10; i++) {
      watcher.schedule();
    }
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(runs, 1);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(runs, 1);
  });

  test('saves during a run queue one pass without overlap', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    var runs = 0;
    var active = 0;
    var maxActive = 0;
    final watcher = GenerationWatch(
      generate: () async {
        active++;
        if (active > maxActive) maxActive = active;
        runs++;
        if (runs == 1) {
          started.complete();
          await release.future;
        }
        active--;
      },
      onError: (error, _) => fail('$error'),
      debounce: const Duration(milliseconds: 20),
    );
    addTearDown(watcher.close);
    watcher.schedule(immediate: true);
    await started.future;
    for (var i = 0; i < 10; i++) {
      watcher.schedule();
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(runs, 1);
    release.complete();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(runs, 2);
    expect(maxActive, 1);
  });

  test(
    'an incomplete save can recover and close cancels pending work',
    () async {
      var runs = 0;
      var errors = 0;
      final watcher = GenerationWatch(
        generate: () async {
          runs++;
          if (runs == 1) throw const FormatException('incomplete edit');
        },
        onError: (_, _) {
          errors++;
        },
        debounce: const Duration(milliseconds: 20),
      );
      watcher.schedule();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      watcher.schedule();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(runs, 2);
      expect(errors, 1);
      watcher.schedule();
      await watcher.close();
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(runs, 2);
    },
  );

  test('Flutter generation cache rejects edited or missing outputs', () {
    final directory = Directory.systemTemp.createTempSync('l10n_cache_test');
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = File('${directory.path}/state.json');
    const outputs = {
      'lib/l10n/app_localizations.dart': 'base',
      'lib/l10n/app_localizations_ko.dart': 'ko',
    };
    file.writeAsStringSync(jsonEncode({'inputs': 'input', 'outputs': outputs}));
    bool current(String input, Map<String, String> actual) =>
        flutterOutputsAreCurrent(
          input,
          statePath: file.path,
          readOutputs: () => actual,
        );
    expect(current('input', outputs), isTrue);
    expect(current('changed input', outputs), isFalse);
    expect(
      current('input', {'lib/l10n/app_localizations.dart': 'base'}),
      isFalse,
    );
    expect(
      current('input', {
        ...outputs,
        'lib/l10n/app_localizations_ko.dart': 'edited',
      }),
      isFalse,
    );
    file.writeAsStringSync('[]');
    expect(current('input', outputs), isFalse);
  });
}
