import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/network/network_http_client.dart';
import '../core/storage/wallet_paths.dart';
import '../rust/api/network_privacy.dart' as rust_network_privacy;
import '../rust/network_privacy.dart' as rust_types;
import '../services/desktop_tor_update_proxy.dart';
import '../services/windows_update_service.dart';
import 'sync_provider.dart';

const kTorEnabledPreferenceKey = 'zcash_tor_enabled';
const kTorStartupFailureNotice =
    "Couldn't connect to Tor. Network requests are paused.";
const kTorUpdateInProgressNotice =
    'Finish the current software update before turning on Tor.';
const kTorUpdateUnavailableNotice =
    'Tor is connected, but software updates are unavailable.';
const kSoftwareUpdateUnavailableNotice =
    'Software updates are unavailable. Network requests are still connected.';

enum NetworkPrivacyConnectionStatus { off, connecting, connected, failed }

class NetworkPrivacyState {
  const NetworkPrivacyState({
    required this.torEnabled,
    required this.status,
    this.targetTorEnabled,
    this.softwareUpdatesAvailable = true,
    this.error,
    this.startupNotice,
  });

  const NetworkPrivacyState.off()
    : torEnabled = false,
      status = NetworkPrivacyConnectionStatus.off,
      targetTorEnabled = null,
      softwareUpdatesAvailable = true,
      error = null,
      startupNotice = null;

  final bool torEnabled;
  final NetworkPrivacyConnectionStatus status;
  final bool? targetTorEnabled;
  final bool softwareUpdatesAvailable;
  final String? error;
  final String? startupNotice;

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

  Future<void> quiesceDirectRequests();

  bool isTorEnabled();

  Future<NetworkPrivacyConnectionStatus> configure({required bool enabled});
}

class RustNetworkPrivacyRuntime implements NetworkPrivacyRuntime {
  const RustNetworkPrivacyRuntime({
    this.configureRuntime = rust_network_privacy.configureNetworkPrivacy,
    this.resolveTorDirectory = getTorDataDirectoryPath,
  });

  final Future<rust_types.NetworkPrivacyStatus> Function({
    required bool enabled,
    required String torDirectory,
  })
  configureRuntime;
  final Future<String> Function() resolveTorDirectory;

  @override
  void beginEnable() {
    rust_network_privacy.beginNetworkPrivacyEnable();
  }

  @override
  Future<void> quiesceDirectRequests() =>
      rust_network_privacy.quiesceNetworkPrivacyDirectRequests();

  @override
  bool isTorEnabled() => rust_network_privacy.isTorEnabled();

  @override
  Future<NetworkPrivacyConnectionStatus> configure({
    required bool enabled,
  }) async {
    final status = await configureRuntime(
      enabled: enabled,
      torDirectory: enabled ? await resolveTorDirectory() : '',
    );
    return _connectionStatus(status);
  }
}

abstract interface class NetworkPrivacyNativeUpdateCoordinator {
  Future<void> setTorEnabled(bool enabled);

  Future<void> pauseForFailClosedStartup();

  Future<void> resumeTorUpdates();
}

