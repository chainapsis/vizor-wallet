import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'native_intake_service.dart';

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
class IncomingUriService extends NativeIntakeService<String> {
  IncomingUriService({MethodChannel? channel})
    : super(
        channel ?? const MethodChannel(kIncomingUriChannelName),
        takePendingMethod: 'takePendingUris',
        pushMethod: 'onUris',
      );

  Stream<String> get uriStream => stream;

  @override
  bool get isSupportedPlatform {
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

  @override
  Iterable<String> parse(Object? arguments) => switch (arguments) {
    final String uri => [uri],
    final Iterable<Object?> items => items.whereType<String>(),
    _ => const [],
  };
}
