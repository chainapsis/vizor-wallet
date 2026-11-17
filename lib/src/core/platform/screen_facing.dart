import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

const _channel = EventChannel('com.zcash.wallet/screen_facing');

/// How far the screen faces the floor, about 20 times a second while
/// listened to: gravity along the screen's normal, -1 with the screen
/// straight up and 1 straight down. The sensor runs only while there is a
/// listener. iOS and Android only; other platforms (desktop, tests) emit
/// nothing, and errors from a missing host handler are swallowed.
Stream<double> screenFacingEvents() {
  if (kIsWeb || !(Platform.isIOS || Platform.isAndroid)) {
    return const Stream.empty();
  }
  return _channel
      .receiveBroadcastStream()
      .where((event) => event is num)
      .map((event) => (event as num).toDouble())
      .handleError((Object _) {});
}
