import 'dart:developer';

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_bootstrap.dart';
import '../core/config/network_config.dart';
import '../core/storage/enhance_pir_preference_store.dart';
import '../core/storage/linux_keyring_coordinator.dart';
import '../core/storage/wallet_paths.dart';
import '../features/migration/services/ironwood_migration_background_credential_store.dart';
import '../rust/api/sync.dart' as rust_sync;
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

/// Overridable in tests; production writes go to shared preferences.
final transparentOptOutStoreProvider = Provider<TransparentOptOutStore>(
  (_) => const SharedPreferencesTransparentOptOutStore(),
);

/// Reconciles the wallet's durable transparent policy with the private
/// queries setting. `true` raises it when this build selects private
/// transparent recovery; `false` lowers it to public in every build. Completes
/// with the policy it applied, mode and generation, or with `null` once
/// nothing needed to change; on failure nothing changed.
typedef TransparentPolicyReconciler =
    Future<rust_sync.ApiAppliedTransparentPolicy?> Function(
      bool privateQueries,
    );

/// Reconciles the existing wallet database for `network`. It only reads the
/// stored database name, never mints one: with no wallet database named, as
/// during or after a reset, it reconciles nothing. Rust never creates a
/// missing wallet either.
TransparentPolicyReconciler walletTransparentPolicyReconciler(
  String network, {
  Future<String?> Function() resolveExistingDbPath = getExistingWalletDbPath,
}) => (privateQueries) async {
  final dbPath = await resolveExistingDbPath();
  if (dbPath == null) return null;
  return rust_sync.reconcileTransparentPolicy(
    dbPath: dbPath,
    network: network,
    privateQueries: privateQueries,
  );
};

/// Overridable in tests; production reconciles the wallet database.
final transparentPolicyReconcilerProvider =
    Provider<TransparentPolicyReconciler>(
      (ref) => walletTransparentPolicyReconciler(
        ref.watch(appBootstrapProvider).network,
      ),
    );

/// What startup did to the wallet's transparent policy; see
/// `applyEnhancePirPolicy`.
@immutable
class TransparentPolicyStartup {
  const TransparentPolicyStartup({
    this.appliedPolicy,
    this.optOutPending = false,
  });

  /// The policy startup applied, or `null` when it applied none.
  final rust_sync.ApiAppliedTransparentPolicy? appliedPolicy;

  /// Whether an explicit opt-out is still unfinished after startup's retry.
  final bool optOutPending;

  /// Recorded by the latest startup before any provider reads it.
  static TransparentPolicyStartup current = const TransparentPolicyStartup();
}

/// Overridable in tests; production reads [TransparentPolicyStartup.current].
final transparentPolicyStartupProvider = Provider<TransparentPolicyStartup>(
  (_) => TransparentPolicyStartup.current,
);

/// Whether an explicit opt-out still has to lower the wallet's transparent
/// policy: its marker is persisted, and startup retries it.
class TransparentOptOutPendingNotifier extends Notifier<bool> {
  @override
  bool build() => ref.watch(transparentPolicyStartupProvider).optOutPending;

  void update(bool pending) => state = pending;
}

final transparentOptOutPendingProvider =
    NotifierProvider<TransparentOptOutPendingNotifier, bool>(
      TransparentOptOutPendingNotifier.new,
    );

/// Whether Settings offers to finish lowering the wallet's transparent
/// policy: private queries are off, but an opt-out is unfinished or the
/// wallet still reads its transparent balance privately. Offered whether or
/// not the private service is available here, so a wallet a flag build made
/// private can always be returned to public lookups.
final transparentOptOutActionProvider = Provider<bool>((ref) {
  if (ref.watch(enhancePirProvider)) return false;
  if (ref.watch(transparentOptOutPendingProvider)) return true;
  return ref.watch(walletTransparentPrivateProvider);
});

/// Whether the active account's latest transparent balance read was private,
/// published by [SyncNotifier]. Settings watches this rather than sync, so
/// showing Settings never starts a sync of its own.
class WalletTransparentPrivateNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void update(bool private) {
    if (state != private) state = private;
  }
}

final walletTransparentPrivateProvider =
    NotifierProvider<WalletTransparentPrivateNotifier, bool>(
      WalletTransparentPrivateNotifier.new,
    );

/// Transition feedback while the setting changes.
const kEnhancePirChangingMessage = 'Changing setting…';

/// Feedback when the setting could not change at all.
const kEnhancePirUnchangedMessage = 'Setting unchanged. Try again.';

/// Feedback when private queries are on but the wallet's transparent policy
/// could not be raised yet. The startup and sync raise paths retry it.
const kTransparentRaisePendingMessage =
    'Private queries are on. Private transparent recovery could not start '
    'yet and will be retried.';

/// Feedback when private queries are off but the wallet's transparent policy
/// is still private. Transparent lookups stay private until it is lowered.
const kTransparentOptOutPendingMessage =
    'Private queries are off. Transparent lookups stay private until this '
    'finishes; it will be retried.';

