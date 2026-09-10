import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/core/config/network_config.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/features/send/models/send_prefill_args.dart';
import 'package:zcash_wallet/src/features/send/services/payment_request_precheck.dart';
import 'package:zcash_wallet/src/features/send/services/send_flow.dart';
import 'package:zcash_wallet/src/features/address_book/models/address_book_contact.dart';
import 'package:zcash_wallet/src/features/address_book/providers/address_book_provider.dart';
import 'package:zcash_wallet/src/features/send/widgets/payment_request_host.dart';
import 'package:zcash_wallet/src/features/send/widgets/send_recipient_resolver.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/migration_send_gate_provider.dart';
import 'package:zcash_wallet/src/providers/payment_request_flow_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/providers/zec_price_change_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import '../../fakes/fake_sync_notifier.dart';

const _address =
    'u1950915183f0fed838d6d2dd92d6f4111ed3c6dd4e3eb19a3702b'
    '73d57f73c6dc05121591a83861cd190591';

const _request = SendPrefillArgs(
  id: 'payment-uri-1',
  source: kPaymentUriPrefillSource,
  address: _address,
  amountText: '0.5',
  label: 'Coffee shop',
);

const _replacementRequest = SendPrefillArgs(
  id: 'payment-uri-2',
  source: kPaymentUriPrefillSource,
  address: _address,
  amountText: '0.75',
  label: 'Bakery',
  message: 'Second request note',
);

AddressBookContact _contact(String label, String address) => AddressBookContact(
  id: 'contact-$label',
  label: label,
  network: AddressBookNetwork.zcash,
  address: address,
  profilePictureId: 'pfp-03',
  createdAtMs: 0,
  updatedAtMs: 0,
);

/// Address book that never finishes loading, so the host has to render the
/// request before it knows who the recipient is.
class _PendingAddressBookNotifier extends AddressBookNotifier {
  @override
  Future<AddressBookState> build() => Completer<AddressBookState>().future;
}

class _FakeAddressBookNotifier extends AddressBookNotifier {
  _FakeAddressBookNotifier(this.contacts);

  final List<AddressBookContact> contacts;

  @override
  Future<AddressBookState> build() async =>
      AddressBookState(contacts: contacts);
}

class _FakeAccountNotifier extends AccountNotifier {
  @override
  FutureOr<AccountState> build() => const AccountState(
    accounts: [AccountInfo(uuid: 'account-1', name: 'Account 1', order: 0)],
    activeAccountUuid: 'account-1',
  );
}

final _discarded = <BigInt>[];

/// Holds the pre-check's `discardProposal` open so a test can look at the
/// router while the card's proposal is still being released.
Completer<void>? _discardGate;

PaymentRequestPrecheck _readyPrecheck() => PaymentRequestPrecheck(
  readNetworkName: () => kZcashDefaultNetworkName,
  spendableIsAuthoritativeNow: () => true,
  validateAddress: ({required String address, required String network}) async =>
      rust_sync.AddressValidationResult(
        isValid: true,
        addressType: 'unified',
        wrongNetwork: false,
      ),
  proposeTransfer:
      ({
        required String accountUuid,
        required String sendFlowId,
        required String address,
        required String addressType,
        required BigInt amountZatoshi,
        String? memo,
        bool isPaymentRequest = false,
        String? requestedBy,
        BigInt? requestedAmountZatoshi,
      }) async => SendReviewArgs(
        proposalId: BigInt.from(11),
        sendFlowId: sendFlowId,
        proposalAccountUuid: accountUuid,
        address: address,
        addressType: addressType,
        amountZatoshi: amountZatoshi,
        feeZatoshi: BigInt.from(10000),
        needsSaplingParams: false,
        isPaymentRequest: isPaymentRequest,
        requestedBy: requestedBy,
        requestedAmountZatoshi: requestedAmountZatoshi,
      ),
  discardProposal:
      ({
        required BigInt proposalId,
        required String sendFlowId,
        required String logContext,
      }) async {
        _discarded.add(proposalId);
        final gate = _discardGate;
        if (gate != null) await gate.future;
        return true;
      },
);

/// A pre-check whose propose leg can be made to fail with the error Rust
/// emits before it has anchor heights — the one the card maps onto its
/// syncing statuses.
class _StallingSendApi {
  Object? proposeThrows = Exception('Wallet must sync before sending');
  var proposeAttempts = 0;

