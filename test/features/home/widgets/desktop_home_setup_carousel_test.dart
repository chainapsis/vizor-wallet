import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_carousel.dart';
import 'package:zcash_wallet/src/features/home/providers/backup_reminder_provider.dart';
import 'package:zcash_wallet/src/features/home/widgets/desktop_home_setup_carousel.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';

const _pending = AccountInfo(
  uuid: 'a',
  name: 'First',
  order: 0,
  setupPending: true,
  giftEducationPending: true,
);

class _Accounts extends AccountNotifier {
  _Accounts(this.initial);
  final AccountState initial;
  @override
  AccountState build() => initial;
  void replace(AccountState next) => state = AsyncData(next);
}

class _Security extends AppSecurityNotifier {
  _Security(this.locked);
  final bool locked;
  @override
  AppSecurityState build() =>
      AppSecurityState(isPasswordConfigured: true, isUnlocked: !locked);
}

Widget _app(_Accounts accounts, {bool locked = false}) => ProviderScope(
  overrides: [
    appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
    accountProvider.overrideWith(() => accounts),
    appSecurityProvider.overrideWith(() => _Security(locked)),
    backupReminderClockProvider.overrideWithValue(
      () => DateTime.utc(2026, 10, 6),
    ),
  ],
  child: MaterialApp(
    home: AppTheme(
      data: AppThemeData.light,
      child: const Center(child: DesktopHomeSetupCarousel()),
    ),
  ),
);

void main() {
  final cases = [
    (name: 'backup and education', account: _pending, count: 2, backup: true),
    (
      name: 'ordinary backup only',
      account: _pending.copyWith(giftEducationPending: false),
      count: 1,
      backup: true,
    ),
    (
      name: 'completed backup with pending education',
      account: _pending.copyWith(setupPending: false),
      count: 1,
      backup: false,
    ),
    (
      name: 'snoozed backup with pending education',
      account: _pending.copyWith(
        backupReminderSnoozedUntilUtc: DateTime.utc(2026, 10, 8),
      ),
      count: 1,
      backup: false,
    ),
    (
      name: 'hardware education without software backup',
      account: const AccountInfo(
        uuid: 'a',
        name: 'Hardware',
        order: 0,
        isHardware: true,
        setupPending: true,
        giftEducationPending: true,
      ),
      count: 1,
      backup: false,
    ),
    (
      name: 'finished setup',
      account: _pending.copyWith(
        setupPending: false,
        giftEducationPending: false,
      ),
      count: 0,
      backup: false,
    ),
  ];
  for (final sample in cases) {
    testWidgets('Home shows only the remaining ${sample.name}', (tester) async {
      await tester.pumpWidget(
        _app(
          _Accounts(
            AccountState(accounts: [sample.account], activeAccountUuid: 'a'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (sample.count == 0) {
        expect(find.byType(AppCarousel), findsNothing);
      } else {
        final carousel = tester.widget<AppCarousel>(find.byType(AppCarousel));
        expect(carousel.items, hasLength(sample.count));
        expect(
          carousel.items.any((item) => item.message.startsWith('Back up')),
          sample.backup,
        );
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  testWidgets('locked and empty wallets expose no setup actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        _Accounts(
          const AccountState(accounts: [_pending], activeAccountUuid: 'a'),
        ),
        locked: true,
      ),
    );
    expect(find.byType(AppCarousel), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(_app(_Accounts(const AccountState())));
    expect(find.byType(AppCarousel), findsNothing);
  });
  testWidgets('switching accounts refreshes the remaining actions', (
    tester,
  ) async {
    final accounts = _Accounts(
      const AccountState(accounts: [_pending], activeAccountUuid: 'a'),
    );
    await tester.pumpWidget(_app(accounts));
    await tester.pumpAndSettle();
    accounts.replace(
      AccountState(
        accounts: [
          _pending,
          const AccountInfo(
            uuid: 'b',
            name: 'Second',
            order: 1,
            setupPending: false,
            giftEducationPending: false,
          ),
        ],
        activeAccountUuid: 'b',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AppCarousel), findsNothing);
    accounts.replace(
      const AccountState(accounts: [_pending], activeAccountUuid: 'a'),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<AppCarousel>(find.byType(AppCarousel)).items,
      hasLength(2),
    );
  });
}