/// Private queries are an **install-scoped** preference: they are chosen
/// once and apply to every wallet that lives on this device, including a
/// wallet created after a full reset. It is stored outside the secure-store
/// bucket that `AppSecureStore.deleteAll()` wipes, and the reset path
/// deliberately leaves it alone — see [kEnhancePirEnabledPreferenceKey].
///
/// The toggle is serialized with wallet resets and account mutations on every
/// platform through [LinuxKeyringCoordinator.runWalletDbMutation].
class EnhancePirNotifier extends Notifier<bool> {
  @override
  bool build() {
    final bootstrap = ref.watch(appBootstrapProvider);
    // An unreadable setting is private for this launch.
    return ref.watch(enhancePirAvailableProvider) &&
        (bootstrap.enhancePirEnabled ?? true);
  }

  Future<void> set(bool enabled) async {
    final effectiveEnabled = enabled && ref.read(enhancePirAvailableProvider);
    if (effectiveEnabled == state) return;
    await _transition(() => effectiveEnabled ? _enable() : _disable());
  }

  /// Finishes an unfinished opt-out, or lowers a wallet whose transparent
  /// policy is still private while private queries are off, even where the
  /// private service is unavailable. Private queries end up off either way.
  Future<void> finishTransparentOptOut() async {
    if (state) return set(false);
    await _transition(_disable);
  }

  Future<void> _transition(Future<String?> Function() change) async {
    final transition = ref.read(enhancePirTransitionProvider.notifier);
    if (ref.read(enhancePirTransitionProvider) == kEnhancePirChangingMessage) {
      return;
    }
    transition.update(kEnhancePirChangingMessage);
    try {
      String? outcome;
      await ref
          .read(linuxKeyringCoordinatorProvider)
          .runWalletDbMutation(
            () => ref.read(syncProvider.notifier).withRecoverySettingPaused(
              () async {
                outcome = await change();
              },
            ),
          );
      transition.update(outcome);
    } catch (error) {
      log('Private queries setting unchanged: $error');
      transition.update(kEnhancePirUnchangedMessage);
    }
  }

  // Apply the stricter state first. A failed save of the setting changes
  // nothing that weakens privacy. Once the setting is saved it stays: a
  // transparent reconcile that fails afterwards leaves the shielded setting
  // where the user put it and is retried, never rolled back.

  /// Returns the feedback to show, or `null` when everything applied.
  Future<String?> _enable() async {
    final store = ref.read(enhancePirPreferenceStoreProvider);
    final reconcile = ref.read(transparentPolicyReconcilerProvider);
    await ref.read(enhancePirBackgroundSinkProvider)(true);
    await store.writeEnabled(true);
    rust_sync.setEnhancePirEnabled(enabled: true);
    rust_sync.setEnhancePirPreferenceConfirmed(confirmed: true);
    state = true;
    // Turning private queries on supersedes an unfinished opt-out. Startup
    // ignores a stale marker while the setting is on, so a failed clear only
    // leaves it to be cleared later.
    await _clearOptOutMarker();
    try {
      ref
          .read(syncProvider.notifier)
          .adoptAppliedTransparentPolicy(await reconcile(true));
    } catch (error) {
      // Shielded private queries stay on. The startup and sync raise paths
      // retry the transparent raise; nothing public was enabled.
      log('Could not raise the transparent policy yet: $error');
      return kTransparentRaisePendingMessage;
    }
    return null;
  }

  /// Returns the feedback to show, or `null` when everything applied.
  Future<String?> _disable() async {
    final store = ref.read(enhancePirPreferenceStoreProvider);
    final optOut = ref.read(transparentOptOutStoreProvider);
    final reconcile = ref.read(transparentPolicyReconcilerProvider);
    // Persist the unfinished opt-out before anything weakens, so startup
    // finishes it if the app dies meanwhile. If saving fails, nothing changes.
    await optOut.writePending(true);
    ref.read(transparentOptOutPendingProvider.notifier).update(true);
    try {
      await store.writeEnabled(false);
    } catch (_) {
      // The setting is still on, so startup ignores the marker; clear it
      // anyway so Settings does not offer to finish an opt-out that never was.
      await _clearOptOutMarker();
      rethrow;
    }
    rust_sync.setEnhancePirEnabled(enabled: false);
    state = false;
    rust_sync.ApiAppliedTransparentPolicy? applied;
    String? outcome;
    try {
      applied = await reconcile(false);
    } catch (error) {
      // Lowering changes nothing on failure: the durable private policy still
      // governs every transparent lookup, so none goes out publicly. The
      // persisted marker retries it at the next launch, and Settings offers
      // to finish it now.
      log('Could not lower the transparent policy yet: $error');
      outcome = kTransparentOptOutPendingMessage;
    }
    try {
      await ref.read(enhancePirBackgroundSinkProvider)(false);
    } catch (error) {
      // Background tracking stays foreground-only until the next launch
      // reapplies the setting; nothing public is issued meanwhile.
      log('Could not release private background recovery: $error');
    }
    if (outcome != null) return outcome;
    await _clearOptOutMarker();
    ref.read(syncProvider.notifier).adoptAppliedTransparentPolicy(applied);
    return null;
  }

  /// Clears the opt-out marker. A failed clear keeps it: the retry it causes
  /// at the next launch lowers an already public wallet, which changes
  /// nothing.
  Future<void> _clearOptOutMarker() async {
    try {
      await ref.read(transparentOptOutStoreProvider).writePending(false);
      ref.read(transparentOptOutPendingProvider.notifier).update(false);
    } catch (error) {
      log('Could not clear the private queries opt-out marker: $error');
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
