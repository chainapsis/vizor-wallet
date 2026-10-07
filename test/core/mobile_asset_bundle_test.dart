@Tags(['mobile'])
library;

import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mobile_test_assets_test.dart' as filter_tests;
import 'platform_asset_contract_test.dart' as contract_tests;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Reuse the same regressions in the opt-in mobile lane; --tags mobile would
  // otherwise exclude their untagged desktop entry points.
  filter_tests.main();
  contract_tests.main();

  testWidgets('mobile root asset loads retain synchronous fixture behavior', (
    tester,
  ) async {
    var loaded = false;
    rootBundle.load('assets/fonts/Geist-Regular.ttf').then((bytes) {
      expect(bytes.lengthInBytes, greaterThan(0));
      loaded = true;
    });
    expect(loaded, isTrue, reason: 'Preserve Flutter host-test mock timing.');
  });

  test('mobile tests expose shared assets without desktop artwork', () async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final assets = manifest.listAssets();

    expect(assets, contains('assets/profile_pictures/profile_picture_01.png'));
    expect(assets, contains('assets/animations/mobile_welcome.mp4'));
    expect(
      assets.where((asset) => asset.contains('/desktop/')),
      isEmpty,
      reason: 'Mobile tests must not expose desktop-only artwork.',
    );
  });

  test('mobile tests retain real shared SVG and WebP bytes', () async {
    final svg = await rootBundle.loadString('assets/icons/book.svg');
    expect(svg, contains('<svg'));

    final bytes = await rootBundle.load(
      'assets/illustrations/mobile_welcome_poster.webp',
    );
    final codec = await ui.instantiateImageCodec(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
    );
    try {
      final frame = await codec.getNextFrame();
      expect(frame.image.width, greaterThan(0));
      frame.image.dispose();
    } finally {
      codec.dispose();
    }
  });
}
