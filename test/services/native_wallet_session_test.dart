import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/services/native_wallet_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('resetWalletState invokes the native wallet-session cleanup', () async {
    const channel = MethodChannel(kNativeWalletSessionChannelName);
    MethodCall? received;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      received = call;
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    await const NativeWalletSessionBridge(channel: channel).resetWalletState();

    expect(received?.method, 'resetWalletState');
    expect(received?.arguments, isNull);
  });
}
