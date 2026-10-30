import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/layout/app_form_factor.dart';

import 'support/mobile_test_assets.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  // Native integration tests use their actual platform bundle. This hook only
  // changes the host widget-test bundle, which normally includes every platform.
  if (kAppFormFactor != AppFormFactor.mobile ||
      !Platform.environment.containsKey('UNIT_TEST_ASSETS')) {
    await testMain();
    return;
  }

  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final manifestMessage = ByteData.sublistView(
    utf8.encode('AssetManifest.bin'),
  );
  final manifest = await messenger.send('flutter/assets', manifestMessage);
  if (manifest == null) {
    throw StateError(
      'Mobile widget tests require the Flutter test asset bundle.',
    );
  }
  final assets = MobileTestAssets(
    manifest: manifest,
    originalLoad: (message) =>
        messenger.delegate.send('flutter/assets', message),
  );
  final originalMessagesHandler = messenger.allMessagesHandler;

  Future<ByteData?>? forward(
    String channel,
    MessageHandler? handler,
    ByteData? message,
  ) {
    if (originalMessagesHandler != null) {
      return originalMessagesHandler(channel, handler, message);
    }
    if (handler != null) return handler(message);
    return messenger.delegate.send(channel, message);
  }

  Future<ByteData?>? filteredLoad(
    String channel,
    MessageHandler? handler,
    ByteData? message,
  ) {
    if (channel != 'flutter/assets') return forward(channel, handler, message);
    return assets.handle(
      message,
      originalLoad: (data) => forward(channel, handler, data),
    );
  }

  void clearAssetCaches() {
    rootBundle.clear();
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    svg.cache.clear();
  }

  void install() {
    clearAssetCaches();
    // Keep Flutter's synchronous file mock and any per-test channel mocks.
    messenger.allMessagesHandler = filteredLoad;
  }

  // Covers setUpAll asset loads as well as individual tests. Filtering above
  // the channel handler also survives reinstalls of Flutter's own asset mock.
  install();
  setUp(install);
  tearDown(() {
    try {
      expect(
        messenger.allMessagesHandler,
        same(filteredLoad),
        reason: 'Keep the mobile asset filter installed during the test.',
      );
      expect(
        assets.blockedRequests,
        isEmpty,
        reason:
            'Mobile tests requested desktop-only assets. Move shared artwork '
            'out of desktop/ and update pubspec.yaml, or fix the mobile caller. '
            'An image errorBuilder must not hide an unavailable asset.',
      );
    } finally {
      assets.blockedRequests.clear();
      clearAssetCaches();
    }
  });
  await testMain();
}
