import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/services/payment_uri_service.dart';

// The cold-start happy path: the app was launched *by* a `zcash:` link, so the
// URI is already waiting natively when Dart comes up and only `takePendingUris`
// can hand it over. Losing it here means the link silently does nothing on the
// launch that opened it.
//
// PaymentUriService initializes exactly once per isolate, so this cannot share
// a file with the failing-drain coverage in payment_uri_service_test.dart — it
// needs its own isolate to observe a *successful* cold-start drain.
void main() {
  const channel = MethodChannel('com.zcash.wallet/payment_uri');
  const coldStartUri = 'zcash:u1coldstart?amount=1.5';

  test('drains the cold-start URI before acknowledging ready, and keeps '
      'forwarding later pushes', () async {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    // _isSupportedPlatform gates on defaultTargetPlatform; pin a supported one.
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

    final messenger = binding.defaultBinaryMessenger;
    const codec = StandardMethodCodec();
    // Outbound Dart -> native calls, in the order the service makes them.
    final nativeCalls = <String>[];

    messenger.setMockMethodCallHandler(channel, (call) async {
      nativeCalls.add(call.method);
      if (call.method == 'takePendingUris') return <String>[coldStartUri];
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

    // (a) The pending URI reaches the stream, so the launch that opened the
    // link actually delivers it.
    expect(received, [coldStartUri]);

    // (b) `ready` is acknowledged only after the pending drain has run.
    // The native side starts flushing later URIs once it sees `ready`, so
    // acknowledging first would race the flush against the drain.
    // (The listener callback above lands one microtask later than the `ready`
    // call itself only because `uriStream` is an async broadcast stream; the
    // handover into the controller is what happens first, and that is the
    // ordering asserted here.)
    expect(nativeCalls, ['takePendingUris', 'ready']);

    // (c) A later native push still reaches the stream on the same channel.
    await messenger.handlePlatformMessage(
      channel.name,
      codec.encodeMethodCall(
        const MethodCall('onUris', <String>['zcash:u1warm?amount=0.25']),
      ),
      (_) {},
    );
    await Future<void>.delayed(Duration.zero);

    expect(received, [coldStartUri, 'zcash:u1warm?amount=0.25']);
  });
}