  PaymentRequestPrecheck get precheck => PaymentRequestPrecheck(
    readNetworkName: () => kZcashDefaultNetworkName,
    // Settled: a shortfall would be final, so the only way to `syncing` here
    // is the propose leg — and with the sync settled there is no completion
    // left for the card to wait for, which is what makes it stall.
    spendableIsAuthoritativeNow: () => true,
    validateAddress:
        ({required String address, required String network}) async =>
            rust_sync.AddressValidationResult(
              isValid: true,
              addressType: 'unified',
              wrongNetwork: false,
            ),
    proposeTransfer:
        ({
          required String accountUuid,
          required String sendFlowId,
          required String address,
          required String addressType,
          required BigInt amountZatoshi,
          String? memo,
          bool isPaymentRequest = false,
          String? requestedBy,
          BigInt? requestedAmountZatoshi,
        }) async {
          proposeAttempts++;
          final failure = proposeThrows;
          if (failure != null) throw failure;
          return SendReviewArgs(
            proposalId: BigInt.from(11),
            sendFlowId: sendFlowId,
            proposalAccountUuid: accountUuid,
            address: address,
            addressType: addressType,
            amountZatoshi: amountZatoshi,
            feeZatoshi: BigInt.from(10000),
            needsSaplingParams: false,
            isPaymentRequest: isPaymentRequest,
            requestedBy: requestedBy,
            requestedAmountZatoshi: requestedAmountZatoshi,
          );
        },
    discardProposal:
        ({
          required BigInt proposalId,
          required String sendFlowId,
          required String logContext,
        }) async {
          _discarded.add(proposalId);
          return true;
        },
  );
}

Future<ProviderContainer> _pumpHost(
  WidgetTester tester, {
  List<AddressBookContact> contacts = const [],
  Map<String, AccountInfo> ownAccounts = const {},
  bool addressBookPending = false,
  PaymentRequestPrecheck? precheck,
  WidgetBuilder? homeScreen,
}) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      for (final path in ['/home', '/send', '/send/review'])
        GoRoute(
          path: path,
          builder: (context, _) => path == '/home' && homeScreen != null
              ? homeScreen(context)
              : Scaffold(body: Text('screen $path')),
        ),
    ],
  );
  addTearDown(router.dispose);

  late ProviderContainer container;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        paymentRequestPrecheckProvider.overrideWithValue(
          precheck ?? _readyPrecheck(),
        ),
        accountProvider.overrideWith(_FakeAccountNotifier.new),
        syncProvider.overrideWith(
          () => FakeSyncNotifier(
            SyncState(
              accountUuid: 'account-1',
              hasAccountScopedData: true,
              isSyncComplete: true,
              chainTipHeight: 3000000,
              scannedHeight: 3000000,
              spendableBalance: BigInt.from(100000000),
            ),
          ),
        ),
        migrationSendGateProvider.overrideWithValue(false),
        // Backed by a state provider so a test can land the price *after*
        // the card is already on screen, which is what the real autoDispose
        // market-data providers do.
        zecHomeUsdUnitPriceProvider.overrideWith(
          (ref) => ref.watch(_testZecUsdPriceProvider),
        ),
        addressBookProvider.overrideWith(
          addressBookPending
              ? _PendingAddressBookNotifier.new
              : () => _FakeAddressBookNotifier(contacts),
        ),
        // The real provider asks Rust for every account's addresses; the host
        // only ever reads its settled value.
        ownAccountAddressesProvider.overrideWith((ref) async => ownAccounts),
      ],
      child: Consumer(
        builder: (context, ref, _) {
          container = ProviderScope.containerOf(context, listen: false);
          return MaterialApp.router(
            routerConfig: router,
            builder: (context, child) => AppTheme(
              data: AppThemeData.light,
              child: PaymentRequestHost(router: router, child: child!),
            ),
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() => _routers.remove(container));
  _routers[container] = router;
  return container;
}

final _routers = <ProviderContainer, GoRouter>{};

/// How many times [_StatefulScreenProbe] has been built from scratch.
var _probeMounts = 0;

/// How many times it has been unhooked from the element tree.
///
/// This is the assertion with teeth. `go_router` gives its `Navigator` a
/// `GlobalKey`, so even a routed subtree that gets re-parented is *retaken*
/// rather than rebuilt: screen state survives either way, and `find.text`
/// alone would pass either way. What re-parenting still costs is a
/// deactivate/activate cycle through every element under the router — plus a
/// fresh `Router` state above them, which is not global-keyed — on every show
/// and every dismiss, for a card that is only supposed to be sitting on top.
/// Zero here is the whole point.
var _probeDeactivations = 0;

/// A screen that owns route-local state, standing in for a half-typed
/// Send form.
class _StatefulScreenProbe extends StatefulWidget {
  const _StatefulScreenProbe();

  @override
  State<_StatefulScreenProbe> createState() => _StatefulScreenProbeState();
}

class _StatefulScreenProbeState extends State<_StatefulScreenProbe> {
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _probeMounts++;
  }

  @override
  void deactivate() {
    _probeDeactivations++;
    super.deactivate();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(child: TextField(controller: _controller)),
  );
}

