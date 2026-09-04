import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/services/incoming_uri_service.dart';

// The full native -> Dart contract of the one incoming-link channel:
//
//  - cold start: `initialize()` calls `takePendingUris` and *then* `ready`,
//    even when the pending drain fails. The `ready` handshake is what unblocks
//    every later native flush, so a malformed cold-start payload must not be
//    able to skip it;
//  - warm: a later native `onUris` push reaches the stream;
//  - the platform gate covers all five runners that install the channel, not
//    just the two that deliver HTTPS deeplinks — desktop has to receive
//    `zcash:` links;
//  - `initialize()` is idempotent, because a second `setMethodCallHandler` on
//    this channel would silently unsubscribe the first.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(kIncomingUriChannelName);
  const coldStartUri = 'https://link.vizor.cash/payment-links/open#v1=cold';
  late List<String> nativeCalls;

  void mockNative({List<String> pending = const [coldStartUri]}) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          nativeCalls.add(call.method);
          return switch (call.method) {
            'takePendingUris' => pending,
            'ready' => null,
            _ => throw MissingPluginException(),
          };
        });
  }

  Future<void> pushNative(Object? arguments) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          kIncomingUriChannelName,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('onUris', arguments),
          ),
          (_) {},
        );
    await Future<void>.delayed(Duration.zero);
  }

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    nativeCalls = [];
    mockNative();
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('every runner that installs the channel is drained', () async {
    // `zcash:` links arrive on all five; only the HTTPS deeplinks are
    // mobile-only, and those are simply never delivered elsewhere.
    for (final platform in [
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.linux,
      TargetPlatform.macOS,
      TargetPlatform.windows,
    ]) {
      debugDefaultTargetPlatformOverride = platform;
      nativeCalls = [];
      final service = IncomingUriService(channel: channel);
      addTearDown(service.dispose);

      await service.initialize();

      expect(nativeCalls, ['takePendingUris', 'ready'], reason: '$platform');
    }
  });

  test('leaves URI intake inert on a platform with no channel', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.fuchsia;
    final service = IncomingUriService(channel: channel);
    addTearDown(service.dispose);

    await service.initialize();

    expect(nativeCalls, isEmpty);
  });

  test('drains cold-start URIs before announcing readiness', () async {
    final service = IncomingUriService(channel: channel);
    final received = <String>[];
    final subscription = service.uriStream.listen(received.add);
    addTearDown(() async {
      await subscription.cancel();
      await service.dispose();
    });

    await service.initialize();
    await Future<void>.delayed(Duration.zero);

    // (a) The pending URI reaches the stream, so the launch that opened the
    // link actually delivers it.
    expect(received, [coldStartUri]);
    // (b) `ready` is acknowledged only after the pending drain has run. The
    // native side starts flushing later URIs once it sees `ready`, so
    // acknowledging first would race the flush against the drain.
    expect(nativeCalls, ['takePendingUris', 'ready']);
  });

  test('forwards warm URIs after initialization', () async {
    final service = IncomingUriService(channel: channel);
    final received = <String>[];
    final subscription = service.uriStream.listen(received.add);
    addTearDown(() async {
      await subscription.cancel();
      await service.dispose();
    });
    await service.initialize();

    await pushNative(<String>[
      'https://link.vizor.cash/payment-links/open#v1=warm',
    ]);

    expect(received.last, 'https://link.vizor.cash/payment-links/open#v1=warm');
  });

  test('a cold-start batch keeps native order', () async {
    nativeCalls = [];
    mockNative(
      pending: const ['zcash:u1first?amount=0.5', 'zcash:u1second?amount=0.25'],
    );
    final service = IncomingUriService(channel: channel);
    final received = <String>[];
    final subscription = service.uriStream.listen(received.add);
    addTearDown(() async {
      await subscription.cancel();
      await service.dispose();
    });

    await service.initialize();
    await Future<void>.delayed(Duration.zero);

    expect(received, [
      'zcash:u1first?amount=0.5',
      'zcash:u1second?amount=0.25',
    ]);
  });

  test(
    'completes the ready handshake even when the pending drain throws',
    () async {
      // Mock the Dart -> native side at the binary level so `takePendingUris`
      // can answer with an undecodable envelope — the real-world shape of a
      // malformed native payload. StandardMessageCodec throws out of
      // invokeMethod itself, so this is not a PlatformException the channel
      // would hand back politely.
      const codec = StandardMethodCodec();
      var readyCalled = false;
      var takePendingCalls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMessageHandler(kIncomingUriChannelName, (message) async {
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
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMessageHandler(kIncomingUriChannelName, null),
      );

      final service = IncomingUriService(channel: channel);
      final received = <String>[];
      final subscription = service.uriStream.listen(received.add);
      addTearDown(() async {
        await subscription.cancel();
        await service.dispose();
      });

      // The drain throws, but initialize() must swallow it rather than
      // propagate — app startup awaits this.
      await service.initialize();
      await Future<void>.delayed(Duration.zero);

      expect(takePendingCalls, 1);
      expect(readyCalled, isTrue);

      // Because `ready` was acknowledged, the native side flushes the URIs it
      // had buffered for cold start.
      await pushNative(<String>['zcash:coldstart?amount=0.5']);
      expect(received, contains('zcash:coldstart?amount=0.5'));
    },
  );

  test(
    'a payload that is neither a String nor a list of Strings is dropped',
    () async {
      final service = IncomingUriService(channel: channel);
      final received = <String>[];
      final subscription = service.uriStream.listen(received.add);
      addTearDown(() async {
        await subscription.cancel();
        await service.dispose();
      });
      await service.initialize();
      await Future<void>.delayed(Duration.zero);
      received.clear();

      // A bare String is accepted; a number is dropped; a mixed list keeps only
      // its Strings. None of them may break the channel for the next push.
      await pushNative('zcash:bare?amount=0.1');
      await pushNative(42);
      await pushNative(<Object?>[7, 'zcash:mixed?amount=0.1']);

      expect(received, ['zcash:bare?amount=0.1', 'zcash:mixed?amount=0.1']);
    },
  );

  test('initialize is idempotent', () async {
    // A second `setMethodCallHandler` on this channel would silently
    // unsubscribe the first, so a re-initialize must be a no-op rather than a
    // re-registration.
    final service = IncomingUriService(channel: channel);
    final received = <String>[];
    final subscription = service.uriStream.listen(received.add);
    addTearDown(() async {
      await subscription.cancel();
      await service.dispose();
    });

    await service.initialize();
    await service.initialize();
    await Future<void>.delayed(Duration.zero);

    expect(nativeCalls, ['takePendingUris', 'ready']);
    expect(received, [coldStartUri]);

    await pushNative(<String>['zcash:stillworking?amount=1']);
    expect(received.last, 'zcash:stillworking?amount=1');
  });
}
