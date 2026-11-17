import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/l10n/app_localizations.dart';
import 'package:zcash_wallet/src/core/l10n/app_language.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/address_book/models/address_book_contact.dart';
import 'package:zcash_wallet/src/features/address_scan/widgets/address_qr_scan_modal.dart';
import 'package:zcash_wallet/src/features/address_scan/widgets/address_scan_resolver.dart';
import 'package:zcash_wallet/src/features/address_scan/widgets/mobile_address_scan_view.dart'
    show MobileScanOutcome, MobileScanResolver;
import 'package:zcash_wallet/src/services/qr_scanner.dart';

import '../../support/app_test_fonts.dart';
import '../../support/localized_test_scope.dart';
import '../../support/test_l10n.dart';

const _evm = '0x157D19957d4047Fb8601783805a54EF6ae80eaD7';

void _mockCamera() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const camera = {
    'id': 'desktop-camera',
    'name': 'Desktop camera',
    'facing': 2,
    'isDefault': true,
  };
  const method = MethodChannel('dev.steenbakker.mobile_scanner/scanner/method');
  messenger.setMockMethodCallHandler(
    method,
    (call) async => switch (call.method) {
      'state' => 1,
      'request' => true,
      'getAvailableCameras' => [camera],
      'start' => {
        'textureId': 1,
        'camera': camera,
        'cameraDirection': 2,
        'numberOfCameras': 1,
        'size': {'width': 640.0, 'height': 480.0},
      },
      _ => null,
    },
  );
  addTearDown(() => messenger.setMockMethodCallHandler(method, null));
  for (final suffix in ['event', 'deviceOrientation']) {
    final channel = MethodChannel(
      'dev.steenbakker.mobile_scanner/scanner/$suffix',
    );
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  }
}

Future<void> _pump(
  WidgetTester tester, {
  required MobileScanResolver resolve,
  required List<String> scanned,
  VoidCallback? onCancel,
  Locale locale = const Locale('en'),
}) async {
  _mockCamera();
  await tester.pumpWidget(
    LocalizedTestScope(
      locale: locale,
      child: AppTheme(
        data: AppThemeData.dark,
        child: Center(
          child: AddressQrScanModal(
            resolve: resolve,
            onAddressScanned: scanned.add,
            onCancel: onCancel ?? () {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

PlainQrScannerView _camera(WidgetTester tester) =>
    tester.widget<PlainQrScannerView>(find.byType(PlainQrScannerView));

void main() {
  setUpAll(loadAppTestFonts);

  testWidgets('a refused code is explained and the camera scans again', (
    tester,
  ) async {
    final scanned = <String>[];
    await _pump(
      tester,
      resolve: addressScanResolver(
        testL10n,
        network: AddressBookNetwork.ethereum,
      ),
      scanned: scanned,
    );

    final firstSession = _camera(tester).scanSessionResetToken;
    _camera(
      tester,
    ).onComplete('bitcoin:bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4');
    await tester.pumpAndSettle();
    expect(
      find.text(testL10n.addressScanWrongNetworkNamed('Bitcoin')),
      findsOneWidget,
    );
    expect(scanned, isEmpty);
    // The camera view latches on a reported code until its session changes.
    expect(_camera(tester).scanSessionResetToken, isNot(firstSession));

    _camera(tester).onComplete('ethereum:$_evm@1?value=1e18');
    await tester.pumpAndSettle();
    expect(scanned, [_evm]);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('every refusal fits under the camera in each language', (
    tester,
  ) async {
    for (final language in AppLanguage.values) {
      final l10n = lookupAppLocalizations(language.locale);
      final resolve = addressScanResolver(
        l10n,
        network: AddressBookNetwork.bitcoinCash,
      );
      await _pump(
        tester,
        resolve: resolve,
        scanned: [],
        locale: language.locale,
      );
      for (final raw in [
        'https://example.com',
        'bitcoin:bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4',
        'ethereum:$_evm',
        // The longest chain name a refusal can carry.
        'ethereum:$_evm@56',
        'not a bitcoin cash address',
      ]) {
        _camera(tester).onComplete(raw);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('address_scan_error')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull, reason: '$language: $raw');
      }
    }
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('a resolver that throws leaves the scanner usable', (
    tester,
  ) async {
    final scanned = <String>[];
    var calls = 0;
    await _pump(
      tester,
      resolve: (raw) async {
        if (calls++ == 0) throw const FormatException('unreadable');
        return MobileScanOutcome.accepted(raw);
      },
      scanned: scanned,
    );

    final firstSession = _camera(tester).scanSessionResetToken;
    _camera(tester).onComplete('first');
    await tester.pumpAndSettle();
    expect(find.text(testL10n.commonKeepQrSteady), findsOneWidget);
    expect(_camera(tester).scanSessionResetToken, isNot(firstSession));

    _camera(tester).onComplete('second');
    await tester.pumpAndSettle();
    expect(scanned, ['second']);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('a result that arrives after Cancel is dropped', (tester) async {
    final scanned = <String>[];
    final result = Completer<MobileScanOutcome>();
    var cancelled = 0;
    await _pump(
      tester,
      resolve: (_) => result.future,
      scanned: scanned,
      onCancel: () => cancelled++,
    );

    _camera(tester).onComplete(_evm);
    await tester.pump();
    await tester.tap(find.text(testL10n.commonCancel));
    expect(cancelled, 1);

    result.complete(const MobileScanOutcome.accepted(_evm));
    await tester.pumpAndSettle();
    expect(scanned, isEmpty);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}
