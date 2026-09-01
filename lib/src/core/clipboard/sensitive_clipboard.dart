import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

const sensitiveClipboardDefaultExpiration = Duration(minutes: 1);

abstract final class SensitiveClipboard {
  static const _channel = MethodChannel('com.zcash.wallet/sensitive_clipboard');
  static final _lifecycleObserver = _SensitiveClipboardLifecycleObserver();
  static int _copyGeneration = 0;
  static bool _lifecycleObserverRegistered = false;
  static _PendingClipboardExpiration? _pendingFallbackExpiration;

  @visibleForTesting
  static bool? debugIsIosOverride;

  @visibleForTesting
  static Future<void> Function(Duration duration)? debugExpirationDelay;

  static Future<void> copyText(
    String text, {
    Duration expiration = sensitiveClipboardDefaultExpiration,
  }) async {
    final copyGeneration = ++_copyGeneration;
    if (_supportsNativeExpiration) {
      await _channel.invokeMethod<void>('copyText', {
        'text': text,
        'expirationSeconds': expiration.inSeconds,
      });
      return;
    }

    _ensureLifecycleObserver();
    await Clipboard.setData(ClipboardData(text: text));
    _pendingFallbackExpiration = _PendingClipboardExpiration(
      text: text,
      copyGeneration: copyGeneration,
    );
    unawaited(
      _clearFallbackAfterExpiration(
        text: text,
        expiration: expiration,
        copyGeneration: copyGeneration,
      ),
    );
  }

  static Future<void> _clearFallbackAfterExpiration({
    required String text,
    required Duration expiration,
    required int copyGeneration,
  }) async {
    final delay = debugExpirationDelay;
    if (delay == null) {
      await Future<void>.delayed(expiration);
    } else {
      await delay(expiration);
    }
    final pending = _pendingFallbackExpiration;
    if (pending == null || pending.copyGeneration != copyGeneration) return;
    pending.expirationElapsed = true;
    await _tryClearExpiredFallback();
  }

  static void _ensureLifecycleObserver() {
    if (_lifecycleObserverRegistered) return;
    WidgetsBinding.instance.addObserver(_lifecycleObserver);
    _lifecycleObserverRegistered = true;
  }

  @visibleForTesting
  static Future<void> debugRetryExpiredFallbackClear() =>
      _tryClearExpiredFallback();

  static Future<void> _tryClearExpiredFallback() async {
    final pending = _pendingFallbackExpiration;
    if (pending == null ||
        !pending.expirationElapsed ||
        pending.copyGeneration != _copyGeneration) {
      return;
    }

    try {
      final current = await Clipboard.getData(Clipboard.kTextPlain);
      if (current?.text == pending.text) {
        await Clipboard.setData(const ClipboardData(text: ''));
      }
      if (identical(_pendingFallbackExpiration, pending)) {
        _pendingFallbackExpiration = null;
      }
    } catch (_) {
      // Clipboard access can be denied while the app is backgrounded. Keep the
      // pending expiry so the lifecycle observer can retry on foreground.
    }
  }

  static bool get _supportsNativeExpiration {
    final override = debugIsIosOverride;
    if (override != null) return override;
    return !kIsWeb && Platform.isIOS;
  }
}

final class _PendingClipboardExpiration {
  _PendingClipboardExpiration({
    required this.text,
    required this.copyGeneration,
  });

  final String text;
  final int copyGeneration;
  bool expirationElapsed = false;
}

final class _SensitiveClipboardLifecycleObserver with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(SensitiveClipboard._tryClearExpiredFallback());
    }
  }
}
