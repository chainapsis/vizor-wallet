@Tags(['mobile'])
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/onboarding/keystone/keystone_onboarding_flow.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_keystone_screens.dart';
import 'package:zcash_wallet/src/rust/frb_generated.dart';
import 'package:zcash_wallet/src/rust/wallet/keystone.dart';
import 'package:zcash_wallet/src/services/qr_scanner.dart';

class _RustApiFake implements RustLibApi {
  List<KeystoneAccountInfo> decodedAccounts = const <KeystoneAccountInfo>[];
  Object? decodeError;

  @override
  void crateApiKeystoneResetUrSession() {}

  @override
  Future<List<KeystoneAccountInfo>> crateApiKeystoneDecodeAccountsFromCbor({
    required List<int> cbor,
  }) async {
    final error = decodeError;
    if (error != null) throw error;
    return decodedAccounts;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _rustApi = _RustApiFake();

Widget _app({MobileScannerController? controller}) {
  return ProviderScope(
    child: MaterialApp(
      home: AppTheme(
        data: AppThemeData.dark,
        child: MobileKeystoneScanScreen(scannerController: controller),
      ),
    ),
  );
}

Widget _routerApp({
  String initialLocation = '/onboarding/keystone/scan',
  MobileScannerController? controller,
}) {
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: KeystoneOnboardingStep.scanQrCode.routePath,
        builder: (_, _) =>
            MobileKeystoneScanScreen(scannerController: controller),
      ),
      GoRoute(
        path: KeystoneOnboardingStep.selectAccount.routePath,
        builder: (_, _) => const MobileKeystoneSelectAccountScreen(),
      ),
      GoRoute(
        path: KeystoneOnboardingStep.walletBirthdayHeight.routePath,
        builder: (_, _) => const SizedBox(key: ValueKey('birthday-screen')),
      ),
    ],
  );

  return ProviderScope(
    child: MaterialApp.router(
      routerConfig: router,
      builder: (context, child) => AppTheme(
        data: AppThemeData.dark,
        child: child ?? const SizedBox.shrink(),
      ),
    ),
  );
}

KeystoneAccountInfo _account(int index) {
  return KeystoneAccountInfo(
    name: 'Account $index',
    ufvk: 'u1testaccount$index ... 3123llasdasd',
    index: index,
    seedFingerprint: Uint8List.fromList([index, 0, 0, 0]),
  );
}

void _setViewSize(WidgetTester tester, Size size) {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1.0;
}

