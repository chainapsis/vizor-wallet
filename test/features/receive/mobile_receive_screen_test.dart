@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/profile_pictures.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/receive/screens/mobile/mobile_receive_screen.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/receive_address_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

import '../../fakes/fake_sync_notifier.dart';

const _shielded = 'u1tvg2412a23kshieldedaddressk64123hhq6d';
const _transparent = 't1transparentaddress12345678901234';

const _accountState = AccountState(
  accounts: [
    AccountInfo(
      uuid: 'account-1',
      name: 'Account Name',
      order: 0,
      profilePictureId: kDefaultProfilePictureId,
    ),
  ],
  activeAccountUuid: 'account-1',
  activeAddress: _shielded,
);

AppBootstrapState _bootstrap() => AppBootstrapState(
  initialLocation: '/receive',
  initialAccountState: _accountState,
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.dark,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);

class _FakeReceiveAddressService implements ReceiveAddressService {
  var renewals = 0;

  @override
  Future<String> loadShieldedAddress({
    required String accountUuid,
    String? currentShieldedAddress,
  }) async => currentShieldedAddress ?? _shielded;

  @override
  Future<String> loadTransparentAddress({required String accountUuid}) async =>
      _transparent;

  @override
  Future<String> renewShieldedAddress({required String accountUuid}) async {
    renewals++;
    return 'u1renewedaddress9876543210abcdefghij';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The QR placeholder spinner animates indefinitely, so pumpAndSettle
/// would time out; settle with bounded pumps instead.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _pumpReceive(
  WidgetTester tester,
  _FakeReceiveAddressService service,
) async {
  // The test-only Ahem font renders every glyph as a full-width square,
  // so the longest share label needs ~520px here; real fonts fit a
  // 393pt phone comfortably.
  tester.view.physicalSize = const Size(520, 932);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_app(service));
  await _settle(tester);
}

Widget _app(_FakeReceiveAddressService service) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap()),
      syncProvider.overrideWith(() => FakeSyncNotifier(SyncState())),
      receiveAddressServiceProvider.overrideWithValue(service),
    ],
    child: MaterialApp(
      builder: (_, child) => AppTheme(data: AppThemeData.dark, child: child!),
      home: const MobileReceiveScreen(),
    ),
  );
}

void main() {
  testWidgets('shows the shielded pool by default with share and copy', (
    tester,
  ) async {
    await _pumpReceive(tester, _FakeReceiveAddressService());

    expect(find.text('Receive ZEC'), findsOneWidget);
    expect(find.text('Account Name'), findsOneWidget);
    expect(find.text('Share shielded address'), findsOneWidget);
    expect(find.text('Copy shielded address'), findsOneWidget);
    // Compact address line: leading 13 chars visible.
    expect(
      find.textContaining(_shielded.substring(0, 13), findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('switching to transparent swaps labels and address', (
    tester,
  ) async {
    await _pumpReceive(tester, _FakeReceiveAddressService());

    await tester.tap(find.text('Transparent'));
    await _settle(tester);

    expect(find.text('Share transparent address'), findsOneWidget);
    expect(find.text('Copy transparent address'), findsOneWidget);
    expect(
      find.textContaining(_transparent.substring(0, 13), findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('renew requests a fresh shielded address', (tester) async {
    final service = _FakeReceiveAddressService();
    await _pumpReceive(tester, service);

    await tester.tap(find.bySemanticsLabel('Generate new shielded address'));
    await _settle(tester);

    expect(service.renewals, 1);
    expect(
      find.textContaining('u1renewedaddr', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('copy puts the selected address on the clipboard', (
    tester,
  ) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await _pumpReceive(tester, _FakeReceiveAddressService());

    await tester.tap(find.text('Copy shielded address'));
    await _settle(tester);

    expect(copied, [_shielded]);
    expect(find.text('Address copied'), findsOneWidget);
  });

  testWidgets('the help icon opens the explainer for the selected pool', (
    tester,
  ) async {
    await _pumpReceive(tester, _FakeReceiveAddressService());

    await tester.tap(find.bySemanticsLabel('About this address type'));
    await _settle(tester);
    expect(find.text('Shielded address'), findsOneWidget);
    expect(find.text('Strong privacy by default.'), findsOneWidget);
    // The mobile explainer adapts the renew bullet to touch.
    expect(
      find.textContaining('tap the Renew button', findRichText: true),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('receive_address_info_close')));
    await _settle(tester);
    expect(find.text('Strong privacy by default.'), findsNothing);

    await tester.tap(find.text('Transparent'));
    await _settle(tester);
    await tester.tap(find.bySemanticsLabel('About this address type'));
    await _settle(tester);
    expect(find.text('Transparent address'), findsOneWidget);
    expect(find.text('Publicly visible'), findsOneWidget);
    expect(
      find.textContaining('publicly visible on-chain', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('share hands the address to the platform share sheet', (
    tester,
  ) async {
    // share_plus rides a method channel; capture the invocation instead
    // of opening a real share sheet.
    final shareCalls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/share'),
      (call) async {
        shareCalls.add(call);
        return 'dev.fluttercommunity.plus/share/success';
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('dev.fluttercommunity.plus/share'),
        null,
      ),
    );

    await _pumpReceive(tester, _FakeReceiveAddressService());

    await tester.tap(find.text('Share shielded address'));
    await _settle(tester);

    expect(find.text('Not available yet'), findsNothing);
    expect(shareCalls, hasLength(1));
    expect(
      (shareCalls.single.arguments as Map<Object?, Object?>)['text'],
      _shielded,
    );
  });
}
