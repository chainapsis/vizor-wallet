import 'package:flutter/services.dart';

const kNativeScreenAwakeChannelName = 'com.zcash.wallet/screen_awake';

class NativeScreenAwakeBridge {
  const NativeScreenAwakeBridge({
    MethodChannel channel = const MethodChannel(kNativeScreenAwakeChannelName),
  }) : _channel = channel;

  final MethodChannel _channel;

  Future<void> setEnabled(bool enabled) {
    return _channel.invokeMethod<void>('setEnabled', {'enabled': enabled});
  }
}
