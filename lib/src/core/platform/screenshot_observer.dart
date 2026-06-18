import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

const _channel = EventChannel('com.zcash.wallet/screenshots');

/// Emits whenever the OS reports a user screenshot (iOS only — Android
/// would use FLAG_SECURE instead and never emits here). Errors from a
/// missing host handler (tests, other platforms) are swallowed so
/// listeners only ever see real events.
Stream<void> screenshotEvents() {
  if (kIsWeb || !Platform.isIOS) return const Stream.empty();
  return _channel
      .receiveBroadcastStream()
      .map((_) {})
      .handleError((Object _) {});
}
