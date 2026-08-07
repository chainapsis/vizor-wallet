@Tags(['mobile'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/passcode_widgets.dart';
import 'package:zcash_wallet/src/features/settings/screens/mobile/mobile_viewing_key_screen.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/providers/biometric_unlock_provider.dart';
import 'package:zcash_wallet/src/services/biometric_unlock.dart';

const _ufvk =
    'uview1qthqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq'
    'previewonly';

const _accountState = AccountState(
  accounts: [
    AccountInfo(uuid: 'account-1', name: 'Current', order: 0),
    AccountInfo(uuid: 'account-2', name: 'Other', order: 1),
    AccountInfo(
      uuid: 'account-3',
      name: 'Keystone',
      order: 2,
      isHardware: true,
    ),
  ],
  activeAccountUuid: 'account-1',
);

AppBootstrapState _bootstrap() => AppBootstrapState(
  initialLocation: '/settings/viewing-key',
  initialAccountState: _accountState,
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.light,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);

class _FakeSecurityNotifier extends AppSecurityNotifier {
  @override
  Future<bool> confirmPassword(String password) async => true;
}

class _FakeAccountNotifier extends AccountNotifier {
  _FakeAccountNotifier([this.initialState = _accountState]);

  final AccountState initialState;

  @override
  FutureOr<AccountState> build() => initialState;

  void setActiveAccount(String uuid) {
    state = AsyncData(state.requireValue.copyWith(activeAccountUuid: uuid));
  }

  void removeAccountLocally(String uuid) {
    state = AsyncData(
      state.requireValue.copyWith(
        accounts: state.requireValue.accounts
            .where((account) => account.uuid != uuid)
            .toList(),
      ),
    );
  }
}

class _FakeBiometricUnlock extends BiometricUnlock {
  @override
  Future<BiometricAvailability> availability() async =>
      BiometricAvailability.unavailable;
}

Widget _app({
  String? accountUuid,
  AccountNotifier Function()? accountNotifier,
  Future<String> Function(String accountUuid)? ufvkLoader,
}) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap()),
      accountProvider.overrideWith(accountNotifier ?? _FakeAccountNotifier.new),
      appSecurityProvider.overrideWith(_FakeSecurityNotifier.new),
      biometricUnlockServiceProvider.overrideWithValue(_FakeBiometricUnlock()),
    ],
    child: MaterialApp(
      builder: (_, child) => AppTheme(data: AppThemeData.light, child: child!),
      home: MobileViewingKeyScreen(
        accountUuid: accountUuid,
        ufvkLoader: ufvkLoader,
      ),
    ),
  );
}

Future<void> _confirmPasscode(WidgetTester tester) async {
  for (final digit in '111111'.split('')) {
    await tester.tap(find.bySemanticsLabel('Digit $digit'));
    await tester.pump();
  }
  await tester.pump();
}

void main() {
  setUp(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first
      ..physicalSize = const Size(520, 1100)
      ..devicePixelRatio = 1.0;
  });

  testWidgets('confirm gate uses the shared passcode layout', (tester) async {
    await tester.pumpWidget(_app(ufvkLoader: (uuid) async => _ufvk));
    await tester.pumpAndSettle();

    expect(find.text('Enter Passcode'), findsOneWidget);
    expect(find.text('Confirm your access'), findsOneWidget);
    expect(find.byType(PasscodeNumpad), findsOneWidget);
  });

  testWidgets(
    'reveals the requested account viewing key without making it active',
    (tester) async {
      final accountNotifier = _FakeAccountNotifier();
      final requestedUuids = <String>[];

      await tester.pumpWidget(
        _app(
          accountUuid: 'account-2',
          accountNotifier: () => accountNotifier,
          ufvkLoader: (uuid) async {
            requestedUuids.add(uuid);
            return _ufvk;
          },
        ),
      );
      await _confirmPasscode(tester);

      expect(requestedUuids, ['account-2']);
      expect(accountNotifier.state.requireValue.activeAccountUuid, 'account-1');
      expect(find.text('Full Viewing Key'), findsOneWidget);
      expect(find.text(_ufvk), findsOneWidget);
    },
  );

  testWidgets('reveals a hardware account viewing key', (tester) async {
    final requestedUuids = <String>[];

    await tester.pumpWidget(
      _app(
        accountUuid: 'account-3',
        ufvkLoader: (uuid) async {
          requestedUuids.add(uuid);
          return _ufvk;
        },
      ),
    );
    await _confirmPasscode(tester);

    expect(requestedUuids, ['account-3']);
    expect(find.text(_ufvk), findsOneWidget);
  });

  testWidgets('shows an error message when the key cannot be loaded', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        accountUuid: 'account-2',
        ufvkLoader: (uuid) async => throw StateError('boom'),
      ),
    );
    await _confirmPasscode(tester);

    expect(
      find.text('Viewing key is not available for this account.'),
      findsOneWidget,
    );
    expect(find.text(_ufvk), findsNothing);
  });

  testWidgets('reports when the target account is removed after reveal', (
    tester,
  ) async {
    final accountNotifier = _FakeAccountNotifier();

    await tester.pumpWidget(
      _app(
        accountUuid: 'account-2',
        accountNotifier: () => accountNotifier,
        ufvkLoader: (uuid) async => _ufvk,
      ),
    );
    await _confirmPasscode(tester);
    expect(find.text(_ufvk), findsOneWidget);

    accountNotifier.removeAccountLocally('account-2');
    await tester.pump();

    expect(
      find.text('Selected account changed. Enter your passcode again.'),
      findsOneWidget,
    );
    expect(find.text(_ufvk), findsNothing);
  });
}
