import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class PaymentUriService {
  PaymentUriService._();

  static const _channel = MethodChannel('com.zcash.wallet/payment_uri');
  static final _controller = StreamController<String>.broadcast();
  static var _initialized = false;

  static Stream<String> get uriStream => _controller.stream;

  static Future<void> initialize() async {
    if (_initialized || !_isSupportedPlatform) return;
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
      // Non-macOS builds do not install this channel yet.
    }
  }

  static bool get _isSupportedPlatform {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.macOS;
  }

  static void _addUris(Object? arguments) {
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
