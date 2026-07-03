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
import 'package:zcash_wallet/src/core/widgets/app_toast.dart';
import 'package:zcash_wallet/src/features/accounts/widgets/mobile/mobile_accounts_sheet.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/receive_address_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

import '../../fakes/fake_sync_notifier.dart';
import 'package:zcash_wallet/l10n/app_localizations.dart';

const _accounts = AccountState(
  accounts: [
    AccountInfo(
      uuid: 'account-1',
      name: 'Account 1',
      order: 0,
      profilePictureId: kDefaultProfilePictureId,
    ),
    AccountInfo(
      uuid: 'account-2',
      name: 'Account 2',
      order: 1,
      profilePictureId: kDefaultProfilePictureId,
    ),
    AccountInfo(
      uuid: 'account-3',
      name: 'Account 3',
      order: 2,
      profilePictureId: kDefaultProfilePictureId,
    ),
  ],
  activeAccountUuid: 'account-1',
  activeAddress: 'u1activeaddress',
);

AccountState _manyAccounts() => AccountState(
  accounts: [
    for (var i = 1; i <= 7; i++)
      AccountInfo(
        uuid: 'account-$i',
        name: 'Account $i',
        order: i - 1,
        profilePictureId: kDefaultProfilePictureId,
      ),
  ],
  activeAccountUuid: 'account-1',
  activeAddress: 'u1activeaddress',
);

AppBootstrapState _bootstrap([AccountState accountState = _accounts]) =>
    AppBootstrapState(
      initialLocation: '/home',
      initialAccountState: accountState,
      initialSyncSnapshot: AppSyncSnapshot.empty,
      network: 'main',
      rpcEndpointConfig: defaultRpcEndpointConfig('main'),
      themeMode: ThemeMode.dark,
      privacyModeEnabled: false,
      isPasswordConfigured: true,
      isUnlocked: true,
      passwordRotationRecoveryFailed: false,
    );

class _FakeAccountNotifier extends AccountNotifier {
  final switched = <String>[];

  @override
  Future<void> switchAccount(String uuid) async {
    switched.add(uuid);
  }
}

class _FakeReceiveAddressService implements ReceiveAddressService {
  _FakeReceiveAddressService(this.address);

  final String address;
  final requested = <String>[];

  @override
  Future<String> loadShieldedAddress({
    required String accountUuid,
    String? currentShieldedAddress,
  }) async {
    requested.add(accountUuid);
    return currentShieldedAddress ?? address;
  }

