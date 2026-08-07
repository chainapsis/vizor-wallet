import 'dart:async' show unawaited;
import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/layout/app_form_factor.dart';
import '../core/layout/app_process_work_policy.dart';
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
const kTorDisableUpdateInProgressNotice =
    'Finish the current software update before turning off Tor.';
const kTorUpdateUnavailableNotice =
    'Tor is connected, but software updates are unavailable. Turn off Tor to update directly.';
const kSoftwareUpdateUnavailableNotice =
    'Software updates are unavailable. Other network requests still use a direct connection.';

enum NetworkPrivacyConnectionStatus { off, connecting, connected, failed }

class NetworkPrivacyState {
  const NetworkPrivacyState({
    required this.torEnabled,
    required this.status,
    this.targetTorEnabled,
    this.softwareUpdatesAvailable = true,
    this.error,
    this.startupNotice,
    bool? savedRouteTorEnabled,
  }) : savedRouteTorEnabled = savedRouteTorEnabled ?? torEnabled;

  const NetworkPrivacyState.off()
    : torEnabled = false,
      status = NetworkPrivacyConnectionStatus.off,
      targetTorEnabled = null,
      softwareUpdatesAvailable = true,
      error = null,
      startupNotice = null,
      savedRouteTorEnabled = false;

  final bool torEnabled;
  /// The route a background wake into a cold process will read.
  ///
  /// Saved and enforced may diverge in one direction only — saved stricter —
  /// and exactly one published state carries the divergence: a disable whose
  /// transport switched and whose preference write then failed. Surfaces that
  /// describe what the native background lanes will do must read this rather
  /// than [torEnabled], because those lanes read the saved preference, not
  /// this process's memory.
  final bool savedRouteTorEnabled;
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
    this.excludeTorDirectoryFromBackup = _excludeFromDeviceBackup,
  });

  final Future<rust_types.NetworkPrivacyStatus> Function({
    required bool enabled,
    required String torDirectory,
  })
  configureRuntime;
  final Future<String> Function() resolveTorDirectory;
  final Future<void> Function(String directory) excludeTorDirectoryFromBackup;

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
    final torDirectory = enabled ? await resolveTorDirectory() : '';
    // Arti's directory records which guards this wallet chose. Restoring it
    // onto a second device would carry that choice across, so keep it out of
    // device backups and let a restored install pick fresh guards.
    //
    // Marked before the bootstrap, because from its first moment the directory
    // holds guard state and the process can be killed at any point during it —
    // and again afterwards, because the mark is best-effort and the run that
    // matters is the one that succeeds.
    await _markTorDirectory(enabled, torDirectory);
    try {
      final status = await configureRuntime(
        enabled: enabled,
        torDirectory: torDirectory,
      );
      return _connectionStatus(status);
    } finally {
      await _markTorDirectory(enabled, torDirectory);
    }
  }

  Future<void> _markTorDirectory(bool enabled, String torDirectory) async {
    if (!enabled) return;
    try {
      await excludeTorDirectoryFromBackup(torDirectory);
    } catch (error, stackTrace) {
      // A weaker backup posture is not a reason to fail the route.
      debugPrint(
        'RustNetworkPrivacyRuntime: failed to keep the Tor directory out '
        'of device backups: $error\n$stackTrace',
      );
    }
  }
}

const _deviceBackupChannel = MethodChannel('com.zcash.wallet/network_privacy');

Future<void> _excludeFromDeviceBackup(String directory) async {
  // Android has no runtime equivalent. `android:allowBackup="false"` in the
  // manifest keeps app files out of cloud backup, but from targetSdk 31 that
  // attribute no longer covers device-to-device transfer; excluding the
  // directory from a phone-to-phone migration takes `<device-transfer>`
  // data-extraction rules in the manifest, which the app does not carry.
  if (!Platform.isIOS) return;
  try {
    await _deviceBackupChannel.invokeMethod<void>('excludeFromBackup', {
      'path': directory,
    });
  } on MissingPluginException {
    // Test hosts and older builds have no native side to ask.
  }
}

abstract interface class NetworkPrivacyNativeUpdateCoordinator {
  Future<void> prepareForTorDisable();

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

