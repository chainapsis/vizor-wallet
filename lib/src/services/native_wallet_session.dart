import 'package:flutter/services.dart';

const kNativeWalletSessionChannelName = 'com.zcash.wallet/wallet_session';

class NativeWalletSessionBridge {
  const NativeWalletSessionBridge({
    MethodChannel channel = const MethodChannel(
      kNativeWalletSessionChannelName,
    ),
  }) : _channel = channel;

  final MethodChannel _channel;

  /// Clears wallet-scoped state owned by the native application process.
  Future<void> resetWalletState() {
    return _channel.invokeMethod<void>('resetWalletState');
  }
}
