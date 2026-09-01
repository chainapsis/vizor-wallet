import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/navigation/vizor_deep_link.dart';

const kIncomingUriChannelName = 'com.zcash.wallet/payment_uri';

final incomingUriServiceProvider = Provider<IncomingUriService>((ref) {
  final service = IncomingUriService();
  ref.onDispose(service.dispose);
  return service;
});

/// Mobile native-to-Dart intake for verified Vizor HTTPS deeplinks.
///
/// Desktop runners intentionally do not register this channel. Desktop users
/// open supported links from their corresponding in-app entry points.
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
      TargetPlatform.android || TargetPlatform.iOS => true,
      _ => false,
    };
  }

  void _addUris(Object? arguments) {
    if (_disposed) return;
    if (arguments is String) {
      debugPrint(
        '[zcash] Incoming URI: ${incomingUriDiagnosticSummary(arguments)}',
      );
      _controller.add(arguments);
      return;
    }
    if (arguments is Iterable) {
      for (final item in arguments) {
        if (item is String) {
          debugPrint(
            '[zcash] Incoming URI: ${incomingUriDiagnosticSummary(item)}',
          );
          _controller.add(item);
        }
      }
    }
  }
}

/// Describes only the routing envelope of an incoming URI.
///
/// Gift Card fragments contain bearer secrets, so diagnostics must never emit
/// the URL, fragment contents, host, or an unsupported path verbatim.
@visibleForTesting
String incomingUriDiagnosticSummary(String rawUri) {
  final uri = Uri.tryParse(rawUri.trim());
  if (uri == null) return 'uri=invalid';

  final trustedOrigin =
      uri.scheme.toLowerCase() == VizorDeepLink.scheme &&
      uri.host.toLowerCase() == VizorDeepLink.host &&
      uri.userInfo.isEmpty &&
      !uri.hasPort;
  final route = switch (uri.path) {
    '' || '/' => 'home',
    VizorDeepLink.paymentLinkPath => 'payment_link',
    _ => 'other',
  };
  final fragment = uri.fragment.isEmpty
      ? 'none'
      : uri.fragment.startsWith('v1=')
      ? 'v1'
      : 'other';
  return 'origin=${trustedOrigin ? 'trusted' : 'untrusted'} '
      'route=$route query=${uri.hasQuery ? 'present' : 'none'} '
      'fragment=$fragment';
}
