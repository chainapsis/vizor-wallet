import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/profile_pictures.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/features/migration/providers/ironwood_migration_announcement_provider.dart';
import 'package:zcash_wallet/src/features/migration/providers/ironwood_migration_coordinator_provider.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/payment_link_gift_card.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

import '../../fakes/fake_sync_notifier.dart';

void main() {
  setUpAll(() async {
    final loader = FontLoader('Geist')
      ..addFont(rootBundle.load('assets/fonts/Geist-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Geist-Medium.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Geist-SemiBold.ttf'));
    await loader.load();
  });

  testWidgets('shows the truthful landing and help copy', (tester) async {
    await _pumpPaymentLinksScreen(tester);

    expect(
      find.byKey(const ValueKey('payment_links_desktop_screen')),
      findsOneWidget,
    );
    expect(find.text('No Gift Cards yet'), findsOneWidget);

    await tester.tap(find.text('How Gift Cards work'));
    await tester.pumpAndSettle();

    expect(find.textContaining('claim secret'), findsOneWidget);
    expect(
      find.textContaining('All data in the link is encrypted'),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey('payment_link_help_close_button')),
    );
    await tester.pumpAndSettle();

    expect(find.text('No Gift Cards yet'), findsOneWidget);
  });

  testWidgets('keeps the local wizard interactive but creation disabled', (
    tester,
  ) async {
    await _pumpPaymentLinksScreen(tester);

    await tester.tap(find.text('Create new card'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Gift card amount input'));
    await tester.enterText(
      find.byKey(const ValueKey('payment_link_amount_editor')),
      '1.25',
    );
    await tester.pump();

    expect(
      find.descendant(
        of: find.byType(PaymentLinkGiftCard),
        matching: find.text('1.25'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Create card'));
    await tester.pumpAndSettle();
    expect(find.text('Attach a message'), findsOneWidget);

    await tester.tap(find.text('Skip message'));
    await tester.pumpAndSettle();
    expect(find.text('Review your Gift Card'), findsOneWidget);
    expect(find.textContaining('Creating fee'), findsNothing);

    final confirmButton = tester.widget<AppButton>(
      find
          .ancestor(
            of: find.text('Confirm & create'),
            matching: find.byType(AppButton),
          )
          .first,
    );
    expect(confirmButton.onPressed, isNull);
  });

  testWidgets('keeps manual redeem intake disabled', (tester) async {
    await _pumpPaymentLinksScreen(tester);

    await tester.tap(find.text('Redeem a card'));
    await tester.pumpAndSettle();

    final pasteButton = tester.widget<AppButton>(
      find
          .ancestor(
            of: find.text('Paste card link'),
            matching: find.byType(AppButton),
          )
          .first,
    );
    expect(pasteButton.onPressed, isNull);
  });
}

Future<void> _pumpPaymentLinksScreen(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1080, 720));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appBootstrapProvider.overrideWithValue(_bootstrap),
        syncProvider.overrideWith(
          () => FakeSyncNotifier(
            SyncState(
              accountUuid: 'account-1',
              hasAccountScopedData: true,
              isSyncComplete: true,
              percentage: 1,
              displayPercentage: 1,
            ),
          ),
        ),
        ironwoodHomeMigrationCtaProvider.overrideWith((ref) async {
          return const IronwoodHomeMigrationCtaState.hidden();
        }),
        ironwoodHomeMigrationPresentationProvider.overrideWithValue(
          const IronwoodHomeMigrationCtaState.hidden(),
        ),
        ironwoodPostMigrationStateProvider.overrideWith((ref) async {
          return const IronwoodPostMigrationState.unavailable();
        }),
        ironwoodMigrationAnnouncementProvider.overrideWith((ref) async {
          return const IronwoodMigrationAnnouncementState.hidden();
        }),
        ironwoodMigrationCoordinatorProvider.overrideWith(
          _FakeMigrationCoordinator.new,
        ),
      ],
      child: const ZcashWalletApp(),
    ),
  );
  await tester.pumpAndSettle();
}

const _accountState = AccountState(
  accounts: [
    AccountInfo(
      uuid: 'account-1',
      name: 'Primary Vault',
      order: 0,
      profilePictureId: kDefaultProfilePictureId,
    ),
  ],
  activeAccountUuid: 'account-1',
  activeAddress: 'u1accountsaddress',
);

final _bootstrap = AppBootstrapState(
  initialLocation: '/payment-links',
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

class _FakeMigrationCoordinator extends IronwoodMigrationCoordinator {
  @override
  IronwoodMigrationCoordinatorState build() =>
      const IronwoodMigrationCoordinatorState();
}
