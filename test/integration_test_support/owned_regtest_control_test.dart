import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/support/owned_regtest_control.dart';

void main() {
  group('withNativeClipboard', () {
    test('protects only the copy/read and returns its actual result', () async {
      final events = <String>[];
      final value = await withNativeClipboard(
        () async {
          events.add('copy/read');
          return 'copied address';
        },
        acquireLease: () async => events.add('acquire'),
        releaseLease: () async => events.add('release'),
      );
      expect(value, 'copied address');
      expect(events, ['acquire', 'copy/read', 'release']);
    });

    test(
      'failed actions preserve the error and retain the lease for host stop',
      () async {
        final original = StateError('copy assertion failed');
        var held = false;
        await expectLater(
          withNativeClipboard<void>(
            () async => throw original,
            acquireLease: () async => held = true,
            releaseLease: () async => held = false,
          ),
          throwsA(same(original)),
        );
        expect(held, isTrue);
      },
    );

    test('acquisition failure starts neither action nor release', () async {
      final events = <String>[];
      await expectLater(
        withNativeClipboard<void>(
          () async => events.add('action'),
          acquireLease: () async => throw StateError('cancelled while queued'),
          releaseLease: () async => events.add('release'),
        ),
        throwsStateError,
      );
      expect(events, isEmpty);
    });

    test(
      'unproven release remains a failure rather than returning success',
      () async {
        await expectLater(
          withNativeClipboard(
            () async => 'copied address',
            acquireLease: () async {},
            releaseLease: () async => throw StateError('release unproven'),
          ),
          throwsStateError,
        );
      },
    );

    test(
      'a deployed manual runner outside the cohort does not request a lease',
      () async {
        expect(
          await withNativeClipboard(() async => 'manual copy'),
          'manual copy',
        );
      },
    );

    test(
      'rejects incomplete test callbacks before starting an action',
      () async {
        var started = false;
        await expectLater(
          withNativeClipboard<void>(
            () async => started = true,
            acquireLease: () async {},
          ),
          throwsArgumentError,
        );
        expect(started, isFalse);
      },
    );
  });
}
