import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/sync_failure.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/providers/sync_short_catch_up_provider.dart';
import 'package:zcash_wallet/src/rust/frb_generated.dart';

import '../fakes/fake_sync_notifier.dart';

void main() {
  setUpAll(() => RustLib.initMock(api: _RustApi()));

  group('isShortSyncCatchUp', () {
    final now = DateTime(2026, 10, 20, 19);

    test('a synced wallet catching up a few blocks is short', () {
      expect(
        isShortSyncCatchUp(
          _catchUp(startedAt: now, remainingScanBlocks: 4),
          now: now,
        ),
        isTrue,
      );
      // Preparation, before the attempt has enumerated its scan queue.
      expect(
        isShortSyncCatchUp(
          _catchUp(startedAt: now, phase: kSyncPhasePreflight),
          now: now,
        ),
        isTrue,
      );
    });

    test('more blocks than the limit are not short', () {
      expect(
        isShortSyncCatchUp(
          _catchUp(
            startedAt: now,
            remainingScanBlocks: kSyncShortCatchUpMaxBlocks,
          ),
          now: now,
        ),
        isTrue,
      );
      expect(
        isShortSyncCatchUp(
          _catchUp(
            startedAt: now,
            remainingScanBlocks: kSyncShortCatchUpMaxBlocks + 1,
          ),
          now: now,
        ),
        isFalse,
      );
    });

    test('the gap to the tip counts until the scan queue is known', () {
      expect(
        isShortSyncCatchUp(
          _catchUp(
            startedAt: now,
            chainTipHeight: _completedHeight + kSyncShortCatchUpMaxBlocks,
          ),
          now: now,
        ),
        isTrue,
      );
      expect(
        isShortSyncCatchUp(
          _catchUp(
            startedAt: now,
            chainTipHeight: _completedHeight + kSyncShortCatchUpMaxBlocks + 1,
          ),
          now: now,
        ),
        isFalse,
      );
    });

    test('running for the time limit is not short', () {
      final justShort = now.subtract(
        kSyncShortCatchUpMaxDuration - const Duration(milliseconds: 1),
      );
      final atLimit = now.subtract(kSyncShortCatchUpMaxDuration);
      expect(
        isShortSyncCatchUp(
          _catchUp(startedAt: justShort, remainingScanBlocks: 4),
          now: now,
        ),
        isTrue,
      );
      expect(
        isShortSyncCatchUp(
          _catchUp(startedAt: atLimit, remainingScanBlocks: 4),
          now: now,
        ),
        isFalse,
      );
    });

    test('only a sync started from a completed one can be short', () {
      // A new wallet's first sync: few blocks, but it never completed.
      expect(
        isShortSyncCatchUp(
          _catchUp(
            startedAt: now,
            remainingScanBlocks: 4,
            startedFromCompletedSync: false,
          ),
          now: now,
        ),
        isFalse,
      );
      // A restore scans the tip first: the scanned height reaches the tip
      // while the history is still pending, or not yet enumerated.
      for (final remaining in [null, 2000000]) {
        expect(
          isShortSyncCatchUp(
            _catchUp(
              startedAt: now,
              scannedHeight: _completedHeight + 4,
              chainTipHeight: _completedHeight + 4,
              remainingScanBlocks: remaining,
              startedFromCompletedSync: false,
            ),
            now: now,
          ),
          isFalse,
        );
      }
      // A catch-up that turns out to include history (an added account).
      expect(
        isShortSyncCatchUp(
          _catchUp(startedAt: now, remainingScanBlocks: 2000000),
          now: now,
        ),
        isFalse,
      );
    });

    test('checking, a failure, a stop and a background run are not short', () {
      final checking = _catchUp(
        startedAt: now,
        remainingScanBlocks: 4,
        checking: const SyncCheckingProgress(
          cycle: 1,
          percentage: 0,
          displayTargetPercentage: 0.5,
        ),
      );
      final failed = _catchUp(
        startedAt: now,
        remainingScanBlocks: 4,
        failure: classifySyncFailure(StateError('connection refused')),
      );
      final stopped = _catchUp(
        startedAt: now,
        remainingScanBlocks: 4,
        isSyncing: false,
      );
      final background = _catchUp(
        startedAt: now,
        remainingScanBlocks: 4,
        isBackgroundMode: true,
      );
      for (final sync in [checking, failed, stopped, background]) {
        expect(isShortSyncCatchUp(sync, now: now), isFalse);
      }
    });
  });

  group('syncShortCatchUpProvider', () {
    test('shows progress once the time limit passes', () async {
      final startedAt = DateTime.now().subtract(
        kSyncShortCatchUpMaxDuration - const Duration(milliseconds: 500),
      );
      final container = _container(
        _catchUp(startedAt: startedAt, remainingScanBlocks: 4),
      );
      await container.read(syncProvider.future);

      expect(container.read(syncShortCatchUpProvider), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 800));
      expect(container.read(syncShortCatchUpProvider), isFalse);
    });

    test('keeps showing progress for the rest of that attempt', () async {
      final startedAt = DateTime.now();
      late FakeSyncNotifier sync;
      final container = _container(
        _catchUp(startedAt: startedAt, remainingScanBlocks: 5000),
        onCreate: (notifier) => sync = notifier,
      );
      await container.read(syncProvider.future);
      expect(container.read(syncShortCatchUpProvider), isFalse);

      // Scanned below the block limit within the time limit: still shown.
      sync.emit(_catchUp(startedAt: startedAt, remainingScanBlocks: 400));
      expect(container.read(syncShortCatchUpProvider), isFalse);

      // The next catch-up, after this one completed, starts short again.
      sync.emit(
        SyncState(
          isSyncComplete: true,
          scannedHeight: _completedHeight,
          chainTipHeight: _completedHeight,
          lastSyncStartedAt: startedAt,
        ),
      );
      expect(container.read(syncShortCatchUpProvider), isFalse);
      sync.emit(
        _catchUp(
          startedAt: startedAt.add(const Duration(seconds: 1)),
          remainingScanBlocks: 4,
        ),
      );
      expect(container.read(syncShortCatchUpProvider), isTrue);
    });
    test('a restart of a catch-up that showed progress is not short', () async {
      final startedAt = DateTime.now();
      late FakeSyncNotifier sync;
      final container = _container(
        _catchUp(startedAt: startedAt, remainingScanBlocks: 5000),
        onCreate: (notifier) => sync = notifier,
      );
      await container.read(syncProvider.future);
      expect(container.read(syncShortCatchUpProvider), isFalse);

      // The first event names the job.
      sync.emit(
        _catchUp(
          startedAt: startedAt,
          remainingScanBlocks: 4000,
          syncJobId: 'job-1',
        ),
      );
      expect(container.read(syncShortCatchUpProvider), isFalse);

      // An endpoint fallback or a retry resumes the job with 800 blocks
      // left, before the scan queue is known: still the same catch-up.
      final restartedAt = startedAt.add(const Duration(seconds: 1));
      sync.emit(
        _catchUp(
          startedAt: restartedAt,
          scannedHeight: _completedHeight,
          chainTipHeight: _completedHeight + 800,
          syncJobId: 'job-1',
        ),
      );
      expect(container.read(syncShortCatchUpProvider), isFalse);
      sync.emit(
        _catchUp(
          startedAt: restartedAt,
          remainingScanBlocks: 800,
          syncJobId: 'job-1',
        ),
      );
      expect(container.read(syncShortCatchUpProvider), isFalse);

      // The next catch-up, a new job after a completion, starts short.
      sync.emit(
        SyncState(
          isSyncComplete: true,
          scannedHeight: _completedHeight,
          chainTipHeight: _completedHeight,
          lastSyncStartedAt: restartedAt,
        ),
      );
      final nextAt = restartedAt.add(const Duration(seconds: 1));
      sync.emit(_catchUp(startedAt: nextAt, remainingScanBlocks: 4));
      expect(container.read(syncShortCatchUpProvider), isTrue);
      sync.emit(
        _catchUp(startedAt: nextAt, remainingScanBlocks: 4, syncJobId: 'job-2'),
      );
      expect(container.read(syncShortCatchUpProvider), isTrue);
    });
  });

  group('a sync start', () {
    test('from a completed sync is a short catch-up', () async {
      final (container, notifier) = await _startedFrom(
        SyncState(
          accountUuid: 'account-1',
          isSyncComplete: true,
          percentage: 1,
          scannedHeight: _completedHeight,
          chainTipHeight: _completedHeight,
          remainingScanBlocks: 0,
        ),
      );

      final preparing = container.read(syncProvider).requireValue;
      expect(preparing.isSyncing, isTrue);
      expect(preparing.startedFromCompletedSync, isTrue);
      expect(isShortSyncCatchUp(preparing, now: DateTime.now()), isTrue);

      // Scan progress keeps it.
      await notifier.handleSyncProgressForTesting(_scanning(remaining: 4));
      final scanning = container.read(syncProvider).requireValue;
      expect(scanning.remainingScanBlocks, 4);
      expect(scanning.startedFromCompletedSync, isTrue);
      expect(isShortSyncCatchUp(scanning, now: DateTime.now()), isTrue);
    });

    test('from an unfinished sync is not a catch-up', () async {
      // A restore that stopped after scanning the tip first: its scanned
      // height reaches the tip, but it never completed.
      final (container, notifier) = await _startedFrom(
        SyncState(
          accountUuid: 'account-1',
          percentage: 0.4,
          syncJobId: 'job-1',
          scannedHeight: _completedHeight,
          chainTipHeight: _completedHeight,
        ),
      );

      final preparing = container.read(syncProvider).requireValue;
      expect(preparing.isSyncing, isTrue);
      expect(preparing.startedFromCompletedSync, isFalse);
      expect(isShortSyncCatchUp(preparing, now: DateTime.now()), isFalse);

      await notifier.handleSyncProgressForTesting(_scanning(remaining: 4));
      final scanning = container.read(syncProvider).requireValue;
      expect(scanning.remainingScanBlocks, 4);
      expect(scanning.startedFromCompletedSync, isFalse);
    });

    test('after a wallet reset starts from zero', () async {
      final unfinished = SyncState(
        accountUuid: 'account-1',
        percentage: 0.4,
        syncJobId: 'job-1',
        scannedHeight: 2000000,
        chainTipHeight: _completedHeight,
      );
      final (resumed, _) = await _startedFrom(unfinished);
      expect(resumed.read(syncProvider).requireValue.syncJobId, 'job-1');
      expect(resumed.read(syncProvider).requireValue.percentage, 0.4);

      final (container, _) = await _startedFrom(
        unfinished,
        beforeStart: (notifier) => notifier.handleWalletResetForTesting(),
      );
      final preparing = container.read(syncProvider).requireValue;
      expect(preparing.isSyncing, isTrue);
      expect(preparing.syncJobId, isEmpty);
      expect(preparing.percentage, 0);
      expect(preparing.sessionStartPercentage, 0);
    });
  });
}