class PlatformNetworkPrivacyNativeUpdateCoordinator
    implements NetworkPrivacyNativeUpdateCoordinator {
  const PlatformNetworkPrivacyNativeUpdateCoordinator();

  static const _macosChannel = MethodChannel(
    'com.zcash.wallet/update_network_privacy',
  );
  static final _torUpdateProxy = DesktopTorUpdateProxy();

  @override
  Future<void> setTorEnabled(bool enabled) async {
    if (Platform.isWindows) {
      final service = WindowsUpdateService();
      if (enabled) {
        final update = await service.getState();
        if (update.busy) {
          throw StateError(
            'Wait for the current software update operation to finish before '
            'enabling Tor.',
          );
        }
        await service.setTorRouting(enabled: true);
      } else {
        await service.setTorRouting(enabled: false);
        await _torUpdateProxy.stop();
      }
      return;
    }
    if (!Platform.isMacOS) return;
    try {
      await _macosChannel.invokeMethod<void>('setTorEnabled', enabled);
      if (!enabled) await _torUpdateProxy.stop();
    } on MissingPluginException {
      // Development builds without Sparkle have no native updater to pause.
    }
  }

  @override
  Future<void> pauseForFailClosedStartup() async {
    if (Platform.isWindows) {
      // Windows update checks are started by Flutter after this bootstrap, so
      // there cannot be an active native update session at this point.
      await setTorEnabled(true);
      return;
    }
    if (!Platform.isMacOS) return;
    try {
      await _macosChannel.invokeMethod<void>('pauseForFailClosedStartup');
    } on MissingPluginException {
      // Development builds without Sparkle have no native updater to stop.
    }
  }

  @override
  Future<void> resumeTorUpdates() async {
    if (Platform.isWindows) {
      final service = WindowsUpdateService();
      final rawBase = await service.getUpdateBaseUrl();
      if (rawBase == null || rawBase.isEmpty) return;
      final localBase = await _torUpdateProxy.configureWindows(
        Uri.parse(rawBase),
      );
      await service.setTorRouting(
        enabled: true,
        proxyBaseUrl: localBase.toString(),
      );
      return;
    }
    if (!Platform.isMacOS) return;
    try {
      final rawFeed = await _macosChannel.invokeMethod<String>(
        'getUpdateFeedUrl',
      );
      if (rawFeed == null || rawFeed.isEmpty) return;
      final proxy = await _torUpdateProxy.configureMacOS(Uri.parse(rawFeed));
      await _macosChannel.invokeMethod<void>('resumeUpdatesThroughTor', {
        'feedUrl': proxy.feedUrl.toString(),
        'resourceUrl': proxy.resourceUrl.toString(),
      });
    } on MissingPluginException {
      // Development builds without Sparkle have no updater to resume.
    }
  }
}

abstract interface class NetworkPrivacyDirectRequestGate {
  Future<void> quiesce();
  void allow();
}

class AppNetworkPrivacyDirectRequestGate
    implements NetworkPrivacyDirectRequestGate {
  const AppNetworkPrivacyDirectRequestGate();

  @override
  Future<void> quiesce() => NetworkHttpClient.quiesceDirectRequests();

  @override
  void allow() => NetworkHttpClient.allowDirectRequests();
}

class _NetworkPrivacyDrainFailure {
  const _NetworkPrivacyDrainFailure(this.error, this.stackTrace);

  final Object error;
  final StackTrace stackTrace;
}

Future<_NetworkPrivacyDrainFailure?> _captureDirectDrain(
  NetworkPrivacyRuntime runtime,
  NetworkPrivacyDirectRequestGate directRequests,
) async {
  try {
    await Future.wait([
      runtime.quiesceDirectRequests(),
      directRequests.quiesce(),
    ]);
    return null;
  } catch (error, stackTrace) {
    return _NetworkPrivacyDrainFailure(error, stackTrace);
  }
}

