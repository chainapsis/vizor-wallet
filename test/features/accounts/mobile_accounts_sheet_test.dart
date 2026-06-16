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

AppBootstrapState _bootstrap() => AppBootstrapState(
  initialLocation: '/home',
  initialAccountState: _accounts,
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
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _app({
  required _FakeAccountNotifier accountNotifier,
  required _FakeReceiveAddressService addressService,
}) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap()),
      accountProvider.overrideWith(() => accountNotifier),
      syncProvider.overrideWith(() => FakeSyncNotifier(SyncState())),
      receiveAddressServiceProvider.overrideWithValue(addressService),
    ],
    child: MaterialApp(
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
    await tester.pumpAndSettle();

    expect(service.requested, ['account-2']);
    expect(copied, ['u1otheraddress']);
    expect(find.text('Address copied'), findsOneWidget);
  });
}