const _completedHeight = 3000000;

SyncState _catchUp({
  required DateTime startedAt,
  int? remainingScanBlocks,
  int scannedHeight = _completedHeight,
  int chainTipHeight = _completedHeight + 4,
  bool startedFromCompletedSync = true,
  bool isSyncing = true,
  bool isBackgroundMode = false,
  String phase = 'scan',
  SyncCheckingProgress? checking,
  SyncFailure? failure,
  String syncJobId = '',
}) => SyncState(
  syncJobId: syncJobId,
  isSyncing: isSyncing,
  isBackgroundMode: isBackgroundMode,
  remainingScanBlocks: remainingScanBlocks,
  scannedHeight: scannedHeight,
  chainTipHeight: chainTipHeight,
  checking: checking,
  failure: failure,
  lastSyncStartedAt: startedAt,
  phase: phase,
  startedFromCompletedSync: startedFromCompletedSync,
);

ProviderContainer _container(
  SyncState initial, {
  void Function(FakeSyncNotifier notifier)? onCreate,
}) {
  final container = ProviderContainer(
    overrides: [
      syncProvider.overrideWith(() {
        final notifier = FakeSyncNotifier(initial);
        onCreate?.call(notifier);
        return notifier;
      }),
    ],
  );
  addTearDown(container.dispose);
  final subscription = container.listen(
    syncShortCatchUpProvider,
    (_, _) {},
    fireImmediately: true,
  );
  addTearDown(subscription.close);
  return container;
}

