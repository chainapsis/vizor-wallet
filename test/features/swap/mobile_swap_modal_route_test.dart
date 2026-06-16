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

  testWidgets('swap address sheet rides the root navigator and dismisses '
      'from the scrim above it', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Swap').last);
    await tester.pumpAndSettle();
    expect(find.byType(MobileSwapScreen), findsOneWidget);

    await tester.tap(find.text('Add recipient address'));
    await tester.pumpAndSettle();
    expect(find.byType(SwapAddressEditModal), findsOneWidget);

    // The sheet rides the root navigator, so its scrim spans the whole
    // screen — including the status-bar strip at the very top that the old
    // inline overlay left uncovered.
    final screen = tester.getRect(find.byType(MaterialApp));
    final barrier = tester.getRect(find.byType(ModalBarrier).last);
    expect(barrier, screen);

    // The sheet stops below a top gap; a tap in that gap hits the scrim and
    // dismisses it.
    await tester.tapAt(const Offset(10, 10));
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

  testWidgets('contacts is a back-navigable view inside the same sheet', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Swap').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add recipient address'));
    await tester.pumpAndSettle();
    expect(find.byType(SwapAddressEditModal), findsOneWidget);
    // No back chevron on the base (editor) view.
    expect(find.byKey(const ValueKey('mobile_sheet_back_button')), findsNothing);

    // Open contacts → the same sheet swaps content: the editor is replaced
    // and a back chevron appears (no second overlapping sheet). The picker
    // watches the address book (which stays loading in-test), so pump a few
    // frames rather than settling.
    await tester.tap(
      find.byKey(const ValueKey('swap_address_contacts_button')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(SwapAddressEditModal), findsNothing);
    expect(
      find.byKey(const ValueKey('mobile_sheet_back_button')),
      findsOneWidget,
    );

    // Back chevron returns to the editor in the same sheet.
    await tester.tap(find.byKey(const ValueKey('mobile_sheet_back_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(SwapAddressEditModal), findsOneWidget);
    expect(find.byKey(const ValueKey('mobile_sheet_back_button')), findsNothing);
  });
}

Future<void> _setNarrowMobileViewport(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(432, 960));
  addTearDown(() async {
    await tester.binding.setSurfaceSize(null);
  });
}
