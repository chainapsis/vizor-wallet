import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';

// The app's logger reaches release device logs; `dart:developer`'s does not.
import '../../main.dart' show log;
import '../app_bootstrap.dart';
import '../core/config/network_config.dart';
import '../core/config/swap_feature_config.dart';
import '../core/storage/enhance_pir_preference_store.dart';
import '../core/storage/linux_keyring_coordinator.dart';
import '../core/storage/wallet_paths.dart';
import '../features/migration/services/ironwood_migration_background_credential_store.dart';
import '../rust/api/sync.dart' as rust_sync;
import '../rust/api/one_time_ivk.dart' as rust_swap;
import 'account_provider.dart';
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
/// queries setting. `true` raises it on mainnet, where private transparent
/// recovery runs; `false` lowers it to public on every network. Completes
/// with the current mode and generation, including a no-op, or with `null`
/// when no wallet exists. On failure the durable policy is unchanged.
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

/// Reads the wallet's durable transparent policy without changing it, or
/// `null` when no wallet exists.
typedef TransparentPolicyReader =
    Future<rust_sync.ApiAppliedTransparentPolicy?> Function();

/// Reads the existing wallet database for `network`, never minting a name or
/// creating a wallet.
TransparentPolicyReader walletTransparentPolicyReader(
  String network, {
  Future<String?> Function() resolveExistingDbPath = getExistingWalletDbPath,
}) => () async {
  final dbPath = await resolveExistingDbPath();
  if (dbPath == null) return null;
  return rust_sync.readTransparentPolicy(dbPath: dbPath, network: network);
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

  /// The policy startup resolved, or `null` when no wallet was reconciled.
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

/// The single toggle stays on while either query path is private, including
/// an unfinished turn-off. It also remains available to turn off a durable
/// private policy on a network without the private service.
final privateQueriesControlEnabledProvider = Provider<bool>(
  (ref) =>
      ref.watch(enhancePirProvider) ||
      ref.watch(transparentOptOutPendingProvider) ||
      ref.watch(walletTransparentPrivateProvider),
);

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

/// Whether turning private queries off would send
/// the wallet's transparent lookups to the server: its transparent policy is
/// still private, an opt-out is unfinished, or private queries are on for an
/// existing wallet, which then recovers its transparent funds privately.
final privateQueriesTurnOffDisclosesProvider = Provider<bool>((ref) {
  if (ref.watch(walletTransparentPrivateProvider) ||
      ref.watch(transparentOptOutPendingProvider)) {
    return true;
  }
  final hasAccounts =
      ref.watch(accountProvider).value?.accounts.isNotEmpty ?? false;
  return hasAccounts && ref.watch(enhancePirProvider);
});

/// Transition feedback while the setting changes.
const kEnhancePirChangingMessage = 'Changing setting…';

/// Feedback when the setting could not change at all.
const kEnhancePirUnchangedMessage = 'Setting unchanged. Try again.';

/// Feedback when private queries are on but the wallet's transparent policy
/// could not be raised yet. The startup and sync raise paths retry it.
const kTransparentRaisePendingMessage =
    'Private queries are on. Private transparent recovery could not start '
    'yet and will be retried.';

/// Feedback when turning off failed. Both query paths remain private and
/// the same toggle can retry the turn-off.
const kTransparentOptOutPendingMessage =
    'Private queries are still on. Try turning them off again.';

/// Private queries are an **install-scoped** preference: they are chosen
/// once and apply to every wallet that lives on this device, including a
/// wallet created after a full reset. It is stored outside the secure-store
/// bucket that `AppSecureStore.deleteAll()` wipes, and the reset path
/// deliberately leaves it alone — see [kEnhancePirEnabledPreferenceKey].
///
/// The toggle is serialized with wallet resets and account mutations on every
/// platform through [LinuxKeyringCoordinator.runMutation].
class EnhancePirNotifier extends Notifier<bool> {
  @override
  bool build() {
    final bootstrap = ref.watch(appBootstrapProvider);
    // An unreadable setting is private for this launch.
    return ref.watch(transparentPolicyStartupProvider).optOutPending ||
        (ref.watch(enhancePirAvailableProvider) &&
            (bootstrap.enhancePirEnabled ?? true));
  }

  Future<void> set(bool enabled) async {
    final effectiveEnabled = enabled && ref.read(enhancePirAvailableProvider);
    if (effectiveEnabled == state && (effectiveEnabled || !_controlEnabled)) {
      return;
    }
    await _transition(() => effectiveEnabled ? _enable() : _disable());
  }

  Future<void> _transition(Future<String?> Function() change) async {
    final transition = ref.read(enhancePirTransitionProvider.notifier);
    if (ref.read(enhancePirTransitionProvider) == kEnhancePirChangingMessage) {
      return;
    }
    transition.update(kEnhancePirChangingMessage);
    // Turning private queries off also turns NEAR swap privacy off, so its
    // last feedback no longer applies.
    ref.read(nearSwapPrivacyTransitionProvider.notifier).update(null);
    try {
      String? outcome;
      await ref
          .read(linuxKeyringCoordinatorProvider)
          .runMutation(
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
    try {
      await store.writeEnabled(true);
    } catch (_) {
      // The native value changed before the save. Restore it too when the
      // saved choice and foreground runtime remain unchanged.
      try {
        await ref.read(enhancePirBackgroundSinkProvider)(state);
      } catch (error) {
        log('Could not restore private background recovery: $error');
      }
      rethrow;
    }
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
    // New private swap addresses need private queries, so their opt-in goes
    // first; if that fails, nothing has changed.
    await ref.read(nearSwapPrivacyProvider.notifier).disableWithParent();
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
      // anyway so the toggle does not report an opt-out that never started.
      await _clearOptOutMarker();
      rethrow;
    }
    try {
      // Adopted at once, before any further wait, so the visible state and
      // the account-switch cache demote as soon as the policy changed.
      ref
          .read(syncProvider.notifier)
          .adoptAppliedTransparentPolicy(await reconcile(false));
    } catch (error) {
      // Keep both runtime query paths private until lowering succeeds. The
      // saved intent survives a crash; the same toggle retries it now.
      log('Could not lower the transparent policy yet: $error');
      final available = ref.read(enhancePirAvailableProvider);
      rust_sync.setEnhancePirEnabled(enabled: available);
      state = true;
      try {
        await ref.read(enhancePirBackgroundSinkProvider)(available);
      } catch (error) {
        log('Could not retain private background recovery: $error');
      }
      return kTransparentOptOutPendingMessage;
    }
    rust_sync.setEnhancePirEnabled(enabled: false);
    state = false;
    try {
      await ref.read(enhancePirBackgroundSinkProvider)(false);
    } catch (error) {
      // Background tracking stays foreground-only until the next launch
      // reapplies the setting; nothing public is issued meanwhile.
      log('Could not release private background recovery: $error');
    }
    await _clearOptOutMarker();
    return null;
  }

  /// Clears the pending UI state once the policy has changed. A failed
  /// persisted clear leaves a harmless retry at startup: lowering an already
  /// public wallet changes nothing.
  Future<void> _clearOptOutMarker() async {
    try {
      await ref.read(transparentOptOutStoreProvider).writePending(false);
    } catch (error) {
      log('Could not clear the private queries opt-out marker: $error');
    }
    ref.read(transparentOptOutPendingProvider.notifier).update(false);
  }

  /// Reapplies the install's saved choice after a full wallet reset succeeds.
  /// Call while the reset still owns the wallet mutation and native work is
  /// paused. The old wallet's pending opt-out is cleared without reconciling
  /// any database, so it cannot govern the next wallet. Storage or native
  /// failures throw; the reset must remain retryable until this completes.
  Future<void> restoreAfterWalletReset() async {
    final saved = await ref
        .read(enhancePirPreferenceStoreProvider)
        .readEnabled();
    final enabled = (saved ?? true) && ref.read(enhancePirAvailableProvider);
    await ref.read(transparentOptOutStoreProvider).writePending(false);
    await ref.read(enhancePirBackgroundSinkProvider)(enabled);
    rust_sync.setEnhancePirEnabled(enabled: enabled);
    rust_sync.setEnhancePirPreferenceConfirmed(confirmed: saved != null);
    state = enabled;
    TransparentPolicyStartup.current = const TransparentPolicyStartup();
    ref.read(transparentOptOutPendingProvider.notifier).update(false);
    ref.read(walletTransparentPrivateProvider.notifier).update(false);
    ref.read(enhancePirTransitionProvider.notifier).update(null);
    ref.read(nearSwapPrivacyTransitionProvider.notifier).update(null);
  }

  bool get _controlEnabled =>
      state ||
      ref.read(transparentOptOutPendingProvider) ||
      ref.read(walletTransparentPrivateProvider);

  Future<void> toggle() => set(!_controlEnabled);
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

/// Feedback for the NEAR swap privacy toggle, shown under its own row. While
/// it changes, [enhancePirTransitionProvider] also holds
/// [kEnhancePirChangingMessage], which keeps other setting changes waiting.
final nearSwapPrivacyTransitionProvider =
    NotifierProvider<EnhancePirTransitionNotifier, String?>(
      EnhancePirTransitionNotifier.new,
    );

/// Feedback for the Private queries row: the shared feedback, unless the
/// change running is NEAR swap privacy's (see
/// [nearSwapPrivacyTransitionProvider]).
final privateQueriesTransitionProvider = Provider<String?>(
  (ref) =>
      ref.watch(nearSwapPrivacyTransitionProvider) == kEnhancePirChangingMessage
      ? null
      : ref.watch(enhancePirTransitionProvider),
);

final nearSwapPrivacyPreferenceStoreProvider =
    Provider<EnhancePirPreferenceStore>(
      (_) => const SharedPreferencesEnhancePirStore(
        key: kNearSwapPrivacyPreferenceKey,
      ),
    );

/// Applies the effective setting to an existing wallet without creating one.
final swapRecoveryReconcilerProvider = Provider<Future<void> Function()>((ref) {
  return () async {
    final path = await getExistingWalletDbPath();
    if (path != null) {
      await rust_swap.reconcileSwapRecovery(
        dbPath: path,
        networkName: ref.read(appBootstrapProvider).network,
      );
    }
  };
});

/// The preference is saved even if the wallet must retry applying it, which
/// a later receiver round does.
const kSwapRecoveryPendingMessage =
    'Saved. Vizor will finish applying it shortly.';

/// Install-scoped opt-in for private addresses and automatic receiver recovery.
class NearSwapPrivacyNotifier extends Notifier<bool> {
  @override
  bool build() {
    final bootstrap = ref.watch(appBootstrapProvider);
    return ref.watch(enhancePirAvailableProvider) &&
        (bootstrap.enhancePirEnabled ?? true) &&
        bootstrap.nearSwapPrivacyEnabled;
  }

  Future<void> set(bool enabled) async {
    if (ref.read(enhancePirTransitionProvider) == kEnhancePirChangingMessage) {
      return;
    }
    if (enabled && !ref.read(enhancePirProvider)) return;
    if (enabled == state) return;
    final transition = ref.read(enhancePirTransitionProvider.notifier);
    final feedback = ref.read(nearSwapPrivacyTransitionProvider.notifier);
    transition.update(kEnhancePirChangingMessage);
    feedback.update(kEnhancePirChangingMessage);
    var reconciled = true;
    String? outcome;
    try {
      await ref
          .read(linuxKeyringCoordinatorProvider)
          .runMutation(
            () => ref.read(syncProvider.notifier).withRecoverySettingPaused(
              () async {
                // Recheck after draining work so a new address cannot race its parent setting.
                if (enabled && !ref.read(enhancePirProvider)) return;
                reconciled = await _apply(enabled);
              },
            ),
          );
      outcome = reconciled ? null : kSwapRecoveryPendingMessage;
    } catch (error) {
      log('NEAR swap privacy transition stopped: $error');
      outcome = state == enabled
          ? kSwapRecoveryPendingMessage
          : kEnhancePirUnchangedMessage;
    }
    transition.update(null);
    feedback.update(outcome);
  }

  /// Called while the parent already holds the shared recovery pause.
  Future<void> disableWithParent() async {
    if (!state) return;
    await _apply(false);
  }

  /// Saves `enabled`, applies it to sync and this provider, then reconciles
  /// the wallet. Returns whether reconciling succeeded.
  Future<bool> _apply(bool enabled) async {
    await ref.read(nearSwapPrivacyPreferenceStoreProvider).writeEnabled(enabled);
    rust_sync.setNearSwapPrivacyEnabled(enabled: enabled);
    state = enabled;
    return _reconcileRecovery();
  }

  /// Leaves the applied preference visible when a short DB update needs retry.
  Future<bool> _reconcileRecovery() async {
    try {
      await ref.read(swapRecoveryReconcilerProvider)();
      return true;
    } catch (error) {
      // Every receiver round reconciles before reading work or issuing requests.
      log('Swap recovery setting will be retried: $error');
      return false;
    }
  }

  Future<void> toggle() => set(!state);
}

final nearSwapPrivacyProvider = NotifierProvider<NearSwapPrivacyNotifier, bool>(
  NearSwapPrivacyNotifier.new,
);

/// Whether Settings offers NEAR swap privacy: swaps are enabled here and the
/// private service exists for this network.
final nearSwapPrivacySettingAvailableProvider = Provider<bool>(
  (ref) =>
      ref.watch(swapFeatureEnabledProvider) &&
      ref.watch(enhancePirAvailableProvider),
);