/// Runs a real sync start from [initial]. The start's own wallet path read
/// never resolves, so it publishes its preparing state and goes no further;
/// progress events handled afterwards read the path normally.
Future<(ProviderContainer, _StartSync)> _startedFrom(
  SyncState initial, {
  void Function(_StartSync notifier)? beforeStart,
}) async {
  final notifier = _StartSync(initial);
  final container = ProviderContainer(
    overrides: [
      appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
      accountProvider.overrideWith(_AccountNotifier.new),
      syncProvider.overrideWith(() => notifier),
    ],
  );
  addTearDown(container.dispose);
  container.listen(syncProvider, (_, _) {});
  await container.read(accountProvider.future);
  await container.read(syncProvider.future);
  beforeStart?.call(notifier);
  notifier.startSync();
  return (container, notifier);
}

/// A scan progress event, which reads nothing from Rust.
SyncProgressEvent _scanning({required int remaining}) => SyncProgressEvent(
  scannedHeight: _completedHeight + 1,
  chainTipHeight: _completedHeight + 4,
  percentage: 0.2,
  displayTargetPercentage: 0.6,
  displayTargetBlocks: 4,
  remainingScanBlocks: remaining,
  isSyncing: true,
  isComplete: false,
  hasNewTx: false,
  phase: 'scan',
  syncJobId: 'job-2',
);

class _StartSync extends SyncNotifier {
  _StartSync(this.initial) : super(walletDbPathResolver: _pathAfterFirstRead());

  final SyncState initial;

  static Future<String> Function() _pathAfterFirstRead() {
    var reads = 0;
    return () => reads++ == 0
        ? Completer<String>().future
        : Future<String>.value('wallet.db');
  }

  @override
  Future<SyncState> build() async => initial;
}

class _AccountNotifier extends AccountNotifier {
  @override
  AccountState build() => const AccountState(
    accounts: [AccountInfo(uuid: 'account-1', name: 'Account 1', order: 0)],
    activeAccountUuid: 'account-1',
  );
}

class _RustApi extends RustLibApi {
  @override
  bool crateApiSyncIsSyncRunning() => false;

  @override
  bool crateApiSyncIsMempoolObserverRunning() => false;

  @override
  void crateApiSyncSetActiveSyncAccount({String? accountUuid}) {}

  @override
  void crateApiSyncCancelFullSync() {}

  @override
  void crateApiSyncStopMempoolObserver() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
