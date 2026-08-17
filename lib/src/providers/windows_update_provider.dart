import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_version_config.dart';
import '../rust/api/network_privacy.dart' as rust_network_privacy;
import '../services/windows_update_service.dart';

enum WindowsUpdateStatus {
  unavailable,
  idle,
  checking,
  noUpdate,
  available,
  downloading,
  ready,
  applying,
  failed,
}

const kWindowsTorUpdateRouteUnavailableMessage =
    'The software updater is not connected to Tor. Retry updates in Settings, '
    'or turn off Tor and try again.';

const kWindowsUpdateGenericFailureMessage =
    "Couldn't complete the update. Try again.";

class WindowsUpdateDownloadResult {
  const WindowsUpdateDownloadResult.started() : started = true, message = '';

  const WindowsUpdateDownloadResult.failed(this.message) : started = false;

  final bool started;
  final String message;
}

/// Why an update operation failed, and whether the user was waiting on it.
///
/// A background startup check that fails must stay silent — the route recovery
/// listener re-runs it — while a failure the user asked for has to be visible.
/// [ordinal] increments per failure so that dismissing one card does not
/// suppress the next failure carrying the same status and version.
class WindowsUpdateFailure {
  const WindowsUpdateFailure({
    required this.userInitiated,
    required this.ordinal,
  });

  final bool userInitiated;
  final int ordinal;
}

class WindowsUpdateState {
  const WindowsUpdateState({
    required this.supported,
    required this.status,
    required this.currentVersion,
    required this.appId,
    required this.repoUrl,
    required this.availableVersion,
    required this.downloadProgress,
    required this.pendingRestart,
    required this.torProxyReady,
    required this.message,
    this.failure,
  });

  factory WindowsUpdateState.initial() {
    return WindowsUpdateState(
      supported: Platform.isWindows,
      status: Platform.isWindows
          ? WindowsUpdateStatus.idle
          : WindowsUpdateStatus.unavailable,
      currentVersion: kVizorReleaseVersion,
      appId: '',
      repoUrl: '',
      availableVersion: '',
      downloadProgress: 0,
      pendingRestart: false,
      torProxyReady: false,
      message: '',
    );
  }

  factory WindowsUpdateState.fromSnapshot(
    WindowsUpdateSnapshot snapshot, {
    WindowsUpdateFailure? failure,
  }) {
    return WindowsUpdateState(
      failure: failure,
      supported: snapshot.supported,
      status: _statusFromName(snapshot.status, snapshot.supported),
      currentVersion: snapshot.currentVersion.isEmpty
          ? kVizorReleaseVersion
          : snapshot.currentVersion,
      appId: snapshot.appId,
      repoUrl: snapshot.repoUrl,
      availableVersion: snapshot.availableVersion,
      downloadProgress: snapshot.downloadProgress,
      pendingRestart: snapshot.pendingRestart,
      torProxyReady: snapshot.torProxyReady,
      message: snapshot.message,
    );
  }

  final bool supported;
  final WindowsUpdateStatus status;
  final String currentVersion;
  final String appId;
  final String repoUrl;
  final String availableVersion;
  final int downloadProgress;
  final bool pendingRestart;
  final bool torProxyReady;
  final String message;

  /// Set only while [status] is [WindowsUpdateStatus.failed]. Carries what the
  /// prompt needs to decide whether the user should be interrupted, and to tell
  /// two consecutive failures apart.
  final WindowsUpdateFailure? failure;

  bool get isBusy => switch (status) {
    WindowsUpdateStatus.checking ||
    WindowsUpdateStatus.downloading ||
    WindowsUpdateStatus.applying => true,
    _ => false,
  };

  bool get canCheck => supported && !isBusy;

  bool get canDownload =>
      supported && !isBusy && status == WindowsUpdateStatus.available;

  bool get canRestart =>
      supported && !isBusy && status == WindowsUpdateStatus.ready;

  static WindowsUpdateStatus _statusFromName(String name, bool supported) {
    if (!supported) return WindowsUpdateStatus.unavailable;
    return switch (name) {
      'idle' => WindowsUpdateStatus.idle,
      'checking' => WindowsUpdateStatus.checking,
      'noUpdate' => WindowsUpdateStatus.noUpdate,
      'available' => WindowsUpdateStatus.available,
      'downloading' => WindowsUpdateStatus.downloading,
      'ready' => WindowsUpdateStatus.ready,
      'applying' => WindowsUpdateStatus.applying,
      'failed' => WindowsUpdateStatus.failed,
      _ => WindowsUpdateStatus.unavailable,
    };
  }
}

final windowsUpdateServiceProvider = Provider<WindowsUpdateService>(
  (ref) => WindowsUpdateService(),
);

final windowsUpdateTorEnabledProvider = Provider<bool Function()>(
  (_) => rust_network_privacy.isTorEnabled,
);

class WindowsUpdateNotifier extends Notifier<WindowsUpdateState> {
  Timer? _pollTimer;
  bool _polling = false;
  bool _startupCheckStarted = false;
  int _failureOrdinal = 0;
  // Whether the operation currently in flight — including the poll that
  // watches it finish — is one the user is waiting on.
  bool _userInitiatedOperation = true;

  @override
  WindowsUpdateState build() {
    ref.onDispose(() {
      _pollTimer?.cancel();
      _pollTimer = null;
    });
    return WindowsUpdateState.initial();
  }

  Future<void> checkOnStartup() async {
    if (!Platform.isWindows) return;
    await runStartupCheck();
  }

