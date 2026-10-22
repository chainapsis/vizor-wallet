import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

bool get _supportsNativePrivacyShield => supportsNativePrivacyShield(
  isWeb: kIsWeb,
  isMacOS: !kIsWeb && Platform.isMacOS,
  isAndroid: !kIsWeb && Platform.isAndroid,
  isIOS: !kIsWeb && Platform.isIOS,
);

/// Whether the platform can natively blank the app in OS screenshots and
/// screen recordings via the `com.zcash.wallet/privacy_shield` channel.
///
/// - macOS suppresses Mission Control capture of the window.
/// - Android sets `FLAG_SECURE`.
/// - iOS re-parents the window layer into a `secureTextEntry` field's canvas
///   (see `SecureScreenshotShield` in `ios/Runner/AppDelegate.swift`); the
///   screenshot warning sheet stays as a secondary post-capture UX because
///   iOS only notifies after the capture completes.
@visibleForTesting
bool supportsNativePrivacyShield({
  required bool isWeb,
  required bool isMacOS,
  required bool isAndroid,
  required bool isIOS,
}) {
  return !isWeb && (isMacOS || isAndroid || isIOS);
}

abstract final class NativeSensitiveContentBridge {
  static const _channel = MethodChannel('com.zcash.wallet/privacy_shield');

  static final Set<int> _visibleTokens = <int>{};
  static int _nextToken = 0;
  static bool? _lastVisible = false;
  static bool _listening = false;
  static int _requestGeneration = 0;

  /// Native attachment status, not proof that OS capture exclusion works.
  /// Platforms that do not report attachment state leave this as unknown.
  static final status = ValueNotifier<String>('unknown');
  static String? failureReason;

  static void _readStatus(Object? reply) {
    if (reply is! Map || reply['visible'] != _visibleTokens.isNotEmpty) return;
    final state = reply['state'];
    if (!const ['applied', 'pending', 'failed', 'disabled'].contains(state)) {
      return;
    }
    failureReason = reply['reason'] as String?;
    status.value = state as String;
  }

  static int createToken() => _nextToken++;

  static void updateToken(int token, bool visible) {
    if (visible) {
      _visibleTokens.add(token);
    } else {
      _visibleTokens.remove(token);
    }
    _syncIfNeeded();
  }

  static void clearToken(int token) {
    _visibleTokens.remove(token);
    _syncIfNeeded();
  }

  @visibleForTesting
  static void resetForTesting() {
    _visibleTokens.clear();
    _nextToken = 0;
    _lastVisible = false;
    _requestGeneration++;
    status.value = 'unknown';
    failureReason = null;
  }

  static void _syncIfNeeded() {
    if (!_supportsNativePrivacyShield) return;
    final visible = _visibleTokens.isNotEmpty;
    if (_lastVisible == visible) return;
    _lastVisible = visible;
    status.value = 'unknown';
    failureReason = null;
    if (!_listening) {
      _listening = true;
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'protectionStatusChanged') {
          _readStatus(call.arguments);
        }
      });
    }
    unawaited(_setSensitiveContentVisible(visible, ++_requestGeneration));
  }

  static Future<void> _setSensitiveContentVisible(
    bool visible,
    int generation,
  ) async {
    final arguments = <String, Object?>{'visible': visible};

    try {
      final reply = await _channel.invokeMethod<Object?>(
        'setSensitiveContentVisible',
        arguments,
      );
      if (generation == _requestGeneration) _readStatus(reply);
    } catch (error) {
      if (generation != _requestGeneration) return;
      // Allow the next visibility update to retry instead of permanently
      // deduplicating a request that never reached the native implementation.
      _lastVisible = null;
      failureReason = 'channel_error';
      status.value = 'failed';
      debugPrint('Native privacy shield request failed: ${error.runtimeType}');
    }
  }
}

@visibleForTesting
typedef MacOSSensitiveContentBridge = NativeSensitiveContentBridge;
