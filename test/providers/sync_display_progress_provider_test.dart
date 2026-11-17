import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/providers/sync_display_progress_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

import '../fakes/fake_sync_notifier.dart';

void main() {
  test('a new job stays at zero through preparation', () async {
    final initial = SyncState(
      isSyncing: true,
      phase: kSyncPhasePreflight,
      lastSyncStartedAt: DateTime.utc(2026, 8, 18),
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
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(container.read(syncDisplayPercentageProvider), 0);

    // Committed preparation work moves nothing either.
    syncNotifier.emit(initial.copyWith(phase: kSyncPhaseActiveUtxo));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(container.read(syncDisplayPercentageProvider), 0);
  });

  test('a scanning job shows at least 1%', () async {
    final initial = SyncState(
      isSyncing: true,
      phase: kSyncPhaseChainPrepare,
      lastSyncStartedAt: DateTime.utc(2026, 8, 18),
      syncJobId: 'job',
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
    expect(container.read(syncDisplayPercentageProvider), 0);

    // The first scan event of a full restore holds a fraction that rounds to
    // 0%; it shows 1% from the start of the scan.
    syncNotifier.emit(
      initial.copyWith(
        phase: 'scan',
        percentage: 0.001,
        displayTargetPercentage: 0.002,
        displayTargetBlocks: 1000,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(container.read(syncDisplayPercentageProvider), 0.01);
    expect(container.read(syncDisplayWholePercentageProvider), 1);

    // Past 1% the work fraction shows as it is.
    syncNotifier.emit(
      initial.copyWith(
        phase: 'scan',
        percentage: 0.03,
        displayTargetPercentage: 0.03,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(container.read(syncDisplayPercentageProvider), 0.03);
  });

  test('maps the work fraction of the job onto 0-99 percent', () async {
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

    expect(container.read(syncDisplayPercentageProvider), 0.5);
  });

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

  test(
    'advances when a retry reports progress over the remaining work',
    () async {
      final initial = SyncState(
        isSyncing: true,
        phase: 'scan',
        percentage: 0.44,
        displayTargetPercentage: 0.44,
        lastSyncStartedAt: DateTime.utc(2026, 10, 9),
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
      expect(container.read(syncDisplayPercentageProvider), 0.44);

      syncNotifier.emit(initial.copyWith(phase: kSyncPhaseChainPrepare));
      await Future<void>.delayed(Duration.zero);
      expect(container.read(syncDisplayPercentageProvider), 0.44);

      // Rust retains 44% completed and reports 1% of the remaining 56%.
      syncNotifier.emit(
        initial.copyWith(percentage: 0.4456, displayTargetPercentage: 0.4456),
      );
      await Future<void>.delayed(Duration.zero);
      expect(container.read(syncDisplayPercentageProvider), 0.4456);
    },
  );

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
    expect(container.read(syncDisplayPercentageProvider), 0.5);

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

  group('sync jobs', () {
    final firstStartedAt = DateTime.utc(2026, 10, 10);
    final secondStartedAt = firstStartedAt.add(const Duration(minutes: 1));

    Future<(ProviderContainer, FakeSyncNotifier)> start(
      SyncState initial,
    ) async {
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
      return (container, syncNotifier);
    }

    SyncState scanState({
      required double percentage,
      required String jobId,
      DateTime? startedAt,
    }) => SyncState(
      isSyncing: true,
      phase: 'scan',
      percentage: percentage,
      displayTargetPercentage: percentage,
      lastSyncStartedAt: startedAt ?? firstStartedAt,
      syncJobId: jobId,
    );

    test('a new session of an unfinished job continues its value', () async {
      final (container, sync) = await start(
        scanState(percentage: 0.5, jobId: 'job-a'),
      );
      expect(container.read(syncDisplayPercentageProvider), 0.5);

      sync.emit(
        SyncState(
          isSyncing: true,
          phase: kSyncPhasePreflight,
          percentage: 0.5,
          lastSyncStartedAt: secondStartedAt,
          syncJobId: 'job-a',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(container.read(syncDisplayPercentageProvider), 0.5);

      sync.emit(
        scanState(percentage: 0.51, jobId: 'job-a', startedAt: secondStartedAt),
      );
      await Future<void>.delayed(Duration.zero);
      expect(container.read(syncDisplayPercentageProvider), 0.51);
    });

    test('holds until the new attempt names its job, then restarts '
        'for a different one', () async {
      final (container, sync) = await start(
        scanState(percentage: 0.5, jobId: 'job-a'),
      );

      sync.emit(
        SyncState(
          isSyncing: true,
          phase: kSyncPhasePreflight,
          lastSyncStartedAt: secondStartedAt,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(container.read(syncDisplayPercentageProvider), 0.5);

      sync.emit(
        scanState(percentage: 0, jobId: 'job-b', startedAt: secondStartedAt),
      );
      await Future<void>.delayed(Duration.zero);
      // The new job restarts the display at the 1% a scanning job shows.
      expect(container.read(syncDisplayPercentageProvider), 0.01);
    });

    test('restarts when Rust replaces the job mid-session', () async {
      final (container, sync) = await start(
        scanState(percentage: 0.5, jobId: 'job-a'),
      );

      sync.emit(scanState(percentage: 0.01, jobId: 'job-b'));
      await Future<void>.delayed(Duration.zero);

      expect(container.read(syncDisplayPercentageProvider), 0.01);
    });

    test(
      'a resumed job keeps its stored percentage through preparation',
      () async {
        final (container, _) = await start(
          SyncState(
            isSyncing: true,
            phase: kSyncPhaseActiveUtxo,
            percentage: 0.4,
            lastSyncStartedAt: firstStartedAt,
            syncJobId: 'job-a',
          ),
        );

        expect(container.read(syncDisplayPercentageProvider), 0.4);
      },
    );

    test('keeps its value between attempts', () async {
      final (container, sync) = await start(
        scanState(percentage: 0.5, jobId: 'job-a'),
      );

      sync.emit(
        SyncState(
          percentage: 0.5,
          lastSyncStartedAt: firstStartedAt,
          syncJobId: 'job-a',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(container.read(syncDisplayPercentageProvider), 0.5);
    });

    test('a relaunch with a stored job resumes where it stopped', () async {
      // The bootstrap snapshot carries the stored job and its fraction.
      final (container, sync) = await start(
        SyncState(percentage: 0.4, syncJobId: 'job-a'),
      );
      expect(container.read(syncDisplayPercentageProvider), 0.4);

      sync.emit(
        SyncState(
          isSyncing: true,
          phase: kSyncPhasePreflight,
          percentage: 0.4,
          lastSyncStartedAt: firstStartedAt,
          syncJobId: 'job-a',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(container.read(syncDisplayPercentageProvider), 0.4);
    });

    test('an idle state without a job drops the held value', () async {
      final (container, sync) = await start(
        scanState(percentage: 0.5, jobId: 'job-a'),
      );

      // Signed out or wallet reset.
      sync.emit(SyncState());
      await Future<void>.delayed(Duration.zero);

      expect(container.read(syncDisplayPercentageProvider), 0);
    });

    test(
      'a new attempt after a completion it never saw starts from zero',
      () async {
        final (container, sync) = await start(
          scanState(percentage: 1, jobId: 'job-a'),
        );
        expect(
          container.read(syncDisplayPercentageProvider),
          closeTo(0.99, 0.001),
        );

        // The job completed after its attempt started, but its completed state
        // was overtaken before this notifier saw it.
        sync.emit(
          SyncState(
            isSyncing: true,
            phase: kSyncPhasePreflight,
            lastSyncStartedAt: secondStartedAt,
            lastSyncCompletedAt: firstStartedAt.add(
              const Duration(seconds: 30),
            ),
          ),
        );
        await Future<void>.delayed(Duration.zero);
        expect(container.read(syncDisplayPercentageProvider), 0);
      },
    );

    test('a completion from before the attempt still holds its job', () async {
      final (container, sync) = await start(
        scanState(percentage: 0.5, jobId: 'job-a'),
      );

      sync.emit(
        SyncState(
          isSyncing: true,
          phase: kSyncPhasePreflight,
          lastSyncStartedAt: secondStartedAt,
          lastSyncCompletedAt: firstStartedAt.subtract(
            const Duration(minutes: 5),
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(container.read(syncDisplayPercentageProvider), 0.5);
    });

    test('a sync after a completed job starts from zero', () async {
      final (container, sync) = await start(
        scanState(percentage: 0.5, jobId: 'job-a'),
      );
      sync.emit(
        SyncState(
          isSyncComplete: true,
          percentage: 1,
          lastSyncStartedAt: firstStartedAt,
          syncJobId: 'job-a',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(container.read(syncDisplayPercentageProvider), 1);

      sync.emit(
        SyncState(
          isSyncing: true,
          phase: kSyncPhasePreflight,
          lastSyncStartedAt: secondStartedAt,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(container.read(syncDisplayPercentageProvider), 0);
    });
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
