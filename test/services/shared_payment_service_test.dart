import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/services/shared_payment_service.dart';

// The native -> Dart contract of the share-sheet channel, the same shape as
// the incoming-link channel's:
//
//  - cold start: `initialize()` calls `takePending` and *then* `ready`, even
//    when the pending drain fails, because `ready` is what unblocks every
//    later native flush;
//  - warm: a later native `onShared` push reaches the stream as one batch,
//    typed, with the capture number the runner stamped on each item, and a
//    bare capture announcement arrives as its own event in it;
//  - only the Android runner, which installs the channel, is drained;
//  - an image item without a path is an unreadable image, and a payload the
//    runner got wrong is dropped, not thrown;
//  - `initialize()` is idempotent, because a second `setMethodCallHandler`
//    on this channel would silently unsubscribe the first.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(kSharedPaymentChannelName);
  late List<String> nativeCalls;

  void mockNative({
    Object? pending = const [
      {'type': 'text', 'text': 'cold', 'seq': 1},
    ],
    bool failDrain = false,
  }) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          nativeCalls.add(call.method);
          return switch (call.method) {
            'takePending' =>
              failDrain ? throw PlatformException(code: 'boom') : pending,
            'ready' => null,
            _ => throw MissingPluginException(),
          };
        });
  }

  Future<void> pushNative(Object? arguments) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          kSharedPaymentChannelName,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('onShared', arguments),
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

  test('cold start drains the runner and then says ready', () async {
    final service = SharedPaymentService(channel: channel);
    addTearDown(service.dispose);
    final payloads = <SharedIntakeEvent>[];
    service.stream.listen(payloads.addAll);

    await service.initialize();
    await Future<void>.delayed(Duration.zero);

    expect(nativeCalls, ['takePending', 'ready']);
    expect(payloads, [
      isA<SharedText>()
          .having((p) => p.text, 'text', 'cold')
          .having((p) => p.seq, 'seq', 1),
    ]);
  });

  test('a failed drain still says ready', () async {
    mockNative(failDrain: true);
    final service = SharedPaymentService(channel: channel);
    addTearDown(service.dispose);

    await service.initialize();

    expect(nativeCalls, ['takePending', 'ready']);
  });

  test(
    'a warm push reaches the stream, typed; a malformed item is dropped',
    () async {
      mockNative(pending: const []);
      final service = SharedPaymentService(channel: channel);
      addTearDown(service.dispose);
      final payloads = <SharedIntakeEvent>[];
      service.stream.listen(payloads.addAll);
      await service.initialize();

      await pushNative([
        {'type': 'captured', 'seq': 2},
        {'type': 'text', 'text': 'zcash:u1recipient', 'seq': 3},
        {'type': 'image', 'path': '/cache/shared.png', 'seq': 4},
        {'type': 'image', 'seq': 5},
        {'type': 'image', 'path': '/cache/unnumbered.png'},
        {'type': 'video', 'path': '/cache/clip.mp4', 'seq': 6},
        'not a map',
      ]);

      expect(payloads, [
        isA<SharedCaptured>().having((e) => e.seq, 'seq', 2),
        isA<SharedText>()
            .having((p) => p.text, 'text', 'zcash:u1recipient')
            .having((p) => p.seq, 'seq', 3),
        isA<SharedImage>()
            .having((p) => p.path, 'path', '/cache/shared.png')
            .having((p) => p.seq, 'seq', 4),
        isA<SharedUnreadableImage>().having((p) => p.seq, 'seq', 5),
      ]);
    },
  );

  test('only the Android runner is drained', () async {
    for (final (platform, drained) in [
      (TargetPlatform.android, true),
      (TargetPlatform.iOS, false),
      (TargetPlatform.linux, false),
      (TargetPlatform.macOS, false),
      (TargetPlatform.windows, false),
    ]) {
      debugDefaultTargetPlatformOverride = platform;
      nativeCalls = [];
      final service = SharedPaymentService(channel: channel);
      addTearDown(service.dispose);

      await service.initialize();

      expect(
        nativeCalls,
        drained ? ['takePending', 'ready'] : isEmpty,
        reason: '$platform',
      );
    }
  });

  test('a runner without the channel leaves intake inert', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    final service = SharedPaymentService(channel: channel);
    addTearDown(service.dispose);

    await expectLater(service.initialize(), completes);
  });

  test('initialize is idempotent', () async {
    final service = SharedPaymentService(channel: channel);
    addTearDown(service.dispose);

    await service.initialize();
    await service.initialize();

    expect(nativeCalls, ['takePending', 'ready']);
  });
}
