import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';
import 'package:zcash_wallet/src/providers/sync_failure.dart';
import 'package:zcash_wallet/src/providers/sync_keep_awake_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/providers/sync_short_catch_up_provider.dart';

import '../fakes/fake_sync_notifier.dart';

void main() {
  test('keep-awake finishes with the main scan and ignores Checking', () {
    final sync = SyncState(
      isSyncing: true,
      percentage: 1,
      scannedHeight: 2000,
      chainTipHeight: 2000,
      remainingScanBlocks: 100,
      lastSyncStartedAt: DateTime.utc(2026, 10, 12),
    );
    for (final checking in [
      null,
      const SyncCheckingProgress(
        cycle: 1,
        percentage: 0,
        displayTargetPercentage: 0.25,
      ),
      const SyncCheckingProgress(
        cycle: 2,
        percentage: 0.5,
        displayTargetPercentage: 0.75,
      ),
      const SyncCheckingProgress(
        cycle: 3,
        percentage: 1,
        displayTargetPercentage: 1,
      ),
    ]) {
      final state = sync.copyWith(checking: checking);
      expect(isSyncKeepAwakeActiveSync(state), isFalse);
      expect(isSyncKeepAwakeCompletedSync(state), isTrue);
      expect(
        isSyncKeepAwakeCompletedSync(state.withSyncActivityStopped()),
        isTrue,
      );
      expect(
        shouldShowSyncKeepAwakePrompt(
          sync: state,
          settings: const SyncKeepAwakeSettings(
            enabled: false,
            promptSeen: false,
          ),
          now: state.lastSyncStartedAt!.add(const Duration(minutes: 10)),
        ),
        isFalse,
      );
    }
    expect(
      isSyncKeepAwakeCompletedSync(sync.copyWith(isBackgroundMode: true)),
      isFalse,
    );
  });

  test('settings provider starts from bootstrap keep-awake fields', () {
    final container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(
          _bootstrap(syncKeepAwakeEnabled: true, syncKeepAwakePromptSeen: true),
        ),
      ],
    );
    addTearDown(container.dispose);

    expect(
      container.read(syncKeepAwakeProvider),
      const SyncKeepAwakeSettings(enabled: true, promptSeen: true),
    );
  });

  test('a drained main scan does not stay awake during retry preparation', () {
    final sync = SyncState(
      isSyncing: true,
      percentage: 1,
      phase: kSyncPhaseChainPrepare,
      scannedHeight: 2000,
      chainTipHeight: 2000,
      lastSyncStartedAt: DateTime.utc(2026, 10, 12),
    );
    expect(isSyncKeepAwakeActiveSync(sync), isFalse);
    expect(isSyncKeepAwakeCompletedSync(sync), isTrue);
    expect(
      isSyncKeepAwakeActiveSync(sync.copyWith(remainingScanBlocks: 0)),
      isFalse,
    );
  });

  test('near-tip catch-up requires known pending work at the chain tip', () {
    expect(
      isNearTipCatchUp(_sync(scannedHeight: 100, chainTipHeight: 102)),
      isTrue,
    );
    expect(
      isNearTipCatchUp(_sync(scannedHeight: 100, chainTipHeight: 103)),
      isFalse,
    );
    expect(
      isNearTipCatchUp(_sync(scannedHeight: 0, chainTipHeight: 0)),
      isFalse,
    );
  });

  test('pending work boundaries use inclusive range starts', () {
    for (var remaining = 0; remaining <= 3; remaining++) {
      final sync = _sync(
        scannedHeight: 200,
        chainTipHeight: 200,
        remainingScanBlocks: remaining,
        pendingScanStartHeight: remaining == 0 ? null : 201 - remaining,
        lastSyncStartedAt: DateTime(2026, 7, 9, 12),
      );
      expect(isNearTipCatchUp(sync), remaining <= 2);
      expect(isSyncKeepAwakeActiveSync(sync), remaining > 2);
    }
  });

  test('tip batch and small next batch cannot hide historical work', () {
    final sync = _sync(
      scannedHeight: 2000,
      chainTipHeight: 2000,
      percentage: 0.7,
      displayTargetBlocks: 2,
      remainingScanBlocks: 102,
      pendingScanStartHeight: 1700,
      lastSyncStartedAt: DateTime(2026, 7, 9, 12),
    );
    expect(isNearTipCatchUp(sync), isFalse);
    expect(isSyncKeepAwakeActiveSync(sync), isTrue);
    expect(isSyncKeepAwakeEligibleSync(sync), isTrue);
    expect(
      shouldShowSyncKeepAwakePrompt(
        sync: sync,
        settings: const SyncKeepAwakeSettings(
          enabled: false,
          promptSeen: false,
        ),
        now: sync.lastSyncStartedAt!.add(const Duration(minutes: 5)),
      ),
      isTrue,
    );
    // Two historical blocks are not a near-tip catch-up either.
    expect(isNearTipCatchUp(sync.copyWith(remainingScanBlocks: 2)), isFalse);
  });

  test(
    'previous completed heights cannot suppress unknown preparation work',
    () {
      for (final phase in [
        kSyncPhasePreflight,
        kSyncPhaseSetup,
        kSyncPhaseActiveUtxo,
        kSyncPhaseChainPrepare,
      ]) {
        final sync = _sync(
          scannedHeight: 2000,
          chainTipHeight: 2000,
          percentage: 0,
          phase: phase,
          scanWorkKnown: false,
          lastSyncStartedAt: DateTime(2026, 7, 9, 12),
        );
        expect(isNearTipCatchUp(sync), isFalse);
        expect(isSyncKeepAwakeActiveSync(sync), isTrue, reason: phase);
      }
    },
  );

  test('screen keep-awake requires enabled settings and substantial work', () {
    final startedAt = DateTime(2026, 7, 9, 12);
    const enabled = SyncKeepAwakeSettings(enabled: true, promptSeen: true);
    const disabled = SyncKeepAwakeSettings(enabled: false, promptSeen: true);
    final eligibleSync = _sync(lastSyncStartedAt: startedAt);

    expect(
      shouldKeepScreenAwakeForSync(settings: enabled, sync: eligibleSync),
      isTrue,
    );
    expect(
      shouldKeepScreenAwakeForSync(settings: disabled, sync: eligibleSync),
      isFalse,
    );
    expect(
      shouldKeepScreenAwakeForSync(
        settings: enabled,
        sync: _sync(
          scannedHeight: 100,
          chainTipHeight: 102,
          lastSyncStartedAt: startedAt,
        ),
      ),
      isFalse,
    );
    expect(
      shouldKeepScreenAwakeForSync(
        settings: enabled,
        sync: _sync(percentage: 0, lastSyncStartedAt: startedAt),
      ),
      isTrue,
    );
    expect(
      shouldKeepScreenAwakeForSync(
        settings: enabled,
        sync: _sync(
          percentage: 0,
          displayTargetBlocks: 100,
          scannedHeight: 0,
          chainTipHeight: 0,
          lastSyncStartedAt: startedAt,
        ),
      ),
      isTrue,
    );
    expect(
      shouldKeepScreenAwakeForSync(
        settings: enabled,
        sync: _sync(
          percentage: 0,
          displayTargetBlocks: 2,
          scannedHeight: 0,
          chainTipHeight: 0,
          lastSyncStartedAt: startedAt,
        ),
      ),
      isTrue,
    );
    expect(
      shouldKeepScreenAwakeForSync(
        settings: enabled,
        sync: _sync(
          percentage: 0,
          displayTargetBlocks: 100,
          scannedHeight: 100,
          chainTipHeight: 102,
          lastSyncStartedAt: startedAt,
        ),
      ),
      isFalse,
    );
  });

  test('screen keep-awake covers progress discovery during sync startup', () {
    final startedAt = DateTime(2026, 7, 9, 12);
    const settings = SyncKeepAwakeSettings(enabled: true, promptSeen: true);

    for (final phase in [
      kSyncPhasePreflight,
      kSyncPhaseSetup,
      kSyncPhaseActiveUtxo,
      kSyncPhaseChainPrepare,
    ]) {
      expect(
        shouldKeepScreenAwakeForSync(
          settings: settings,
          sync: _sync(
            percentage: 0,
            displayTargetBlocks: 0,
            scannedHeight: 0,
            chainTipHeight: 0,
            lastSyncStartedAt: startedAt,
            phase: phase,
          ),
        ),
        isTrue,
        reason: 'foreground $phase should stay awake before progress arrives',
      );
    }

    expect(
      shouldKeepScreenAwakeForSync(
        settings: settings,
        sync: _sync(
          isBackgroundMode: true,
          percentage: 0,
          lastSyncStartedAt: startedAt,
          phase: kSyncPhasePreflight,
        ),
      ),
      isFalse,
    );
  });

  test('preparation phases preserve the known near-tip exclusion', () {
    final startedAt = DateTime(2026, 7, 9, 12);
    const settings = SyncKeepAwakeSettings(enabled: true, promptSeen: true);

    for (final phase in [
      kSyncPhasePreflight,
      kSyncPhaseSetup,
      kSyncPhaseActiveUtxo,
      kSyncPhaseChainPrepare,
    ]) {
      expect(
        shouldKeepScreenAwakeForSync(
          settings: settings,
          sync: _sync(
            percentage: 0,
            scannedHeight: 100,
            chainTipHeight: 102,
            lastSyncStartedAt: startedAt,
            phase: phase,
          ),
        ),
        isFalse,
        reason: 'known near-tip $phase should not keep the screen awake',
      );
      expect(
        shouldKeepScreenAwakeForSync(
          settings: settings,
          sync: _sync(
            percentage: 0,
            scannedHeight: 100,
            chainTipHeight: 103,
            lastSyncStartedAt: startedAt,
            phase: phase,
          ),
        ),
        isTrue,
        reason: '$phase with more than two blocks should stay awake',
      );
    }
  });

  test(
    'screen keep-awake active provider combines settings and sync state',
    () async {
      final container = ProviderContainer(
        overrides: [
          appBootstrapProvider.overrideWithValue(
            _bootstrap(
              syncKeepAwakeEnabled: true,
              syncKeepAwakePromptSeen: true,
            ),
          ),
          syncProvider.overrideWith(
            () => FakeSyncNotifier(
              _sync(lastSyncStartedAt: DateTime(2026, 7, 9, 12)),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(syncKeepAwakeActiveProvider), isFalse);
      await container.read(syncProvider.future);
      expect(container.read(syncKeepAwakeActiveProvider), isTrue);
    },
  );

  test('screen keep-awake active provider stays false while locked', () async {
    final container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(
          _bootstrap(
            syncKeepAwakeEnabled: true,
            syncKeepAwakePromptSeen: true,
            isPasswordConfigured: true,
            isUnlocked: false,
          ),
        ),
        syncProvider.overrideWith(
          () => FakeSyncNotifier(
            _sync(lastSyncStartedAt: DateTime(2026, 7, 9, 12)),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(syncProvider.future);
    expect(container.read(syncKeepAwakeActiveProvider), isFalse);
  });

  test('screen keep-awake stays off for a synced wallet\'s short catch-up, '
      'and comes on past it or for a sync that is not a catch-up', () async {
    const settings = SyncKeepAwakeSettings(enabled: true, promptSeen: true);
    final startedAt = DateTime.now();
    // A catch-up preparing, before its scan queue is known.
    final catchUp = _sync(
      percentage: 0,
      scannedHeight: 200,
      chainTipHeight: 204,
      lastSyncStartedAt: startedAt,
      phase: kSyncPhasePreflight,
      scanWorkKnown: false,
      startedFromCompletedSync: true,
    );
    final syncNotifier = FakeSyncNotifier(catchUp);
    final container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(
          _bootstrap(
            syncKeepAwakeEnabled: true,
            syncKeepAwakePromptSeen: true,
            isPasswordConfigured: true,
            isUnlocked: true,
          ),
        ),
        syncProvider.overrideWith(() => syncNotifier),
      ],
    );
    addTearDown(container.dispose);
    await container.read(syncProvider.future);

    // The per-state rule alone keeps unknown scan work awake.
    expect(
      shouldKeepScreenAwakeForSync(settings: settings, sync: catchUp),
      isTrue,
    );
    expect(container.read(syncKeepAwakeActiveProvider), isFalse);

    // Past 1,000 blocks, the catch-up keeps the screen awake.
    syncNotifier.emit(
      _sync(
        percentage: 0.1,
        scannedHeight: 200,
        chainTipHeight: 5200,
        lastSyncStartedAt: startedAt,
        phase: 'scan',
        startedFromCompletedSync: true,
      ),
    );
    expect(container.read(syncKeepAwakeActiveProvider), isTrue);

    // A sync that did not start from a completed one (a restore, a wallet
    // that never completed) keeps it awake from the start.
    syncNotifier.emit(
      _sync(
        percentage: 0,
        scannedHeight: 200,
        chainTipHeight: 204,
        lastSyncStartedAt: startedAt.add(const Duration(seconds: 1)),
        phase: kSyncPhasePreflight,
        scanWorkKnown: false,
      ),
    );
    expect(container.read(syncKeepAwakeActiveProvider), isTrue);
  });

  test('privacy lock mode shows done after a locked sync completes', () async {
    final syncNotifier = FakeSyncNotifier(
      _sync(lastSyncStartedAt: DateTime(2026, 7, 9, 12)),
    );
    final container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(
          _bootstrap(
            syncKeepAwakeEnabled: true,
            syncKeepAwakePromptSeen: true,
            isPasswordConfigured: true,
            isUnlocked: true,
          ),
        ),
        syncProvider.overrideWith(() => syncNotifier),
      ],
    );
    addTearDown(container.dispose);

    await container.read(syncProvider.future);
    container
        .read(syncKeepAwakePrivacyLockProvider.notifier)
        .lock(at: DateTime(2026, 7, 9, 12, 1));

    expect(
      container.read(syncKeepAwakePrivacyLockModeProvider),
      SyncKeepAwakePrivacyLockMode.syncing,
    );

    syncNotifier.emit(
      _sync(
        isSyncing: false,
        percentage: 1,
        scannedHeight: 200,
        chainTipHeight: 200,
        lastSyncStartedAt: DateTime(2026, 7, 9, 12),
      ),
    );

    expect(container.read(syncKeepAwakeActiveProvider), isFalse);
    expect(
      container.read(syncKeepAwakePrivacyLockModeProvider),
      SyncKeepAwakePrivacyLockMode.done,
    );
    expect(container.read(syncKeepAwakePrivacyLockVisibleProvider), isTrue);
  });

  test(
    'privacy lock mode shows interrupted when locked sync stops early',
    () async {
      final syncNotifier = FakeSyncNotifier(
        _sync(lastSyncStartedAt: DateTime(2026, 7, 9, 12)),
      );
      final container = ProviderContainer(
        overrides: [
          appBootstrapProvider.overrideWithValue(
            _bootstrap(
              syncKeepAwakeEnabled: true,
              syncKeepAwakePromptSeen: true,
              isPasswordConfigured: true,
              isUnlocked: true,
            ),
          ),
          syncProvider.overrideWith(() => syncNotifier),
        ],
      );
      addTearDown(container.dispose);

      await container.read(syncProvider.future);
      container
          .read(syncKeepAwakePrivacyLockProvider.notifier)
          .lock(at: DateTime(2026, 7, 9, 12, 1));

      syncNotifier.emit(
        _sync(
          isSyncing: false,
          percentage: 0.5,
          scannedHeight: 150,
          chainTipHeight: 200,
          lastSyncStartedAt: DateTime(2026, 7, 9, 12),
        ),
      );

      expect(container.read(syncKeepAwakeActiveProvider), isFalse);
      expect(container.read(syncKeepAwakePrivacyLockVisibleProvider), isTrue);
      expect(
        container.read(syncKeepAwakePrivacyLockModeProvider),
        SyncKeepAwakePrivacyLockMode.interrupted,
      );
    },
  );

  test(
    'privacy lock mode stays latched across near-tip follow-up syncs',
    () async {
      final syncNotifier = FakeSyncNotifier(
        _sync(lastSyncStartedAt: DateTime(2026, 7, 9, 12)),
      );
      final container = ProviderContainer(
        overrides: [
          appBootstrapProvider.overrideWithValue(
            _bootstrap(
              syncKeepAwakeEnabled: true,
              syncKeepAwakePromptSeen: true,
              isPasswordConfigured: true,
              isUnlocked: true,
            ),
          ),
          syncProvider.overrideWith(() => syncNotifier),
        ],
      );
      addTearDown(container.dispose);

      await container.read(syncProvider.future);
      container
          .read(syncKeepAwakePrivacyLockProvider.notifier)
          .lock(at: DateTime(2026, 7, 9, 12, 1));
      syncNotifier.emit(
        _sync(
          isSyncing: false,
          percentage: 1,
          scannedHeight: 200,
          chainTipHeight: 200,
          lastSyncStartedAt: DateTime(2026, 7, 9, 12),
        ),
      );

      expect(
        container.read(syncKeepAwakePrivacyLockModeProvider),
        SyncKeepAwakePrivacyLockMode.done,
      );

      syncNotifier.emit(
        _sync(
          percentage: 0,
          scannedHeight: 200,
          chainTipHeight: 202,
          lastSyncStartedAt: DateTime(2026, 7, 9, 12, 2),
        ),
      );

      expect(container.read(syncKeepAwakeActiveProvider), isFalse);
      expect(container.read(syncKeepAwakePrivacyLockVisibleProvider), isTrue);
      expect(
        container.read(syncKeepAwakePrivacyLockModeProvider),
        SyncKeepAwakePrivacyLockMode.syncing,
      );

      syncNotifier.emit(
        _sync(
          isSyncing: false,
          percentage: 1,
          scannedHeight: 202,
          chainTipHeight: 202,
          lastSyncStartedAt: DateTime(2026, 7, 9, 12, 2),
        ),
      );

      expect(container.read(syncKeepAwakePrivacyLockVisibleProvider), isTrue);
      expect(
        container.read(syncKeepAwakePrivacyLockModeProvider),
        SyncKeepAwakePrivacyLockMode.done,
      );
    },
  );

  test('privacy lock mode stays done through a short catch-up of the synced '
      'wallet', () async {
    final syncNotifier = FakeSyncNotifier(
      _sync(lastSyncStartedAt: DateTime(2026, 7, 9, 12)),
    );
    final container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(
          _bootstrap(
            syncKeepAwakeEnabled: true,
            syncKeepAwakePromptSeen: true,
            isPasswordConfigured: true,
            isUnlocked: true,
          ),
        ),
        syncProvider.overrideWith(() => syncNotifier),
      ],
    );
    addTearDown(container.dispose);

    await container.read(syncProvider.future);
    container
        .read(syncKeepAwakePrivacyLockProvider.notifier)
        .lock(at: DateTime(2026, 7, 9, 12, 1));
    syncNotifier.emit(
      _sync(
        isSyncing: false,
        percentage: 1,
        scannedHeight: 200,
        chainTipHeight: 200,
        lastSyncStartedAt: DateTime(2026, 7, 9, 12),
      ),
    );
    expect(
      container.read(syncKeepAwakePrivacyLockModeProvider),
      SyncKeepAwakePrivacyLockMode.done,
    );

    final startedAt = DateTime.now();
    syncNotifier.emit(
      _sync(
        percentage: 0,
        scannedHeight: 200,
        chainTipHeight: 204,
        lastSyncStartedAt: startedAt,
        phase: kSyncPhasePreflight,
        scanWorkKnown: false,
        startedFromCompletedSync: true,
      ),
    );
    expect(
      container.read(syncKeepAwakePrivacyLockModeProvider),
      SyncKeepAwakePrivacyLockMode.done,
    );

    // The catch-up turns out large: "Sync Complete" stays until it ends
    // rather than flash to the ring and back.
    syncNotifier.emit(
      _sync(
        percentage: 0.1,
        scannedHeight: 200,
        chainTipHeight: 5200,
        lastSyncStartedAt: startedAt,
        phase: 'scan',
        startedFromCompletedSync: true,
      ),
    );
    expect(
      container.read(syncKeepAwakePrivacyLockModeProvider),
      SyncKeepAwakePrivacyLockMode.done,
    );

    syncNotifier.emit(
      _sync(
        isSyncing: false,
        percentage: 1,
        scannedHeight: 5200,
        chainTipHeight: 5200,
        lastSyncStartedAt: startedAt,
        startedFromCompletedSync: true,
      ),
    );
    expect(
      container.read(syncKeepAwakePrivacyLockModeProvider),
      SyncKeepAwakePrivacyLockMode.done,
    );

    // A later attempt that is large from its start shows its progress.
    syncNotifier.emit(
      _sync(
        percentage: 0.1,
        scannedHeight: 5200,
        chainTipHeight: 12000,
        lastSyncStartedAt: startedAt.add(const Duration(minutes: 5)),
        phase: 'scan',
        startedFromCompletedSync: true,
      ),
    );
    expect(
      container.read(syncKeepAwakePrivacyLockModeProvider),
      SyncKeepAwakePrivacyLockMode.syncing,
    );
  });

  test('privacy lock mode shows the ring for a catch-up past its short '
      'limits when the lock comes up after "Sync Complete" was gone', () async {
    final startedAt = DateTime.now();
    SyncState catchUp(int chainTipHeight) => _sync(
      percentage: 0.1,
      scannedHeight: 200,
      chainTipHeight: chainTipHeight,
      lastSyncStartedAt: startedAt,
      phase: 'scan',
      startedFromCompletedSync: true,
    );
    final syncNotifier = FakeSyncNotifier(catchUp(204));
    final container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(
          _bootstrap(
            syncKeepAwakeEnabled: true,
            syncKeepAwakePromptSeen: true,
            isPasswordConfigured: true,
            isUnlocked: true,
          ),
        ),
        syncProvider.overrideWith(() => syncNotifier),
      ],
    );
    addTearDown(container.dispose);
    await container.read(syncProvider.future);
    expect(container.read(syncShortCatchUpProvider), isTrue);
    expect(
      container.read(syncKeepAwakePrivacyLockModeProvider),
      SyncKeepAwakePrivacyLockMode.hidden,
    );

    // The catch-up outgrows its limits while unlocked, then the lock comes
    // up: there was no "Sync Complete" to keep.
    syncNotifier.emit(catchUp(5200));
    container
        .read(syncKeepAwakePrivacyLockProvider.notifier)
        .lock(at: DateTime.now());
    expect(
      container.read(syncKeepAwakePrivacyLockModeProvider),
      SyncKeepAwakePrivacyLockMode.syncing,
    );
  });

  test('privacy lock keeps the ring and the screen awake when a catch-up '
      'that showed progress restarts with few blocks left', () async {
    final startedAt = DateTime.now();
    SyncState catchUp({
      required DateTime at,
      required int scannedHeight,
      String phase = 'scan',
    }) => _sync(
      percentage: 0.84,
      scannedHeight: scannedHeight,
      chainTipHeight: 5200,
      lastSyncStartedAt: at,
      phase: phase,
      startedFromCompletedSync: true,
      syncJobId: 'job-1',
    );
    final syncNotifier = FakeSyncNotifier(
      catchUp(at: startedAt, scannedHeight: 1200),
    );
    final container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(
          _bootstrap(
            syncKeepAwakeEnabled: true,
            syncKeepAwakePromptSeen: true,
            isPasswordConfigured: true,
            isUnlocked: true,
          ),
        ),
        syncProvider.overrideWith(() => syncNotifier),
      ],
    );
    addTearDown(container.dispose);
    await container.read(syncProvider.future);
    container
        .read(syncKeepAwakePrivacyLockProvider.notifier)
        .lock(at: DateTime.now());
    expect(container.read(syncKeepAwakeActiveProvider), isTrue);
    expect(
      container.read(syncKeepAwakePrivacyLockModeProvider),
      SyncKeepAwakePrivacyLockMode.syncing,
    );

    // An endpoint fallback restarts the job with 800 blocks left.
    syncNotifier.emit(
      catchUp(
        at: startedAt.add(const Duration(minutes: 3)),
        scannedHeight: 4400,
        phase: kSyncPhasePreflight,
      ),
    );
    expect(container.read(syncShortCatchUpProvider), isFalse);
    expect(container.read(syncKeepAwakeActiveProvider), isTrue);
    expect(
      container.read(syncKeepAwakePrivacyLockModeProvider),
      SyncKeepAwakePrivacyLockMode.syncing,
    );
  });

  test('interaction notifier records the last user activity time', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final first = DateTime(2026, 7, 9, 12);
    final second = first.add(const Duration(seconds: 2));

    container
        .read(syncKeepAwakeInteractionProvider.notifier)
        .markInteraction(at: first);
    expect(
      container.read(syncKeepAwakeInteractionProvider).lastInteractionAt,
      first,
    );
    expect(container.read(syncKeepAwakeInteractionProvider).revision, 1);

    container
        .read(syncKeepAwakeInteractionProvider.notifier)
        .markInteraction(at: second);
    final state = container.read(syncKeepAwakeInteractionProvider);
    expect(state.lastInteractionAt, second);
    expect(state.revision, 2);
    expect(
      state.idleDuration(second.add(const Duration(seconds: 3))),
      const Duration(seconds: 3),
    );
  });

  test('privacy lock provider tracks virtual lock and unlock activity', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final lockedAt = DateTime(2026, 7, 9, 12);
    final unlockedAt = lockedAt.add(const Duration(seconds: 5));

    container
        .read(syncKeepAwakePrivacyLockProvider.notifier)
        .lock(at: lockedAt);
    expect(
      container.read(syncKeepAwakePrivacyLockProvider),
      SyncKeepAwakePrivacyLockState(isLocked: true, lockedAt: lockedAt),
    );

    container
        .read(syncKeepAwakePrivacyLockProvider.notifier)
        .unlock(at: unlockedAt);

    expect(
      container.read(syncKeepAwakePrivacyLockProvider),
      const SyncKeepAwakePrivacyLockState.unlocked(),
    );
    expect(
      container.read(syncKeepAwakeInteractionProvider).lastInteractionAt,
      unlockedAt,
    );
  });

  test('ETA is not estimated for ineligible sync states', () {
    final startedAt = DateTime(2026, 7, 9, 12);
    final now = startedAt.add(const Duration(seconds: 30));
    final zeroProgressSync = _sync(
      percentage: 0,
      displayTargetBlocks: 100,
      lastSyncStartedAt: startedAt,
    );

    expect(
      estimateSyncKeepAwakeEta(zeroProgressSync, now: now).remaining,
      isNull,
    );
    expect(canEstimateSyncKeepAwakeEta(zeroProgressSync), isFalse);
    expect(
      shouldShowSyncKeepAwakePrompt(
        sync: zeroProgressSync,
        settings: const SyncKeepAwakeSettings(
          enabled: false,
          promptSeen: false,
        ),
        now: now,
      ),
      isFalse,
    );
    expect(
      estimateSyncKeepAwakeEta(
        _sync(
          isBackgroundMode: true,
          percentage: 0.25,
          lastSyncStartedAt: startedAt,
        ),
        now: now,
      ).remaining,
      isNull,
    );
    expect(
      estimateSyncKeepAwakeEta(
        _sync(
          percentage: 0.25,
          scannedHeight: 100,
          chainTipHeight: 102,
          lastSyncStartedAt: startedAt,
        ),
        now: now,
      ).remaining,
      isNull,
    );
  });

  test('ETA falls back to elapsed run percentage without samples', () {
    final startedAt = DateTime(2026, 7, 9, 12);
    final now = startedAt.add(const Duration(seconds: 30));

    final estimate = estimateSyncKeepAwakeEta(
      _sync(percentage: 0.25, lastSyncStartedAt: startedAt),
      now: now,
    );

    expect(estimate.remaining, const Duration(seconds: 90));
    expect(estimate.sample, isNull);
  });

  test('ETA of a resumed job counts only this session\'s progress', () {
    final startedAt = DateTime(2026, 7, 9, 12);
    final now = startedAt.add(const Duration(seconds: 30));

    // The job resumed at 40% and reached 50% in 30 seconds: 50% left at
    // that rate is 150 seconds, not the 30 seconds a 0% start would imply.
    final estimate = estimateSyncKeepAwakeEta(
      _sync(
        percentage: 0.5,
        sessionStartPercentage: 0.4,
        lastSyncStartedAt: startedAt,
      ),
      now: now,
    );
    expect(estimate.remaining, const Duration(seconds: 150));

    final noProgressYet = estimateSyncKeepAwakeEta(
      _sync(
        percentage: 0.4,
        sessionStartPercentage: 0.4,
        lastSyncStartedAt: startedAt,
      ),
      now: now,
    );
    expect(noProgressYet.remaining, isNull);
  });

  test('ETA uses the observed rate between batch samples', () {
    final startedAt = DateTime(2026, 7, 9, 12);
    final previous = estimateSyncKeepAwakeEta(
      _sync(
        percentage: 0.10,
        displayTargetPercentage: 0.20,
        displayTargetBlocks: 100,
        lastSyncStartedAt: startedAt,
      ),
      now: startedAt.add(const Duration(seconds: 10)),
    );

    final current = estimateSyncKeepAwakeEta(
      _sync(
        percentage: 0.20,
        displayTargetPercentage: 0.30,
        displayTargetBlocks: 100,
        lastSyncStartedAt: startedAt,
      ),
      now: startedAt.add(const Duration(seconds: 20)),
      previousSample: previous.sample,
    );

    expect(current.remaining, const Duration(seconds: 80));
    expect(current.sample, isNotNull);
  });

  test('ETA does not depend on how much work a batch packs per block', () {
    final startedAt = DateTime(2026, 7, 9, 12);
    // A dense 100-block batch, then a sparse 2,000-block one. Both carry
    // work fractions, so the rate is 1% per second either way.
    final previous = estimateSyncKeepAwakeEta(
      _sync(
        percentage: 0.10,
        displayTargetPercentage: 0.11,
        displayTargetBlocks: 100,
        lastSyncStartedAt: startedAt,
      ),
      now: startedAt.add(const Duration(seconds: 10)),
    );

    final current = estimateSyncKeepAwakeEta(
      _sync(
        percentage: 0.20,
        displayTargetPercentage: 0.40,
        displayTargetBlocks: 2000,
        lastSyncStartedAt: startedAt,
      ),
      now: startedAt.add(const Duration(seconds: 20)),
      previousSample: previous.sample,
    );

    expect(current.remaining, const Duration(seconds: 80));
  });

  test('a failed sync is not complete even at the tip', () {
    final failed = SyncState(
      percentage: 0.99,
      scannedHeight: 200,
      chainTipHeight: 200,
      failure: classifySyncFailure(Exception('connection reset')),
    );
    expect(isSyncKeepAwakeCompletedSync(failed), isFalse);
    // A failure after the main scan keeps its 100% for the retry.
    expect(
      isSyncKeepAwakeCompletedSync(failed.copyWith(percentage: 1)),
      isFalse,
    );
    expect(
      isSyncKeepAwakeCompletedSync(
        SyncState(percentage: 1, scannedHeight: 200, chainTipHeight: 200),
      ),
      isTrue,
    );
  });

  test('prompt requires unseen state and at least one minute ETA', () {
    final startedAt = DateTime(2026, 7, 9, 12);
    final sync = _sync(percentage: 0.25, lastSyncStartedAt: startedAt);
    final now = startedAt.add(const Duration(seconds: 30));

    expect(
      shouldShowSyncKeepAwakePrompt(
        sync: sync,
        settings: const SyncKeepAwakeSettings(
          enabled: false,
          promptSeen: false,
        ),
        now: now,
      ),
      isTrue,
    );
    expect(
      shouldShowSyncKeepAwakePrompt(
        sync: sync,
        settings: const SyncKeepAwakeSettings(enabled: false, promptSeen: true),
        now: now,
      ),
      isFalse,
    );
  });
}

