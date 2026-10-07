import 'dart:developer';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_bootstrap.dart';
import '../core/config/network_config.dart';
import '../core/config/private_transparent_recovery_config.dart';
import '../core/storage/enhance_pir_preference_store.dart';
import '../core/storage/wallet_paths.dart';
import '../features/migration/services/ironwood_migration_background_credential_store.dart';
import '../rust/api/sync.dart' as rust_sync;
import 'sync_provider.dart';

/// Whether the configured chain has a matching private enhancement service:
/// mainnet, outside masquerade builds. In a debug build with
/// [kZcashE2ePrivateTransparentRegtest], also regtest, whose only private
/// service is the transparent history harness's transparent PIR service.
bool isEnhancePirAvailableForNetwork(
  String network, {
  bool isMasquerade = kZcashIronwoodMasquerade,
  bool regtestHarness = kZcashE2ePrivateTransparentRegtest,
}) {
  if (isMasquerade) return false;
  return switch (zcashNetworkFromName(network)) {
    ZcashNetwork.mainnet => true,
    ZcashNetwork.testnet => false,
    ZcashNetwork.regtest => regtestHarness,
  };
}

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

/// Reconciles the wallet's durable transparent policy with the private
/// queries setting. `true` raises it when this build selects private
/// transparent recovery; `false` lowers it to public in every build. Completes
/// once the policy is applied, with `true`, or once nothing needed to change,
/// with `false`; on failure nothing changed.
typedef TransparentPolicyReconciler =
    Future<bool> Function(bool privateQueries);

/// Reconciles the wallet database for `network`. A missing wallet is left
/// alone.
TransparentPolicyReconciler walletTransparentPolicyReconciler(String network) =>
    (privateQueries) async => rust_sync.reconcileTransparentPolicy(
      dbPath: await getWalletDbPath(),
      network: network,
      privateQueries: privateQueries,
    );

/// Overridable in tests; production reconciles the wallet database.
final transparentPolicyReconcilerProvider =
    Provider<TransparentPolicyReconciler>(
      (ref) => walletTransparentPolicyReconciler(
        ref.watch(appBootstrapProvider).network,
      ),
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
    // An unreadable setting is private for this launch.
    return ref.watch(enhancePirAvailableProvider) &&
        (bootstrap.enhancePirEnabled ?? true);
  }

  Future<void> set(bool enabled) async {
    final transition = ref.read(enhancePirTransitionProvider.notifier);
    if (ref.read(enhancePirTransitionProvider) == 'Changing setting…') return;
    final effectiveEnabled = enabled && ref.read(enhancePirAvailableProvider);
    if (effectiveEnabled == state) return;
    transition.update('Changing setting…');
    try {
      await ref
          .read(syncProvider.notifier)
          .withRecoverySettingPaused(
            () => effectiveEnabled ? _enable() : _disable(),
          );
      transition.update(null);
    } catch (_) {
      transition.update('Setting unchanged. Try again.');
    }
  }

  // Each side may be stricter than the saved setting, never laxer: the
  // stricter state is applied first, and every failure restores it before
  // reporting the setting unchanged.

  Future<void> _enable() async {
    final store = ref.read(enhancePirPreferenceStoreProvider);
    final reconcile = ref.read(transparentPolicyReconcilerProvider);
    await ref.read(enhancePirBackgroundSinkProvider)(true);
    await store.writeEnabled(true);
    rust_sync.setEnhancePirEnabled(enabled: true);
    rust_sync.setEnhancePirPreferenceConfirmed(confirmed: true);
    try {
      await reconcile(true);
    } catch (_) {
      rust_sync.setEnhancePirEnabled(enabled: false);
      await store.writeEnabled(false);
      rethrow;
    }
    state = true;
  }

  Future<void> _disable() async {
    final store = ref.read(enhancePirPreferenceStoreProvider);
    final reconcile = ref.read(transparentPolicyReconcilerProvider);
    rust_sync.setEnhancePirEnabled(enabled: false);
    final bool lowered;
    try {
      lowered = await reconcile(false);
    } catch (_) {
      rust_sync.setEnhancePirEnabled(enabled: true);
      rethrow;
    }
    try {
      await store.writeEnabled(false);
    } catch (_) {
      // The wallet is already public; the saved setting is still on. Raise
      // again only a wallet this disable lowered: one still public was never
      // raised, for example because the setting could not be read at launch.
      rust_sync.setEnhancePirEnabled(enabled: true);
      if (lowered) await reconcile(true);
      rethrow;
    }
    state = false;
    try {
      await ref.read(enhancePirBackgroundSinkProvider)(false);
    } catch (error) {
      // Background tracking stays foreground-only until the next launch
      // reapplies the setting; nothing public is issued meanwhile.
      log('Could not release private background recovery: $error');
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
