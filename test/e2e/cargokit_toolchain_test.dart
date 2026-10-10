import 'package:flutter_test/flutter_test.dart';

import '../../scripts/e2e/cargokit_toolchain.dart';

void main() {
  group('Cargokit native debug toolchain', () {
    test('defaults only when debug selection is absent', () {
      for (final contents in [
        '{}',
        'cargo: {}',
        'cargo: {release: {toolchain: nightly}}',
        'cargo: {debug: {extra_flags: [--locked]}}',
      ]) {
        expect(configuredNativeToolchain(contents), 'stable');
      }
    });

    for (final channel in ['stable', 'beta', 'nightly']) {
      test('selects $channel independently of installed channels', () {
        expect(
          configuredNativeToolchain('cargo: {debug: {toolchain: "$channel"}}'),
          channel,
        );
      });
    }

    test('uses normal YAML anchors and comments', () {
      expect(
        configuredNativeToolchain('''
cargo:
  release: &selection
    toolchain: nightly # shared selection
  debug: *selection
'''),
        'nightly',
      );
    });

    test('rejects invalid maps or explicit toolchain values', () {
      for (final contents in [
        '[]',
        'cargo: null',
        'cargo: {debug: null}',
        'cargo: {debug: {toolchain: null}}',
        'cargo: {debug: {toolchain: 1}}',
        'cargo: {debug: {toolchain: custom}}',
      ]) {
        expect(
          () => configuredNativeToolchain(contents),
          throwsFormatException,
        );
      }
    });
  });
}
