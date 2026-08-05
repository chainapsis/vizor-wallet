import 'dart:io' show Platform;

import 'package:flutter/services.dart';

class WindowsUpdateSnapshot {
  const WindowsUpdateSnapshot({
    required this.supported,
    required this.busy,
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

  factory WindowsUpdateSnapshot.unavailable() {
    return const WindowsUpdateSnapshot(
      supported: false,
      busy: false,
      status: 'unavailable',
      currentVersion: '',
      appId: '',
      repoUrl: '',
      availableVersion: '',
      downloadProgress: 0,
      pendingRestart: false,
      torProxyReady: false,
      message: '',
    );
  }

  factory WindowsUpdateSnapshot.fromMap(Map<dynamic, dynamic> map) {
    return WindowsUpdateSnapshot(
      supported: map['supported'] == true,
      busy: map['busy'] == true,
      status: _stringValue(map['status'], fallback: 'unavailable'),
      currentVersion: _stringValue(map['currentVersion']),
      appId: _stringValue(map['appId']),
      repoUrl: _stringValue(map['repoUrl']),
      availableVersion: _stringValue(map['availableVersion']),
      downloadProgress: _intValue(map['downloadProgress']).clamp(0, 100),
      pendingRestart: map['pendingRestart'] == true,
      torProxyReady: map['torProxyReady'] == true,
      message: _stringValue(map['message']),
    );
  }

  final bool supported;
  final bool busy;
  final String status;
  final String currentVersion;
  final String appId;
  final String repoUrl;
  final String availableVersion;
  final int downloadProgress;
  final bool pendingRestart;
  final bool torProxyReady;
  final String message;

  static String _stringValue(Object? value, {String fallback = ''}) {
    return value is String ? value : fallback;
  }

  static int _intValue(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return 0;
  }
}

class WindowsUpdateService {
  static const _channel = MethodChannel('com.zcash.wallet/windows_update');

  Future<WindowsUpdateSnapshot> getState() => _invoke('getState');

  Future<WindowsUpdateSnapshot> checkForUpdates() => _invoke('checkForUpdates');

  Future<WindowsUpdateSnapshot> downloadUpdate() => _invoke('downloadUpdate');

  Future<WindowsUpdateSnapshot> applyUpdateAndRestart() =>
      _invoke('applyUpdateAndRestart');

  Future<String?> getUpdateBaseUrl() async {
    if (!Platform.isWindows) return null;
    try {
      return await _channel.invokeMethod<String>('getUpdateBaseUrl');
    } on MissingPluginException {
      return null;
    }
  }

  Future<void> setTorRouting({
    required bool enabled,
    String? proxyBaseUrl,
  }) async {
    if (!Platform.isWindows) return;
    try {
      await _channel.invokeMethod<void>('setTorRouting', {
        'enabled': enabled,
        'proxyBaseUrl': proxyBaseUrl,
      });
    } on MissingPluginException {
      // Development builds without Velopack have no updater to configure.
    }
  }

  Future<WindowsUpdateSnapshot> _invoke(String method) async {
    if (!Platform.isWindows) {
      return WindowsUpdateSnapshot.unavailable();
    }

    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>(method);
      if (raw == null) return WindowsUpdateSnapshot.unavailable();
      return WindowsUpdateSnapshot.fromMap(raw);
    } on MissingPluginException {
      return WindowsUpdateSnapshot.unavailable();
    }
  }
}
