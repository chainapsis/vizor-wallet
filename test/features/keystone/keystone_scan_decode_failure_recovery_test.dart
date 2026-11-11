import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/l10n/app_language.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/keystone/widgets/keystone_qr_scanner_card.dart';
import 'package:zcash_wallet/src/features/onboarding/keystone/keystone_scan_qr_screen.dart';
import 'package:zcash_wallet/src/features/send/screens/keystone_send_scan_screen.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/frb_generated.dart';
import 'package:zcash_wallet/src/rust/wallet/keystone.dart';
import 'package:zcash_wallet/src/services/qr_scanner.dart';

import '../../fakes/fake_sync_notifier.dart';

class _RustApiFake implements RustLibApi {
  int urPartCalls = 0;
  int payloadDecodeCalls = 0;
  bool completes = true;

  @override
  void crateApiKeystoneResetUrSession() {}

  @override
  Future<UrDecodeResult> crateApiKeystoneDecodeUrPart({
    required String part_,
    required String expectedUrType,
  }) async {
    urPartCalls++;
    return UrDecodeResult(
      complete: completes,
      progress: completes ? 100 : 10,
      data: completes ? Uint8List.fromList(part_.codeUnits) : null,
      urType: expectedUrType,
    );
  }

  @override
  Future<List<KeystoneAccountInfo>> crateApiKeystoneDecodeAccountsFromCbor({
    required List<int> cbor,
  }) async {
    payloadDecodeCalls++;
    throw StateError('malformed account CBOR');
  }

  @override
  Future<Uint8List> crateApiKeystoneDecodePcztFromCbor({
    required List<int> cbor,
  }) async {
    payloadDecodeCalls++;
    throw StateError('malformed PCZT CBOR');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _rust = _RustApiFake();

Future<void> _detect(WidgetTester tester, String value) async {
  final scanner = tester.widget<MobileScanner>(find.byType(MobileScanner));
  scanner.onDetect!(BarcodeCapture(barcodes: [Barcode(rawValue: value)]));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> _expectRecovery(WidgetTester tester, String errorText) async {
  await _detect(tester, 'ur:type/malformed');
  expect(_rust.urPartCalls, 1);
  expect(_rust.payloadDecodeCalls, 1);
  expect(find.text(errorText), findsOneWidget);

  // The scanner completed on the bad QR; the next QR must still be read.
  await _detect(tester, 'ur:type/next-qr');
  expect(_rust.urPartCalls, 2);
  expect(_rust.payloadDecodeCalls, 2);
}

AppBootstrapState _bootstrap() => AppBootstrapState(
  initialLocation: '/home',
  initialAccountState: const AccountState(
    accounts: [AccountInfo(uuid: 'account-1', name: 'Account1', order: 0)],
    activeAccountUuid: 'account-1',
    activeAddress: 'u1scan',
  ),
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.dark,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);

Widget _host(Widget child) {
  final router = GoRouter(
    routes: [GoRoute(path: '/', builder: (_, _) => child)],
  );
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap()),
      syncProvider.overrideWith(FakeSyncNotifier.new),
    ],
    child: AppTheme(
      data: AppThemeData.dark,
      child: MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: appLocalizationsDelegates,
        builder: (context, child) => Scaffold(body: child),
      ),
    ),
  );
}

void _drainFrameworkErrors(WidgetTester tester) {
  // Platform camera and shell calls are unavailable on the test host; they
  // are not what this test exercises.
  while (tester.takeException() != null) {}
}

/// A screen that stays on the scanner and decides, after each completed scan,
/// whether it is still using the payload (`decoding`).
class _CardHost extends StatefulWidget {
  const _CardHost({required this.keepsDecoding});

  final bool keepsDecoding;

  @override
  State<_CardHost> createState() => _CardHostState();
}

class _CardHostState extends State<_CardHost> {
  bool decoding = false;

  void rebuild() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return KeystoneQrScannerCard(
      expectedUrType: 'zcash-pczt',
      decoding: decoding,
      error: null,
      onProgress: (_) {},
      onDecodeError: (_) {},
      onComplete: (_) => setState(() => decoding = widget.keepsDecoding),
      unavailableMessage: 'Camera required',
    );
  }
}

Object? _sessionToken(WidgetTester tester) => tester
    .widget<AnimatedUrScannerView>(find.byType(AnimatedUrScannerView))
    .scanSessionResetToken;

void main() {
  setUpAll(() => RustLib.initMock(api: _rust));
  tearDownAll(RustLib.dispose);

  setUp(() {
    _rust
      ..urPartCalls = 0
      ..payloadDecodeCalls = 0
      ..completes = true;
  });

  testWidgets('account scan reads the next QR after an unusable payload', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const KeystoneScanQrScreen()));
    await tester.pump();
    _drainFrameworkErrors(tester);
    await _expectRecovery(
      tester,
      'This QR code could not be decoded as a Keystone Zcash account.',
    );
    _drainFrameworkErrors(tester);
  });

  testWidgets('frames reach the decoder until a scan completes', (
    tester,
  ) async {
    _rust.completes = false;
    await tester.pumpWidget(_host(const KeystoneScanQrScreen()));
    await tester.pump();
    _drainFrameworkErrors(tester);
    await _detect(tester, 'ur:type/part-1');
    await _detect(tester, 'ur:type/part-2');
    expect(_rust.urPartCalls, 2);
    _drainFrameworkErrors(tester);
  });

  testWidgets('send scan reads the next QR after an unusable payload', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const KeystoneSendScanScreen()));
    await tester.pump();
    _drainFrameworkErrors(tester);
    await _expectRecovery(
      tester,
      'This QR code could not be decoded as a Keystone transaction signature.',
    );
    _drainFrameworkErrors(tester);
  });

  testWidgets('a screen still using the payload keeps the scan session', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const _CardHost(keepsDecoding: true)));
    await tester.pump();
    _drainFrameworkErrors(tester);
    final before = _sessionToken(tester);
    await _detect(tester, 'ur:type/signature');
    // Later rebuilds, such as proof polling, must not reopen the scanner.
    tester.state<_CardHostState>(find.byType(_CardHost)).rebuild();
    await tester.pump();
    expect(_sessionToken(tester), before);
    await _detect(tester, 'ur:type/other');
    expect(_rust.urPartCalls, 1);
    _drainFrameworkErrors(tester);
  });

  testWidgets('a screen that drops the payload gets a new scan session', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const _CardHost(keepsDecoding: false)));
    await tester.pump();
    _drainFrameworkErrors(tester);
    final before = _sessionToken(tester);
    await _detect(tester, 'ur:type/signature');
    expect(_sessionToken(tester), isNot(before));
    await _detect(tester, 'ur:type/other');
    expect(_rust.urPartCalls, 2);
    _drainFrameworkErrors(tester);
  });
}