  @visibleForTesting
  Future<void> runStartupCheck() async {
    if (_startupCheckStarted) return;
    // The startup check is automatic and re-armed once the route recovers, so
    // an unusable route stays silent instead of raising a failure the user
    // never asked for.
    if (!await _updateNetworkReady()) return;
    _startupCheckStarted = true;
    _userInitiatedOperation = false;
    try {
      await _runAndPoll(
        ref.read(windowsUpdateServiceProvider).checkForUpdates(),
      );
    } catch (error) {
      // Callers start this unawaited, so an escaping error would surface as an
      // unhandled async error and leave the check permanently spent. Record it
      // silently and let route recovery run it again.
      debugPrint('[zcash] Windows startup update check failed: $error');
      _setFailed(_updateErrorMessage(error));
      _startupCheckStarted = false;
    }
  }

  Future<void> refresh() async {
    await _updateFrom(ref.read(windowsUpdateServiceProvider).getState());
  }

  Future<void> checkForUpdates() async {
    _userInitiatedOperation = true;
    if (!await _updateNetworkReady()) {
      _setFailed(kWindowsTorUpdateRouteUnavailableMessage);
      return;
    }
    try {
      await _runAndPoll(
        ref.read(windowsUpdateServiceProvider).checkForUpdates(),
      );
    } catch (error) {
      _setFailed(_updateErrorMessage(error));
    }
  }

  Future<WindowsUpdateDownloadResult> downloadUpdate() async {
    if (!state.canDownload) {
      return const WindowsUpdateDownloadResult.failed(
        'This update is no longer ready to download. Check for updates again.',
      );
    }

    _userInitiatedOperation = true;
    try {
      if (!await _updateNetworkReady()) {
        return const WindowsUpdateDownloadResult.failed(
          kWindowsTorUpdateRouteUnavailableMessage,
        );
      }
      await _runAndPoll(
        ref.read(windowsUpdateServiceProvider).downloadUpdate(),
      );
    } catch (error) {
      final message = _updateErrorMessage(error);
      _setFailed(message);
      return WindowsUpdateDownloadResult.failed(message);
    }

    if (state.status == WindowsUpdateStatus.failed) {
      final message = state.message.trim();
      return WindowsUpdateDownloadResult.failed(
        message.isEmpty ? kWindowsUpdateGenericFailureMessage : message,
      );
    }
    return const WindowsUpdateDownloadResult.started();
  }

  Future<void> applyUpdateAndRestart() async {
    if (!state.canRestart) return;
    _userInitiatedOperation = true;
    try {
      await _runAndPoll(
        ref.read(windowsUpdateServiceProvider).applyUpdateAndRestart(),
      );
    } catch (error) {
      _setFailed(_updateErrorMessage(error));
    }
  }

  bool get _torEnabled => ref.read(windowsUpdateTorEnabledProvider)();

  Future<bool> _updateNetworkReady() async {
    if (!_torEnabled) return true;
    final snapshot = await ref.read(windowsUpdateServiceProvider).getState();
    return snapshot.torProxyReady;
  }

  Future<void> _runAndPoll(Future<WindowsUpdateSnapshot> action) async {
    _pollTimer?.cancel();
    await _updateFrom(action);
    _startPollingIfBusy();
  }

  Future<void> _updateFrom(Future<WindowsUpdateSnapshot> action) async {
    final snapshot = await action;
    final next = WindowsUpdateState.fromSnapshot(snapshot);
    if (next.status != WindowsUpdateStatus.failed) {
      state = next;
      return;
    }
    state = WindowsUpdateState.fromSnapshot(snapshot, failure: _nextFailure());
    // The native check runs detached and can report its failure through a
    // later polled snapshot rather than by throwing, so the startup check has
    // to be re-armed here too or route recovery can never retry it.
    if (!_userInitiatedOperation) _startupCheckStarted = false;
  }

  WindowsUpdateFailure _nextFailure() => WindowsUpdateFailure(
    userInitiated: _userInitiatedOperation,
    ordinal: ++_failureOrdinal,
  );

  void _setFailed(String message) {
    final current = state;
    state = WindowsUpdateState(
      supported: current.supported,
      status: WindowsUpdateStatus.failed,
      currentVersion: current.currentVersion,
      appId: current.appId,
      repoUrl: current.repoUrl,
      availableVersion: current.availableVersion,
      downloadProgress: current.downloadProgress,
      pendingRestart: current.pendingRestart,
      torProxyReady: current.torProxyReady,
      message: message,
      failure: _nextFailure(),
    );
  }

  void _startPollingIfBusy() {
    _pollTimer?.cancel();
    if (!state.isBusy) return;

    _pollTimer = Timer.periodic(const Duration(milliseconds: 500), (_) async {
      if (_polling) return;
      _polling = true;
      try {
        await refresh();
        if (!state.isBusy) {
          _pollTimer?.cancel();
          _pollTimer = null;
        }
      } finally {
        _polling = false;
      }
    });
  }
}

String _updateErrorMessage(Object error) {
  if (error is PlatformException) {
    final message = error.message?.trim();
    if (message != null && message.isNotEmpty) return message;
  }
  // Only the native updater writes copy meant for the user. Anything else can
  // carry local paths or transport internals, so it stays in the log.
  debugPrint('[zcash] Windows update failed: $error');
  return kWindowsUpdateGenericFailureMessage;
}

final windowsUpdateProvider =
    NotifierProvider<WindowsUpdateNotifier, WindowsUpdateState>(
      WindowsUpdateNotifier.new,
    );
