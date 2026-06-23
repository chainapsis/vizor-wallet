import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/services/payment_uri_service.dart';

// Exercises the full native -> Dart contract of PaymentUriService:
//  - cold start: initialize() must call `takePendingUris`, forward whatever the
//    native side buffered, then call `ready`;
//  - warm: a later native `onUris` push must be forwarded to the stream.
// PaymentUriService keeps process-global state (it initializes once), so this
// lives in a single test that covers both halves of the flow in order.
void main() {
  const channel = MethodChannel('com.zcash.wallet/payment_uri');

  test(
    'initialize drains takePendingUris and forwards a later onUris push',
    () async {
      final binding = TestWidgetsFlutterBinding.ensureInitialized();
      // _isSupportedPlatform gates on defaultTargetPlatform; pin a supported one.
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

      final messenger = binding.defaultBinaryMessenger;
      const codec = StandardMethodCodec();
      var readyCalled = false;
      var takePendingCalls = 0;

      // Mock the Dart -> native side: native reports one buffered cold-start URI
      // on takePendingUris, and acknowledges ready.
      messenger.setMockMethodCallHandler(channel, (call) async {
        switch (call.method) {
          case 'takePendingUris':
            takePendingCalls++;
            return <String>['zcash:coldstart?amount=0.5'];
          case 'ready':
            readyCalled = true;
            return null;
        }
        return null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(channel, null);
        debugDefaultTargetPlatformOverride = null;
      });

      final received = <String>[];
      final sub = PaymentUriService.uriStream.listen(received.add);
      addTearDown(sub.cancel);

      await PaymentUriService.initialize();
      await Future<void>.delayed(Duration.zero);

      // Cold-start buffered URI was drained via takePendingUris, then ready fired.
      expect(takePendingCalls, 1);
      expect(readyCalled, isTrue);
      expect(received, contains('zcash:coldstart?amount=0.5'));

      // A later native onUris push (warm path) is forwarded to the stream.
      await messenger.handlePlatformMessage(
        channel.name,
        codec.encodeMethodCall(
          const MethodCall('onUris', <String>['zcash:warm?amount=0.25']),
        ),
        (_) {},
      );
      await Future<void>.delayed(Duration.zero);

      expect(received, contains('zcash:warm?amount=0.25'));
    },
  );
}
