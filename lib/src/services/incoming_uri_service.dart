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

/// Shared native-to-Dart URI intake. Scheme-specific parsing belongs to
/// subscribers so `zcash:` ZIP-321 requests and `vizor:` bearer links can use
/// one OS channel without competing MethodChannel handlers.
class IncomingUriService {
  IncomingUriService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(kIncomingUriChannelName);

  final MethodChannel _channel;
  final StreamController<String> _controller =
      StreamController<String>.broadcast();
  bool _initialized = false;
  bool _disposed = false;

  Stream<String> get uriStream => _controller.stream;

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
      final pending = await _channel.invokeMethod<List<dynamic>>(
        'takePendingUris',
      );
      _addUris(pending);
      await _channel.invokeMethod<void>('ready');
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
