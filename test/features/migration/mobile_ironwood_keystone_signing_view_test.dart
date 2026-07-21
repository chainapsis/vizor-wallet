@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/features/migration/widgets/mobile/mobile_ironwood_keystone_signing_view.dart';

Widget _app({
  required MobileIronwoodKeystoneSigningViewState state,
  Widget? qrCode,
  Widget? camera,
  VoidCallback? onNext,
  VoidCallback? onCancel,
  VoidCallback? onToggleFlashlight,
  VoidCallback? onShowRequestQr,
}) {
  return MaterialApp(
    home: AppTheme(
      data: AppThemeData.dark,
      child: MobileIronwoodKeystoneSigningView(
        state: state,
        round: MobileIronwoodKeystoneSigningRound.denominationSplit,
        qrCode: qrCode,
        camera: camera,
        onNext: onNext,
        onCancel: onCancel,
        onToggleFlashlight: onToggleFlashlight,
        onShowRequestQr: onShowRequestQr,
      ),
    ),
  );
}

void _useMobileViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(393, 852);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

void main() {
  testWidgets('loading matches the standalone Figma waiting state', (
    tester,
  ) async {
    _useMobileViewport(tester);
    var nexts = 0;
    var cancels = 0;
    await tester.pumpWidget(
      _app(
        state: MobileIronwoodKeystoneSigningViewState.loading,
        onNext: () => nexts++,
        onCancel: () => cancels++,
      ),
    );

    expect(find.text('Step 1/2'), findsOneWidget);
    expect(find.text('Confirm Migration with Keystone'), findsOneWidget);
    expect(find.text('Loading QR code ...'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile_ironwood_keystone_signing_next')),
      findsOneWidget,
    );
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey('mobile_ironwood_keystone_signing_next')),
          )
          .width,
      361,
    );
    expect(
      find.byKey(const ValueKey('mobile_ironwood_keystone_signing_cancel')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('mobile_ironwood_keystone_signing_next')),
    );
    await tester.tap(
      find.byKey(const ValueKey('mobile_ironwood_keystone_signing_cancel')),
    );
    expect(nexts, 1);
    expect(cancels, 1);
  });

  testWidgets('loading keeps Back and Cancel visible without callbacks', (
    tester,
  ) async {
    _useMobileViewport(tester);
    await tester.pumpWidget(
      _app(state: MobileIronwoodKeystoneSigningViewState.loading),
    );

    expect(find.bySemanticsLabel('Back'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile_ironwood_keystone_signing_cancel')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('mobile_ironwood_keystone_signing_next')),
      findsOneWidget,
    );
  });

  testWidgets('ready renders QR and calls Next and Cancel', (tester) async {
    _useMobileViewport(tester);
    var nexts = 0;
    var cancels = 0;
    await tester.pumpWidget(
      _app(
        state: MobileIronwoodKeystoneSigningViewState.ready,
        qrCode: const ColoredBox(color: Colors.black),
        onNext: () => nexts++,
        onCancel: () => cancels++,
      ),
    );

    expect(find.text('Scan with Keystone'), findsOneWidget);
    expect(find.text('Tap'), findsOneWidget);
    expect(find.text('on your Keystone,'), findsOneWidget);
    expect(find.text('then scan this QR code'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is AppIcon && widget.name == AppIcons.keystoneScan,
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('mobile_ironwood_keystone_signing_qr_container'),
      ),
      findsOneWidget,
    );
    final qrContainer = tester.widget<Container>(
      find.byKey(
        const ValueKey('mobile_ironwood_keystone_signing_qr_container'),
      ),
    );
    expect(qrContainer.color, Colors.white);
    expect(qrContainer.padding, const EdgeInsets.all(8));
    await tester.tap(
      find.byKey(const ValueKey('mobile_ironwood_keystone_signing_next')),
    );
    await tester.tap(
      find.byKey(const ValueKey('mobile_ironwood_keystone_signing_cancel')),
    );
    expect(nexts, 1);
    expect(cancels, 1);
  });

  testWidgets('scanner exposes camera, target, and wired controls only', (
    tester,
  ) async {
    _useMobileViewport(tester);
    var qrReturns = 0;
    await tester.pumpWidget(
      _app(
        state: MobileIronwoodKeystoneSigningViewState.scanner,
        camera: const ColoredBox(
          key: ValueKey('mobile_ironwood_keystone_signing_camera'),
          color: Colors.blue,
        ),
        onShowRequestQr: () => qrReturns++,
      ),
    );

    expect(
      find.byKey(const ValueKey('mobile_ironwood_keystone_signing_camera')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('mobile_ironwood_keystone_signing_flashlight')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('mobile_ironwood_keystone_signing_qr_action')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('mobile_ironwood_keystone_signing_scan_target'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(
          const ValueKey('mobile_ironwood_keystone_signing_qr_action'),
        ),
        matching: find.byType(AppIcon),
      ),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('mobile_ironwood_keystone_signing_qr_action')),
    );
    expect(qrReturns, 1);
  });

  testWidgets('all states remain usable at 320 by 568', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _app(
        state: MobileIronwoodKeystoneSigningViewState.loading,
        onNext: () {},
        onCancel: () {},
      ),
    );
    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('mobile_ironwood_keystone_signing_next')),
      findsOneWidget,
    );

    await tester.pumpWidget(
      _app(
        state: MobileIronwoodKeystoneSigningViewState.ready,
        qrCode: const ColoredBox(color: Colors.black),
        onNext: () {},
        onCancel: () {},
      ),
    );
    expect(tester.takeException(), isNull);
    expect(
      find.byKey(
        const ValueKey('mobile_ironwood_keystone_signing_qr_container'),
      ),
      findsOneWidget,
    );

    await tester.pumpWidget(
      _app(
        state: MobileIronwoodKeystoneSigningViewState.scanner,
        camera: const ColoredBox(color: Colors.black),
        onShowRequestQr: () {},
      ),
    );
    expect(tester.takeException(), isNull);

    final target = find.byKey(
      const ValueKey('mobile_ironwood_keystone_signing_scan_target'),
    );
    final flashlight = find.byKey(
      const ValueKey('mobile_ironwood_keystone_signing_flashlight'),
    );
    expect(tester.getBottomLeft(target).dy, lessThan(568));
    expect(tester.getBottomLeft(flashlight).dy, lessThanOrEqualTo(568));
  });
}
