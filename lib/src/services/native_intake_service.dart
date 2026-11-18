import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The Dart side of the handshake every native-to-Dart intake channel uses.
///
/// A runner queues what arrives before Dart is listening. [initialize]
/// installs the push handler, drains that queue with [takePendingMethod] and
/// only then says `ready`, after which the runner pushes directly with
/// [pushMethod]. A subclass says which runners install the channel and turns
/// a native payload into the items it delivers on [stream]; a runner without
/// the channel leaves the intake inert.
///
/// Exactly one of these may install the channel's method-call handler:
/// `setMethodCallHandler` has room for one handler, and a second registration
/// silently unsubscribes the first.
abstract class NativeIntakeService<T> {
  NativeIntakeService(
    this._channel, {
    required this.takePendingMethod,
    required this.pushMethod,
  });

  final MethodChannel _channel;

  /// Drains what the runner queued before Dart came up.
  final String takePendingMethod;

  /// What the runner calls with later arrivals, once `ready` is acknowledged.
  final String pushMethod;

  final StreamController<T> _controller = StreamController<T>.broadcast();
  bool _initialized = false;
  bool _disposed = false;

  Stream<T> get stream => _controller.stream;

  /// Whether this runner installs the channel at all.
  @protected
  bool get isSupportedPlatform;

  /// The items in a native payload. A malformed payload yields none: it must
  /// surface as a dropped item, not as a cast error that strands the handshake.
  @protected
  Iterable<T> parse(Object? arguments);

  /// Installs the handler and drains whatever native buffered before Dart came
  /// up. Idempotent: a second call is a no-op, so it cannot replace the
  /// handler the first call installed.
  Future<void> initialize() async {
    if (_initialized || _disposed || !isSupportedPlatform) return;
    _initialized = true;

    _channel.setMethodCallHandler((call) async {
      if (call.method != pushMethod) {
        throw MissingPluginException('Unknown method ${call.method}');
      }
      _add(call.arguments);
    });

    try {
      try {
        // Deliberately untyped: a malformed native payload must reach [parse],
        // not fail a cast inside the channel.
        _add(await _channel.invokeMethod<Object?>(takePendingMethod));
      } on MissingPluginException {
        rethrow;
      } catch (error) {
        debugPrint('$runtimeType: pending drain failed: $error');
      } finally {
        // The native side only starts flushing later arrivals once `ready` is
        // acknowledged, so a failed drain must never skip this.
        await _channel.invokeMethod<void>('ready');
      }
    } on MissingPluginException {
      // A runner without the native channel leaves the intake inert.
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _channel.setMethodCallHandler(null);
    await _controller.close();
  }

  void _add(Object? arguments) {
    if (_disposed) return;
    for (final item in parse(arguments)) {
      _controller.add(item);
    }
  }
}
