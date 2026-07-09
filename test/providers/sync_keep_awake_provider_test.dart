import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';
import 'package:zcash_wallet/src/providers/sync_keep_awake_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

void main() {
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

  test('near-tip catch-up requires known heights and a gap of two or less', () {
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

  test('ETA is not estimated for ineligible sync states', () {
    final startedAt = DateTime(2026, 7, 9, 12);
    final now = startedAt.add(const Duration(seconds: 30));

    expect(
      estimateSyncKeepAwakeEta(
        _sync(percentage: 0, lastSyncStartedAt: startedAt),
        now: now,
      ).remaining,
      isNull,
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

  test('ETA uses display target block samples when available', () {
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
    isPasswordConfigured: false,
    isUnlocked: false,
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
}) {
  return SyncState(
    isSyncing: isSyncing,
    isBackgroundMode: isBackgroundMode,
    percentage: percentage,
    displayTargetPercentage: displayTargetPercentage,
    displayTargetBlocks: displayTargetBlocks,
    scannedHeight: scannedHeight,
    chainTipHeight: chainTipHeight,
    lastSyncStartedAt: lastSyncStartedAt,
  );
}