  @override
  Future<String> loadTransparentReceiveAddress({
    required String accountUuid,
  }) async => address;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _app({
  required _FakeAccountNotifier accountNotifier,
  required _FakeReceiveAddressService addressService,
  AccountState accountState = _accounts,
}) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap(accountState)),
      accountProvider.overrideWith(() => accountNotifier),
      syncProvider.overrideWith(() => FakeSyncNotifier(SyncState())),
      receiveAddressServiceProvider.overrideWithValue(addressService),
    ],
    child: MaterialApp(
      localizationsDelegates:
          AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (_, child) => AppTheme(data: AppThemeData.dark, child: child!),
      home: AppToastHost(
        child: Builder(
          builder: (context) => Center(
            child: GestureDetector(
              onTap: () => showMobileAccountsSheet(context),
              child: const Text('open accounts'),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(find.text('open accounts'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lists the active account and the others', (tester) async {
    final notifier = _FakeAccountNotifier();
    await tester.pumpWidget(
      _app(
        accountNotifier: notifier,
        addressService: _FakeReceiveAddressService('u1other'),
      ),
    );
    await _openSheet(tester);

    expect(find.text('Account 1'), findsOneWidget);
    expect(find.text('Other accounts'), findsOneWidget);
    expect(find.text('Account 2'), findsOneWidget);
    expect(find.text('Account 3'), findsOneWidget);
    expect(find.text('Manage accounts'), findsOneWidget);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('mobile_accounts_manage')))
          .height,
      50,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('mobile_accounts_add'))).height,
      50,
    );
  });

  testWidgets('uses Figma row pitch and scrollbar for overflow accounts', (
    tester,
  ) async {
    final notifier = _FakeAccountNotifier();
    await tester.pumpWidget(
      _app(
        accountNotifier: notifier,
        addressService: _FakeReceiveAddressService('u1other'),
        accountState: _manyAccounts(),
      ),
    );
    await _openSheet(tester);
    await tester.pump(const Duration(milliseconds: 300));

    final listRect = tester.getRect(
      find.byKey(const ValueKey('mobile_accounts_sheet_list')),
    );
    final scrollbarRect = tester.getRect(
      find.byKey(const ValueKey('mobile_accounts_sheet_scrollbar')),
    );
    final scrollbar = tester.widget<RawScrollbar>(
      find.byKey(const ValueKey('mobile_accounts_sheet_scrollbar')),
    );
    final row2Rect = tester.getRect(
      find.byKey(const ValueKey('account_row_account-2')),
    );
    final row3Rect = tester.getRect(
      find.byKey(const ValueKey('account_row_account-3')),
    );
    final gutter = tester.widget<Padding>(
      find.byKey(const ValueKey('mobile_accounts_sheet_list_gutter')),
    );
    final list = tester.widget<ListView>(find.byType(ListView));
    final controller = list.controller!;
    final activeNameRect = tester.getRect(find.text('Account 1'));
    final sectionTitleRect = tester.getRect(find.text('Other accounts'));
    final rowLabel = tester.widget<Text>(find.text('Account 2'));

    expect(
      sectionTitleRect.top - activeNameRect.bottom,
      moreOrLessEquals(24, epsilon: 0.1),
    );
    expect(
      listRect.top - sectionTitleRect.bottom,
      moreOrLessEquals(20, epsilon: 0.1),
    );
    expect(listRect.height, 216);
    expect(scrollbar.thumbVisibility, isTrue);
    expect(scrollbar.interactive, isTrue);
    expect(scrollbar.thickness, 6);
    expect(scrollbar.mainAxisMargin, 0);
    expect(scrollbar.padding, EdgeInsets.zero);
    expect(scrollbar.crossAxisMargin, 6);
    expect(list.physics, isA<ClampingScrollPhysics>());
    expect(row2Rect.height, 48);
    expect(row3Rect.top - row2Rect.bottom, 8);
    expect((gutter.padding as EdgeInsets).right, 18);
    expect(rowLabel.style?.fontSize, 14);
    expect(rowLabel.style?.height, 16 / 14);
    expect(rowLabel.style?.fontWeight, FontWeight.w500);

    await tester.dragFrom(
      Offset(scrollbarRect.right - 9, scrollbarRect.top + 24),
      const Offset(0, 1000),
    );
    await tester.pump();

    expect(
      controller.position.pixels,
      moreOrLessEquals(controller.position.maxScrollExtent, epsilon: 0.1),
    );
  });

  testWidgets('tapping another account switches and closes the sheet', (
    tester,
  ) async {
    final notifier = _FakeAccountNotifier();
    await tester.pumpWidget(
      _app(
        accountNotifier: notifier,
        addressService: _FakeReceiveAddressService('u1other'),
      ),
    );
    await _openSheet(tester);

    await tester.tap(find.text('Account 2'));
    await tester.pumpAndSettle();

    expect(notifier.switched, ['account-2']);
    expect(find.text('Other accounts'), findsNothing);
  });

  testWidgets('copy loads the shielded address and confirms with a toast', (
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

    final notifier = _FakeAccountNotifier();
    final service = _FakeReceiveAddressService('u1otheraddress');
    await tester.pumpWidget(
      _app(accountNotifier: notifier, addressService: service),
    );
    await _openSheet(tester);

    await tester.tap(find.bySemanticsLabel('Copy shielded address').first);
    await tester.pump();

    expect(service.requested, ['account-2']);
    expect(copied, ['u1otheraddress']);
    expect(find.text('Address copied'), findsOneWidget);
    final widgets = tester.allWidgets.toList(growable: false);
    final toastIndex = widgets.indexWhere(
      (widget) => widget is AppToast && widget.message == 'Address copied',
    );
    final barrierIndex = widgets.lastIndexWhere(
      (widget) => widget is ModalBarrier,
    );
    expect(toastIndex, greaterThan(barrierIndex));

    await tester.pump(AppToast.defaultDuration);
    await tester.pump();
  });
}
