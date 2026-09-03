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
  static bool? debugSupportsNativeClipboardOverride;

  @visibleForTesting
  static Future<void> Function(Duration duration)? debugExpirationDelay;

  static Future<void> copyText(
    String text, {
    Duration expiration = sensitiveClipboardDefaultExpiration,
  }) async {
    if (_supportsNativeClipboard) {
      await _channel.invokeMethod<void>('copyText', {
        'text': text,
        'expirationSeconds': expiration.inSeconds,
      });
      _supersedePendingExpiration();
      return;
    }

    _ensureLifecycleObserver();
    await Clipboard.setData(ClipboardData(text: text));
    // Only now is the previous secret actually off the clipboard, so only now
    // may its expiry be retired. Retiring it first would strand that secret
    // there with nothing scheduled to clear it whenever the write above
    // throws -- clipboard writes are denied often enough (backgrounded app,
    // OS policy) that this is a real state, not a theoretical one.
    final copyGeneration = _supersedePendingExpiration();
    final pending = _PendingClipboardExpiration(
      text: text,
      copyGeneration: copyGeneration,
    );
    _pendingFallbackExpiration = pending;
    final delay = debugExpirationDelay;
    if (delay == null) {
      pending.timer = Timer(
        expiration,
        () => unawaited(_onExpirationElapsed(pending)),
      );
    } else {
      unawaited(delay(expiration).then((_) => _onExpirationElapsed(pending)));
    }
  }

  /// Drops any scheduled fallback auto-clear together with the plaintext it
  /// holds, leaving the clipboard itself untouched.
  ///
  /// Widget tests that exercise a copy need this so the pending expiry timer
  /// does not outlive the widget tree.
  @visibleForTesting
  static void debugCancelPendingExpiration() => _cancelPendingExpiration();

  /// Retires the previous expiry -- its timer and the plaintext it held -- now
  /// that a newer copy has replaced the secret it guarded, and returns the
  /// generation that newer copy owns.
  ///
  /// Both the timer and the generation move together on purpose: a bumped
  /// generation alone would make the surviving expiry a no-op in
  /// [_tryClearExpiredFallback], which is the same leak by another route.
  static int _supersedePendingExpiration() {
    _cancelPendingExpiration();
    return ++_copyGeneration;
  }

  static void _cancelPendingExpiration() {
    _pendingFallbackExpiration?.timer?.cancel();
    _pendingFallbackExpiration = null;
  }

  static Future<void> _onExpirationElapsed(
    _PendingClipboardExpiration pending,
  ) async {
    if (!identical(_pendingFallbackExpiration, pending)) return;
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

  static bool get _supportsNativeClipboard {
    final override = debugSupportsNativeClipboardOverride;
    if (override != null) return override;
    return !kIsWeb && (Platform.isIOS || Platform.isAndroid);
  }
}

final class _PendingClipboardExpiration {
  _PendingClipboardExpiration({
    required this.text,
    required this.copyGeneration,
  });

  final String text;
  final int copyGeneration;
  Timer? timer;
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