void _throwIfDirectDrainFailed(_NetworkPrivacyDrainFailure? failure) {
  if (failure == null) return;
  Error.throwWithStackTrace(failure.error, failure.stackTrace);
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
  NetworkPrivacyDirectRequestGate directRequests =
      const AppNetworkPrivacyDirectRequestGate(),
}) async {
  late final bool enabled;
  try {
    enabled = await store.readTorEnabled();
  } catch (error) {
    Object? nativeUpdateError;
    try {
      await nativeUpdates.pauseForFailClosedStartup();
    } catch (nativeError) {
      nativeUpdateError = nativeError;
    }
    runtime.beginEnable();
    final drainFailure = await _captureDirectDrain(runtime, directRequests);
    final failureDetails = [
      'Could not read the saved Tor preference: $error',
      if (drainFailure != null)
        'Could not stop direct requests: ${drainFailure.error}',
      if (nativeUpdateError != null)
        'Could not pause software updates: $nativeUpdateError',
    ].join(' ');
    _initialNetworkPrivacyState = NetworkPrivacyState(
      torEnabled: true,
      status: NetworkPrivacyConnectionStatus.failed,
      softwareUpdatesAvailable: false,
      error: failureDetails,
      startupNotice: kTorStartupFailureNotice,
    );
    return;
  }
  if (!enabled) {
    await runtime.configure(enabled: false);
    directRequests.allow();
    try {
      await nativeUpdates.setTorEnabled(false);
      _initialNetworkPrivacyState = const NetworkPrivacyState.off();
    } catch (error) {
      _initialNetworkPrivacyState = NetworkPrivacyState(
        torEnabled: false,
        status: NetworkPrivacyConnectionStatus.off,
        softwareUpdatesAvailable: false,
        error: error.toString(),
        startupNotice: kSoftwareUpdateUnavailableNotice,
      );
    }
    return;
  }

  runtime.beginEnable();
  final directDrain = _captureDirectDrain(runtime, directRequests);
  _initialNetworkPrivacyState = const NetworkPrivacyState(
    torEnabled: true,
    status: NetworkPrivacyConnectionStatus.connecting,
  );
  try {
    await nativeUpdates.setTorEnabled(true);
    _throwIfDirectDrainFailed(await directDrain);
    final status = await runtime.configure(enabled: true);
    String? startupNotice;
    var softwareUpdatesAvailable = true;
    if (status == NetworkPrivacyConnectionStatus.connected) {
      try {
        await nativeUpdates.resumeTorUpdates();
      } catch (_) {
        startupNotice = kTorUpdateUnavailableNotice;
        softwareUpdatesAvailable = false;
      }
    }
    _initialNetworkPrivacyState = NetworkPrivacyState(
      torEnabled: true,
      status: status,
      softwareUpdatesAvailable: softwareUpdatesAvailable,
      startupNotice: startupNotice,
    );
  } catch (error) {
    _initialNetworkPrivacyState = NetworkPrivacyState(
      torEnabled: true,
      status: NetworkPrivacyConnectionStatus.failed,
      softwareUpdatesAvailable: false,
      error: error.toString(),
      startupNotice: kTorStartupFailureNotice,
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

final networkPrivacyDirectRequestGateProvider =
    Provider<NetworkPrivacyDirectRequestGate>(
      (_) => const AppNetworkPrivacyDirectRequestGate(),
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

  void clearStartupNotice() {
    if (state.startupNotice == null) return;
    state = NetworkPrivacyState(
      torEnabled: state.torEnabled,
      status: state.status,
      targetTorEnabled: state.targetTorEnabled,
      softwareUpdatesAvailable: state.softwareUpdatesAvailable,
      error: state.error,
    );
  }

  Future<void> setTorEnabled(bool enabled) async {
    final generation = ++_generation;
    final previousState = state;
    final store = ref.read(networkPrivacyPreferenceStoreProvider);
    final runtime = ref.read(networkPrivacyRuntimeProvider);
    final nativeUpdates = ref.read(
      networkPrivacyNativeUpdateCoordinatorProvider,
    );
    final restartTransport = ref.read(networkPrivacyTransportRestartProvider);
    final directRequests = ref.read(networkPrivacyDirectRequestGateProvider);

    // Native updaters do not use the embedded Tor client. Atomically reject an
    // active update session and pause future checks before accepting the route
    // change. Until this preflight succeeds, the previous privacy state stays
    // authoritative.
    if (enabled) {
      try {
        await nativeUpdates.setTorEnabled(true);
      } catch (error) {
        if (generation != _generation) return;
        state = NetworkPrivacyState(
          torEnabled: previousState.torEnabled,
          status: previousState.status,
          targetTorEnabled: true,
          softwareUpdatesAvailable: previousState.softwareUpdatesAvailable,
          error: error.toString(),
          startupNotice: kTorUpdateInProgressNotice,
        );
        return;
      }
      if (generation != _generation) return;
      runtime.beginEnable();
    }

    final directDrain = enabled
        ? _captureDirectDrain(runtime, directRequests)
        : null;

    // Enabling now blocks new direct requests synchronously. The transport
    // restart below starts cancellation before its callback performs any
    // preference write or Tor bootstrap await. Disabling keeps Tor desired
    // until existing Tor work is quiescent and configure(false) runs.
    state = NetworkPrivacyState(
      torEnabled: enabled ? true : previousState.torEnabled,
      status: NetworkPrivacyConnectionStatus.connecting,
      targetTorEnabled: enabled,
      softwareUpdatesAvailable: previousState.softwareUpdatesAvailable,
    );

    try {
      NetworkPrivacyConnectionStatus? nextStatus;
      await restartTransport(() async {
        if (directDrain != null) {
          _throwIfDirectDrainFailed(await directDrain);
        }
        if (generation != _generation) return;
        await store.writeTorEnabled(enabled);
        nextStatus = await runtime.configure(enabled: enabled);
        if (!enabled) {
          directRequests.allow();
        }
      });
      if (generation != _generation) return;
      String? startupNotice;
      var softwareUpdatesAvailable = true;
      if (enabled && nextStatus == NetworkPrivacyConnectionStatus.connected) {
        try {
          await nativeUpdates.resumeTorUpdates();
        } catch (_) {
          startupNotice = kTorUpdateUnavailableNotice;
          softwareUpdatesAvailable = false;
        }
      } else if (!enabled) {
        try {
          await nativeUpdates.setTorEnabled(false);
        } catch (_) {
          startupNotice = kSoftwareUpdateUnavailableNotice;
          softwareUpdatesAvailable = false;
        }
      }
      state = NetworkPrivacyState(
        torEnabled: runtime.isTorEnabled(),
        status: nextStatus ?? NetworkPrivacyConnectionStatus.failed,
        softwareUpdatesAvailable: softwareUpdatesAvailable,
        startupNotice: startupNotice,
      );
    } catch (error) {
      if (generation != _generation) return;
      final effectiveTorEnabled = runtime.isTorEnabled();
      state = NetworkPrivacyState(
        torEnabled: effectiveTorEnabled,
        status: NetworkPrivacyConnectionStatus.failed,
        targetTorEnabled: enabled,
        softwareUpdatesAvailable: enabled
            ? false
            : previousState.softwareUpdatesAvailable,
        error: error.toString(),
      );
    }
  }

  Future<void> retry() =>
      setTorEnabled(state.targetTorEnabled ?? state.torEnabled);

  Future<void> retrySoftwareUpdates() async {
    if (state.status != NetworkPrivacyConnectionStatus.connected &&
        state.status != NetworkPrivacyConnectionStatus.off) {
      return;
    }
    final nativeUpdates = ref.read(
      networkPrivacyNativeUpdateCoordinatorProvider,
    );
    try {
      if (state.torEnabled) {
        await nativeUpdates.resumeTorUpdates();
      } else {
        await nativeUpdates.setTorEnabled(false);
      }
      state = NetworkPrivacyState(
        torEnabled: state.torEnabled,
        status: state.status,
        softwareUpdatesAvailable: true,
      );
    } catch (error) {
      state = NetworkPrivacyState(
        torEnabled: state.torEnabled,
        status: state.status,
        softwareUpdatesAvailable: false,
        error: error.toString(),
        startupNotice: state.torEnabled
            ? kTorUpdateUnavailableNotice
            : kSoftwareUpdateUnavailableNotice,
      );
    }
  }
}

final networkPrivacyProvider =
    NotifierProvider<NetworkPrivacyNotifier, NetworkPrivacyState>(
      NetworkPrivacyNotifier.new,
    );
