import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/providers/sync_display_progress_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

import '../fakes/fake_sync_notifier.dart';

void main() {
  for (final checking in [false, true]) {
    testWidgets(
      '${checking ? 'Checking' : 'Syncing'} ticks rebuild only progress consumers',
      (tester) async {
        final initial = SyncState(
          isSyncing: true,
          percentage: checking ? 1 : 0.2,
          displayTargetPercentage: checking ? 1 : 0.3,
          displayTargetBlocks: 100,
          checking: checking
              ? const SyncCheckingProgress(
                  cycle: 1,
                  percentage: 0.2,
                  displayTargetPercentage: 0.3,
                )
              : null,
        );
        final container = ProviderContainer(
          overrides: [
            syncProvider.overrideWith(() => FakeSyncNotifier(initial)),
          ],
        );
        addTearDown(container.dispose);
        var ringBuilds = 0;
        var labelBuilds = 0;
        var walletBuilds = 0;
        var stageBuilds = 0;
        var syncUpdates = 0;
        await container.read(syncProvider.future);
        container.listen(syncProvider, (_, _) => syncUpdates++);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Column(
                children: [
                  Consumer(
                    builder: (_, ref, _) {
                      ringBuilds++;
                      return Text(
                        '${ref.watch(syncDisplayPercentageProvider)}',
                      );
                    },
                  ),
                  Consumer(
                    builder: (_, ref, _) {
                      labelBuilds++;
                      return Text(
                        '${ref.watch(syncDisplayWholePercentageProvider)}',
                      );
                    },
                  ),
                  Consumer(
                    builder: (_, ref, _) {
                      walletBuilds++;
                      return Text(
                        '${ref.watch(syncProvider).requireValue.percentage}',
                      );
                    },
                  ),
                  Consumer(
                    builder: (_, ref, _) {
                      stageBuilds++;
                      return Text(
                        '${ref.watch(syncDisplayCheckingCycleProvider)}',
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pump();
        final baseline = (
          ring: ringBuilds,
          label: labelBuilds,
          wallet: walletBuilds,
          stage: stageBuilds,
        );
        await tester.pump(const Duration(milliseconds: 40));
        expect(
          container.read(syncDisplayPercentageProvider),
          closeTo(0.202, 0.00001),
        );
        expect(ringBuilds, greaterThan(baseline.ring));
        expect(labelBuilds, baseline.label);
        expect(walletBuilds, baseline.wallet);
        expect(stageBuilds, baseline.stage);
        expect(syncUpdates, 0);
        await tester.pump(const Duration(milliseconds: 200));
        expect(container.read(syncDisplayWholePercentageProvider), 21);
        expect(labelBuilds, baseline.label + 1);
        expect(walletBuilds, baseline.wallet);
        expect(stageBuilds, baseline.stage);
        expect(syncUpdates, 0);
        await tester.pump(const Duration(seconds: 3));
        expect(
          container.read(syncDisplayPercentageProvider),
          closeTo(0.3, 0.00001),
        );
        final settledBuilds = ringBuilds;
        await tester.pump(const Duration(seconds: 1));
        expect(ringBuilds, settledBuilds);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'Checking resets for discovered retry work but does not oscillate on ordinary events',
    (tester) async {
      final startedAt = DateTime.utc(2026, 10, 12);
      final initial = SyncState(
        isSyncing: true,
        phase: 'scan',
        percentage: 1,
        lastSyncStartedAt: startedAt,
      );
      final notifier = FakeSyncNotifier(initial);
      final container = ProviderContainer(
        overrides: [syncProvider.overrideWith(() => notifier)],
      );
      addTearDown(container.dispose);
      container.listen(syncDisplayPercentageProvider, (_, _) {});
      await container.read(syncProvider.future);
      await tester.pump();
      expect(container.read(syncDisplayPercentageProvider), 0.99);
      final repair = initial.copyWith(
        displayTargetBlocks: 10,
        checking: const SyncCheckingProgress(
          cycle: 1,
          percentage: 0,
          displayTargetPercentage: 0.5,
        ),
      );
      notifier.emit(repair);
      await tester.pump();
      expect(container.read(syncDisplayPercentageProvider), 0);
      await tester.pump(const Duration(milliseconds: 100));
      expect(container.read(syncDisplayPercentageProvider), 0.25);
      // Retry preparation carries committed work and has no speculative batch.
      notifier.emit(
        repair.copyWith(
          phase: kSyncPhaseChainPrepare,
          displayTargetBlocks: 0,
          checking: const SyncCheckingProgress(
            cycle: 1,
            percentage: 0.2,
            displayTargetPercentage: 0.2,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(container.read(syncDisplayPercentageProvider), 0.25);
      notifier.emit(
        repair.copyWith(
          displayTargetBlocks: 0,
          checking: const SyncCheckingProgress(
            cycle: 1,
            percentage: 0.75,
            displayTargetPercentage: 0.75,
          ),
        ),
      );
      await tester.pump();
      expect(container.read(syncDisplayPercentageProvider), 0.75);
      // A newly discovered retry queue resets progress, including the old
      // interpolation target. The user sees only a lower Checking percentage.
      notifier.emit(
        repair.copyWith(
          displayTargetBlocks: 10,
          checking: const SyncCheckingProgress(
            cycle: 2,
            percentage: 0,
            displayTargetPercentage: 0.5,
          ),
        ),
      );
      await tester.pump();
      expect(container.read(syncDisplayPercentageProvider), 0);
      await tester.pump(const Duration(milliseconds: 100));
      expect(container.read(syncDisplayPercentageProvider), 0.25);
      notifier.emit(
        repair.copyWith(
          displayTargetBlocks: 0,
          checking: const SyncCheckingProgress(
            cycle: 2,
            percentage: 0.2,
            displayTargetPercentage: 0.2,
          ),
        ),
      );
      await tester.pump();
      expect(container.read(syncDisplayPercentageProvider), 0.25);
      // A changed work denominator may restart above zero, at its actual
      // recalculated fraction rather than holding the previous display floor.
      notifier.emit(
        repair.copyWith(
          displayTargetBlocks: 0,
          checking: const SyncCheckingProgress(
            cycle: 3,
            percentage: 0.1,
            displayTargetPercentage: 0.1,
          ),
        ),
      );
      await tester.pump();
      expect(container.read(syncDisplayPercentageProvider), 0.1);
      notifier.emit(
        repair.copyWith(
          displayTargetBlocks: 0,
          checking: const SyncCheckingProgress(
            cycle: 3,
            percentage: 1,
            displayTargetPercentage: 1,
          ),
        ),
      );
      await tester.pump();
      expect(container.read(syncDisplayPercentageProvider), 0.99);
      expect(container.read(syncProvider).requireValue.isSyncComplete, isFalse);
      notifier.emit(
        repair.copyWith(
          isSyncing: false,
          isSyncComplete: true,
          clearChecking: true,
        ),
      );
      await tester.pump();
      expect(container.read(syncDisplayPercentageProvider), 1);
      expect(container.read(syncDisplayCheckingCycleProvider), 0);
      container.dispose();
      await tester.pump();
    },
  );
}
