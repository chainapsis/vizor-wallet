@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/features/address_book/models/address_book_contact.dart';
import 'package:zcash_wallet/src/features/address_book/providers/address_book_provider.dart';
import 'package:zcash_wallet/src/features/send/screens/mobile/mobile_send_screen.dart';
import 'package:zcash_wallet/src/features/send/widgets/send_recipient_resolver.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/providers/zec_price_change_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart';
import 'package:zcash_wallet/src/rust/frb_generated.dart';

const _shieldedAddress =
    'u1testshieldedaddress00000000000000000000000000000000000000000000000';
const _transparentAddress = 't1transparentdestination0000000000000000000';
const _invalidAddress = 'not-an-address';

var _proposeSendSucceeds = false;

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
    // Real fee estimation crosses the FFI boundary and takes real time;
    // the timer keeps an in-flight validation window open so tests can
    // assert Continue stays blocked until the estimate lands.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return BigInt.from(10000);
  }

  @override
  Future<ProposalResult> crateApiSyncProposeSend({
    required String dbPath,
    required String network,
    required String accountUuid,
    required String sendFlowId,
    required String toAddress,
    required BigInt amountZatoshi,
    String? memo,
  }) async {
    if (!_proposeSendSucceeds) {
      throw StateError('proposal failed');
    }
    return ProposalResult(
      proposalId: BigInt.from(1),
      needsSaplingParams: false,
      feeZatoshi: BigInt.from(10000),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMarketDataSource implements ZecMarketDataSource {
  const _FakeMarketDataSource();

  @override
  Future<ZecMarketData?> fetchMarketData() async {
    return const ZecMarketData(usdPrice: 70);
  }
}

AppBootstrapState _bootstrap({AccountState? accountState}) => AppBootstrapState(
  initialLocation: '/send',
  initialAccountState:
      accountState ??
      const AccountState(
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

Widget _app({
  List<AddressBookContact> contacts = const [],
  AccountState? accountState,
  Map<String, AccountInfo> ownAccounts = const {},
  EdgeInsets viewPadding = EdgeInsets.zero,
  MobileSendScanner? openScanner,
}) {
  final router = GoRouter(
    initialLocation: '/send',
    routes: [
      GoRoute(
        path: '/send',
        builder: (_, _) => MobileSendScreen(
          loadWalletDbPath: () async => '/tmp/zcash-test',
          openScanner: openScanner ?? (_) async => null,
        ),
      ),
      GoRoute(path: '/home', builder: (_, _) => const Text('home')),
    ],
  );
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(
        _bootstrap(accountState: accountState),
      ),
      syncProvider.overrideWith(_FakeSyncNotifier.new),
      zecMarketDataSourceProvider.overrideWithValue(
        const _FakeMarketDataSource(),
      ),
      addressBookRepositoryProvider.overrideWithValue(
        _FakeAddressBookRepository(contacts),
      ),
      ownAccountAddressesProvider.overrideWith((ref) async => ownAccounts),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (context, c) {
        final mediaQuery = MediaQuery.of(
          context,
        ).copyWith(padding: viewPadding, viewPadding: viewPadding);
        return AppTheme(
          data: AppThemeData.light,
          child: MediaQuery(data: mediaQuery, child: c!),
        );
      },
    ),
  );
}

Widget _sendFlowRouterApp() {
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(
        path: '/home',
        builder: (context, _) => TextButton(
          key: const ValueKey('mobile_send_open_from_home'),
          onPressed: () => context.push('/send'),
          child: const Text('home'),
        ),
      ),
      GoRoute(
        path: '/send',
        builder: (_, _) => MobileSendScreen(
          loadWalletDbPath: () async => '/tmp/zcash-test',
          openScanner: (_) async => null,
        ),
      ),
      GoRoute(
        path: '/send/status',
        builder: (context, _) => TextButton(
          key: const ValueKey('mobile_send_status_pop'),
          onPressed: context.canPop() ? () => context.pop() : null,
          child: Text(
            context.canPop() ? 'status can pop' : 'status cannot pop',
          ),
        ),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap()),
      syncProvider.overrideWith(_FakeSyncNotifier.new),
      zecMarketDataSourceProvider.overrideWithValue(
        const _FakeMarketDataSource(),
      ),
      addressBookRepositoryProvider.overrideWithValue(
        _FakeAddressBookRepository(const []),
      ),
      ownAccountAddressesProvider.overrideWith((ref) async => const {}),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (context, c) => AppTheme(data: AppThemeData.light, child: c!),
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

Future<void> _enterAmount(WidgetTester tester, String amount) async {
  await tester.enterText(
    find.byKey(const ValueKey('mobile_send_amount_input')),
    amount,
  );
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
  await _enterAmount(tester, amount);
  await tester.tap(find.byKey(const ValueKey('mobile_send_review_button')));
  await tester.pumpAndSettle();
}

bool _sendRouteCanPop(WidgetTester tester) {
  final popScope = tester.widget<PopScope<void>>(find.byType(PopScope<void>));
  return popScope.canPop;
}

void main() {
  setUpAll(() {
    RustLib.initMock(api: _RustApiFake());
  });
  tearDownAll(RustLib.dispose);

  setUp(() {
    _proposeSendSucceeds = false;
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first
      ..physicalSize = const Size(520, 1100)
      ..devicePixelRatio = 1.0;
  });

  testWidgets('route pop is allowed only on the first recipient step', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.text('Select Recipient'), findsOneWidget);
    expect(_sendRouteCanPop(tester), isTrue);

    await _toAmountStep(tester, _shieldedAddress);
    expect(find.text('Enter amount'), findsOneWidget);
    expect(_sendRouteCanPop(tester), isFalse);

    await _enterAmount(tester, '1.5');
    await tester.tap(find.byKey(const ValueKey('mobile_send_review_button')));
    await tester.pumpAndSettle();

    expect(find.text('Review Send'), findsOneWidget);
    expect(_sendRouteCanPop(tester), isFalse);
  });

  testWidgets(
    'send status replaces the send route so completed status can pop',
    (tester) async {
      _proposeSendSucceeds = true;

      await tester.pumpWidget(_sendFlowRouterApp());
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('mobile_send_open_from_home')),
      );
      await tester.pumpAndSettle();

      await _toReviewStep(tester);
      await tester.tap(find.byKey(const ValueKey('mobile_send_confirm')));
      await tester.pumpAndSettle();

      expect(find.text('status can pop'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('mobile_send_status_pop')));
      await tester.pumpAndSettle();

      expect(find.text('home'), findsOneWidget);
      expect(find.text('Review Send'), findsNothing);
    },
  );

  testWidgets('recipient step gates Continue on a valid address', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.text('Select Recipient'), findsOneWidget);
    expect(find.text('Scan a QR Code'), findsOneWidget);
    // The unfocused empty state carries no Continue button.
    expect(find.byKey(const ValueKey('mobile_send_continue')), findsNothing);
    expect(find.text('Paste'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('mobile_send_address_field')));
    await tester.pumpAndSettle();
    expect(find.text('Paste'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile_send_recipient_focus_scrim')),
      findsOneWidget,
    );
    expect(find.text('Enter address to continue'), findsOneWidget);
    final focusedContinue = tester.widget<AppButton>(
      find.byKey(const ValueKey('mobile_send_continue')),
    );
    expect(focusedContinue.onPressed, isNull);

    await _enterAddress(tester, _invalidAddress);
    expect(find.text('Invalid address'), findsOneWidget);

    await _enterAddress(tester, _shieldedAddress);
    expect(find.text('Invalid address'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('mobile_send_continue')));
    await tester.pumpAndSettle();
    expect(find.text('Enter amount'), findsOneWidget);
  });

  testWidgets('scan result fills the recipient on the current send screen', (
    tester,
  ) async {
    var scannerOpenCount = 0;
    await tester.pumpWidget(
      _app(
        openScanner: (_) async {
          scannerOpenCount++;
          return _shieldedAddress;
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Scan a QR Code'));
    await tester.pumpAndSettle();

    expect(scannerOpenCount, 1);
    expect(find.text('Select Recipient'), findsOneWidget);
    expect(find.text('scanner'), findsNothing);
    final editable = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const ValueKey('mobile_send_address_field')),
        matching: find.byType(EditableText),
      ),
    );
    expect(editable.controller.text, _shieldedAddress);
    expect(find.text('Continue'), findsOneWidget);
  });

  testWidgets(
    'recipient focus keeps the address field mounted and stationary',
    (tester) async {
      await tester.pumpWidget(
        _app(viewPadding: const EdgeInsets.only(top: 55, bottom: 34)),
      );
      await tester.pumpAndSettle();

      final fieldFinder = find.byKey(
        const ValueKey('mobile_send_address_field'),
      );
      final inputFinder = find.descendant(
        of: fieldFinder,
        matching: find.byType(EditableText),
      );
      final rectBeforeFocus = tester.getRect(fieldFinder);
      expect(
        tester.widget<EditableText>(inputFinder).focusNode.hasFocus,
        isFalse,
      );

      await tester.tap(find.byKey(const ValueKey('mobile_send_address_field')));
      await tester.pumpAndSettle();

      expect(fieldFinder, findsOneWidget);
      expect(inputFinder, findsOneWidget);
      expect(
        tester.widget<EditableText>(inputFinder).focusNode.hasFocus,
        isTrue,
      );
      expect(tester.getRect(fieldFinder), rectBeforeFocus);
      expect(tester.getSize(fieldFinder).height, AppInputSizing.height);
      expect(
        find.byKey(const ValueKey('mobile_send_recipient_focus_address_layer')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('mobile_send_address_field_placeholder')),
        findsNothing,
      );

      final fieldRect = tester.getRect(fieldFinder);
      final scrimRect = tester.getRect(
        find.byKey(const ValueKey('mobile_send_recipient_focus_scrim')),
      );
      expect(scrimRect.top, greaterThanOrEqualTo(fieldRect.bottom));
    },
  );

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

  testWidgets('review resolves stored contact before matching own accounts', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        accountState: const AccountState(
          accounts: [
            AccountInfo(uuid: 'account-1', name: 'Account 1', order: 0),
            AccountInfo(
              uuid: 'account-2',
              name: 'Savings',
              order: 1,
              profilePictureId: 'pfp-02',
            ),
          ],
          activeAccountUuid: 'account-1',
          activeAddress: 'u1activeaddress',
        ),
        ownAccounts: const {
          _shieldedAddress: AccountInfo(
            uuid: 'account-2',
            name: 'Savings',
            order: 1,
            profilePictureId: 'pfp-02',
          ),
        },
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

    await _toReviewStep(tester);

    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Savings'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('mobile_send_full_address')));
    await tester.pumpAndSettle();
    expect(find.text('Alice'), findsWidgets);
  });

  testWidgets(
    'review resolves another wallet account when no contact matches',
    (tester) async {
      await tester.pumpWidget(
        _app(
          accountState: const AccountState(
            accounts: [
              AccountInfo(uuid: 'account-1', name: 'Account 1', order: 0),
              AccountInfo(
                uuid: 'account-2',
                name: 'Savings',
                order: 1,
                profilePictureId: 'pfp-02',
              ),
            ],
            activeAccountUuid: 'account-1',
            activeAddress: 'u1activeaddress',
          ),
          ownAccounts: const {
            _shieldedAddress: AccountInfo(
              uuid: 'account-2',
              name: 'Savings',
              order: 1,
              profilePictureId: 'pfp-02',
            ),
          },
        ),
      );
      await tester.pumpAndSettle();

      await _toReviewStep(tester);

      expect(find.text('Savings'), findsOneWidget);
      expect(find.text('Unified address'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('mobile_send_full_address')));
      await tester.pumpAndSettle();
      expect(find.text('Savings'), findsWidgets);
    },
  );

  testWidgets('the amount step enforces the spendable balance', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await _toAmountStep(tester, _shieldedAddress);

    expect(find.text('Enter amount to continue'), findsOneWidget);
    expect(find.textContaining('Max:'), findsOneWidget);
    final emptyAmountInput = tester.widget<TextField>(
      find.byKey(const ValueKey('mobile_send_amount_input')),
    );
    expect(emptyAmountInput.focusNode?.hasFocus, isTrue);
    expect(emptyAmountInput.decoration?.hintText, '0');
    expect(
      emptyAmountInput.keyboardType,
      const TextInputType.numberWithOptions(decimal: true),
    );
    expect(emptyAmountInput.cursorWidth, 3);
    expect(emptyAmountInput.cursorHeight, 48);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('mobile_send_amount_field')))
          .height,
      178,
    );
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey('mobile_send_amount_recipient_picture')),
          )
          .height,
      40,
    );
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey('mobile_send_amount_recipient_row')),
          )
          .height,
      68,
    );
    final maxText = tester.widget<Text>(find.textContaining('Max:'));
    expect(maxText.style?.fontSize, AppTypography.labelLarge.fontSize);
    expect(maxText.style?.height, AppTypography.labelLarge.height);

    await tester.tap(find.text('Sending to'));
    await tester.pumpAndSettle();
    final unfocusedAmountInput = tester.widget<TextField>(
      find.byKey(const ValueKey('mobile_send_amount_input')),
    );
    expect(unfocusedAmountInput.focusNode?.hasFocus, isFalse);

    // 9 ZEC > the 5 ZEC spendable fixture.
    await tester.tap(find.byKey(const ValueKey('mobile_send_amount_input')));
    await tester.pumpAndSettle();
    await _enterAmount(tester, '9');
    expect(find.text('Not enough ZEC'), findsOneWidget);
    final amountText = tester.widget<TextField>(
      find.byKey(const ValueKey('mobile_send_amount_input')),
    );
    expect(amountText.style?.fontSize, 48);
    expect(amountText.style?.height, 40 / 48);

    await _enterAmount(tester, '1.5');
    expect(find.text('Not enough ZEC'), findsNothing);
    expect(find.text('Finish & Review'), findsOneWidget);
  });

  testWidgets('continue stays blocked while the fee check is pending', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await _toAmountStep(tester, _shieldedAddress);

    // Settle a valid amount first, then change it and tap Continue on
    // the very next frame — while the fee re-validation is still in
    // flight. The previous amount's "valid" result must not let the
    // tap through.
    await _enterAmount(tester, '1');
    await tester.enterText(
      find.byKey(const ValueKey('mobile_send_amount_input')),
      '1.5',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('mobile_send_review_button')));
    await tester.pump();
    expect(find.text('Review Send'), findsNothing);

    // Once the re-validation settles, 1.5 ZEC is spendable again.
    await tester.pumpAndSettle();
    expect(find.text('Finish & Review'), findsOneWidget);
  });

  testWidgets('review shows the receipt and the shielded memo entry', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await _toReviewStep(tester);

    expect(find.text('Review Send'), findsOneWidget);
    expect(find.text(r'$105.00'), findsOneWidget);
    expect(find.text('Add short encrypted message'), findsOneWidget);
    expect(find.text('Tx fee'), findsOneWidget);
    expect(find.text('Confirm & Send'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('mobile_send_review_info'))),
      const Size(488, 268),
    );
    expect(
      tester.getSize(
        find.byKey(const ValueKey('mobile_send_review_recipient_picture')),
      ),
      const Size(40, 40),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('mobile_send_review_wrap'))),
      const Size(488, 161),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('mobile_send_review_buttons'))),
      const Size(488, 112),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('mobile_send_cancel'))).height,
      50,
    );
    final reviewAmount = tester.widget<Text>(
      find.byKey(const ValueKey('mobile_send_review_amount')),
    );
    expect(reviewAmount.style?.fontSize, AppTypography.headlineLarge.fontSize);
    expect(reviewAmount.style?.height, AppTypography.headlineLarge.height);
    expect(find.text('Unified address'), findsOneWidget);
    expect(find.text('u1tests .... 0000000'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('mobile_send_full_address'))),
      isA<Size>().having((size) => size.height, 'height', 24),
    );

    await tester.tap(find.byKey(const ValueKey('mobile_send_full_address')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('mobile_address_verify_chunks')),
      findsOneWidget,
    );
    expect(find.text('u1tes'), findsOneWidget);
    expect(find.text('Cancel'), findsWidgets);
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();

    // Memo round-trip through the sheet.
    await tester.tap(find.byKey(const ValueKey('mobile_send_memo_row')));
    await tester.pumpAndSettle();
    expect(find.text('Add Memo'), findsNWidgets(2)); // title + button
    expect(
      tester
          .getSize(find.byKey(const ValueKey('mobile_send_memo_text_area')))
          .height,
      222,
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('mobile_send_memo_field')))
          .height,
      148,
    );
    final memoFieldRect = tester.getRect(
      find.byKey(const ValueKey('mobile_send_memo_field')),
    );
    final memoEditableRect = tester.getRect(
      find.descendant(
        of: find.byKey(const ValueKey('mobile_send_memo_field')),
        matching: find.byType(EditableText),
      ),
    );
    expect(memoEditableRect.left - memoFieldRect.left, closeTo(13.5, 0.01));
    expect(
      tester
          .getSize(find.byKey(const ValueKey('mobile_send_memo_buttons')))
          .height,
      112,
    );
    expect(
      find.byKey(const ValueKey('mobile_send_memo_scrollbar')),
      findsNothing,
    );
    await tester.enterText(
      find.byKey(const ValueKey('mobile_send_memo_editable')),
      List.filled(12, 'thanks for testing the memo scrollbar').join('\n'),
    );
    await tester.pump();
    await tester.pump();
    expect(
      find.byKey(const ValueKey('mobile_send_memo_scrollbar')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('mobile_send_memo_scrollbar_thumb')),
      findsOneWidget,
    );
    final editable = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const ValueKey('mobile_send_memo_field')),
        matching: find.byType(EditableText),
      ),
    );
    final memoScrollController = editable.scrollController!;
    expect(memoScrollController.position.maxScrollExtent, greaterThan(0));
    final maxMemoScroll = memoScrollController.position.maxScrollExtent;
    memoScrollController.jumpTo(0);
    await tester.pump();
    await tester.tapAt(
      tester
          .getRect(find.byKey(const ValueKey('mobile_send_memo_field')))
          .centerRight
          .translate(-6, 0),
    );
    await tester.pumpAndSettle();
    expect(memoScrollController.offset, greaterThan(maxMemoScroll * 0.15));
    expect(memoScrollController.offset, lessThan(maxMemoScroll * 0.85));

    await tester.tapAt(
      tester
          .getRect(find.byKey(const ValueKey('mobile_send_memo_field')))
          .bottomRight
          .translate(-6, -12),
    );
    await tester.pumpAndSettle();
    expect(memoScrollController.offset, greaterThan(maxMemoScroll * 0.85));
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

    await tester.tap(find.byKey(const ValueKey('mobile_send_memo_row')));
    await tester.pumpAndSettle();
    expect(find.text('Add Memo'), findsOneWidget); // title only
    expect(find.text('Clear memo'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile_send_memo_clear')),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const ValueKey('mobile_send_memo_editable')),
      'updated thanks!',
    );
    await tester.pump();
    expect(find.text('Clear memo'), findsNothing);
    expect(find.text('Add Memo'), findsNWidgets(2)); // title + button
    await tester.tap(find.byKey(const ValueKey('mobile_send_memo_cancel')));
    await tester.pumpAndSettle();
    expect(find.text('thanks!'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('mobile_send_memo_row')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mobile_send_memo_clear')));
    await tester.pumpAndSettle();
    expect(find.text('Add short encrypted message'), findsOneWidget);
  });

  testWidgets('a transparent recipient hides the memo entry', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await _toReviewStep(tester, address: _transparentAddress);

    expect(find.text('Add short encrypted message'), findsNothing);
    expect(find.text('Transparent address'), findsOneWidget);
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
    expect(_sendRouteCanPop(tester), isFalse);
    await tester.tap(find.byKey(const ValueKey('mobile_send_try_again')));
    await tester.pumpAndSettle();
    expect(find.text('Review Send'), findsOneWidget);
  });
}
