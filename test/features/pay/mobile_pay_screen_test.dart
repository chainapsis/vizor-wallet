@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/profile_pictures.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/pay/screens/pay_screen.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

import '../../fakes/fake_sync_notifier.dart';

const _accountState = AccountState(
  accounts: [
    AccountInfo(
      uuid: 'account-1',
      name: 'Account1',
      order: 0,
      profilePictureId: kDefaultProfilePictureId,
    ),
  ],
  activeAccountUuid: 'account-1',
  activeAddress: 'u1payaddress',
);

AppBootstrapState _bootstrap() => AppBootstrapState(
  initialLocation: '/pay',
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

Widget _app() {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap()),
      syncProvider.overrideWith(
        () => FakeSyncNotifier(
          SyncState(
            accountUuid: 'account-1',
            hasAccountScopedData: true,
            orchardBalance: BigInt.from(14_312_000_000),
            spendableBalance: BigInt.from(14_312_000_000),
            totalBalance: BigInt.from(14_312_000_000),
          ),
        ),
      ),
    ],
    child: MaterialApp(
      home: AppTheme(
        data: AppThemeData.dark,
        child: const MobilePayScreen(),
      ),
    ),
  );
}

Future<void> _setMobileViewport(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('mobile pay screen renders recipient and amount steps', (
    tester,
  ) async {
    await _setMobileViewport(tester, const Size(320, 568));
    await tester.pumpWidget(_app());
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(MobilePayScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('pay_page_title')), findsNothing);
    expect(find.byKey(const ValueKey('pay_page_icon')), findsNothing);
    expect(
      find.byKey(const ValueKey('swap_near_intents_attribution')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('pay_recipient_address_field')),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const ValueKey('pay_recipient_address_field')),
      '0x1111111111111111111111111111111111111111',
    );
    await tester.pump();
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('pay_network_option_eth')));
    await tester.pump();
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('pay_continue_button')));
    await tester.pump();
    expect(tester.takeException(), isNull);

    expect(find.byKey(const ValueKey('pay_token_picker')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('pay_recipient_amount_field')),
      findsOneWidget,
    );
  });
}
