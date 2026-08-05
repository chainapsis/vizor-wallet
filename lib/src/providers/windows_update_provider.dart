import 'dart:async';
import 'dart:io' show Platform;

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

class WindowsUpdateDownloadResult {
  const WindowsUpdateDownloadResult.started() : started = true, message = '';

  const WindowsUpdateDownloadResult.failed(this.message) : started = false;

  final bool started;
  final String message;
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

  factory WindowsUpdateState.fromSnapshot(WindowsUpdateSnapshot snapshot) {
    return WindowsUpdateState(
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

  @override
  WindowsUpdateState build() {
    ref.onDispose(() {
      _pollTimer?.cancel();
      _pollTimer = null;
    });
    return WindowsUpdateState.initial();
  }

  Future<void> checkOnStartup() async {
    if (_startupCheckStarted || !Platform.isWindows) return;
    if (!await _updateNetworkReady()) return;
    _startupCheckStarted = true;
    await checkForUpdates();
  }

  Future<void> refresh() async {
    await _updateFrom(ref.read(windowsUpdateServiceProvider).getState());
  }

  Future<void> checkForUpdates() async {
    if (!await _updateNetworkReady()) return;
    await _runAndPoll(ref.read(windowsUpdateServiceProvider).checkForUpdates());
  }

  Future<WindowsUpdateDownloadResult> downloadUpdate() async {
    if (!state.canDownload) {
      return const WindowsUpdateDownloadResult.failed(
        'This update is no longer ready to download. Check for updates again.',
      );
    }

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
        message.isEmpty ? "Couldn't complete the update. Try again." : message,
      );
    }
    return const WindowsUpdateDownloadResult.started();
  }

  Future<void> applyUpdateAndRestart() async {
    if (!state.canRestart) return;
    await _runAndPoll(
      ref.read(windowsUpdateServiceProvider).applyUpdateAndRestart(),
    );
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
    state = WindowsUpdateState.fromSnapshot(snapshot);
  }

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
  final message = error.toString().trim();
  return message.isEmpty ? "Couldn't complete the update. Try again." : message;
}

final windowsUpdateProvider =
    NotifierProvider<WindowsUpdateNotifier, WindowsUpdateState>(
      WindowsUpdateNotifier.new,
    );
