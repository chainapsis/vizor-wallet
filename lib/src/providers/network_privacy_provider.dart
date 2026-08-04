import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/storage/wallet_paths.dart';
import '../rust/api/network_privacy.dart' as rust_network_privacy;
import '../rust/network_privacy.dart' as rust_types;
import '../services/windows_update_service.dart';
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
  void beginEnable();

  Future<NetworkPrivacyConnectionStatus> configure({required bool enabled});
}

class RustNetworkPrivacyRuntime implements NetworkPrivacyRuntime {
  const RustNetworkPrivacyRuntime();

  @override
  void beginEnable() {
    rust_network_privacy.beginNetworkPrivacyEnable();
  }

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

abstract interface class NetworkPrivacyNativeUpdateCoordinator {
  Future<void> setTorEnabled(bool enabled);
}

class PlatformNetworkPrivacyNativeUpdateCoordinator
    implements NetworkPrivacyNativeUpdateCoordinator {
  const PlatformNetworkPrivacyNativeUpdateCoordinator();

  static const _macosChannel = MethodChannel(
    'com.zcash.wallet/update_network_privacy',
  );

  @override
  Future<void> setTorEnabled(bool enabled) async {
    if (Platform.isWindows && enabled) {
      final update = await WindowsUpdateService().getState();
      if (update.busy) {
        throw StateError(
          'Wait for the current software update operation to finish before '
          'enabling Tor.',
        );
      }
      return;
    }
    if (!Platform.isMacOS) return;
    try {
      await _macosChannel.invokeMethod<void>('setTorEnabled', enabled);
    } on MissingPluginException {
      // Development builds without Sparkle have no native updater to pause.
    }
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
Future<void> initializeNetworkPrivacyRuntime({
  NetworkPrivacyPreferenceStore store =
      const SharedPreferencesNetworkPrivacyStore(),
  NetworkPrivacyRuntime runtime = const RustNetworkPrivacyRuntime(),
  NetworkPrivacyNativeUpdateCoordinator nativeUpdates =
      const PlatformNetworkPrivacyNativeUpdateCoordinator(),
}) async {
  late final bool enabled;
  try {
    enabled = await store.readTorEnabled();
  } catch (error) {
    runtime.beginEnable();
    await nativeUpdates.setTorEnabled(true);
    _initialNetworkPrivacyState = NetworkPrivacyState(
      torEnabled: true,
      status: NetworkPrivacyConnectionStatus.failed,
      error: 'Could not read the saved Tor preference: $error',
    );
    return;
  }
  if (!enabled) {
    await runtime.configure(enabled: false);
    await nativeUpdates.setTorEnabled(false);
    _initialNetworkPrivacyState = const NetworkPrivacyState.off();
    return;
  }

  runtime.beginEnable();
  _initialNetworkPrivacyState = const NetworkPrivacyState(
    torEnabled: true,
    status: NetworkPrivacyConnectionStatus.connecting,
  );
  try {
    await nativeUpdates.setTorEnabled(true);
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

final networkPrivacyNativeUpdateCoordinatorProvider =
    Provider<NetworkPrivacyNativeUpdateCoordinator>(
      (_) => const PlatformNetworkPrivacyNativeUpdateCoordinator(),
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
    final nativeUpdates = ref.read(
      networkPrivacyNativeUpdateCoordinatorProvider,
    );
    final restartTransport = ref.read(networkPrivacyTransportRestartProvider);

    // Enabling blocks new direct requests synchronously, before persistence or
    // channel teardown reaches its first await. Disabling keeps Tor desired
    // until existing Tor work is quiescent and configure(false) runs.
    if (enabled) runtime.beginEnable();
    state = NetworkPrivacyState(
      torEnabled: enabled,
      status: NetworkPrivacyConnectionStatus.connecting,
    );

    try {
      if (enabled) await nativeUpdates.setTorEnabled(true);
      await store.writeTorEnabled(enabled);
      if (generation != _generation) return;

      NetworkPrivacyConnectionStatus? nextStatus;
      await restartTransport(() async {
        nextStatus = await runtime.configure(enabled: enabled);
      });
      if (generation != _generation) return;
      if (!enabled) await nativeUpdates.setTorEnabled(false);
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
