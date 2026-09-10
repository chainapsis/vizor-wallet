@Tags(['mobile'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_profile_picture.dart';
import 'package:zcash_wallet/src/core/widgets/mobile/mobile_surface_card.dart';
import 'package:zcash_wallet/src/features/accounts/screens/hardware_account_details_screen.dart';
import 'package:zcash_wallet/src/features/ledger/ledger_capability.dart';
import 'package:zcash_wallet/src/features/onboarding/ledger/ledger_setup_args.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';

const _account = AccountInfo(
  uuid: 'layout-ledger',
  name: 'Long-term savings',
  order: 0,
  isHardware: true,
  hardwareSignerKind: HardwareSignerKind.ledger,
  ledgerWalletName: 'Family cold storage',
  ledgerWalletFingerprint:
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  ledgerDeviceId: 'layout-device',
  ledgerDeviceName: 'Ledger Flex',
  ledgerDeviceModel: 'Ledger Flex',
  zip32AccountIndex: 2147483647,
  birthdayHeight: 2870000,
);

void main() {
  setUpAll(() async {
    await (FontLoader('Geist')
          ..addFont(rootBundle.load('assets/fonts/Geist-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Geist-Medium.ttf')))
        .load();
    await (FontLoader(
      'Young Serif',
    )..addFont(rootBundle.load('assets/fonts/YoungSerif-Regular.ttf'))).load();
  });

  testWidgets('birthday loading and failure keep known values copyable', (
    tester,
  ) async {
    final birthday = Completer<int?>();
    await _pumpRecovery(tester, loadBirthday: () => birthday.future);
    expect(find.text('Loading…'), findsOneWidget);
    expect(find.byKey(const ValueKey('copy_Birthday date')), findsNothing);
    expect(find.byKey(const ValueKey('copy_Account index')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('copy_Birthday block height')),
      findsOneWidget,
    );
    birthday.completeError(StateError('offline'));
    await tester.pumpAndSettle();
    expect(find.text('Unavailable'), findsOneWidget);
    expect(find.text('Loading…'), findsNothing);
    expect(find.byKey(const ValueKey('copy_Birthday date')), findsNothing);
    expect(find.text('2147483647'), findsOneWidget);
    expect(find.text('2870000'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a verified Ledger account can add another index', (
    tester,
  ) async {
    Object? routeExtra;
    await _pumpRecovery(
      tester,
      loadBirthday: () async => null,
      onLedgerConnect: (extra) => routeExtra = extra,
    );
    await tester.pumpAndSettle();

    final button = find.byKey(
      const ValueKey('hardware_account_details_add_ledger_account'),
    );
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(find.text('ledger-connect-route'), findsOneWidget);
    expect(routeExtra, isA<LedgerConnectArgs>());
    expect(
      (routeExtra! as LedgerConnectArgs).sourceAccountUuid,
      'layout-ledger',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('an account without a wallet fingerprint cannot add an index', (
    tester,
  ) async {
    await _pumpRecovery(
      tester,
      account: const AccountInfo(
        uuid: 'layout-ledger',
        name: 'Hardware',
        order: 0,
        isHardware: true,
        hardwareSignerKind: HardwareSignerKind.ledger,
        zip32AccountIndex: 0,
      ),
      loadBirthday: () async => null,
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('hardware_account_details_add_ledger_account')),
      findsNothing,
    );
    expect(find.text('Add Ledger account'), findsNothing);
  });

  testWidgets('missing recovery values have no copy actions or date query', (
    tester,
  ) async {
    var requests = 0;
    await _pumpRecovery(
      tester,
      account: const AccountInfo(
        uuid: 'layout-ledger',
        name: 'Hardware',
        order: 0,
        isHardware: true,
        hardwareSignerKind: HardwareSignerKind.ledger,
      ),
      loadBirthday: () async {
        requests++;
        return null;
      },
    );
    await tester.pumpAndSettle();
    expect(find.text('Unavailable'), findsNWidgets(3));
    expect(find.byKey(const ValueKey('copy_Account index')), findsNothing);
    expect(find.byKey(const ValueKey('copy_Birthday date')), findsNothing);
    expect(
      find.byKey(const ValueKey('copy_Birthday block height')),
      findsNothing,
    );
    expect(requests, 0);
    expect(tester.takeException(), isNull);
  });

  for (final direction in TextDirection.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('Ledger details fit 320px at $scale scale in $direction', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 852);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              accountProvider.overrideWith(_PreviewAccounts.new),
              hardwareAccountBirthdayBlockTimeProvider.overrideWith(
                (ref, height) async => 1785196800,
              ),
              ledgerTargetPlatformProvider.overrideWithValue(
                TargetPlatform.iOS,
              ),
            ],
            child: MaterialApp(
              builder: (context, child) => AppTheme(
                data: AppThemeData.light,
                child: Directionality(
                  textDirection: direction,
                  child: MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.linear(scale)),
                    child: child!,
                  ),
                ),
              ),
              home: const MobileHardwareAccountDetailsScreen(
                accountUuid: 'layout-ledger',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Recovery info'), findsOneWidget);
        expect(find.text('Long-term savings'), findsNothing);
        expect(find.text('In Family cold storage'), findsNothing);
        expect(find.text('Ledger connection'), findsNothing);
        expect(find.byType(AppProfilePicture), findsNothing);
        expect(find.text('2147483647'), findsOneWidget);
        expect(find.text('2870000'), findsOneWidget);
        expect(find.text('July 28, 2026'), findsOneWidget);
        final card = find.byKey(
          const ValueKey('hardware_recovery_information_card'),
        );
        expect(tester.widget(card), isA<MobileSurfaceCard>());
        expect(
          tester
              .getRect(card)
              .contains(tester.getCenter(find.text('2147483647'))),
          isTrue,
        );
        expect(
          tester.getRect(card).contains(tester.getCenter(find.text('2870000'))),
          isTrue,
        );
        expect(
          find.byKey(const ValueKey('ledger_add_another_account_button')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }
}

class _PreviewAccounts extends AccountNotifier {
  _PreviewAccounts([this.account = _account]);

  final AccountInfo account;

  @override
  AccountState build() =>
      AccountState(accounts: [account], activeAccountUuid: 'layout-ledger');
}

Future<void> _pumpRecovery(
  WidgetTester tester, {
  required Future<int?> Function() loadBirthday,
  AccountInfo account = _account,
  ValueChanged<Object?>? onLedgerConnect,
}) async {
  tester.view.physicalSize = const Size(393, 852);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const MobileHardwareAccountDetailsScreen(
          accountUuid: 'layout-ledger',
        ),
      ),
      GoRoute(
        path: '/onboarding/ledger',
        builder: (_, state) {
          onLedgerConnect?.call(state.extra);
          return const Text('ledger-connect-route');
        },
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        accountProvider.overrideWith(() => _PreviewAccounts(account)),
        hardwareAccountBirthdayBlockTimeProvider.overrideWith(
          (ref, height) => loadBirthday(),
        ),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        builder: (_, child) =>
            AppTheme(data: AppThemeData.light, child: child!),
      ),
    ),
  );
  await tester.pump();
}
