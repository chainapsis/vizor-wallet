@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_keystone_screens.dart';
import 'package:zcash_wallet/src/rust/frb_generated.dart';

class _RustApiFake implements RustLibApi {
  @override
  void crateApiKeystoneResetUrSession() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _app() {
  return const ProviderScope(
    child: MaterialApp(
      home: AppTheme(
        data: AppThemeData.dark,
        child: MobileKeystoneScanScreen(),
      ),
    ),
  );
}

void _setViewSize(WidgetTester tester, Size size) {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1.0;
}

void main() {
  setUpAll(() {
    RustLib.initMock(api: _RustApiFake());
  });

  tearDownAll(RustLib.dispose);

  tearDown(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first
      ..resetPhysicalSize()
      ..resetDevicePixelRatio();
  });

  testWidgets('keeps the Figma camera height on tall phones', (tester) async {
    _setViewSize(tester, const Size(393, 852));

    await tester.pumpWidget(_app());
    await tester.pump();

    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(_cameraViewportSize(tester), const Size(361, 464));
  });

  testWidgets('shrinks only the camera viewport on shorter phones', (
    tester,
  ) async {
    _setViewSize(tester, const Size(393, 667));

    await tester.pumpWidget(_app());
    await tester.pump();

    final cameraSize = _cameraViewportSize(tester);
    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(cameraSize.width, 361);
    expect(cameraSize.height, lessThan(464));
    expect(cameraSize.height, greaterThan(300));

    final buttonBottom = tester
        .getBottomLeft(
          find.byKey(const ValueKey('mobile_keystone_scan_explainer')),
        )
        .dy;
    expect(buttonBottom, lessThanOrEqualTo(667));
  });
}

Size _cameraViewportSize(WidgetTester tester) {
  return tester.getSize(
    find.byKey(const ValueKey('keystone_qr_scanner_camera_viewport')),
  );
}
