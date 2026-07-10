@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/profile_pictures.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/pay/screens/mobile/mobile_pay_screen.dart';
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
      home: AppTheme(data: AppThemeData.dark, child: const MobilePayScreen()),
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
  testWidgets('mobile pay follows the amount to recipient flow', (
    tester,
  ) async {
    await _setMobileViewport(tester, const Size(393, 852));
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(MobilePayScreen), findsOneWidget);
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(
      scaffold.backgroundColor,
      AppThemeData.dark.colors.background.window,
    );
    expect(find.text('Pay in USDC'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile_pay_amount_step')),
      findsOneWidget,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('mobile_pay_amount_card'))),
      const Size(361, 240),
    );
    expect(
      find.byKey(const ValueKey('mobile_pay_amount_continue_button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('mobile_pay_recipient_step')),
      findsNothing,
    );

    await tester.enterText(
      find.byKey(const ValueKey('mobile_pay_amount_input')),
      '10',
    );
    await tester.pump();
    expect(tester.takeException(), isNull);

    await tester.tap(
      find.byKey(const ValueKey('mobile_pay_amount_continue_button')),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    expect(find.text('Select Recipient'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile_pay_recipient_step')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('mobile_pay_recipient_field')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('mobile_pay_amount_step')), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('mobile_pay_recipient_input')),
      '0x1111111111111111111111111111111111111111',
    );
    await tester.pump();
    expect(tester.takeException(), isNull);

    expect(
      find.byKey(const ValueKey('mobile_pay_recipient_error')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('mobile_pay_new_address_notice')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('mobile_pay_add_to_contacts_button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('mobile_pay_recipient_continue_button')),
      findsOneWidget,
    );

    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.tap(
      find.byKey(const ValueKey('mobile_pay_add_to_contacts_button')),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('mobile_pay_add_contact_card')),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const ValueKey('mobile_pay_add_contact_label')),
      'Mike',
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(
      tester
          .getRect(find.byKey(const ValueKey('mobile_pay_add_contact_save')))
          .bottom,
      lessThanOrEqualTo(552),
    );

    tester.view.resetViewInsets();
    await tester.tap(
      find.byKey(const ValueKey('mobile_pay_add_contact_cancel')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    expect(find.text('Pay in USDC'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile_pay_amount_step')),
      findsOneWidget,
    );
    final amountInput = tester.widget<TextField>(
      find.byKey(const ValueKey('mobile_pay_amount_input')),
    );
    expect(amountInput.controller?.text, '10');
  });
}