class _TestZecUsdPriceNotifier extends Notifier<double?> {
  @override
  double? build() => null;

  void setPrice(double? price) => state = price;
}

final _testZecUsdPriceProvider =
    NotifierProvider<_TestZecUsdPriceNotifier, double?>(
      _TestZecUsdPriceNotifier.new,
    );

String _location(ProviderContainer container) =>
    _routers[container]!.routerDelegate.currentConfiguration.uri.path;

void main() {
  setUp(() {
    _discarded.clear();
    _discardGate = null;
    _probeMounts = 0;
    _probeDeactivations = 0;
  });

  testWidgets('the card renders over the current screen', (tester) async {
    final container = await _pumpHost(tester);
    container
        .read(paymentRequestFlowProvider.notifier)
        .present(_request, source: PaymentRequestSource.link);
    await tester.pumpAndSettle();

    expect(find.text('Payment request'), findsOneWidget);
    expect(find.text('Requester'), findsOneWidget);
    expect(find.text('Coffee shop'), findsOneWidget);
    expect(find.text('Requested by Coffee shop'), findsNothing);
    expect(
      find.text('screen /home'),
      findsOneWidget,
      reason: 'the screen underneath stays mounted',
    );
    expect(_location(container), '/home');
  });

  testWidgets('the screen under the card stays put across show and dismiss', (
    tester,
  ) async {
    final container = await _pumpHost(
      tester,
      homeScreen: (_) => const _StatefulScreenProbe(),
    );
    await tester.enterText(find.byType(TextField), 'half typed');
    await tester.pumpAndSettle();
    expect(_probeMounts, 1);
    expect(_probeDeactivations, 0);
    final screen = tester.state<_StatefulScreenProbeState>(
      find.byType(_StatefulScreenProbe),
    );
    final router = tester.state(find.byType(Router<Object>));

    container
        .read(paymentRequestFlowProvider.notifier)
        .present(_request, source: PaymentRequestSource.link);
    await tester.pumpAndSettle();

    expect(find.text('Payment request'), findsOneWidget);
    expect(
      _probeDeactivations,
      0,
      reason: 'showing the card must not move the routed subtree',
    );
    expect(
      tester.state(find.byType(Router<Object>)),
      same(router),
      reason: 'the router above it is not global-keyed, so it would be rebuilt',
    );
    expect(_probeMounts, 1);
    expect(screen.mounted, isTrue);
    expect(find.text('half typed'), findsOneWidget);

    container.read(paymentRequestFlowProvider.notifier).dismiss();
    await tester.pumpAndSettle();

    expect(find.text('Payment request'), findsNothing);
    expect(
      _probeDeactivations,
      0,
      reason: 'dismissing it must not move the subtree back',
    );
    expect(tester.state(find.byType(Router<Object>)), same(router));
    expect(_probeMounts, 1);
    expect(
      tester.state<_StatefulScreenProbeState>(
        find.byType(_StatefulScreenProbe),
      ),
      same(screen),
    );
    expect(
      find.text('half typed'),
      findsOneWidget,
      reason: 'a link arriving over the composer cannot empty it',
    );
  });

  // Hosted above the router there is no `Navigator`, so the caveat tooltip
  // only works because the surface carries its own `Overlay`.
  testWidgets('the requester caveat opens over the live host', (tester) async {
    final container = await _pumpHost(tester);
    final semantics = tester.ensureSemantics();
    container
        .read(paymentRequestFlowProvider.notifier)
        .present(_replacementRequest, source: PaymentRequestSource.link);
    await tester.pumpAndSettle();

    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Show requester details'))
          .value,
      'Label from link, Bakery',
      reason: 'the summary announces a link label, not a verified sender',
    );

    await tester.tap(
      find.byKey(const ValueKey('payment_request_requester_help')),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        "Name supplied by the payment link. Vizor can't verify who sent it.",
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('a replacement request starts with disclosures collapsed', (
    tester,
  ) async {
    final container = await _pumpHost(tester);
    container
        .read(paymentRequestFlowProvider.notifier)
        .present(
          const SendPrefillArgs(
            id: 'payment-uri-1-with-note',
            source: kPaymentUriPrefillSource,
            address: _address,
            amountText: '0.5',
            label: 'Coffee shop',
            message: 'First request note',
          ),
          source: PaymentRequestSource.link,
        );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('payment_request_requester_toggle')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('payment_request_requester_note')),
      findsOneWidget,
    );

    container
        .read(paymentRequestFlowProvider.notifier)
        .present(_replacementRequest, source: PaymentRequestSource.link);
    await tester.pumpAndSettle();

    expect(find.text('Bakery'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('payment_request_requester_note')),
      findsNothing,
    );
    expect(find.text('screen /home'), findsOneWidget);
    expect(_location(container), '/home');
  });

  testWidgets('Review routes to the review screen and keeps the proposal', (
    tester,
  ) async {
    final container = await _pumpHost(tester);
    container
        .read(paymentRequestFlowProvider.notifier)
        .present(_request, source: PaymentRequestSource.link);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();

    expect(_location(container), '/send/review');
    expect(container.read(paymentRequestFlowProvider), isNull);
    expect(
      _discarded,
      isEmpty,
      reason: 'the review screen owns the proposal from here',
    );
  });

  testWidgets('Edit routes to the composer and releases the proposal', (
    tester,
  ) async {
    final container = await _pumpHost(tester);
    container
        .read(paymentRequestFlowProvider.notifier)
        .present(_request, source: PaymentRequestSource.link);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    expect(_location(container), '/send');
    expect(container.read(paymentRequestFlowProvider), isNull);
    expect(_discarded, [BigInt.from(11)]);
  });

  testWidgets('Edit opens the composer only once the proposal is released', (
    tester,
  ) async {
    final gate = Completer<void>();
    _discardGate = gate;
    final container = await _pumpHost(tester);
    container
        .read(paymentRequestFlowProvider.notifier)
        .present(_request, source: PaymentRequestSource.link);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Edit'));
    await tester.pump();

    // The card is gone at once, but the composer — which re-quotes the fee
    // as it mounts — must not open against inputs the proposal still holds.
    expect(container.read(paymentRequestFlowProvider), isNull);
    expect(_discarded, [BigInt.from(11)]);
    expect(_location(container), '/home');

    gate.complete();
    await tester.pumpAndSettle();

    expect(_location(container), '/send');
  });

  testWidgets('Cancel dismisses the card and releases the proposal', (
    tester,
  ) async {
    final container = await _pumpHost(tester);
    container
        .read(paymentRequestFlowProvider.notifier)
        .present(_request, source: PaymentRequestSource.link);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('payment_request_close')));
    await tester.pumpAndSettle();

    expect(_location(container), '/home');
    expect(container.read(paymentRequestFlowProvider), isNull);
    expect(_discarded, [BigInt.from(11)]);
  });

  testWidgets('a saved contact names the recipient on the card', (
    tester,
  ) async {
    final container = await _pumpHost(
      tester,
      contacts: [_contact('Blue Door Coffee', _address)],
    );
    container
        .read(paymentRequestFlowProvider.notifier)
        .present(_request, source: PaymentRequestSource.link);
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('payment_request_recipient_name')),
          )
          .data,
      'Blue Door Coffee',
    );
    expect(find.text('Your account'), findsNothing);
  });

  testWidgets('an own account is named as the user own account', (
    tester,
  ) async {
    final container = await _pumpHost(
      tester,
      ownAccounts: const {
        _address: AccountInfo(
          uuid: 'account-1',
          name: 'Account 1',
          profilePictureId: 'pfp-07',
          order: 0,
        ),
      },
    );
    container
        .read(paymentRequestFlowProvider.notifier)
        .present(_request, source: PaymentRequestSource.link);
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('payment_request_recipient_name')),
          )
          .data,
      'Account 1',
    );
    expect(find.text('Your account'), findsOneWidget);
  });

  testWidgets('a contact saved for an own account wins, as on the review', (
    tester,
  ) async {
    final container = await _pumpHost(
      tester,
      contacts: [_contact('Blue Door Coffee', _address)],
      ownAccounts: const {
        _address: AccountInfo(uuid: 'account-1', name: 'Account 1', order: 0),
      },
    );
    container
        .read(paymentRequestFlowProvider.notifier)
        .present(_request, source: PaymentRequestSource.link);
    await tester.pumpAndSettle();

    expect(find.text('Your account'), findsNothing);
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('payment_request_recipient_name')),
          )
          .data,
      'Blue Door Coffee',
    );
  });

  testWidgets('an unresolved lookup renders the plain address, not a wait', (
    tester,
  ) async {
    final container = await _pumpHost(tester, addressBookPending: true);
    container
        .read(paymentRequestFlowProvider.notifier)
        .present(_request, source: PaymentRequestSource.link);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // The card is up and answerable while the address book is still loading.
    expect(find.text('Payment request'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('payment_request_recipient_name')),
      findsNothing,
    );
    expect(find.text('u195091 ... 190591'), findsOneWidget);
  });

  testWidgets('the fiat line lands when the price arrives after the card', (
    tester,
  ) async {
    // A link that arrives over Settings or Activity finds the autoDispose
    // price providers with no subscriber, so the value is null at present
    // time and fills a moment later.
    final container = await _pumpHost(tester);
    container
        .read(paymentRequestFlowProvider.notifier)
        .present(_request, source: PaymentRequestSource.link);
    await tester.pumpAndSettle();

    expect(find.text(r'$50.00'), findsNothing);

    container.read(_testZecUsdPriceProvider.notifier).setPrice(100);
    await tester.pumpAndSettle();

    expect(find.text(r'$50.00'), findsOneWidget);
  });

  testWidgets('an address in neither source keeps the plain address', (
    tester,
  ) async {
    final container = await _pumpHost(
      tester,
      contacts: [
        _contact('Someone else', 't1PZ4vMuLdt2wRfDGGKS1qXfBpJt5CJHhNz'),
      ],
    );
    container
        .read(paymentRequestFlowProvider.notifier)
        .present(_request, source: PaymentRequestSource.link);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('payment_request_recipient_name')),
      findsNothing,
    );
    expect(find.text('u195091 ... 190591'), findsOneWidget);
  });

  // A card that has run out of ways to answer itself stops promising an
  // update and hands the next move to the user.
  testWidgets('a stalled check offers Check again instead of a dead Review', (
    tester,
  ) async {
    final api = _StallingSendApi();
    final container = await _pumpHost(tester, precheck: api.precheck);
    container
        .read(paymentRequestFlowProvider.notifier)
        .present(_request, source: PaymentRequestSource.link);
    await tester.pumpAndSettle();

    expect(
      find.text('Still syncing — check again when the wallet is up to date'),
      findsOneWidget,
    );
    expect(find.text('Check again'), findsOneWidget);
    expect(find.text('Review'), findsNothing);
    final primary = tester.widget<AppButton>(
      find.byKey(const ValueKey('payment_request_continue')),
    );
    expect(
      primary.onPressed,
      isNotNull,
      reason: 'the one control that can change the answer must be usable',
    );
    final asked = api.proposeAttempts;

    // The wallet caught up; the tap is what asks again.
    api.proposeThrows = null;
    await tester.tap(find.byKey(const ValueKey('payment_request_continue')));
    await tester.pumpAndSettle();

    expect(api.proposeAttempts, asked + 1);
    expect(find.text('Review'), findsOneWidget);
    expect(find.text('Check again'), findsNothing);
    expect(
      container.read(paymentRequestFlowProvider)!.canReview,
      isTrue,
      reason: 'the re-check made the proposal the review screen needs',
    );
    expect(_location(container), '/home');
  });
}
