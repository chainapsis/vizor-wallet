import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/providers/sync_display_progress_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

import '../fakes/fake_sync_notifier.dart';

void main() {
  test(
    'time-interpolates preparation without reaching its phase cap',
    () async {
      final initial = SyncState(
        isSyncing: true,
        phase: kSyncPhasePreflight,
        lastSyncStartedAt: DateTime.utc(2026, 8, 18),
      );
      final container = ProviderContainer(
        overrides: [syncProvider.overrideWith(() => FakeSyncNotifier(initial))],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        syncDisplayPercentageProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      await container.read(syncProvider.future);
      await Future<void>.delayed(const Duration(milliseconds: 500));

      final progress = container.read(syncDisplayPercentageProvider);
      expect(progress, greaterThan(0.005));
      expect(progress, lessThan(0.01));
    },
  );

  test(
    'uses elapsed time when preparation timer delivery is delayed',
    () async {
      final initial = SyncState(
        isSyncing: true,
        phase: kSyncPhasePreflight,
        lastSyncStartedAt: DateTime.utc(2026, 8, 18),
      );
      final container = ProviderContainer(
        overrides: [syncProvider.overrideWith(() => FakeSyncNotifier(initial))],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        syncDisplayPercentageProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      await container.read(syncProvider.future);
      await Future<void>.delayed(Duration.zero);

      // Simulate a busy/throttled UI isolate. Only one periodic callback should
      // be needed afterward because progress is based on real elapsed time.
      sleep(const Duration(milliseconds: 500));
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(container.read(syncDisplayPercentageProvider), greaterThan(0.005));
    },
  );

  test('uses committed UTXO work units inside the preparation range', () async {
    final startedAt = DateTime.utc(2026, 8, 18);
    final initial = SyncState(
      isSyncing: true,
      phase: kSyncPhaseActiveUtxo,
      phaseTotalUnits: 4,
      lastSyncStartedAt: startedAt,
    );
    late FakeSyncNotifier syncNotifier;
    final container = ProviderContainer(
      overrides: [
        syncProvider.overrideWith(
          () => syncNotifier = FakeSyncNotifier(initial),
        ),
      ],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      syncDisplayPercentageProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    await container.read(syncProvider.future);
    await Future<void>.delayed(Duration.zero);

    expect(container.read(syncDisplayPercentageProvider), closeTo(0.02, 0.001));
    syncNotifier.emit(initial.copyWith(phaseCompletedUnits: 2));
    await Future<void>.delayed(Duration.zero);
    expect(container.read(syncDisplayPercentageProvider), closeTo(0.03, 0.001));

    syncNotifier.emit(initial.copyWith(phaseCompletedUnits: 4));
    await Future<void>.delayed(Duration.zero);
    expect(container.read(syncDisplayPercentageProvider), closeTo(0.04, 0.001));
  });

  test(
    'maps authoritative block progress into the 5-99 percent range',
    () async {
      final initial = SyncState(
        isSyncing: true,
        phase: 'scan',
        percentage: 0.5,
        displayTargetPercentage: 0.5,
        lastSyncStartedAt: DateTime.utc(2026, 8, 18),
      );
      final container = ProviderContainer(
        overrides: [syncProvider.overrideWith(() => FakeSyncNotifier(initial))],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        syncDisplayPercentageProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      await container.read(syncProvider.future);
      await Future<void>.delayed(Duration.zero);

      expect(
        container.read(syncDisplayPercentageProvider),
        closeTo(0.52, 0.001),
      );
    },
  );

  test('does not regress when a Rust retry returns to preparation', () async {
    final startedAt = DateTime.utc(2026, 8, 18);
    final initial = SyncState(
      isSyncing: true,
      phase: 'scan',
      percentage: 0.5,
      displayTargetPercentage: 0.5,
      lastSyncStartedAt: startedAt,
    );
    late FakeSyncNotifier syncNotifier;
    final container = ProviderContainer(
      overrides: [
        syncProvider.overrideWith(
          () => syncNotifier = FakeSyncNotifier(initial),
        ),
      ],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      syncDisplayPercentageProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    await container.read(syncProvider.future);
    await Future<void>.delayed(Duration.zero);
    final beforeRetry = container.read(syncDisplayPercentageProvider);

    syncNotifier.emit(
      initial.copyWith(
        phase: kSyncPhaseActiveUtxo,
        percentage: 0,
        displayTargetPercentage: 0,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(container.read(syncDisplayPercentageProvider), beforeRetry);
  });

  test('resets estimated progress when a new sync session starts', () async {
    final firstStartedAt = DateTime.utc(2026, 8, 18);
    final initial = SyncState(
      isSyncing: true,
      phase: 'scan',
      percentage: 0.5,
      displayTargetPercentage: 0.5,
      lastSyncStartedAt: firstStartedAt,
    );
    late FakeSyncNotifier syncNotifier;
    final container = ProviderContainer(
      overrides: [
        syncProvider.overrideWith(
          () => syncNotifier = FakeSyncNotifier(initial),
        ),
      ],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      syncDisplayPercentageProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    await container.read(syncProvider.future);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(syncDisplayPercentageProvider), closeTo(0.52, 0.001));

    syncNotifier.emit(
      SyncState(
        isSyncing: true,
        phase: kSyncPhasePreflight,
        lastSyncStartedAt: firstStartedAt.add(const Duration(minutes: 1)),
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(container.read(syncDisplayPercentageProvider), 0);
  });

  test('interpolates without republishing SyncState', () async {
    final initial = SyncState(
      isSyncing: true,
      percentage: 0.2,
      displayTargetPercentage: 0.3,
      displayTargetBlocks: 10,
    );
    late FakeSyncNotifier syncNotifier;
    final container = ProviderContainer(
      overrides: [
        syncProvider.overrideWith(
          () => syncNotifier = FakeSyncNotifier(initial),
        ),
      ],
    );
    addTearDown(container.dispose);
    final displaySubscription = container.listen(
      syncDisplayPercentageProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(displaySubscription.close);
    await container.read(syncProvider.future);
    await Future<void>.delayed(Duration.zero);

    var syncUpdates = 0;
    final syncSubscription = container.listen(syncProvider, (_, _) {
      syncUpdates += 1;
    });
    addTearDown(syncSubscription.close);

    expect(container.read(syncDisplayPercentageProvider), 0.2);
    await Future<void>.delayed(const Duration(milliseconds: 110));

    expect(container.read(syncDisplayPercentageProvider), closeTo(0.25, 0.011));
    expect(container.read(syncProvider).requireValue.percentage, 0.2);
    expect(syncUpdates, 0);

    syncNotifier.emit(
      initial.copyWith(
        isSyncing: false,
        isSyncComplete: true,
        percentage: 1,
        displayTargetPercentage: 1,
        displayTargetBlocks: 0,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(container.read(syncDisplayPercentageProvider), 1);
  });

  test('whole percentage notifies only when its label changes', () async {
    final initial = SyncState(
      isSyncing: true,
      percentage: 0.2,
      displayTargetPercentage: 0.3,
      displayTargetBlocks: 100,
    );
    final container = ProviderContainer(
      overrides: [syncProvider.overrideWith(() => FakeSyncNotifier(initial))],
    );
    addTearDown(container.dispose);
    var updates = 0;
    final subscription = container.listen(
      syncDisplayWholePercentageProvider,
      (_, _) => updates += 1,
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    await container.read(syncProvider.future);
    await Future<void>.delayed(Duration.zero);
    final initialUpdates = updates;

    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(container.read(syncDisplayWholePercentageProvider), 20);
    expect(updates, initialUpdates);
  });
}
