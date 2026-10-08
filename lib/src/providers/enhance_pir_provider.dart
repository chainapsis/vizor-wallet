import 'dart:developer';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_bootstrap.dart';
import '../core/config/network_config.dart';
import '../core/storage/enhance_pir_preference_store.dart';
import '../core/storage/wallet_paths.dart';
import '../core/widgets/app_toast.dart';
import '../features/migration/services/ironwood_migration_background_credential_store.dart';
import '../rust/api/swap_receive.dart' as rust_swap;
import '../rust/api/sync.dart' as rust_sync;
import 'rpc_endpoint_failover_provider.dart';
import 'sync_provider.dart';

/// Whether the configured chain has a matching private enhancement service.
bool isEnhancePirAvailableForNetwork(
  String network, {
  bool isMasquerade = kZcashIronwoodMasquerade,
}) => !isMasquerade && zcashNetworkFromName(network) == ZcashNetwork.mainnet;

/// Exposes private enhancement availability to both settings form factors.
final enhancePirAvailableProvider = Provider<bool>((ref) {
  final network = ref.watch(appBootstrapProvider).network;
  return isEnhancePirAvailableForNetwork(network);
});

/// Applies the effective setting to native background work. Overridable in tests.
final enhancePirBackgroundSinkProvider = Provider<Future<void> Function(bool)>(
  (_) => IronwoodMigrationBackgroundLifecycle.instance.setPrivateRecovery,
);

/// Overridable in tests; production writes go to shared preferences.
final enhancePirPreferenceStoreProvider = Provider<EnhancePirPreferenceStore>(
  (_) => const SharedPreferencesEnhancePirStore(),
);

/// Private queries are an **install-scoped** preference: they are chosen
/// once and apply to every wallet that lives on this device, including a
/// wallet created after a full reset. It is stored outside the secure-store
/// bucket that `AppSecureStore.deleteAll()` wipes, and the reset path
/// deliberately leaves it alone — see [kEnhancePirEnabledPreferenceKey].
class EnhancePirNotifier extends Notifier<bool> {
  @override
  bool build() {
    final bootstrap = ref.watch(appBootstrapProvider);
    return ref.watch(enhancePirAvailableProvider) &&
        bootstrap.enhancePirEnabled;
  }

  Future<void> set(bool enabled) async {
    final transition = ref.read(enhancePirTransitionProvider.notifier);
    if (ref.read(enhancePirTransitionProvider) == 'Changing setting…') return;
    final effectiveEnabled = enabled && ref.read(enhancePirAvailableProvider);
    if (effectiveEnabled == state) return;
    transition.update('Changing setting…');
    try {
      final background = ref.read(enhancePirBackgroundSinkProvider);
      await ref.read(syncProvider.notifier).withRecoverySettingPaused(() async {
        // Background work may be stricter than the saved setting, never laxer:
        // enabling reaches native before anything commits, and disabling
        // releases it only after the new setting is saved and enforced.
        if (effectiveEnabled) await background(true);
        if (!effectiveEnabled) {
          await ref.read(nearSwapPrivacyProvider.notifier).disableWithParent();
        }
        await ref
            .read(enhancePirPreferenceStoreProvider)
            .writeEnabled(effectiveEnabled);
        rust_sync.setEnhancePirEnabled(enabled: effectiveEnabled);
        state = effectiveEnabled;
        if (!effectiveEnabled) {
          try {
            await background(false);
          } catch (error) {
            // Background tracking stays foreground-only until the next launch
            // reapplies the setting; nothing public is issued meanwhile.
            log('Could not release private background recovery: $error');
          }
        }
      });
      transition.update(null);
    } catch (_) {
      transition.update('Setting unchanged. Try again.');
    }
  }

  Future<void> toggle() => set(!state);
}

final enhancePirProvider = NotifierProvider<EnhancePirNotifier, bool>(
  EnhancePirNotifier.new,
);

class EnhancePirTransitionNotifier extends Notifier<String?> {
  @override
  String? build() => null;
  void update(String? message) => state = message;
}

