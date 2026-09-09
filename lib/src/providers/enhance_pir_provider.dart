import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_bootstrap.dart';
import '../core/config/network_config.dart';
import '../core/storage/app_secure_store.dart';
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

class EnhancePirNotifier extends Notifier<bool> {
  static final _store = AppSecureStore.instance;

  @override
  bool build() {
    final bootstrap = ref.watch(appBootstrapProvider);
    return ref.watch(enhancePirAvailableProvider) &&
        bootstrap.enhancePirEnabled;
  }

  Future<void> set(bool enabled) async {
    final effectiveEnabled = enabled && ref.read(enhancePirAvailableProvider);
    await _store.writePlain(
      kEnhancePirEnabledKey,
      effectiveEnabled ? 'true' : 'false',
    );
    rust_sync.setEnhancePirEnabled(enabled: effectiveEnabled);
    state = effectiveEnabled;
    await ref.read(syncProvider.notifier).restartSync();
  }

  Future<void> toggle() => set(!state);

  /// Clears process-local private recovery state after the wallet database has
  /// been deleted. Secure storage is wiped separately by the reset sequence;
  /// restarting sync here would race creation of the next wallet.
  void clearAfterWalletReset() {
    rust_sync.setEnhancePirEnabled(enabled: false);
    state = false;
  }
}

final enhancePirProvider = NotifierProvider<EnhancePirNotifier, bool>(
  EnhancePirNotifier.new,
);
