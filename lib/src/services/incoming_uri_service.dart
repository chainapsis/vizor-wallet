import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const kIncomingUriChannelName = 'com.zcash.wallet/payment_uri';

final incomingUriServiceProvider = Provider<IncomingUriService>((ref) {
  final service = IncomingUriService();
  ref.onDispose(service.dispose);
  return service;
});

/// The one native-to-Dart intake for every link this app is opened by.
///
/// Two products share the pipe: ZIP-321 `zcash:` payment requests, which every
/// runner delivers, and Vizor Gift Card `https://` deeplinks, which only the
/// Android and iOS runners deliver (desktop users open a Gift Card from the
/// in-app Payment Links screen). Dart therefore gates on the five platforms
/// that install the channel at all and lets `classifyIncomingLink` decide
/// which product a delivered link belongs to — an https link simply never
/// arrives on desktop, so it needs no gate of its own here.
///
/// Exactly one of these may install the channel's method-call handler:
/// `setMethodCallHandler` has room for one handler, and a second registration
/// silently unsubscribes the first.
class IncomingUriService {
  IncomingUriService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(kIncomingUriChannelName);

  final MethodChannel _channel;
  final StreamController<String> _controller =
      StreamController<String>.broadcast();
  bool _initialized = false;
  bool _disposed = false;

  Stream<String> get uriStream => _controller.stream;

  /// Installs the handler and drains whatever native buffered before Dart came
  /// up. Idempotent: a second call is a no-op, so it cannot replace the
  /// handler the first call installed.
  Future<void> initialize() async {
    if (_initialized || _disposed || !_isSupportedPlatform) return;
    _initialized = true;

    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onUris':
          _addUris(call.arguments);
        default:
          throw MissingPluginException('Unknown method ${call.method}');
      }
    });

    try {
      try {
        // Deliberately untyped: a malformed native payload must surface as a
        // dropped URI, not as a cast error that strands the handshake.
        final pending = await _channel.invokeMethod<Object?>('takePendingUris');
        _addUris(pending);
      } on MissingPluginException {
        rethrow;
      } catch (error) {
        debugPrint('IncomingUriService: pending URI drain failed: $error');
      } finally {
        // The native side only starts flushing later URIs once `ready` is
        // acknowledged, so a failed drain must never skip this.
        await _channel.invokeMethod<void>('ready');
      }
    } on MissingPluginException {
      // A runner without the native channel leaves URI intake inert.
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _channel.setMethodCallHandler(null);
    await _controller.close();
  }

  bool get _isSupportedPlatform {
    if (kIsWeb) return false;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android ||
      TargetPlatform.iOS ||
      TargetPlatform.linux ||
      TargetPlatform.macOS ||
      TargetPlatform.windows => true,
      _ => false,
    };
  }

  void _addUris(Object? arguments) {
    if (_disposed) return;
    if (arguments is String) {
      _controller.add(arguments);
      return;
    }
    if (arguments is Iterable) {
      for (final item in arguments) {
        if (item is String) _controller.add(item);
      }
    }
  }
}
