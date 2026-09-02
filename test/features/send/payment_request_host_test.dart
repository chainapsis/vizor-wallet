import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
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

PaymentRequestPrecheck _readyPrecheck() => PaymentRequestPrecheck(
  spendableIsAuthoritativeNow: () => true,
  validateAddress: ({required String address}) async =>
      rust_sync.AddressValidationResult(isValid: true, addressType: 'unified'),
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
      }) async => _discarded.add(proposalId),
);

Future<ProviderContainer> _pumpHost(
  WidgetTester tester, {
  List<AddressBookContact> contacts = const [],
  Map<String, AccountInfo> ownAccounts = const {},
  bool addressBookPending = false,
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
          builder: (_, _) => Scaffold(body: Text('screen $path')),
        ),
    ],
  );
  addTearDown(router.dispose);

  late ProviderContainer container;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
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

String _location(ProviderContainer container) =>
    _routers[container]!.routerDelegate.currentConfiguration.uri.path;

void main() {
  setUp(_discarded.clear);

  testWidgets('the card renders over the current screen', (tester) async {
    final container = await _pumpHost(tester);
    container
        .read(paymentRequestFlowProvider.notifier)
        .present(_request, source: PaymentRequestSource.link);
    await tester.pumpAndSettle();

    expect(find.text('Payment request'), findsOneWidget);
    expect(find.text('Requested by Coffee shop'), findsOneWidget);
    expect(
      find.text('screen /home'),
      findsOneWidget,
      reason: 'the screen underneath stays mounted',
    );
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
}
