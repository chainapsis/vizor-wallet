@Tags(['mobile'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/navigation/mobile_routes.dart';
import 'package:zcash_wallet/src/features/send/services/send_proving_key_warmup.dart';
import 'package:zcash_wallet/src/rust/frb_generated.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/address_book/models/address_book_contact.dart';
import 'package:zcash_wallet/src/features/address_book/providers/address_book_provider.dart';
import 'package:zcash_wallet/src/features/send/models/send_prefill_args.dart';
import 'package:zcash_wallet/src/features/send/screens/mobile/mobile_send_screen.dart'
    show MobileSendReviewDraftArgs, MobileSendScreen;
import 'package:zcash_wallet/src/features/send/services/payment_request_precheck.dart';
import 'package:zcash_wallet/src/features/send/services/send_flow.dart';
import 'package:zcash_wallet/src/features/send/widgets/payment_request_host.dart';
import 'package:zcash_wallet/src/features/send/widgets/send_recipient_resolver.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/migration_send_gate_provider.dart';
import 'package:zcash_wallet/src/providers/payment_request_flow_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/providers/zec_price_change_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import '../../fakes/fake_sync_notifier.dart';

// The mobile half of `payment_request_host_test.dart`: the card's Review
// hands the proposal *back* (the wizard's review step creates its own) and
// must not open that step until Rust has released it.

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

class _RustApiFake implements RustLibApi {
  bool validAddress = true;

  @override
  Future<rust_sync.AddressValidationResult> crateApiSyncValidateAddress({
    required String address,
    required String network,
  }) async => rust_sync.AddressValidationResult(
    isValid: validAddress,
    addressType: validAddress ? 'unified' : 'invalid',
    wrongNetwork: false,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAddressBookNotifier extends AddressBookNotifier {
  _FakeAddressBookNotifier(this.contacts);

  final FutureOr<List<AddressBookContact>> contacts;

  @override
  Future<AddressBookState> build() async =>
      AddressBookState(contacts: await contacts);
}

class _FakeAccountNotifier extends AccountNotifier {
  @override
  FutureOr<AccountState> build() => const AccountState(
    accounts: [AccountInfo(uuid: 'account-1', name: 'Account 1', order: 0)],
    activeAccountUuid: 'account-1',
  );
}

final _discarded = <BigInt>[];

/// Held open until the test releases it, so "Rust still holds the
/// proposal's inputs" is a state the test can stand in.
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
        required String accountUuid,
      }) async {
        final pending = _discardGate;
        if (pending != null) await pending.future;
        _discarded.add(proposalId);
        return true;
      },
);

class _Harness {
  _Harness(this.container, this.router);

  final ProviderContainer container;
  final GoRouter router;

  /// What `/send/review` was opened with, once it was.
  Object? reviewExtra;

  String get location => router.routerDelegate.currentConfiguration.uri.path;
}

Future<_Harness> _pumpHost(
  WidgetTester tester, {
  bool realComposer = false,
  FutureOr<List<AddressBookContact>> contacts = const [],
  FutureOr<Map<String, AccountInfo>> ownAccounts = const {},
}) async {
  tester.view.physicalSize = const Size(393, 852);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  late _Harness harness;
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      for (final path in ['/home', if (!realComposer) '/send'])
        GoRoute(
          path: path,
          builder: (_, _) => Scaffold(body: Text('screen $path')),
        ),
      if (realComposer)
        buildMobileRoutes(
          entryRoutes: const [],
        ).whereType<GoRoute>().singleWhere((route) => route.path == '/send'),
      GoRoute(
        path: '/send/review',
        builder: (_, state) {
          harness.reviewExtra = state.extra;
          return const Scaffold(body: Text('screen /send/review'));
        },
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appBootstrapProvider.overrideWithValue(
          AppBootstrapState(
            initialLocation: '/home',
            initialAccountState: const AccountState(
              accounts: [
                AccountInfo(uuid: 'account-1', name: 'Account 1', order: 0),
              ],
              activeAccountUuid: 'account-1',
            ),
            initialSyncSnapshot: AppSyncSnapshot.empty,
            network: 'main',
            rpcEndpointConfig: defaultRpcEndpointConfig('main'),
            themeMode: ThemeMode.light,
            privacyModeEnabled: false,
            isPasswordConfigured: true,
            isUnlocked: true,
            passwordRotationRecoveryFailed: false,
          ),
        ),
        paymentRequestPrecheckProvider.overrideWithValue(_readyPrecheck()),
        accountProvider.overrideWith(_FakeAccountNotifier.new),
        syncProvider.overrideWith(
          () => FakeSyncNotifier(
            SyncState(
              accountUuid: 'account-1',
              hasAccountScopedData: true,
              spendableBalance: BigInt.from(100000000),
            ),
          ),
        ),
        migrationSendGateProvider.overrideWithValue(false),
        zecHomeUsdUnitPriceProvider.overrideWithValue(null),
        zecLiveUsdUnitPriceProvider.overrideWithValue(100),
        sendProvingKeyWarmupProvider.overrideWithValue(() {}),
        addressBookProvider.overrideWith(
          () => _FakeAddressBookNotifier(contacts),
        ),
        ownAccountAddressesProvider.overrideWith((ref) async => ownAccounts),
      ],
      child: Consumer(
        builder: (context, ref, _) {
          harness = _Harness(
            ProviderScope.containerOf(context, listen: false),
            router,
          );
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
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
  return harness;
}

void main() {
  final rustApi = _RustApiFake();
  setUpAll(() => RustLib.initMock(api: rustApi));
  tearDownAll(RustLib.dispose);
  setUp(() {
    rustApi.validAddress = true;
    _discarded.clear();
    _discardGate = null;
  });

  testWidgets('dragging the sheet down dismisses and releases its proposal', (
    tester,
  ) async {
    final harness = await _pumpHost(tester);
    harness.container
        .read(paymentRequestFlowProvider.notifier)
        .present(_request, source: PaymentRequestSource.link);
    await tester.pumpAndSettle();

    final title = find.text('Payment request');
    final start = tester.getCenter(title);
    final gesture = await tester.startGesture(start);
    await gesture.moveBy(const Offset(0, 20));
    await gesture.moveBy(const Offset(0, 100));
    await tester.pump();
    expect(tester.getCenter(title).dy, greaterThan(start.dy));
    await gesture.moveBy(const Offset(0, 300));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.text('Payment request'), findsNothing);
    expect(harness.container.read(paymentRequestFlowProvider), isNull);
    expect(_discarded, [BigInt.from(11)]);
    expect(harness.location, '/home');
  });

  testWidgets('a short drag returns the sheet to its original position', (
    tester,
  ) async {
    final harness = await _pumpHost(tester);
    harness.container
        .read(paymentRequestFlowProvider.notifier)
        .present(_request, source: PaymentRequestSource.link);
    await tester.pumpAndSettle();

    final title = find.text('Payment request');
    final start = tester.getCenter(title);
    final gesture = await tester.startGesture(start);
    await gesture.moveBy(const Offset(0, 20));
    await gesture.moveBy(const Offset(0, 40));
    await tester.pump();
    expect(tester.getCenter(title).dy, greaterThan(start.dy));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(tester.getCenter(title), start);
    expect(harness.container.read(paymentRequestFlowProvider), isNotNull);
    expect(_discarded, isEmpty);
  });

  testWidgets('a replacement request survives the previous sheet closing', (
    tester,
  ) async {
    final harness = await _pumpHost(tester);
    final notifier = harness.container.read(
      paymentRequestFlowProvider.notifier,
    );
    notifier.present(_request, source: PaymentRequestSource.link);
    await tester.pumpAndSettle();

    final originalTop = tester.getTopLeft(find.text('Payment request')).dy;
    await tester.fling(
      find.text('Payment request'),
      const Offset(0, 100),
      1000,
    );
    await tester.pump(const Duration(milliseconds: 20));
    expect(
      tester.getTopLeft(find.text('Payment request')).dy,
      greaterThan(originalTop),
    );
    notifier.present(
      const SendPrefillArgs(
        id: 'replacement',
        source: kPaymentUriPrefillSource,
        address: _address,
        amountText: '0.75',
      ),
      source: PaymentRequestSource.link,
    );
    // Let the old animation finish in the frame that rebuilds the host for
    // the new request: its completion callback runs before that rebuild.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.text('Payment request'), findsOneWidget);
    expect(
      harness.container.read(paymentRequestFlowProvider)!.prefill.id,
      'replacement',
    );
    expect(find.text('0.75 ZEC'), findsOneWidget);
    expect(_discarded, [BigInt.from(11)]);
  });

  for (final ownAccount in [false, true]) {
    testWidgets(
      'the mobile recipient updates when ${ownAccount ? 'own accounts' : 'contacts'} load',
      (tester) async {
        final contacts = Completer<List<AddressBookContact>>();
        final accounts = Completer<Map<String, AccountInfo>>();
        final harness = await _pumpHost(
          tester,
          contacts: contacts.future,
          ownAccounts: accounts.future,
        );
        harness.container
            .read(paymentRequestFlowProvider.notifier)
            .present(_request, source: PaymentRequestSource.qrCode);
        await tester.pumpAndSettle();

        expect(find.text('Payment request'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('payment_request_recipient_name')),
          findsNothing,
        );
        contacts.complete(
          ownAccount
              ? []
              : [
                  const AddressBookContact(
                    id: 'contact',
                    label: 'Blue Door Coffee',
                    network: AddressBookNetwork.zcash,
                    address: _address,
                    profilePictureId: 'pfp-03',
                    createdAtMs: 0,
                    updatedAtMs: 0,
                  ),
                ],
        );
        accounts.complete(
          ownAccount
              ? {
                  _address: const AccountInfo(
                    uuid: 'account-2',
                    name: 'Savings',
                    order: 1,
                  ),
                }
              : {},
        );
        await tester.pumpAndSettle();

        expect(
          find.text(ownAccount ? 'Savings' : 'Blue Door Coffee'),
          findsOneWidget,
        );
        expect(
          find.text('Your account'),
          ownAccount ? findsOneWidget : findsNothing,
        );
        expect(
          find.byKey(const ValueKey('payment_request_recipient_address')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('payment_request_recipient_avatar')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Enter amount opens the real amount step for an address-only request',
    (tester) async {
      final harness = await _pumpHost(tester, realComposer: true);
      harness.container
          .read(paymentRequestFlowProvider.notifier)
          .present(
            const SendPrefillArgs(
              id: 'address-only',
              source: kPaymentUriPrefillSource,
              address: _address,
            ),
            source: PaymentRequestSource.link,
          );
      await tester.pumpAndSettle();
      expect(find.text('Transaction content'), findsNothing);
      expect(find.text('To'), findsOneWidget);
      await tester.tap(find.text('Enter amount'));
      await tester.pumpAndSettle();
      expect(harness.location, '/send');
      expect(find.text('Enter Amount'), findsOneWidget);
      expect(find.text('Select Recipient'), findsNothing);
      expect(
        tester
            .widget<MobileSendScreen>(find.byType(MobileSendScreen))
            .initialRecipient,
        _address,
      );
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('mobile_send_amount_input')),
            )
            .controller!
            .text,
        isEmpty,
      );
      expect(harness.container.read(paymentRequestFlowProvider), isNull);
      expect(_discarded, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'an address-only request returns to recipient entry when validation fails',
    (tester) async {
      final harness = await _pumpHost(tester, realComposer: true);
      harness.container
          .read(paymentRequestFlowProvider.notifier)
          .present(
            const SendPrefillArgs(
              id: 'address-only-invalid',
              source: kPaymentUriPrefillSource,
              address: _address,
            ),
            source: PaymentRequestSource.link,
          );
      await tester.pumpAndSettle();
      rustApi.validAddress = false;
      await tester.tap(find.text('Enter amount'));
      await tester.pumpAndSettle();
      expect(find.text('Select Recipient'), findsOneWidget);
      expect(find.text('Enter Amount'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a bare recipient still starts at address entry', (tester) async {
    final harness = await _pumpHost(tester, realComposer: true);
    harness.router.go('/send', extra: _address);
    await tester.pumpAndSettle();
    expect(find.text('Select Recipient'), findsOneWidget);
    expect(find.text('Enter Amount'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Review opens the wizard only once the card proposal is handed back',
    (tester) async {
      final harness = await _pumpHost(tester);
      harness.container
          .read(paymentRequestFlowProvider.notifier)
          .present(_request, source: PaymentRequestSource.link);
      await tester.pumpAndSettle();

      _discardGate = Completer<void>();
      await tester.tap(find.byKey(const ValueKey('payment_request_continue')));
      await tester.pumpAndSettle();

      // The card answers at once, but the review step — which re-quotes the
      // fee as it mounts — waits for the inputs to be released.
      expect(harness.container.read(paymentRequestFlowProvider), isNull);
      expect(harness.location, '/home');
      expect(_discarded, isEmpty);

      _discardGate!.complete();
      await tester.pumpAndSettle();

      expect(_discarded, [BigInt.from(11)]);
      expect(harness.location, '/send/review');
      final draft = harness.reviewExtra! as MobileSendReviewDraftArgs;
      // `activityDetail` formatting, which the wizard parses back exactly.
      expect(draft.amountText, '0.50');
      expect(draft.feeZatoshi, BigInt.from(10000));
      expect(draft.isPaymentRequest, isTrue);
      expect(draft.requestedBy, 'Coffee shop');
    },
  );

  testWidgets('a route change during the hand-back cancels it', (tester) async {
    final harness = await _pumpHost(tester);
    harness.container
        .read(paymentRequestFlowProvider.notifier)
        .present(_request, source: PaymentRequestSource.link);
    await tester.pumpAndSettle();

    _discardGate = Completer<void>();
    await tester.tap(find.byKey(const ValueKey('payment_request_continue')));
    await tester.pumpAndSettle();
    expect(harness.location, '/home');

    // The card is gone and the app is usable; the user moves on.
    harness.router.go('/send');
    await tester.pumpAndSettle();

    _discardGate!.complete();
    await tester.pumpAndSettle();

    expect(harness.location, '/send');
    expect(harness.reviewExtra, isNull);
  });

  testWidgets('a newer link during the hand-back keeps the wizard closed', (
    tester,
  ) async {
    final harness = await _pumpHost(tester);
    final notifier = harness.container.read(
      paymentRequestFlowProvider.notifier,
    );
    notifier.present(_request, source: PaymentRequestSource.link);
    await tester.pumpAndSettle();

    _discardGate = Completer<void>();
    await tester.tap(find.byKey(const ValueKey('payment_request_continue')));
    await tester.pumpAndSettle();

    notifier.present(
      const SendPrefillArgs(
        id: 'payment-uri-2',
        source: kPaymentUriPrefillSource,
        address: _address,
        amountText: '0.75',
        label: 'Bakery',
      ),
      source: PaymentRequestSource.link,
    );
    _discardGate!.complete();
    await tester.pumpAndSettle();

    // The first proposal was still handed back, but its review never opened:
    // the user is answering the second request now.
    expect(_discarded, [BigInt.from(11)]);
    expect(harness.location, '/home');
    expect(harness.reviewExtra, isNull);
    expect(
      harness.container.read(paymentRequestFlowProvider)!.prefill.id,
      'payment-uri-2',
    );
    // And the dropped tap is not silent: the card that took the first
    // request's place carries the standard replaced notice. `present` cannot
    // raise it on its own here — the hand-back had already cleared the card
    // it replaced, so there was nothing for it to notice.
    expect(
      find.byKey(const ValueKey('payment_request_replaced_notice')),
      findsOneWidget,
    );
    expect(find.text('Replaced an earlier link'), findsOneWidget);
  });
}
