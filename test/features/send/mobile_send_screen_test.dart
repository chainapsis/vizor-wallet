@Tags(['mobile'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/formatting/zec_amount.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
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
const _texAddress = 'tex1s2rt77ggv6q989lr49rkgzmh5slsksa9khdgte';
const _invalidAddress = 'not-an-address';

var _proposeSendSucceeds = false;
Completer<ProposalResult>? _proposeSendCompleter;
int _estimateSendMaxCalls = 0;
String? _lastEstimateSendMaxToAddress;
String? _lastEstimateSendMaxMemo;
_SendMaxEstimateBuilder? _sendMaxEstimateBuilder;

typedef _SendMaxEstimateBuilder =
    SendMaxEstimateResult Function({required String toAddress, String? memo});

class _RustApiFake implements RustLibApi {
  @override
  Future<AddressValidationResult> crateApiSyncValidateAddress({
    required String address,
  }) async {
    if (address == _invalidAddress) {
      return const AddressValidationResult(isValid: false, addressType: '');
    }
    if (address.startsWith('tex')) {
      return const AddressValidationResult(isValid: true, addressType: 'tex');
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
  Future<SendMaxEstimateResult> crateApiSyncEstimateSendMax({
    required String dbPath,
    required String network,
    required String accountUuid,
    required String toAddress,
    String? memo,
  }) async {
    _estimateSendMaxCalls++;
    _lastEstimateSendMaxToAddress = toAddress;
    _lastEstimateSendMaxMemo = memo;
    final builder = _sendMaxEstimateBuilder;
    if (builder != null) {
      return builder(toAddress: toAddress, memo: memo);
    }
    return SendMaxEstimateResult(
      amountZatoshi: BigInt.from(499990000),
      feeZatoshi: BigInt.from(10000),
      needsSaplingParams: false,
    );
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
    final completer = _proposeSendCompleter;
    if (completer != null) return completer.future;
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
  String? initialRecipient,
  MobileSendAddressValidator? validateAddress,
}) {
  final router = GoRouter(
    initialLocation: '/send',
    routes: [
      GoRoute(
        path: '/send',
        builder: (_, _) => MobileSendScreen(
          loadWalletDbPath: () async => '/tmp/zcash-test',
          openScanner: openScanner ?? (_) async => null,
          initialRecipient: initialRecipient,
          validateAddress: validateAddress,
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

Widget _amountStepWithPriceLoadingApp() {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap()),
      syncProvider.overrideWith(_FakeSyncNotifier.new),
      zecHomeUsdUnitPriceProvider.overrideWithValue(null),
      addressBookRepositoryProvider.overrideWithValue(
        _FakeAddressBookRepository(const []),
      ),
      ownAccountAddressesProvider.overrideWith((ref) async => const {}),
    ],
    child: MaterialApp(
      home: AppTheme(
        data: AppThemeData.light,
        child: MobileSendScreen(
          loadWalletDbPath: () async => '/tmp/zcash-test',
          initialAmountStep: true,
          initialRecipient: _shieldedAddress,
          initialAddressType: 'unified',
        ),
      ),
    ),
  );
}

Widget _sendFlowRouterApp({MobileSendFeeEstimator? estimateFee}) {
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
          useRouteSteps: true,
          loadWalletDbPath: () async => '/tmp/zcash-test',
          openScanner: (_) async => null,
          estimateFee: estimateFee,
        ),
      ),
      GoRoute(
        path: '/send/amount',
        builder: (_, state) {
          final args = state.extra! as MobileSendAmountArgs;
          return MobileSendScreen(
            useRouteSteps: true,
            initialAmountStep: true,
            initialSendFlowId: args.sendFlowId,
            initialRecipient: args.recipient,
            initialAddressType: args.addressType,
            initialContactLabel: args.contactLabel,
            initialContactPictureId: args.contactPictureId,
            loadWalletDbPath: () async => '/tmp/zcash-test',
            openScanner: (_) async => null,
            estimateFee: estimateFee,
          );
        },
      ),
      GoRoute(
        path: '/send/review',
        builder: (_, state) {
          final args = state.extra! as MobileSendReviewDraftArgs;
          return MobileSendScreen(
            useRouteSteps: true,
            initialReview: true,
            initialAmountReady: true,
            initialSendFlowId: args.sendFlowId,
            initialRecipient: args.recipient,
            initialAddressType: args.addressType,
            initialAmount: args.amountText,
            initialFeeZatoshi: args.feeZatoshi,
            refreshReviewFeeOnInit: true,
            initialMaxMode: args.isMaxMode,
            initialMemo: args.memo,
            initialContactLabel: args.contactLabel,
            initialContactPictureId: args.contactPictureId,
            loadWalletDbPath: () async => '/tmp/zcash-test',
            openScanner: (_) async => null,
            estimateFee: estimateFee,
          );
        },
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

String _compactReviewAddress(String address) {
  final value = address.trim();
  if (value.length <= 18) return value;
  return '${value.substring(0, 7)} .... '
      '${value.substring(value.length - 7)}';
}

bool _sendRouteCanPop(WidgetTester tester) {
  final popScope = tester.widget<PopScope<void>>(find.byType(PopScope<void>));
  return popScope.canPop;
}

BoxDecoration _fieldDecoration(WidgetTester tester, Finder fieldFinder) {
  final containers = tester.widgetList<Container>(
    find.descendant(of: fieldFinder, matching: find.byType(Container)),
  );
  return containers
      .map((container) => container.decoration)
      .whereType<BoxDecoration>()
      .firstWhere(
        (decoration) =>
            decoration.borderRadius ==
            BorderRadius.circular(AppInputSizing.radius),
      );
}

ShapeDecoration _continueButtonDecoration(WidgetTester tester) {
  final containers = tester.widgetList<AnimatedContainer>(
    find.descendant(
      of: find.byKey(const ValueKey('mobile_send_continue')),
      matching: find.byType(AnimatedContainer),
    ),
  );
  return containers
      .map((container) => container.decoration)
      .whereType<ShapeDecoration>()
      .firstWhere((decoration) => decoration.shape is StadiumBorder);
}

void main() {
  setUpAll(() {
    RustLib.initMock(api: _RustApiFake());
  });
  tearDownAll(RustLib.dispose);

  setUp(() {
    _proposeSendSucceeds = false;
    _proposeSendCompleter = null;
    _estimateSendMaxCalls = 0;
    _lastEstimateSendMaxToAddress = null;
    _lastEstimateSendMaxMemo = null;
    _sendMaxEstimateBuilder = null;
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first
      ..physicalSize = const Size(520, 1100)
      ..devicePixelRatio = 1.0;
  });

  testWidgets('recipient step blocks a hardware account from a TEX address', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        accountState: const AccountState(
          accounts: [
            AccountInfo(
              uuid: 'account-1',
              name: 'Keystone',
              order: 0,
              isHardware: true,
            ),
          ],
          activeAccountUuid: 'account-1',
          activeAddress: 'u1activeaddress',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('mobile_send_address_field')));
    await tester.pumpAndSettle();
    await _enterAddress(tester, _texAddress);

    // Keystone cannot sign the TEX two-step, so the address step rejects it ...
    expect(
      find.text('Keystone does not support TEX sends yet.'),
      findsOneWidget,
    );
    // ... and Continue stays disabled.
    final continueButton = tester.widget<AppButton>(
      find.byKey(const ValueKey('mobile_send_continue')),
    );
    expect(continueButton.onPressed, isNull);
  });

  testWidgets('prefilled recipient waits for validation before Continue', (
    tester,
  ) async {
    final validation = Completer<AddressValidationResult>();

    await tester.pumpWidget(
      _app(
        initialRecipient: _texAddress,
        validateAddress: ({required address}) => validation.future,
        accountState: const AccountState(
          accounts: [
            AccountInfo(
              uuid: 'account-1',
              name: 'Keystone',
              order: 0,
              isHardware: true,
            ),
          ],
          activeAccountUuid: 'account-1',
          activeAddress: 'u1activeaddress',
        ),
      ),
    );
    await tester.pump();

    final pendingContinue = tester.widget<AppButton>(
      find.byKey(const ValueKey('mobile_send_continue')),
    );
    expect(pendingContinue.onPressed, isNull);

    await tester.tap(find.byKey(const ValueKey('mobile_send_continue')));
    await tester.pump();
    expect(find.text('Enter Amount'), findsNothing);

    validation.complete(
      const AddressValidationResult(isValid: true, addressType: 'tex'),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Keystone does not support TEX sends yet.'),
      findsOneWidget,
    );
    final blockedContinue = tester.widget<AppButton>(
      find.byKey(const ValueKey('mobile_send_continue')),
    );
    expect(blockedContinue.onPressed, isNull);
  });

  testWidgets('recipient step lets a software account send to a TEX address', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('mobile_send_address_field')));
    await tester.pumpAndSettle();
    await _enterAddress(tester, _texAddress);

    // Software wallets do TEX via the ZIP-320 two-step, so no block.
    expect(find.text('Keystone does not support TEX sends yet.'), findsNothing);
    final continueButton = tester.widget<AppButton>(
      find.byKey(const ValueKey('mobile_send_continue')),
    );
    expect(continueButton.onPressed, isNotNull);
  });

  testWidgets('route pop is allowed only on the first recipient step', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.text('Select Recipient'), findsOneWidget);
    expect(_sendRouteCanPop(tester), isTrue);

    await _toAmountStep(tester, _shieldedAddress);
    expect(find.text('Enter Amount'), findsOneWidget);
    expect(_sendRouteCanPop(tester), isFalse);

    await _enterAmount(tester, '1.5');
    await tester.tap(find.byKey(const ValueKey('mobile_send_review_button')));
    await tester.pumpAndSettle();

    expect(find.text('Review Send'), findsOneWidget);
    expect(_sendRouteCanPop(tester), isFalse);
  });

  testWidgets('route-step mode lets amount and review pop as pages', (
    tester,
  ) async {
    await tester.pumpWidget(_sendFlowRouterApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('mobile_send_open_from_home')));
    await tester.pumpAndSettle();

    await _toAmountStep(tester, _shieldedAddress);
    expect(find.text('Enter Amount'), findsOneWidget);
    expect(_sendRouteCanPop(tester), isTrue);

    await _enterAmount(tester, '1.5');
    await tester.tap(find.byKey(const ValueKey('mobile_send_review_button')));
    await tester.pumpAndSettle();

    expect(find.text('Review Send'), findsOneWidget);
    expect(_sendRouteCanPop(tester), isTrue);

    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Enter Amount'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Select Recipient'), findsOneWidget);
  });

  testWidgets('route-step review refreshes the fee on entry', (tester) async {
    var feeCalls = 0;
    final refreshedFee = BigInt.from(30000);

    await tester.pumpWidget(
      _sendFlowRouterApp(
        estimateFee:
            ({
              required dbPath,
              required network,
              required accountUuid,
              required toAddress,
              required amountZatoshi,
              memo,
            }) async {
              feeCalls++;
              return feeCalls == 1 ? BigInt.from(10000) : refreshedFee;
            },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('mobile_send_open_from_home')));
    await tester.pumpAndSettle();

    await _toAmountStep(tester, _shieldedAddress);
    await _enterAmount(tester, '1.5');
    expect(feeCalls, 1);

    await tester.tap(find.byKey(const ValueKey('mobile_send_review_button')));
    await tester.pumpAndSettle();

    expect(find.text('Review Send'), findsOneWidget);
    expect(feeCalls, greaterThanOrEqualTo(2));
    final feeText = tester.widget<Text>(
      find.byKey(const ValueKey('mobile_send_fee')),
    );
    expect(feeText.data, ZecAmount.fromZatoshi(refreshedFee).fee.toString());
  });

  testWidgets('route-step send status clears intermediate send pages', (
    tester,
  ) async {
    _proposeSendSucceeds = true;

    await tester.pumpWidget(_sendFlowRouterApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('mobile_send_open_from_home')));
    await tester.pumpAndSettle();

    await _toReviewStep(tester);
    await tester.tap(find.byKey(const ValueKey('mobile_send_confirm')));
    await tester.pumpAndSettle();

    expect(find.text('status can pop'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('mobile_send_status_pop')));
    await tester.pumpAndSettle();

    expect(find.text('home'), findsOneWidget);
    expect(find.text('Review Send'), findsNothing);
  });

  testWidgets('route-step review ignores back while preparing send', (
    tester,
  ) async {
    final proposalCompleter = Completer<ProposalResult>();
    _proposeSendCompleter = proposalCompleter;
    addTearDown(() {
      if (!proposalCompleter.isCompleted) {
        proposalCompleter.completeError(StateError('test ended'));
      }
      _proposeSendCompleter = null;
    });

    await tester.pumpWidget(_sendFlowRouterApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('mobile_send_open_from_home')));
    await tester.pumpAndSettle();

    await _toReviewStep(tester);
    await tester.tap(find.byKey(const ValueKey('mobile_send_confirm')));
    await tester.pump();

    expect(find.text('Preparing...'), findsOneWidget);
    expect(find.bySemanticsLabel('Back'), findsNothing);
    expect(_sendRouteCanPop(tester), isFalse);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('Review Send'), findsOneWidget);
    expect(find.text('Preparing...'), findsOneWidget);

    proposalCompleter.complete(
      ProposalResult(
        proposalId: BigInt.from(1),
        needsSaplingParams: false,
        feeZatoshi: BigInt.from(10000),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('status can pop'), findsOneWidget);
  });

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
    expect(find.text('Enter Amount'), findsOneWidget);
  });

  testWidgets('recipient step names a matched saved contact', (tester) async {
    await tester.pumpWidget(
      _app(
        contacts: const [
          AddressBookContact(
            id: 'alice',
            label: 'Alice',
            network: AddressBookNetwork.zcash,
            address: _shieldedAddress,
            profilePictureId: 'default',
            createdAtMs: 0,
            updatedAtMs: 0,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('mobile_send_address_field')));
    await tester.pumpAndSettle();

    await _enterAddress(tester, _invalidAddress);
    // The error owns the reserved line; no match indicator alongside it.
    expect(find.text('Invalid address'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile_send_address_contact_match')),
      findsNothing,
    );

    await _enterAddress(tester, _shieldedAddress);
    expect(find.text('Invalid address'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('mobile_send_address_contact_match')),
        matching: find.text('Alice'),
      ),
      findsOneWidget,
    );
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
      final fieldLayerFinder = find.byKey(
        const ValueKey('mobile_send_recipient_field_layer'),
      );
      final groupFinder = find.byKey(
        const ValueKey('mobile_send_address_field_group'),
      );
      final scanRowFinder = find.byKey(const ValueKey('mobile_send_scan_row'));
      final inputFinder = find.descendant(
        of: fieldFinder,
        matching: find.byType(EditableText),
      );
      final fieldLayerElementBeforeFocus = tester.element(fieldLayerFinder);
      final inputElementBeforeFocus = tester.element(inputFinder);
      final rectBeforeFocus = tester.getRect(fieldFinder);
      final groupRectBeforeFocus = tester.getRect(groupFinder);
      final scanRowRectBeforeFocus = tester.getRect(scanRowFinder);
      expect(
        tester.widget<EditableText>(inputFinder).focusNode.hasFocus,
        isFalse,
      );

      await tester.tap(find.byKey(const ValueKey('mobile_send_address_field')));
      await tester.pumpAndSettle();

      expect(fieldFinder, findsOneWidget);
      expect(inputFinder, findsOneWidget);
      expect(
        tester.element(fieldLayerFinder),
        same(fieldLayerElementBeforeFocus),
      );
      expect(tester.element(inputFinder), same(inputElementBeforeFocus));
      expect(
        tester.widget<EditableText>(inputFinder).focusNode.hasFocus,
        isTrue,
      );
      final focusedDecoration = _fieldDecoration(tester, fieldFinder);
      final focusedBorder = focusedDecoration.border as Border;
      expect(focusedBorder.top.color, const Color(0x00000000));
      final focusedShadow = focusedDecoration.boxShadow!.single;
      expect(
        focusedShadow.color,
        AppThemeData.light.colors.background.neutralScrim,
      );
      expect(focusedShadow.offset, const Offset(0, 4));
      expect(focusedShadow.blurRadius, 4);
      expect(focusedShadow.spreadRadius, 1000);
      expect(tester.getRect(fieldFinder), rectBeforeFocus);
      expect(tester.getRect(groupFinder), groupRectBeforeFocus);
      expect(tester.getRect(scanRowFinder), scanRowRectBeforeFocus);
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
      expect(scrimRect, Offset.zero & const Size(520, 1100));
      expect(scrimRect.top, lessThan(fieldRect.top));
      expect(scrimRect.bottom, greaterThan(fieldRect.bottom));
    },
  );

  testWidgets('recipient focus applies backdrop-only Continue colors', (
    tester,
  ) async {
    final colors = AppThemeData.light.colors;
    final fieldFinder = find.byKey(const ValueKey('mobile_send_address_field'));
    final scrimFinder = find.byKey(
      const ValueKey('mobile_send_recipient_focus_scrim'),
    );

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(fieldFinder);
    await tester.pumpAndSettle();

    var decoration = _continueButtonDecoration(tester);
    expect(
      decoration.color,
      Color.alphaBlend(colors.button.disabled.bg, colors.surface.input.primary),
    );

    await _enterAddress(tester, _invalidAddress);
    await tester.tap(scrimFinder);
    await tester.pumpAndSettle();

    decoration = _continueButtonDecoration(tester);
    expect(decoration.color, colors.button.disabled.bg);

    await tester.tap(fieldFinder);
    await tester.pumpAndSettle();
    await _enterAddress(tester, _shieldedAddress);

    decoration = _continueButtonDecoration(tester);
    final focusedEnabledBorder = decoration.shape as StadiumBorder;
    expect(decoration.color, colors.button.primary.bg);
    expect(focusedEnabledBorder.side.color, colors.border.subtleOpacity);
    expect(focusedEnabledBorder.side.width, 1.5);

    await tester.tap(scrimFinder);
    await tester.pumpAndSettle();

    decoration = _continueButtonDecoration(tester);
    final normalEnabledBorder = decoration.shape as StadiumBorder;
    expect(decoration.color, colors.button.primary.bg);
    expect(normalEnabledBorder.side.color, colors.button.primary.border);
    expect(normalEnabledBorder.side.width, 1.5);
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
    expect(find.text('Enter Amount'), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);
  });

  testWidgets('review marks a TEX contact distinctly from transparent', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        contacts: const [
          AddressBookContact(
            id: 'alice',
            label: 'Alice',
            network: AddressBookNetwork.zcash,
            address: _texAddress,
            profilePictureId: 'pfp-01',
            createdAtMs: 1,
            updatedAtMs: 1,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await _toReviewStep(tester, address: _texAddress);

    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('TEX - ${_compactReviewAddress(_texAddress)}'), findsOne);
    expect(find.text('Transparent address'), findsNothing);
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

  testWidgets('amount step shows animated price loading placeholder', (
    tester,
  ) async {
    await tester.pumpWidget(_amountStepWithPriceLoadingApp());
    await tester.pump();
    await tester.pump();

    final loadingFinder = find.byKey(
      const ValueKey('mobile_send_amount_price_loading'),
    );
    expect(loadingFinder, findsOneWidget);
    expect(tester.getSize(loadingFinder), const Size(48, 12));
    expect(
      find.descendant(
        of: loadingFinder,
        matching: find.byType(AnimatedBuilder),
      ),
      findsOneWidget,
    );

    await tester.pump(const Duration(milliseconds: 600));
    expect(loadingFinder, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the amount step enforces the spendable balance', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await _toAmountStep(tester, _shieldedAddress);

    expect(find.text('Enter amount to continue'), findsOneWidget);
    expect(find.text('Max'), findsOneWidget);
    final emptyAmountInput = tester.widget<TextField>(
      find.byKey(const ValueKey('mobile_send_amount_input')),
    );
    expect(emptyAmountInput.focusNode?.hasFocus, isTrue);
    expect(emptyAmountInput.decoration?.hintText, isNull);
    final zecHintPadding = emptyAmountInput.decoration?.hint as Padding?;
    expect(zecHintPadding, isA<Padding>());
    expect(zecHintPadding!.padding, const EdgeInsetsDirectional.only(end: 3.7));
    final zecHintText = zecHintPadding.child as Text?;
    expect(zecHintText, isA<Text>());
    expect(zecHintText!.data, '0');
    expect(zecHintText.textAlign, TextAlign.right);
    expect(
      emptyAmountInput.keyboardType,
      const TextInputType.numberWithOptions(decimal: true),
    );
    expect(emptyAmountInput.showCursor, isFalse);
    expect(
      find.byKey(const ValueKey('mobile_send_amount_empty_cursor')),
      findsOneWidget,
    );
    expect(emptyAmountInput.cursorColor, AppThemeData.light.colors.text.accent);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('mobile_send_amount_field')))
          .height,
      164,
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
    final maxText = tester.widget<Text>(find.text('Max'));
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
    expect(find.text('Enter amount to continue'), findsNothing);
    final amountText = tester.widget<TextField>(
      find.byKey(const ValueKey('mobile_send_amount_input')),
    );
    expect(amountText.style?.fontSize, 48);
    expect(amountText.style?.height, 40 / 48);
    expect(amountText.showCursor, isTrue);
    expect(
      find.byKey(const ValueKey('mobile_send_amount_empty_cursor')),
      findsNothing,
    );
    final zecUnitText = tester.widget<Text>(find.text('ZEC'));
    expect(
      zecUnitText.style?.color,
      AppThemeData.light.colors.text.destructive.withValues(alpha: 0.5),
    );

    await _enterAmount(tester, '1.5');
    expect(find.text('Not enough ZEC'), findsNothing);
    expect(find.text('Finish & review'), findsOneWidget);
  });

  testWidgets('the amount step Max action fills the estimated send amount', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await _toAmountStep(tester, _shieldedAddress);

    await tester.tap(find.byKey(const ValueKey('mobile_send_max_button')));
    await tester.pumpAndSettle();

    expect(_estimateSendMaxCalls, 1);
    expect(_lastEstimateSendMaxToAddress, _shieldedAddress);
    expect(_lastEstimateSendMaxMemo, isNull);
    final amountInput = tester.widget<TextField>(
      find.byKey(const ValueKey('mobile_send_amount_input')),
    );
    expect(amountInput.controller?.text, '4.9999');
    expect(find.text('Finish & review'), findsOneWidget);
  });

  testWidgets('Max estimate failure is shown through the disabled CTA', (
    tester,
  ) async {
    _sendMaxEstimateBuilder = ({required toAddress, memo}) {
      throw StateError('estimate unavailable');
    };

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await _toAmountStep(tester, _shieldedAddress);

    await tester.tap(find.byKey(const ValueKey('mobile_send_max_button')));
    await tester.pumpAndSettle();

    expect(_estimateSendMaxCalls, 1);
    expect(find.text('Max amount unavailable'), findsOneWidget);
    expect(find.text('Not enough ZEC'), findsNothing);
  });

  testWidgets('Max insufficient balance is shown through the disabled CTA', (
    tester,
  ) async {
    _sendMaxEstimateBuilder = ({required toAddress, memo}) =>
        SendMaxEstimateResult(
          amountZatoshi: BigInt.zero,
          feeZatoshi: BigInt.zero,
          needsSaplingParams: false,
        );

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await _toAmountStep(tester, _shieldedAddress);

    await tester.tap(find.byKey(const ValueKey('mobile_send_max_button')));
    await tester.pumpAndSettle();

    expect(_estimateSendMaxCalls, 1);
    expect(find.text('Not enough ZEC'), findsOneWidget);
    expect(find.text('Enter amount to continue'), findsNothing);
  });

  testWidgets('USD input derives the canonical ZEC amount for review', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await _toAmountStep(tester, _shieldedAddress);
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('mobile_send_amount_mode_toggle')),
    );
    await tester.pumpAndSettle();

    final usdInput = tester.widget<TextField>(
      find.byKey(const ValueKey('mobile_send_amount_input')),
    );
    expect(usdInput.decoration?.hintText, '0');
    expect(usdInput.showCursor, isTrue);
    expect(
      find.byKey(const ValueKey('mobile_send_amount_empty_cursor')),
      findsNothing,
    );

    await tester.enterText(
      find.byKey(const ValueKey('mobile_send_amount_input')),
      '105',
    );
    await tester.pumpAndSettle();

    expect(find.text('1.5 ZEC'), findsOneWidget);
    expect(find.text('Finish & review'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('mobile_send_review_button')));
    await tester.pumpAndSettle();

    expect(find.text('Review Send'), findsOneWidget);
    expect(find.text('1.50 ZEC'), findsOneWidget);
  });

  testWidgets('USD mode clears ZEC amounts that round to zero cents', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await _toAmountStep(tester, _shieldedAddress);

    await _enterAmount(tester, '0.00000001');
    expect(find.text('Finish & review'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('mobile_send_amount_mode_toggle')),
    );
    await tester.pumpAndSettle();

    final amountInput = tester.widget<TextField>(
      find.byKey(const ValueKey('mobile_send_amount_input')),
    );
    expect(amountInput.controller?.text, isEmpty);
    expect(find.text('0 ZEC'), findsOneWidget);
    expect(find.text('Finish & review'), findsNothing);
    expect(find.text('Enter amount to continue'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('mobile_send_review_button')));
    await tester.pumpAndSettle();
    expect(find.text('Review Send'), findsNothing);
  });

  testWidgets(
    'USD input error applies destructive color to the dollar prefix',
    (tester) async {
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();
      await _toAmountStep(tester, _shieldedAddress);
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('mobile_send_amount_mode_toggle')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('mobile_send_amount_input')),
        '400',
      );
      await tester.pumpAndSettle();

      expect(find.text('Not enough ZEC'), findsOneWidget);
      expect(find.text('Enter amount to continue'), findsNothing);
      final dollarPrefix = tester.widget<Text>(find.text(r'$'));
      expect(
        dollarPrefix.style?.color,
        AppThemeData.light.colors.text.destructive.withValues(alpha: 0.5),
      );
    },
  );

  testWidgets('Max in USD mode keeps USD mode and syncs the display amount', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await _toAmountStep(tester, _shieldedAddress);
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('mobile_send_amount_mode_toggle')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mobile_send_max_button')));
    await tester.pumpAndSettle();

    expect(_estimateSendMaxCalls, 1);
    final amountInput = tester.widget<TextField>(
      find.byKey(const ValueKey('mobile_send_amount_input')),
    );
    expect(amountInput.decoration?.hintText, '0');
    expect(amountInput.controller?.text, '349.99');
    expect(find.text('4.9999 ZEC'), findsOneWidget);
    expect(find.text('Finish & review'), findsOneWidget);
  });

  testWidgets('Max in USD mode does not leave a hidden sub-cent amount', (
    tester,
  ) async {
    _sendMaxEstimateBuilder = ({required toAddress, memo}) =>
        SendMaxEstimateResult(
          amountZatoshi: BigInt.one,
          feeZatoshi: BigInt.from(10000),
          needsSaplingParams: false,
        );

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await _toAmountStep(tester, _shieldedAddress);

    await tester.tap(
      find.byKey(const ValueKey('mobile_send_amount_mode_toggle')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mobile_send_max_button')));
    await tester.pumpAndSettle();

    expect(_estimateSendMaxCalls, 1);
    final amountInput = tester.widget<TextField>(
      find.byKey(const ValueKey('mobile_send_amount_input')),
    );
    expect(amountInput.controller?.text, isEmpty);
    expect(find.text('0 ZEC'), findsOneWidget);
    expect(find.text('Finish & review'), findsNothing);
    expect(find.text('Enter amount to continue'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('mobile_send_review_button')));
    await tester.pumpAndSettle();
    expect(find.text('Review Send'), findsNothing);
  });

  testWidgets('Max ignores a stale pending amount fee validation', (
    tester,
  ) async {
    final feeCompleter = Completer<BigInt>();
    var feeCalls = 0;

    await tester.pumpWidget(
      _sendFlowRouterApp(
        estimateFee:
            ({
              required dbPath,
              required network,
              required accountUuid,
              required toAddress,
              required amountZatoshi,
              memo,
            }) {
              feeCalls++;
              return feeCompleter.future;
            },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('mobile_send_open_from_home')));
    await tester.pumpAndSettle();
    await _toAmountStep(tester, _shieldedAddress);

    await tester.enterText(
      find.byKey(const ValueKey('mobile_send_amount_input')),
      '1.5',
    );
    await tester.pump();
    expect(feeCalls, 1);

    await tester.tap(find.byKey(const ValueKey('mobile_send_max_button')));
    await tester.pumpAndSettle();
    expect(find.text('Finish & review'), findsOneWidget);

    feeCompleter.complete(BigInt.from(12345));
    await tester.pumpAndSettle();

    final amountInput = tester.widget<TextField>(
      find.byKey(const ValueKey('mobile_send_amount_input')),
    );
    expect(amountInput.controller?.text, '4.9999');
    expect(find.text('Finish & review'), findsOneWidget);
  });

  testWidgets(
    'the amount step Max action omits memo for transparent recipients',
    (tester) async {
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();
      await _toAmountStep(tester, _transparentAddress);

      await tester.tap(find.byKey(const ValueKey('mobile_send_max_button')));
      await tester.pumpAndSettle();

      expect(_estimateSendMaxCalls, 1);
      expect(_lastEstimateSendMaxToAddress, _transparentAddress);
      expect(_lastEstimateSendMaxMemo, isNull);
      expect(find.text('Finish & review'), findsOneWidget);
    },
  );

  testWidgets('route-step max mode recalculates amount when memo changes', (
    tester,
  ) async {
    _sendMaxEstimateBuilder = ({required toAddress, memo}) =>
        SendMaxEstimateResult(
          amountZatoshi: memo == 'thanks!'
              ? BigInt.from(499980000)
              : BigInt.from(499990000),
          feeZatoshi: memo == 'thanks!'
              ? BigInt.from(20000)
              : BigInt.from(10000),
          needsSaplingParams: false,
        );

    await tester.pumpWidget(_sendFlowRouterApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('mobile_send_open_from_home')));
    await tester.pumpAndSettle();
    await _toAmountStep(tester, _shieldedAddress);
    await tester.tap(find.byKey(const ValueKey('mobile_send_max_button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('mobile_send_review_button')));
    await tester.pumpAndSettle();

    expect(find.text('Review Send'), findsOneWidget);
    expect(find.text('4.9999 ZEC'), findsOneWidget);
    expect(
      find.text(ZecAmount.fromZatoshi(BigInt.from(10000)).fee.toString()),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('mobile_send_memo_row')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('mobile_send_memo_editable')),
      'thanks!',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('mobile_send_memo_save')));
    await tester.pumpAndSettle();

    expect(_lastEstimateSendMaxMemo, 'thanks!');
    expect(find.text('4.9998 ZEC'), findsOneWidget);
    final feeText = tester.widget<Text>(
      find.byKey(const ValueKey('mobile_send_fee')),
    );
    expect(
      feeText.data,
      ZecAmount.fromZatoshi(BigInt.from(20000)).fee.toString(),
    );
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
    expect(find.text('Finish & review'), findsOneWidget);
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
    // M4b: a raw (no-contact) recipient gets the neutral wallet badge
    // (AppIcons.wallet), not the brand ZEC currency coin
    // (AppIcons.zcashCurrency).
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('mobile_send_review_recipient_picture')),
        matching: find.byWidgetPredicate(
          (w) => w is AppIcon && w.name == AppIcons.wallet,
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('mobile_send_review_recipient_picture')),
        matching: find.byWidgetPredicate(
          (w) => w is AppIcon && w.name == AppIcons.zcashCurrency,
        ),
      ),
      findsNothing,
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
    expect(find.text('Shielded address'), findsOneWidget);
    expect(find.text('Unified address'), findsNothing);
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

  testWidgets('review uses Keystone CTA for a hardware account', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        accountState: const AccountState(
          accounts: [
            AccountInfo(
              uuid: 'account-1',
              name: 'Keystone',
              order: 0,
              isHardware: true,
            ),
          ],
          activeAccountUuid: 'account-1',
          activeAddress: 'u1activeaddress',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _toReviewStep(tester);

    expect(find.text('Confirm with Keystone'), findsOneWidget);
    expect(find.text('Confirm & Send'), findsNothing);

    final confirmButton = tester.widget<AppButton>(
      find.byKey(const ValueKey('mobile_send_confirm')),
    );
    final leading = confirmButton.leading;
    expect(leading, isA<AppIcon>());
    expect((leading! as AppIcon).name, AppIcons.qr);
  });

  testWidgets('a transparent recipient hides the memo entry', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await _toReviewStep(tester, address: _transparentAddress);

    expect(find.text('Add short encrypted message'), findsNothing);
    expect(find.text('Transparent address'), findsOneWidget);
    expect(find.text('Tx fee'), findsOneWidget);
  });

  testWidgets('a TEX recipient hides memo but keeps the TEX label', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await _toReviewStep(tester, address: _texAddress);

    expect(find.text('Add short encrypted message'), findsNothing);
    expect(find.text('TEX address'), findsOneWidget);
    expect(find.text('TEX - ${_compactReviewAddress(_texAddress)}'), findsOne);
    expect(find.text('Transparent address'), findsNothing);
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