final enhancePirTransitionProvider =
    NotifierProvider<EnhancePirTransitionNotifier, String?>(
      EnhancePirTransitionNotifier.new,
    );

final nearSwapPrivacyPreferenceStoreProvider =
    Provider<EnhancePirPreferenceStore>(
      (_) => const SharedPreferencesEnhancePirStore(
        key: kNearSwapPrivacyPreferenceKey,
      ),
    );

/// Queues one private sweep of every closed swap key for the next sync, which
/// finds a refund or payout that arrived after its key stopped scanning.
/// Overridable in tests.
final swapHistoryRecheckProvider = Provider<Future<void> Function()>(
  (ref) =>
      () async => rust_swap.recheckSwapHistory(
        dbPath: await getWalletDbPath(),
        networkName: ref.read(rpcEndpointFailoverProvider).current.networkName,
      ),
);

/// Install-scoped opt-in for new swap addresses. Recovery of existing keys is independent.
class NearSwapPrivacyNotifier extends Notifier<bool> {
  @override
  bool build() {
    final bootstrap = ref.watch(appBootstrapProvider);
    return ref.watch(enhancePirAvailableProvider) &&
        bootstrap.enhancePirEnabled &&
        bootstrap.nearSwapPrivacyEnabled;
  }

  Future<void> set(bool enabled) async {
    if (ref.read(enhancePirTransitionProvider) == 'Changing setting…') return;
    if (enabled && !ref.read(enhancePirProvider)) return;
    if (enabled == state) return;
    final transition = ref.read(enhancePirTransitionProvider.notifier);
    transition.update('Changing setting…');
    try {
      await ref.read(syncProvider.notifier).withRecoverySettingPaused(() async {
        // Recheck after draining work so a new address cannot race its parent setting.
        if (enabled && !ref.read(enhancePirProvider)) return;
        await ref
            .read(nearSwapPrivacyPreferenceStoreProvider)
            .writeEnabled(enabled);
        rust_sync.setNearSwapPrivacyEnabled(enabled: enabled);
        state = enabled;
        if (enabled) {
          // A failed recheck leaves the setting on; toggling again retries it.
          try {
            await ref.read(swapHistoryRecheckProvider)();
          } catch (error) {
            log('near swap privacy: history recheck not queued: $error');
          }
        }
      });
      transition.update(null);
    } catch (_) {
      transition.update('Setting unchanged. Try again.');
    }
  }

  /// Called while the parent already holds the shared recovery pause.
  Future<void> disableWithParent() async {
    if (!state) return;
    await ref.read(nearSwapPrivacyPreferenceStoreProvider).writeEnabled(false);
    rust_sync.setNearSwapPrivacyEnabled(enabled: false);
    state = false;
  }

  Future<void> toggle() => set(!state);

  /// Sweeps every closed swap key once more and starts a sync to run it, so a refund
  /// or payout that arrived after its key stopped scanning appears. Returns whether
  /// the check was queued.
  Future<bool> recheckHistory() async {
    try {
      await ref.read(swapHistoryRecheckProvider)();
    } catch (error) {
      log('near swap privacy: history recheck not queued: $error');
      return false;
    }
    ref.read(syncProvider.notifier).startSync();
    return true;
  }
}

/// Shows whether a swap history check was queued (see
/// [NearSwapPrivacyNotifier.recheckHistory]).
Future<void> recheckSwapHistory(BuildContext context, WidgetRef ref) async {
  final queued = await ref
      .read(nearSwapPrivacyProvider.notifier)
      .recheckHistory();
  if (!context.mounted) return;
  showAppToast(
    context,
    queued
        ? 'Checking swap history. Late refunds and payouts appear after this sync.'
        : "Swap history couldn't be checked. Try again.",
  );
}

final nearSwapPrivacyProvider = NotifierProvider<NearSwapPrivacyNotifier, bool>(
  NearSwapPrivacyNotifier.new,
);
