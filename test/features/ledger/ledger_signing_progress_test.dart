import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_signing_progress.dart';

void main() {
  test(
    'progress is monotonic within an attempt and resets for the next round',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final controller = container.read(ledgerSigningProgressProvider.notifier);
      final first = controller.begin('a');
      first('sending');
      first('reviewing');
      first(
        'sending',
      ); // A retry of the review-busy request is not a new upload.
      expect(
        container.read(ledgerSigningProgressProvider)?.stage,
        LedgerSigningStage.reviewing,
      );
      final second = controller.begin('a');
      first('finishing');
      expect(
        container.read(ledgerSigningProgressProvider)?.stage,
        LedgerSigningStage.preparing,
      );
      second('sending');
      controller.cancel();
      second('finishing');
      await Future<void>.value();
      expect(container.read(ledgerSigningProgressProvider), isNull);
    },
  );
  test(
    'deferred cancel cleanup cannot clear a new attempt or disposed provider',
    () async {
      final container = ProviderContainer();
      final controller = container.read(ledgerSigningProgressProvider.notifier);
      controller.begin('old');
      controller.cancel();
      controller.begin('new')('sending');
      await Future<void>.value();
      expect(container.read(ledgerSigningProgressProvider)?.accountUuid, 'new');
      expect(
        container.read(ledgerSigningProgressProvider)?.stage,
        LedgerSigningStage.sending,
      );
      controller.cancel();
      container.dispose();
      await Future<void>.value();
    },
  );
  test('late progress after provider disposal is ignored', () {
    final container = ProviderContainer();
    final update = container
        .read(ledgerSigningProgressProvider.notifier)
        .begin('a');
    container.dispose();
    expect(() => update('sending'), returnsNormally);
  });
}
