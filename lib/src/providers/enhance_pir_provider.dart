import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_bootstrap.dart';
import '../core/config/network_config.dart';
import '../core/storage/enhance_pir_preference_store.dart';
import '../rust/api/sync.dart' as rust_sync;
import 'sync_provider.dart';

/// Whether the configured chain has a matching private enhancement service.
bool isEnhancePirAvailableForNetwork(String network) =>
    zcashNetworkFromName(network) == ZcashNetwork.mainnet;

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
    final effectiveEnabled = enabled && ref.read(enhancePirAvailableProvider);
    await ref
        .read(enhancePirPreferenceStoreProvider)
        .writeEnabled(effectiveEnabled);
    rust_sync.setEnhancePirEnabled(enabled: effectiveEnabled);
    state = effectiveEnabled;
    await ref.read(syncProvider.notifier).restartSync();
  }

  Future<void> toggle() => set(!state);
}

final enhancePirProvider = NotifierProvider<EnhancePirNotifier, bool>(
  EnhancePirNotifier.new,
);
