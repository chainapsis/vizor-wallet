@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/address_book/models/address_book_contact.dart';
import 'package:zcash_wallet/src/features/address_book/providers/address_book_provider.dart';
import 'package:zcash_wallet/src/features/send/screens/mobile/mobile_send_screen.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart';
import 'package:zcash_wallet/src/rust/frb_generated.dart';

const _shieldedAddress =
    'u1testshieldedaddress00000000000000000000000000000000000000000000000';
const _transparentAddress = 't1transparentdestination0000000000000000000';
const _invalidAddress = 'not-an-address';

class _RustApiFake implements RustLibApi {
  @override
  Future<AddressValidationResult> crateApiSyncValidateAddress({
    required String address,
  }) async {
    if (address == _invalidAddress) {
      return const AddressValidationResult(isValid: false, addressType: '');
    }
    if (address.startsWith('t1')) {
      return const AddressValidationResult(
        isValid: true,
        addressType: 'transparent',
      );
    }
    return const AddressValidationResult(isValid: true, addressType: 'unified');
  }

  @override
  Future<BigInt> crateApiSyncEstimateFee({
    required String dbPath,
    required String network,
    required String accountUuid,
    required String toAddress,
    required BigInt amountZatoshi,
    String? memo,
  }) async {
    return BigInt.from(10000);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}


AppBootstrapState _bootstrap() => AppBootstrapState(
  initialLocation: '/send',
  initialAccountState: const AccountState(
    accounts: [AccountInfo(uuid: 'account-1', name: 'Account 1', order: 0)],
    activeAccountUuid: 'account-1',
    activeAddress: 'u1activeaddress',
  ),
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.light,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);

class _FakeSyncNotifier extends SyncNotifier {
  @override
  Future<SyncState> build() async => SyncState(
    accountUuid: 'account-1',
    hasAccountScopedData: true,
    spendableBalance: BigInt.from(500000000), // 5 ZEC
    totalBalance: BigInt.from(500000000),
  );
}

class _FakeAddressBookRepository implements AddressBookRepository {
  _FakeAddressBookRepository(this.contacts);

  final List<AddressBookContact> contacts;

  @override
  Future<List<AddressBookContact>> loadContacts() async => [...contacts];

  @override
  Future<void> saveContacts(List<AddressBookContact> contacts) async {}
}

Widget _app({List<AddressBookContact> contacts = const []}) {
  final router = GoRouter(
    initialLocation: '/send',
    routes: [
      GoRoute(
        path: '/send',
        builder: (_, _) =>
            MobileSendScreen(loadWalletDbPath: () async => '/tmp/zcash-test'),
      ),
      GoRoute(path: '/home', builder: (_, _) => const Text('home')),
      GoRoute(path: '/send/scan', builder: (_, _) => const Text('scanner')),
    ],
  );
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap()),
      syncProvider.overrideWith(_FakeSyncNotifier.new),
      addressBookRepositoryProvider.overrideWithValue(
        _FakeAddressBookRepository(contacts),
      ),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (_, c) => AppTheme(data: AppThemeData.light, child: c!),
    ),
  );
}

Future<void> _enterAddress(WidgetTester tester, String address) async {
  await tester.enterText(
    find.descendant(
      of: find.byKey(const ValueKey('mobile_send_address_field')),
      matching: find.byType(EditableText),
    ),
    address,
  );
  await tester.pumpAndSettle();
}

