import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/services/payment_uri_service.dart';

// Exercises the full native -> Dart contract of PaymentUriService:
//  - cold start: initialize() must call `takePendingUris` and then call
//    `ready`, even when the pending drain fails;
//  - warm: a later native `onUris` push must be forwarded to the stream.
// The `ready` handshake is what unblocks every later native flush, so a
// malformed cold-start payload must not be able to skip it.
// PaymentUriService keeps process-global state (it initializes exactly once
// per isolate), so this lives in a single test that covers the whole flow in
// order rather than in one test per phase.
void main() {
  const channel = MethodChannel('com.zcash.wallet/payment_uri');

  test('initialize completes the ready handshake even when the pending drain '
      'fails, and still forwards later onUris pushes', () async {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    // _isSupportedPlatform gates on defaultTargetPlatform; pin a supported one.
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

    final messenger = binding.defaultBinaryMessenger;
    const codec = StandardMethodCodec();
    var readyCalled = false;
    var takePendingCalls = 0;

    // Mock the Dart -> native side at the binary level so `takePendingUris`
    // can answer with an undecodable envelope — the real-world shape of a
    // malformed native payload. StandardMessageCodec throws out of
    // invokeMethod itself, so this is not a PlatformException the channel
    // would hand back politely.
    messenger.setMockMessageHandler(channel.name, (message) async {
      final call = codec.decodeMethodCall(message);
      switch (call.method) {
        case 'takePendingUris':
          takePendingCalls++;
          return ByteData.sublistView(Uint8List.fromList(<int>[7, 7, 7]));
        case 'ready':
          readyCalled = true;
          return codec.encodeSuccessEnvelope(null);
      }
      return codec.encodeSuccessEnvelope(null);
    });
    addTearDown(() {
      messenger.setMockMessageHandler(channel.name, null);
      debugDefaultTargetPlatformOverride = null;
    });

    final received = <String>[];
    final sub = PaymentUriService.uriStream.listen(received.add);
    addTearDown(sub.cancel);

    // The drain throws, but initialize() must swallow it rather than
    // propagate — app startup awaits this.
    await PaymentUriService.initialize();
    await Future<void>.delayed(Duration.zero);

    expect(takePendingCalls, 1);
    expect(readyCalled, isTrue);

    // Because `ready` was acknowledged, the native side flushes the URIs it
    // had buffered for cold start.
    await messenger.handlePlatformMessage(
      channel.name,
      codec.encodeMethodCall(
        const MethodCall('onUris', <String>['zcash:coldstart?amount=0.5']),
      ),
      (_) {},
    );
    await Future<void>.delayed(Duration.zero);

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

    // A payload that is neither a String nor a list of Strings is dropped
    // without breaking the channel.
    await messenger.handlePlatformMessage(
      channel.name,
      codec.encodeMethodCall(const MethodCall('onUris', 42)),
      (_) {},
    );
    await messenger.handlePlatformMessage(
      channel.name,
      codec.encodeMethodCall(
        const MethodCall('onUris', <Object?>[7, 'zcash:mixed?amount=0.1']),
      ),
      (_) {},
    );
    await Future<void>.delayed(Duration.zero);

    expect(received, contains('zcash:mixed?amount=0.1'));
    expect(received, hasLength(3));
  });
}
