import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_bootstrap.dart';
import '../core/config/network_config.dart';
import '../core/storage/enhance_pir_preference_store.dart';
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

/// Overridable in tests; production writes go to shared preferences.
final enhancePirPreferenceStoreProvider = Provider<EnhancePirPreferenceStore>(
  (_) => const SharedPreferencesEnhancePirStore(),
);

/// Private Ironwood recovery is an **install-scoped** preference: it is chosen
/// once and applies to every wallet that lives on this device, including a
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
      await ref.read(syncProvider.notifier).withRecoverySettingPaused(() async {
        await ref
            .read(enhancePirPreferenceStoreProvider)
            .writeEnabled(effectiveEnabled);
        rust_sync.setEnhancePirEnabled(enabled: effectiveEnabled);
        state = effectiveEnabled;
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
final enhancePirRecoveryStatusProvider =
    FutureProvider<rust_sync.EnhanceRecoveryStatus?>((ref) async {
      // Refresh when a sync starts or reaches a terminal state, not for every
      // progress event emitted while that sync is running.
      ref.watch(
        syncProvider.select((sync) {
          final state = sync.value;
          return (
            state?.accountUuid,
            state?.isSyncing,
            state?.isSyncComplete,
            state?.lastSyncCompletedAt,
            state?.lastSyncFailedAt,
          );
        }),
      );
      ref.watch(enhancePirProvider);
      if (!ref.watch(enhancePirAvailableProvider)) return null;
      return ref.read(syncProvider.notifier).recoveryStatus();
    });
String recoveryStatusText(
  rust_sync.EnhanceRecoveryStatus? status, {
  bool enabled = true,
}) {
  if (status == null) return '';
  final active = status.queries + status.rediscovery;
  final incomplete = status.suspended;
  if (!enabled) {
    if (active == 0 && incomplete == 0) return '';
    return 'Recovery paused'
        '${active > 0 ? ' · $active pending' : ''}'
        '${incomplete > 0 ? ' · $incomplete suspended' : ''}';
  }
  if (active == 0) {
    return incomplete > 0
        ? 'Incomplete recovery · $incomplete suspended'
        : 'No pending private recovery';
  }
  final message = switch (status.serviceState) {
    'waiting_for_scanning' => 'Waiting for scanning',
    'waiting_for_snapshot' => 'Waiting for a newer snapshot',
    'retrying_later' => 'Retrying later',
    _ => 'Recovering',
  };
  return '$message · $active pending${incomplete > 0 ? ' · $incomplete suspended' : ''}';
}

final enhancePirStatusTextProvider = Provider<String>((ref) {
  final enabled = ref.watch(enhancePirProvider);
  return ref.watch(enhancePirTransitionProvider) ??
      ref
          .watch(enhancePirRecoveryStatusProvider)
          .when(
            data: (status) => recoveryStatusText(status, enabled: enabled),
            loading: () => '',
            error: (_, _) => 'Recovery status unavailable',
          );
});