Future<void> _tapDigits(WidgetTester tester, String digits) async {
  for (final ch in digits.split('')) {
    final label = ch == '.' ? 'Decimal point' : 'Digit $ch';
    await tester.tap(find.bySemanticsLabel(label));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

Future<void> _toAmountStep(WidgetTester tester, String address) async {
  await _enterAddress(tester, address);
  await tester.tap(find.byKey(const ValueKey('mobile_send_continue')));
  await tester.pumpAndSettle();
}

Future<void> _toReviewStep(
  WidgetTester tester, {
  String address = _shieldedAddress,
  String amount = '1.5',
}) async {
  await _toAmountStep(tester, address);
  await _tapDigits(tester, amount);
  await tester.tap(find.byKey(const ValueKey('mobile_send_review_button')));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    RustLib.initMock(api: _RustApiFake());
  });
  tearDownAll(RustLib.dispose);

  setUp(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first
      ..physicalSize = const Size(520, 1100)
      ..devicePixelRatio = 1.0;
  });

  testWidgets('recipient step gates Continue on a valid address', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.text('Select Recipient'), findsOneWidget);
    expect(find.text('Scan a QR Code'), findsOneWidget);
    var button = tester.widget<GestureDetector>(
      find.ancestor(
        of: find.text('Continue'),
        matching: find.byType(GestureDetector),
      ).first,
    );

    await _enterAddress(tester, _invalidAddress);
    expect(find.text('Invalid address'), findsOneWidget);

    await _enterAddress(tester, _shieldedAddress);
    expect(find.text('Invalid address'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('mobile_send_continue')));
    await tester.pumpAndSettle();
    expect(find.text('Enter amount'), findsOneWidget);
    expect(button, isNotNull);
  });

  testWidgets('tapping a contact fills its address', (tester) async {
    await tester.pumpWidget(
      _app(
        contacts: const [
          AddressBookContact(
            id: 'alice',
            label: 'Alice',
            network: AddressBookNetwork.zcash,
            address: _shieldedAddress,
            profilePictureId: 'pfp-01',
            createdAtMs: 1,
            updatedAtMs: 1,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1 contact'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('mobile_send_contact_alice')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('mobile_send_continue')));
    await tester.pumpAndSettle();
    expect(find.text('Enter amount'), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);
  });

  testWidgets('the amount step enforces the spendable balance', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await _toAmountStep(tester, _shieldedAddress);

    expect(find.text('Enter amount to continue'), findsOneWidget);
    expect(find.textContaining('Max:'), findsOneWidget);

    // 9 ZEC > the 5 ZEC spendable fixture.
    await _tapDigits(tester, '9');
    expect(find.text('Not enough ZEC'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Delete digit'));
    await tester.pumpAndSettle();
    await _tapDigits(tester, '1.5');
    expect(find.text('Not enough ZEC'), findsNothing);
    expect(find.text('Finish & Review'), findsOneWidget);
  });

  testWidgets('review shows the receipt and the shielded memo entry', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await _toReviewStep(tester);

    expect(find.text('Review Send'), findsOneWidget);
    expect(find.text('Add short encrypted message'), findsOneWidget);
    expect(find.text('Tx fee'), findsOneWidget);
    expect(find.text('Confirm & Send'), findsOneWidget);

    // Memo round-trip through the sheet.
    await tester.tap(find.byKey(const ValueKey('mobile_send_memo_row')));
    await tester.pumpAndSettle();
    expect(find.text('Add Memo'), findsNWidgets(2)); // title + button
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('mobile_send_memo_field')),
        matching: find.byType(EditableText),
      ),
      'thanks!',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('mobile_send_memo_save')));
    await tester.pumpAndSettle();
    expect(find.text('Message'), findsOneWidget);
    expect(find.text('thanks!'), findsOneWidget);
  });

  testWidgets('a transparent recipient hides the memo entry', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await _toReviewStep(tester, address: _transparentAddress);

    expect(find.text('Add short encrypted message'), findsNothing);
    expect(find.text('Tx fee'), findsOneWidget);
  });

  testWidgets('a failing send lands on the failed status with retry', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await _toReviewStep(tester);

    // The fake Rust API has no proposeSend, so the propose step throws
    // and the wizard must surface the friendly failure.
    await tester.tap(find.byKey(const ValueKey('mobile_send_confirm')));
    await tester.pumpAndSettle();

    expect(find.text('Send failed'), findsNWidgets(2)); // nav title + headline
    await tester.tap(find.byKey(const ValueKey('mobile_send_try_again')));
    await tester.pumpAndSettle();
    expect(find.text('Review Send'), findsOneWidget);
  });
}