AppBootstrapState _bootstrap({
  bool syncKeepAwakeEnabled = false,
  bool syncKeepAwakePromptSeen = false,
  bool isPasswordConfigured = false,
  bool isUnlocked = false,
}) {
  return AppBootstrapState(
    initialLocation: '/home',
    initialAccountState: AccountState(),
    initialSyncSnapshot: AppSyncSnapshot.empty,
    network: kZcashDefaultNetworkName,
    rpcEndpointConfig: defaultRpcEndpointConfig(kZcashDefaultNetworkName),
    themeMode: ThemeMode.system,
    privacyModeEnabled: false,
    syncKeepAwakeEnabled: syncKeepAwakeEnabled,
    syncKeepAwakePromptSeen: syncKeepAwakePromptSeen,
    isPasswordConfigured: isPasswordConfigured,
    isUnlocked: isUnlocked,
    passwordRotationRecoveryFailed: false,
  );
}

SyncState _sync({
  bool isSyncing = true,
  bool isBackgroundMode = false,
  double percentage = 0.25,
  double? displayTargetPercentage,
  int displayTargetBlocks = 0,
  int scannedHeight = 100,
  int chainTipHeight = 200,
  DateTime? lastSyncStartedAt,
  String phase = '',
  int? remainingScanBlocks,
  int? pendingScanStartHeight,
  bool scanWorkKnown = true,
  double sessionStartPercentage = 0,
  bool startedFromCompletedSync = false,
  String syncJobId = '',
}) {
  return SyncState(
    syncJobId: syncJobId,
    isSyncing: isSyncing,
    isBackgroundMode: isBackgroundMode,
    percentage: percentage,
    displayTargetPercentage: displayTargetPercentage,
    displayTargetBlocks: displayTargetBlocks,
    remainingScanBlocks: scanWorkKnown && chainTipHeight > 0
        ? remainingScanBlocks ??
              (chainTipHeight - scannedHeight).clamp(0, chainTipHeight)
        : null,
    pendingScanStartHeight: scanWorkKnown && chainTipHeight > scannedHeight
        ? pendingScanStartHeight ?? scannedHeight + 1
        : pendingScanStartHeight,
    scannedHeight: scannedHeight,
    chainTipHeight: chainTipHeight,
    lastSyncStartedAt: lastSyncStartedAt,
    phase: phase,
    sessionStartPercentage: sessionStartPercentage,
    startedFromCompletedSync: startedFromCompletedSync,
  );
}
