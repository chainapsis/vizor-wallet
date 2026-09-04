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
  static Future<void>? _fallbackWriteInFlight;

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
    // The write and the generation it installs are one critical section. Split
    // across the queue's boundary they would not be: an expiry that revalidated
    // while this write was still in flight would still see the old generation,
    // pass, and issue its clear afterwards -- landing it on top of the secret
    // written here.
    await _serializeFallbackWrite(() async {
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
    });
  }

  /// Runs [write] after any fallback write already in flight, one at a time.
  ///
  /// A copy's write and an expiry's clear both mutate the same clipboard and
  /// both span an await, and the platform applies writes in the order they
  /// arrive. Interleaved, a clear issued while a copy's write was in flight
  /// lands *after* it and erases the secret the user just copied. Serializing
  /// them means the generation a clear re-checks after acquiring is the one the
  /// completed copy installed, so it can tell it has been superseded.
  ///
  /// The handle is dropped once nothing is in flight, rather than kept as a
  /// growing chain of completed futures. That is not just tidiness: a retained
  /// future belongs to the zone that created it, so a chain living in a static
  /// would make each caller wait on a callback scheduled in whichever zone ran
  /// first -- which under `testWidgets`, where every test gets its own
  /// `FakeAsync`, is a queue that is never pumped again.
  ///
  /// A failing [write] still releases the lock and reports to its own caller:
  /// one denied clipboard write must not wedge every later copy.
  static Future<void> _serializeFallbackWrite(
    Future<void> Function() write,
  ) async {
    final previous = _fallbackWriteInFlight;
    final completer = Completer<void>();
    _fallbackWriteInFlight = completer.future;
    if (previous != null) {
      await previous;
    }
    try {
      await write();
    } finally {
      if (identical(_fallbackWriteInFlight, completer.future)) {
        _fallbackWriteInFlight = null;
      }
      completer.complete();
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

  /// Whether [pending] is still the expiry the clipboard is guarded by. Both
  /// halves matter: the entry can be replaced, and the generation can move
  /// under an entry that is still installed.
  static bool _isCurrentFallbackExpiration(
    _PendingClipboardExpiration pending,
  ) =>
      identical(_pendingFallbackExpiration, pending) &&
      pending.copyGeneration == _copyGeneration;

  static Future<void> _tryClearExpiredFallback() async {
    final pending = _pendingFallbackExpiration;
    if (pending == null ||
        !pending.expirationElapsed ||
        pending.copyGeneration != _copyGeneration) {
      return;
    }

    try {
      // Read outside the queue. A clipboard read can stall, and a copy must
      // never wait behind one -- the user pressed Copy, and the write that
      // answers them cannot be held up by a clear that is only housekeeping.
      final current = await Clipboard.getData(Clipboard.kTextPlain);
      // Revalidate before acting on the answer. The read is asynchronous, and a
      // copy that lands while it is in flight puts a *newer* secret on the
      // clipboard and installs a newer generation. `current` is then a snapshot
      // from before that copy, so a stale continuation would find its own old
      // text, conclude the clipboard still held it, and erase the secret the
      // user just copied. Only the entry that is still the current one may
      // clear.
      if (!_isCurrentFallbackExpiration(pending)) return;

      await _serializeFallbackWrite(() async {
        // Re-check after acquiring. Passing the test above only proves no copy
        // had *completed* by then; one could have been mid-write, and it is the
        // generation that copy installed -- while this was queued behind it --
        // that decides whether there is still anything here to clear.
        if (!_isCurrentFallbackExpiration(pending)) return;
        if (current?.text == pending.text) {
          await Clipboard.setData(const ClipboardData(text: ''));
        }
        // Re-checked rather than assumed: the clear above is awaited too, so a
        // copy can land during it and install the entry this must not drop.
        if (identical(_pendingFallbackExpiration, pending)) {
          _pendingFallbackExpiration = null;
        }
      });
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
