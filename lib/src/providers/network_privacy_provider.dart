import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/storage/wallet_paths.dart';
import '../rust/api/network_privacy.dart' as rust_network_privacy;
import '../rust/network_privacy.dart' as rust_types;
import 'sync_provider.dart';

const kTorEnabledPreferenceKey = 'zcash_tor_enabled';

enum NetworkPrivacyConnectionStatus { off, connecting, connected, failed }

class NetworkPrivacyState {
  const NetworkPrivacyState({
    required this.torEnabled,
    required this.status,
    this.error,
  });

  const NetworkPrivacyState.off()
    : torEnabled = false,
      status = NetworkPrivacyConnectionStatus.off,
      error = null;

  final bool torEnabled;
  final NetworkPrivacyConnectionStatus status;
  final String? error;

  bool get isBusy => status == NetworkPrivacyConnectionStatus.connecting;
}

abstract interface class NetworkPrivacyPreferenceStore {
  Future<bool> readTorEnabled();
  Future<void> writeTorEnabled(bool enabled);
}

class SharedPreferencesNetworkPrivacyStore
    implements NetworkPrivacyPreferenceStore {
  const SharedPreferencesNetworkPrivacyStore();

  @override
  Future<bool> readTorEnabled() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(kTorEnabledPreferenceKey) ?? false;
  }

  @override
  Future<void> writeTorEnabled(bool enabled) async {
    final preferences = await SharedPreferences.getInstance();
    final saved = await preferences.setBool(kTorEnabledPreferenceKey, enabled);
    if (!saved) {
      throw StateError('Could not save the Tor preference.');
    }
  }
}

abstract interface class NetworkPrivacyRuntime {
  Future<NetworkPrivacyConnectionStatus> configure({required bool enabled});
}

class RustNetworkPrivacyRuntime implements NetworkPrivacyRuntime {
  const RustNetworkPrivacyRuntime();

  @override
  Future<NetworkPrivacyConnectionStatus> configure({
    required bool enabled,
  }) async {
    final status = await rust_network_privacy.configureNetworkPrivacy(
      enabled: enabled,
      torDirectory: await getTorDataDirectoryPath(),
    );
    return _connectionStatus(status);
  }
}

NetworkPrivacyConnectionStatus _connectionStatus(
  rust_types.NetworkPrivacyStatus status,
) => switch (status) {
  rust_types.NetworkPrivacyStatus.direct => NetworkPrivacyConnectionStatus.off,
  rust_types.NetworkPrivacyStatus.bootstrapping =>
    NetworkPrivacyConnectionStatus.connecting,
  rust_types.NetworkPrivacyStatus.ready =>
    NetworkPrivacyConnectionStatus.connected,
  rust_types.NetworkPrivacyStatus.failed =>
    NetworkPrivacyConnectionStatus.failed,
};

var _initialNetworkPrivacyState = const NetworkPrivacyState.off();

/// Applies the persisted route before app bootstrap or providers can start any
/// network work. Failure is retained as an enabled/failed state; Rust has
/// already switched to fail-closed routing at that point.
Future<void> initializeNetworkPrivacyRuntime() async {
  const store = SharedPreferencesNetworkPrivacyStore();
  const runtime = RustNetworkPrivacyRuntime();
  final enabled = await store.readTorEnabled();
  if (!enabled) {
    await runtime.configure(enabled: false);
    _initialNetworkPrivacyState = const NetworkPrivacyState.off();
    return;
  }

  _initialNetworkPrivacyState = const NetworkPrivacyState(
    torEnabled: true,
    status: NetworkPrivacyConnectionStatus.connecting,
  );
  try {
    final status = await runtime.configure(enabled: true);
    _initialNetworkPrivacyState = NetworkPrivacyState(
      torEnabled: true,
      status: status,
    );
  } catch (error) {
    _initialNetworkPrivacyState = NetworkPrivacyState(
      torEnabled: true,
      status: NetworkPrivacyConnectionStatus.failed,
      error: error.toString(),
    );
  }
}

final networkPrivacyPreferenceStoreProvider =
    Provider<NetworkPrivacyPreferenceStore>(
      (_) => const SharedPreferencesNetworkPrivacyStore(),
    );

final networkPrivacyRuntimeProvider = Provider<NetworkPrivacyRuntime>(
  (_) => const RustNetworkPrivacyRuntime(),
);

typedef NetworkPrivacyTransportRestart =
    Future<void> Function(Future<void> Function() updateTransport);

final networkPrivacyTransportRestartProvider =
    Provider<NetworkPrivacyTransportRestart>((ref) {
      return (updateTransport) => ref
          .read(syncProvider.notifier)
          .restartSyncAfterTransportChange(updateTransport);
    });

class NetworkPrivacyNotifier extends Notifier<NetworkPrivacyState> {
  var _generation = 0;

  @override
  NetworkPrivacyState build() => _initialNetworkPrivacyState;

  Future<void> setTorEnabled(bool enabled) async {
    final generation = ++_generation;
    final store = ref.read(networkPrivacyPreferenceStoreProvider);
    final runtime = ref.read(networkPrivacyRuntimeProvider);
    final restartTransport = ref.read(networkPrivacyTransportRestartProvider);

    // Persist intent before any runtime change. A crash or bootstrap failure
    // must restart in Tor/fail-closed mode, not silently revert to direct.
    await store.writeTorEnabled(enabled);
    if (generation != _generation) return;

    state = NetworkPrivacyState(
      torEnabled: enabled,
      status: enabled
          ? NetworkPrivacyConnectionStatus.connecting
          : NetworkPrivacyConnectionStatus.off,
    );

    try {
      NetworkPrivacyConnectionStatus? nextStatus;
      await restartTransport(() async {
        nextStatus = await runtime.configure(enabled: enabled);
      });
      if (generation != _generation) return;
      state = NetworkPrivacyState(
        torEnabled: enabled,
        status: nextStatus ?? NetworkPrivacyConnectionStatus.failed,
      );
    } catch (error) {
      if (generation != _generation) return;
      state = NetworkPrivacyState(
        torEnabled: enabled,
        status: NetworkPrivacyConnectionStatus.failed,
        error: error.toString(),
      );
    }
  }

  Future<void> retry() => setTorEnabled(true);
}

final networkPrivacyProvider =
    NotifierProvider<NetworkPrivacyNotifier, NetworkPrivacyState>(
      NetworkPrivacyNotifier.new,
    );
