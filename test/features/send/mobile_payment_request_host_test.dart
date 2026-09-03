@Tags(['mobile'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/address_book/providers/address_book_provider.dart';
import 'package:zcash_wallet/src/features/send/models/send_prefill_args.dart';
import 'package:zcash_wallet/src/features/send/screens/mobile/mobile_send_screen.dart'
    show MobileSendReviewDraftArgs;
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

class _FakeAddressBookNotifier extends AddressBookNotifier {
  @override
  Future<AddressBookState> build() async => const AddressBookState();
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
        final pending = _discardGate;
        if (pending != null) await pending.future;
        _discarded.add(proposalId);
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

Future<_Harness> _pumpHost(WidgetTester tester) async {
  tester.view.physicalSize = const Size(393, 852);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  late _Harness harness;
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      for (final path in ['/home', '/send'])
        GoRoute(
          path: path,
          builder: (_, _) => Scaffold(body: Text('screen $path')),
        ),
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
        addressBookProvider.overrideWith(_FakeAddressBookNotifier.new),
        ownAccountAddressesProvider.overrideWith((ref) async => const {}),
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
  return harness;
}

void main() {
  setUp(() {
    _discarded.clear();
    _discardGate = null;
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