void main() {
  setUpAll(() {
    RustLib.initMock(api: _rustApi);
  });

  setUp(() {
    _rustApi
      ..decodedAccounts = const <KeystoneAccountInfo>[]
      ..decodeError = null;
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
    final controller = MobileScannerController(autoStart: false);
    addTearDown(controller.dispose);

    controller.value = controller.value.copyWith(isInitialized: true);

    await tester.pumpWidget(_app(controller: controller));
    await tester.pump();

    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(
      find.byKey(const ValueKey('mobile_keystone_scan_explainer')),
      findsNothing,
    );
    expect(_cameraViewportSize(tester), const Size(361, 464));
  });

  testWidgets('uses the Keystone permission card while access is pending', (
    tester,
  ) async {
    _setViewSize(tester, const Size(393, 852));
    final controller = MobileScannerController(autoStart: false);
    addTearDown(controller.dispose);

    await tester.pumpWidget(_app(controller: controller));
    await tester.pump();

    final cameraElement = tester.element(
      find.byKey(const ValueKey('mobile_keystone_scan_camera')),
    );
    expect(
      find.byKey(const ValueKey('mobile_keystone_scan_permission_card')),
      findsOneWidget,
    );
    expect(find.text('Enable camera access'), findsOneWidget);
    expect(
      find.text('A camera is required to connect Keystone.'),
      findsOneWidget,
    );
    expect(find.text('Grant access to your camera'), findsNothing);
    expect(find.text('Scan the address QR code'), findsNothing);

    controller.value = controller.value.copyWith(isInitialized: true);
    await tester.pump();

    expect(find.text('Loading...'), findsOneWidget);
    expect(find.text('Enable camera access'), findsNothing);
    expect(
      find.byKey(const ValueKey('mobile_keystone_scan_permission_card')),
      findsNothing,
    );
    expect(
      identical(
        tester.element(
          find.byKey(const ValueKey('mobile_keystone_scan_camera')),
        ),
        cameraElement,
      ),
      isTrue,
    );
  });

  testWidgets('denied access uses the Keystone retry card', (tester) async {
    _setViewSize(tester, const Size(393, 852));
    final controller = MobileScannerController(autoStart: false);
    addTearDown(controller.dispose);

    await tester.pumpWidget(_app(controller: controller));
    await tester.pump();

    controller.value = controller.value.copyWith(
      isInitialized: true,
      error: const MobileScannerException(
        errorCode: MobileScannerErrorCode.permissionDenied,
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('mobile_keystone_scan_permission_card')),
      findsOneWidget,
    );
    expect(find.text("You've denied camera access"), findsOneWidget);
    expect(find.text('Request again'), findsOneWidget);
    expect(find.text('Cancel'), findsNothing);
  });

  testWidgets('shows scan card once camera permission is granted and running', (
    tester,
  ) async {
    _setViewSize(tester, const Size(393, 852));
    final controller = MobileScannerController(autoStart: false);
    addTearDown(controller.dispose);

    controller.value = controller.value.copyWith(
      isInitialized: true,
      isRunning: true,
    );
    await tester.pumpWidget(_app(controller: controller));
    await tester.pump();

    expect(find.byKey(const ValueKey('mobile_keystone_scan_camera')), findsOne);
    expect(find.text('Scan a Zcash QR code to continue'), findsOneWidget);
    expect(find.text('Loading...'), findsNothing);
    expect(find.text('Enable camera access'), findsNothing);
    expect(
      find.byKey(const ValueKey('mobile_keystone_scan_permission_card')),
      findsNothing,
    );
  });

  testWidgets('shrinks only the camera viewport on shorter phones', (
    tester,
  ) async {
    _setViewSize(tester, const Size(393, 667));
    final controller = MobileScannerController(autoStart: false);
    addTearDown(controller.dispose);

    controller.value = controller.value.copyWith(isInitialized: true);

    await tester.pumpWidget(_app(controller: controller));
    await tester.pump();

    final cameraSize = _cameraViewportSize(tester);
    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(
      find.byKey(const ValueKey('mobile_keystone_scan_explainer')),
      findsNothing,
    );
    expect(cameraSize.width, 361);
    expect(cameraSize.height, lessThan(464));
    expect(cameraSize.height, greaterThan(300));
  });

  testWidgets('moves to select account after a Keystone account QR scan', (
    tester,
  ) async {
    _setViewSize(tester, const Size(393, 852));
    _rustApi.decodedAccounts = [_account(1), _account(2)];
    final controller = MobileScannerController(autoStart: false);
    addTearDown(controller.dispose);

    await tester.pumpWidget(_routerApp(controller: controller));
    await tester.pump();

    tester
        .widget<AnimatedUrScannerView>(
          find.byKey(const ValueKey('mobile_keystone_scan_camera')),
        )
        .onComplete(
          const ScanResult(urType: 'zcash-accounts', data: [1, 2, 3]),
        );

    await tester.pump();
    await tester.pump();

    expect(find.byType(MobileKeystoneSelectAccountScreen), findsOneWidget);
    expect(find.text('2 accounts found'), findsOneWidget);
    expect(find.text('Account 1'), findsOneWidget);
  });

  testWidgets('resets the scan session when returning from select account', (
    tester,
  ) async {
    _setViewSize(tester, const Size(393, 852));
    _rustApi.decodedAccounts = [_account(1), _account(2)];
    final controller = MobileScannerController(autoStart: false);
    addTearDown(controller.dispose);

    await tester.pumpWidget(_routerApp(controller: controller));
    await tester.pump();

    int token() =>
        tester
                .widget<AnimatedUrScannerView>(
                  find.byKey(const ValueKey('mobile_keystone_scan_camera')),
                )
                .scanSessionResetToken!
            as int;

    final initial = token();

    tester
        .widget<AnimatedUrScannerView>(
          find.byKey(const ValueKey('mobile_keystone_scan_camera')),
        )
        .onComplete(
          const ScanResult(urType: 'zcash-accounts', data: [1, 2, 3]),
        );
    await tester.pump();
    await tester.pump();
    expect(find.byType(MobileKeystoneSelectAccountScreen), findsOneWidget);

    // Backing out to scan a different Keystone QR must reset the scanner so
    // it can complete again instead of staying in its finished state.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byType(MobileKeystoneScanScreen), findsOneWidget);
    expect(token(), greaterThan(initial));
  });

  testWidgets('stays on scan with an inline error when no accounts decode', (
    tester,
  ) async {
    _setViewSize(tester, const Size(393, 852));
    final controller = MobileScannerController(autoStart: false);
    addTearDown(controller.dispose);

    controller.value = controller.value.copyWith(
      isInitialized: true,
      isRunning: true,
    );

    await tester.pumpWidget(_app(controller: controller));
    await tester.pump();

    tester
        .widget<AnimatedUrScannerView>(
          find.byKey(const ValueKey('mobile_keystone_scan_camera')),
        )
        .onComplete(
          const ScanResult(urType: 'zcash-accounts', data: [1, 2, 3]),
        );

    await tester.pump();
    await tester.pump();

    expect(find.byType(MobileKeystoneScanScreen), findsOneWidget);
    expect(
      find.text('No Zcash accounts were found on this Keystone QR.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'select account redirects back to scan without scanned accounts',
    (tester) async {
      _setViewSize(tester, const Size(393, 852));

      await tester.pumpWidget(
        _routerApp(
          initialLocation: KeystoneOnboardingStep.selectAccount.routePath,
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byType(MobileKeystoneScanScreen), findsOneWidget);
    },
  );
}

Size _cameraViewportSize(WidgetTester tester) {
  return tester.getSize(
    find.byKey(const ValueKey('mobile_keystone_scan_card')),
  );
}
