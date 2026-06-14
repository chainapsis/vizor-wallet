@Tags(['mobile'])
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/keystone/widgets/keystone_qr_scanner_card.dart';
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

Widget _routerApp({String initialLocation = '/onboarding/keystone/scan'}) {
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: KeystoneOnboardingStep.scanQrCode.routePath,
        builder: (_, _) => const MobileKeystoneScanScreen(),
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

    await tester.pumpWidget(_app());
    await tester.pump();

    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(
      find.byKey(const ValueKey('mobile_keystone_scan_explainer')),
      findsNothing,
    );
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

    await tester.pumpWidget(_routerApp());
    await tester.pump();

    tester
        .widget<KeystoneQrScannerCard>(
          find.byKey(const ValueKey('mobile_keystone_scan_card')),
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

  testWidgets('stays on scan with an inline error when no accounts decode', (
    tester,
  ) async {
    _setViewSize(tester, const Size(393, 852));

    await tester.pumpWidget(_app());
    await tester.pump();

    tester
        .widget<KeystoneQrScannerCard>(
          find.byKey(const ValueKey('mobile_keystone_scan_card')),
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
    find.byKey(const ValueKey('keystone_qr_scanner_camera_viewport')),
  );
}
