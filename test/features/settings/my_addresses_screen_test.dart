import 'package:flutter/material.dart' show MaterialApp, Scaffold, ThemeMode;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/settings/screens/my_addresses_screen.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/address_list_provider.dart';
import 'package:zcash_wallet/src/providers/hidden_memos_provider.dart'
    show appSecureStoreProvider;
import 'package:zcash_wallet/src/rust/api/wallet.dart' as rust_wallet;

import '../../helpers/in_memory_secure_storage.dart';

// ---------------------------------------------------------------------------
// Fake repository
// ---------------------------------------------------------------------------

class _FakeAddressRepository implements AddressRepository {
  _FakeAddressRepository(this._addresses);
  final List<rust_wallet.AccountAddress> _addresses;

  @override
  Future<List<rust_wallet.AccountAddress>> list(String accountUuid) async =>
      _addresses;
}

// ---------------------------------------------------------------------------
// Canned addresses
// ---------------------------------------------------------------------------

const _addr1 = rust_wallet.AccountAddress(
  address:
      'u1abc123longunifiedaddressthatisatleasttwentycharacters000000000000000',
  isDefault: true,
);

const _addr2 = rust_wallet.AccountAddress(
  address:
      'u1def456longunifiedaddressthatisatleasttwentycharacters111111111111111',
  isDefault: false,
);

// ---------------------------------------------------------------------------
// Test bootstrap
// ---------------------------------------------------------------------------

final _bootstrap = AppBootstrapState(
  initialLocation: '/my-addresses-test',
  initialAccountState: const AccountState(
    accounts: [
      AccountInfo(
        uuid: 'test-account-uuid',
        name: 'Test Account',
        order: 0,
        isSeedAnchor: true,
      ),
    ],
    activeAccountUuid: 'test-account-uuid',
    activeAddress: 'u1testaddress',
  ),
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.system,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);

Widget _harness({required AddressRepository addressRepo}) {
  final store = AppSecureStore.testing(storage: InMemorySecureStorage());

  final router = GoRouter(
    initialLocation: '/my-addresses-test',
    routes: [
      GoRoute(
        path: '/my-addresses-test',
        builder: (context, state) =>
            const Scaffold(body: MyAddressesScreen()),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap),
      addressRepositoryProvider.overrideWithValue(addressRepo),
      appSecureStoreProvider.overrideWithValue(store),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (_, child) => AppTheme(data: AppThemeData.light, child: child!),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  testWidgets(
    'renders two address rows with unlabeled showing italic Unnamed',
    (tester) async {
      final repo = _FakeAddressRepository([_addr1, _addr2]);

      await tester.pumpWidget(_harness(addressRepo: repo));
      await tester.pump(); // provider resolves
      await tester.pump(); // frame

      // Both addresses render (truncated form)
      expect(find.text('u1abc123lo...0000000000'), findsOneWidget);
      expect(find.text('u1def456lo...1111111111'), findsOneWidget);

      // Both unlabeled addresses show "Unnamed" (italic is style, not text)
      expect(find.text('Unnamed'), findsNWidgets(2));
    },
  );

  testWidgets(
    'Rename action updates label and persists via addressLabelsProvider',
    (tester) async {
      final repo = _FakeAddressRepository([_addr1]);

      await tester.pumpWidget(_harness(addressRepo: repo));
      await tester.pump();
      await tester.pump();

      // Initially shows Unnamed
      expect(find.text('Unnamed'), findsOneWidget);
      expect(find.text('My UA'), findsNothing);

      // Tap Rename
      await tester.tap(find.text('Rename'));
      await tester.pump();

      // Enter new label in the editable text field
      await tester.enterText(find.byType(EditableText), 'My UA');
      await tester.pump();

      // Tap Save
      await tester.tap(find.text('Save'));
      await tester.pump();

      // Row now shows the new label
      expect(find.text('My UA'), findsOneWidget);
      expect(find.text('Unnamed'), findsNothing);
    },
  );

  testWidgets(
    'Cancel during rename reverts to previous state',
    (tester) async {
      final repo = _FakeAddressRepository([_addr1]);

      await tester.pumpWidget(_harness(addressRepo: repo));
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('Rename'));
      await tester.pump();

      await tester.enterText(find.byType(EditableText), 'Draft Label');
      await tester.pump();

      // Cancel without saving
      await tester.tap(find.text('Cancel'));
      await tester.pump();

      // Still unnamed
      expect(find.text('Unnamed'), findsOneWidget);
      expect(find.text('Draft Label'), findsNothing);
    },
  );
}