  static void registerDisableTorForUpdateHandler(
    Future<bool> Function() handler,
  ) {
    _macosChannel.setMethodCallHandler((call) async {
      if (call.method != 'disableTorForUpdate') {
        throw MissingPluginException('Unknown update privacy method.');
      }
      return handler();
    });
  }

  static void clearDisableTorForUpdateHandler() {
    _macosChannel.setMethodCallHandler(null);
  }

  @override
  Future<void> prepareForTorDisable() async {
    if (Platform.isWindows) {
      await WindowsUpdateService().prepareForTorDisable();
      return;
    }
    if (!Platform.isMacOS) return;
    try {
      await _macosChannel.invokeMethod<void>('prepareForTorDisable');
    } on MissingPluginException {
      // Development builds without Sparkle have no updater to drain.
    }
  }

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

/// Whether a (saved route, enforced route) pair is one a background wake can be
/// trusted with.
///
/// The saved value is the only thing a process that never ran Dart has to go
/// on. A background wake reads it, declares that route to Rust, and — finding
/// direct — queries lightwalletd and broadcasts already-signed transactions
/// over a direct connection. So the saved value may be stricter than what this
/// process is enforcing, never laxer: a wake that declares Tor and cannot
/// afford it defers, which costs a delay, while a wake that declares direct
/// against a session enforcing Tor leaks.
///
/// A route change therefore persists in whichever order keeps this true at
/// every point in between: tightening writes before the runtime switch, so a
/// failure in between leaves the strict value behind; loosening writes after
/// it, so the lax value never precedes the runtime it describes.
bool networkPrivacyPersistedRouteIsSafe({
  required bool persistedTorEnabled,
  required bool runtimeTorDesired,
}) => persistedTorEnabled || !runtimeTorDesired;

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

/// Tor activation left running by [initializeNetworkPrivacyRuntime] when the
/// persisted route is Tor. `null` on every other startup path.
Future<NetworkPrivacyState?>? _pendingStartupActivation;

/// Set as soon as the user picks a route, so the startup activation stops
/// before its next mutation. Rust already refuses a stale enable, but the
/// native updaters would otherwise be left routed for a Tor session the user
/// has since turned off.
var _startupActivationSuperseded = false;

/// A saved Tor preference must not be able to keep the app from launching, so
/// the fail-closed startup pause waits only this long for an active native
/// update session to finish.
const _kStartupNativeUpdatePauseTimeout = Duration(seconds: 10);

/// Ties the process-wide Tor dormancy intent to the app lifecycle.
///
/// Owned here rather than by a provider because a provider only exists once
/// something reads it, and the launch that most needs this one reads the least:
/// a locked app routes to `/unlock`, the keep-awake providers return early on
/// `requiresUnlock` before they reach `syncProvider`, and the unlock screens
/// only read it when the user submits. Meanwhile the persisted route is applied
/// regardless of the lock, so Tor can be up and padding its guard connection
/// with nothing constructed to put it to sleep when the user walks away.
///
/// Rust holds the intent process-wide and applies it to the client whenever one
/// appears, so an intent stated before a bootstrap finishes is not lost.
AppLifecycleListener? _torDormancyLifecycle;

/// Starts the lifecycle owner, replacing any previous one.
///
/// Sleeping is asked for only where backgrounding actually stops this process
/// working: a desktop app with every window hidden keeps polling, and a client
/// put to sleep underneath it would pay a circuit build on each of those polls.
void startTorDormancyLifecycle({
  void Function({required bool dormant}) setTorDormant =
      rust_network_privacy.setNetworkPrivacyDormant,
  AppFormFactor formFactor = kAppFormFactor,
}) {
  _torDormancyLifecycle?.dispose();
  _torDormancyLifecycle = AppLifecycleListener(
    // Asked for on every foreground entry, not only after a sleep this owner
    // requested: a request that outlived its asker — issued before Tor
    // finished bootstrapping, so it lands on the client only once that client
    // exists — would otherwise keep the client asleep for the whole foreground
    // session.
    onResume: () => setTorDormant(dormant: false),
    onHide: () {
      if (!canRunAppProcessWork(
        isInForeground: false,
        formFactor: formFactor,
      )) {
        setTorDormant(dormant: true);
      }
    },
  );
}

@visibleForTesting
void disposeTorDormancyLifecycle() {
  _torDormancyLifecycle?.dispose();
  _torDormancyLifecycle = null;
}

/// Applies the persisted route before app bootstrap or providers can start any
/// network work. Failure is retained as an enabled/failed state; Rust has
/// already switched to fail-closed routing at that point.
///
/// This never waits for Tor to bootstrap. `beginEnable` installs fail-closed
/// routing synchronously, so blocking here would only delay the first frame —
/// and on a network that blocks Tor it would delay it forever, leaving the
/// user no window to turn the setting back off from.
Future<void> initializeNetworkPrivacyRuntime({
  NetworkPrivacyPreferenceStore store =
      const SharedPreferencesNetworkPrivacyStore(),
  NetworkPrivacyRuntime runtime = const RustNetworkPrivacyRuntime(),
  NetworkPrivacyNativeUpdateCoordinator nativeUpdates =
      const PlatformNetworkPrivacyNativeUpdateCoordinator(),
  NetworkPrivacyDirectRequestGate directRequests =
      const AppNetworkPrivacyDirectRequestGate(),
}) async {
  _pendingStartupActivation = null;
  _startupActivationSuperseded = false;
  // Before the route is applied, and outside the try: the owner has to exist
  // on every launch, including the one where reading the preference throws and
  // this process goes fail-closed Tor without ever being asked.
  startTorDormancyLifecycle();
  late final bool enabled;
  try {
    enabled = await store.readTorEnabled();
  } catch (error) {
    Object? nativeUpdateError;
    try {
      // On macOS this waits for Sparkle to finish an already-running update
      // cycle. Bound it: an updater that never reports back must not hold the
      // first frame hostage.
      await nativeUpdates.pauseForFailClosedStartup().timeout(
        _kStartupNativeUpdatePauseTimeout,
      );
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
  // Started, deliberately not awaited: the app launches into the connecting
  // state and `networkPrivacyProvider` publishes the outcome when it arrives.
  _pendingStartupActivation = _activateTorForStartup(
    runtime: runtime,
    nativeUpdates: nativeUpdates,
    directDrain: directDrain,
  );
}

Future<NetworkPrivacyState?> _activateTorForStartup({
  required NetworkPrivacyRuntime runtime,
  required NetworkPrivacyNativeUpdateCoordinator nativeUpdates,
  required Future<_NetworkPrivacyDrainFailure?> directDrain,
}) async {
  try {
    if (_startupActivationSuperseded) return null;
    await nativeUpdates.setTorEnabled(true);
    _throwIfDirectDrainFailed(await directDrain);
    if (_startupActivationSuperseded) return null;
    final status = await runtime.configure(enabled: true);
    if (_startupActivationSuperseded) return null;
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
    return NetworkPrivacyState(
      torEnabled: true,
      status: status,
      softwareUpdatesAvailable: softwareUpdatesAvailable,
      startupNotice: startupNotice,
    );
  } catch (error) {
    if (_startupActivationSuperseded) return null;
    return NetworkPrivacyState(
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
  NetworkPrivacyState build() {
    final pending = _pendingStartupActivation;
    if (pending != null) {
      _pendingStartupActivation = null;
      final generation = _generation;
      var disposed = false;
      ref.onDispose(() => disposed = true);
      unawaited(
        pending.then((activated) {
          // A user toggle during startup bootstrap owns the route instead.
          if (activated == null || disposed || generation != _generation) {
            return;
          }
          _initialNetworkPrivacyState = activated;
          state = activated;
        }),
      );
    }
    return _initialNetworkPrivacyState;
  }

  /// Publishes the Direct route a wallet reset has already applied to Rust.
  ///
  /// The reset switches the runtime itself, because routing a wipe through
  /// [setTorEnabled] would restart sync against the database being deleted.
  /// This keeps the published state from outliving the wallet it belonged to.
  void markRouteDirectAfterReset() {
    _startupActivationSuperseded = true;
    ++_generation;
    _initialNetworkPrivacyState = const NetworkPrivacyState.off();
    state = const NetworkPrivacyState.off();
  }

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
    _startupActivationSuperseded = true;
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
      // The saved route is written before this process changes at all. The
      // two halves may diverge in only one direction: saved may be stricter
      // than the route the user has been told about, never laxer. Written
      // after `beginEnable`, a failed write would leave this process
      // enforcing Tor while the saved route still said direct — and the
      // saved half is what a relaunch believes, so restarting the app would
      // silently undo a choice the user never reversed. Written first, a
      // failure aborts a toggle that has not changed anything yet: the route
      // is still direct, requests still flow, nothing needs rolling back.
      try {
        await store.writeTorEnabled(true);
      } catch (error) {
        if (generation != _generation) return;
        // Undo the updater preflight so software updates are not left routed
        // for a Tor session that never started. Best-effort: failing here
        // only pauses update checks, and `retry()` re-runs the whole toggle.
        var softwareUpdatesAvailable = previousState.softwareUpdatesAvailable;
        try {
          await nativeUpdates.setTorEnabled(false);
        } catch (_) {
          softwareUpdatesAvailable = false;
        }
        if (generation != _generation) return;
        state = NetworkPrivacyState(
          torEnabled: previousState.torEnabled,
          status: NetworkPrivacyConnectionStatus.failed,
          targetTorEnabled: true,
          softwareUpdatesAvailable: softwareUpdatesAvailable,
          error: error.toString(),
        );
        return;
      }
      if (generation != _generation) return;
      runtime.beginEnable();
    } else {
      state = NetworkPrivacyState(
        torEnabled: previousState.torEnabled,
        status: NetworkPrivacyConnectionStatus.connecting,
        targetTorEnabled: false,
        softwareUpdatesAvailable: previousState.softwareUpdatesAvailable,
      );
      try {
        // Keep the current Tor updater proxy alive until a running native
        // update cycle has finished. Only then may the shared Tor runtime and
        // its loopback relay be switched back to direct routing.
        await nativeUpdates.prepareForTorDisable();
      } catch (error) {
        if (generation != _generation) return;
        state = NetworkPrivacyState(
          torEnabled: previousState.torEnabled,
          status: previousState.status,
          targetTorEnabled: false,
          softwareUpdatesAvailable: previousState.softwareUpdatesAvailable,
          error: error.toString(),
          startupNotice: kTorDisableUpdateInProgressNotice,
        );
        return;
      }
      if (generation != _generation) return;
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
        // Re-check after every suspension point: a superseded disable that
        // reached `configure(false)` or `allow()` would reopen clearnet
        // underneath a newer enable that has already gone fail-closed.
        if (generation != _generation) return;
        nextStatus = await runtime.configure(enabled: enabled);
        if (enabled || generation != _generation) return;
        try {
          // Written only now that the runtime has actually gone direct — the
          // mirror of the enable ordering above. Saved any earlier, a
          // relaunch would read direct while this process was still
          // enforcing Tor.
          await store.writeTorEnabled(false);
        } finally {
          // The gate follows the runtime, not the preference. Rust is on the
          // direct route with its Tor client dropped, so a gate left shut
          // would strand every direct request for the rest of the session
          // while the UI reports Tor off. A failed write leaves the saved
          // route at Tor — the stricter half — so the next launch comes back
          // on Tor instead of silently staying direct.
          if (generation == _generation) directRequests.allow();
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
      var softwareUpdatesAvailable = enabled
          ? false
          : previousState.softwareUpdatesAvailable;
      String? startupNotice;
      if (!enabled && effectiveTorEnabled) {
        try {
          await nativeUpdates.resumeTorUpdates();
        } catch (_) {
          softwareUpdatesAvailable = false;
          startupNotice = kTorUpdateUnavailableNotice;
        }
      }
      if (generation != _generation) return;
      state = NetworkPrivacyState(
        torEnabled: effectiveTorEnabled,
        status: NetworkPrivacyConnectionStatus.failed,
        targetTorEnabled: enabled,
        softwareUpdatesAvailable: softwareUpdatesAvailable,
        error: error.toString(),
        startupNotice: startupNotice,
        // A disable that switched the transport and then failed to save is
        // the one state whose saved half is stricter than its enforced half:
        // the preference still says Tor, and that is what a background wake
        // will read.
        savedRouteTorEnabled: !enabled && !effectiveTorEnabled ? true : null,
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
