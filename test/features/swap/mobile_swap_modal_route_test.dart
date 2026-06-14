@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/navigation/mobile_routes.dart';
import 'package:zcash_wallet/src/core/profile_pictures.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/swap/screens/mobile/mobile_swap_screen.dart';
import 'package:zcash_wallet/src/features/swap/widgets/swap_address_edit_modal.dart';
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
  activeAddress: 'u1swapmodaladdress',
);

AppBootstrapState _bootstrap() => AppBootstrapState(
  initialLocation: '/home',
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

Widget _app() => ProviderScope(
  overrides: [
    appBootstrapProvider.overrideWithValue(_bootstrap()),
    syncProvider.overrideWith(
      () => FakeSyncNotifier(
        SyncState(
          accountUuid: 'account-1',
          hasAccountScopedData: true,
          orchardBalance: BigInt.from(100000000),
        ),
      ),
    ),
  ],
  child: MaterialApp.router(
    routerConfig: GoRouter(
      initialLocation: '/home',
      routes: buildMobileRoutes(
        entryRoutes: const [],
        swapFeatureEnabled: true,
      ),
    ),
    builder: (_, child) => AppTheme(data: AppThemeData.dark, child: child!),
  ),
);

void main() {
  testWidgets('swap composer CTA fits on narrow Android-sized screens', (
    tester,
  ) async {
    await _setNarrowMobileViewport(tester);
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Swap').last);
    await tester.pumpAndSettle();

    expect(find.byType(MobileSwapScreen), findsOneWidget);
    expect(find.text('Add recipient address'), findsOneWidget);
    expect(tester.takeException(), isNull);

    final screen = tester.getRect(find.byType(MaterialApp));
    final button = tester.getRect(
      find.byKey(const ValueKey('mobile_swap_review_button')),
    );
    expect(button.right, lessThanOrEqualTo(screen.right - AppSpacing.sm));
  });

  testWidgets('swap modal rides the root navigator and covers the whole '
      'screen, tab bar included', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Swap').last);
    await tester.pumpAndSettle();
    expect(find.byType(MobileSwapScreen), findsOneWidget);

    await tester.tap(find.text('Add recipient address'));
    await tester.pumpAndSettle();
    expect(find.byType(SwapAddressEditModal), findsOneWidget);

    // The dialog barrier spans the full screen — including the status
    // bar strip at the very top and the floating tab bar at the bottom
    // (neither was covered by the old inline overlay).
    final screen = tester.getRect(find.byType(MaterialApp));
    final barrier = tester.getRect(find.byType(ModalBarrier).last);
    expect(barrier, screen);

    // A tap in the top strip — which the old inline overlay left
    // uncovered — now hits the barrier and dismisses the modal.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.byType(SwapAddressEditModal), findsNothing);
    expect(find.byType(MobileSwapScreen), findsOneWidget);

    // The bottom strip — where the floating tab bar sits — is under the
    // barrier too. The modal card is bottom-anchored with a gap beneath
    // it, so a tap in that gap hits the barrier and dismisses the modal
    // instead of reaching the tab bar to switch branches.
    await tester.tap(find.text('Add recipient address'));
    await tester.pumpAndSettle();
    expect(find.byType(SwapAddressEditModal), findsOneWidget);
    await tester.tapAt(Offset(screen.center.dx, screen.bottom - 4));
    await tester.pumpAndSettle();
    expect(find.byType(SwapAddressEditModal), findsNothing);
    expect(find.byType(MobileSwapScreen), findsOneWidget);
  });

  testWidgets('cancel inside the address editor closes the modal route', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Swap').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add recipient address'));
    await tester.pumpAndSettle();
    expect(find.byType(SwapAddressEditModal), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(SwapAddressEditModal), findsNothing);
    expect(find.byType(MobileSwapScreen), findsOneWidget);
  });
}

Future<void> _setNarrowMobileViewport(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(432, 960));
  addTearDown(() async {
    await tester.binding.setSurfaceSize(null);
  });
}
