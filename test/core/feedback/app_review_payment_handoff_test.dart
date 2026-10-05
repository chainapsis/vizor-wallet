@Tags(['mobile'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/core/feedback/app_review.dart';
import 'package:zcash_wallet/src/core/feedback/app_review_host.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/address_book/providers/address_book_provider.dart';
import 'package:zcash_wallet/src/features/send/models/send_prefill_args.dart';
import 'package:zcash_wallet/src/features/send/services/payment_request_precheck.dart';
import 'package:zcash_wallet/src/features/send/services/send_flow.dart';
import 'package:zcash_wallet/src/features/send/widgets/payment_request_host.dart';
import 'package:zcash_wallet/src/features/send/widgets/send_recipient_resolver.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/providers/payment_request_flow_provider.dart';
import 'package:zcash_wallet/src/providers/wallet_provider.dart';
import 'package:zcash_wallet/src/providers/zec_price_change_provider.dart';

import 'app_review_test.dart' show MemoryReviewStore, FakeReviewNative;

const _request = SendPrefillArgs(
  id: 'payment-request',
  source: kPaymentUriPrefillSource,
  address:
      'u1950915183f0fed838d6d2dd92d6f4111ed3c6dd4e3eb19a3702b73d57f73c6dc05121591a83861cd190591',
  amountText: '0.5',
);

// Start with a completed pre-check. Handoff, release retries and cancellation
// use the production notifier methods; only external startup work is replaced.
class _ReadyPaymentRequest extends PaymentRequestFlowNotifier {
  _ReadyPaymentRequest(this.release);
  final Future<bool> Function() release;

  @override
  PaymentRequestFlowState? build() => PaymentRequestFlowState(
    prefill: _request,
    view: PaymentRequestView(
      source: PaymentRequestSource.link,
      address: _request.address,
      amountZecText: '0.5 ZEC',
    ),
    proposal: PaymentRequestProposalHandle(
      reviewArgs: SendReviewArgs(
        proposalId: BigInt.one,
        sendFlowId: 'flow-1',
        proposalAccountUuid: 'account-1',
        address: _request.address,
        addressType: 'unified',
        amountZatoshi: BigInt.from(50000000),
        feeZatoshi: BigInt.from(10000),
        needsSaplingParams: false,
      ),
      discardProposal:
          ({
            required proposalId,
            required sendFlowId,
            required logContext,
            required accountUuid,
          }) => release(),
    ),
  );
}

class _UnlockedSecurity extends AppSecurityNotifier {
  @override
  AppSecurityState build() =>
      const AppSecurityState(isPasswordConfigured: true, isUnlocked: true);
}

class _ExistingWallet extends WalletNotifier {
  @override
  FutureOr<WalletState> build() => const WalletState(hasWallet: true);
}

class _EmptyAddressBook extends AddressBookNotifier {
  @override
  Future<AddressBookState> build() async => const AddressBookState();
}

void main() {
  late AppReviewController controller;
  late FakeReviewNative native;
  late GoRouter router;
  late ProviderContainer container;

  Future<void> mount(
    WidgetTester tester,
    Future<bool> Function() release, {
    bool enabled = true,
  }) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    router = GoRouter(
      initialLocation: '/home',
      routes: [
        for (final path in ['/home', '/send', '/send/review', '/settings'])
          GoRoute(
            path: path,
            builder: (_, _) => Scaffold(body: Text(path)),
          ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appReviewEnabledProvider.overrideWithValue(enabled),
          appReviewControllerProvider.overrideWithValue(controller),
          appSecurityProvider.overrideWith(_UnlockedSecurity.new),
          walletProvider.overrideWith(_ExistingWallet.new),
          paymentRequestFlowProvider.overrideWith(
            () => _ReadyPaymentRequest(release),
          ),
          addressBookProvider.overrideWith(_EmptyAddressBook.new),
          ownAccountAddressesProvider.overrideWith((_) async => {}),
          zecHomeUsdUnitPriceProvider.overrideWithValue(null),
        ],
        child: Consumer(
          builder: (context, _, _) {
            container = ProviderScope.containerOf(context, listen: false);
            return MaterialApp.router(
              routerConfig: router,
              builder: (_, child) => AppTheme(
                data: AppThemeData.light,
                child: PaymentRequestHost(
                  router: router,
                  child: AppReviewHost(router: router, child: child!),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    controller.recordUse();
    expect(native.requests, 0);
  }

  Future<void> idle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
  }

  setUp(() {
    native = FakeReviewNative();
    controller = AppReviewController(
      store: MemoryReviewStore(const AppReviewHistory(launches: 2)),
      native: native,
    );
  });
  tearDown(() {
    router.dispose();
    controller.dispose();
  });

  for (final (action, destination) in [
    ('Edit', '/send'),
    ('Review', '/send/review'),
  ]) {
    testWidgets('$action blocks reviews through slow release and navigation', (
      tester,
    ) async {
      final release = Completer<bool>();
      await mount(tester, () => release.future);
      await tester.tap(find.text(action));
      await tester.pump();
      expect(container.read(paymentRequestFlowProvider), isNull);
      expect(router.state.uri.path, '/home');
      await tester.pump(const Duration(seconds: 3));
      expect(native.preparations, 0);
      expect(native.requests, 0);
      expect(controller.isBusy, isTrue);
      release.complete(true);
      await tester.pumpAndSettle();
      expect(router.state.uri.path, destination);
      expect(controller.isBusy, isFalse);
      await idle(tester);
      expect(native.requests, 0);
      router.go('/home');
      await idle(tester);
      expect(native.requests, 1);
    });

    testWidgets('$action stays blocked during the three-second release retry', (
      tester,
    ) async {
      final retry = Completer<bool>();
      var releases = 0;
      await mount(
        tester,
        () async => ++releases == 1 ? false : await retry.future,
      );
      await tester.tap(find.text(action));
      await tester.pump();
      expect(releases, 1);
      await idle(tester);
      expect(native.preparations, 0);
      expect(controller.isBusy, isTrue);
      await tester.pump(const Duration(seconds: 1));
      expect(releases, 2);
      expect(controller.isBusy, isTrue);
      retry.complete(true);
      await tester.pumpAndSettle();
      expect(router.state.uri.path, destination);
      expect(controller.isBusy, isFalse);
      expect(native.requests, 0);
    });

    testWidgets(
      '$action releases its review guard when navigation overtakes it',
      (tester) async {
        final release = Completer<bool>();
        await mount(tester, () => release.future);
        await tester.tap(find.text(action));
        await tester.pump();
        router.go('/settings');
        await tester.pump();
        release.complete(true);
        await tester.pumpAndSettle();
        expect(router.state.uri.path, '/settings');
        expect(controller.isBusy, isFalse);
        router.go('/home');
        await idle(tester);
        expect(native.requests, 1);
      },
    );

    testWidgets(
      '$action releases its review guard when the request is cancelled',
      (tester) async {
        final release = Completer<bool>();
        await mount(tester, () => release.future);
        await tester.tap(find.text(action));
        await tester.pump();
        container.read(paymentRequestFlowProvider.notifier).clear();
        release.complete(true);
        await tester.pump();
        expect(router.state.uri.path, '/home');
        expect(controller.isBusy, isFalse);
        await tester.pump(const Duration(seconds: 1));
        expect(native.requests, 0);
        await tester.pump(const Duration(seconds: 1));
        await tester.pump();
        expect(native.requests, 1);
      },
    );

    testWidgets(
      '$action works without review tracking when reviews are disabled',
      (tester) async {
        final release = Completer<bool>();
        await mount(tester, () => release.future, enabled: false);
        await tester.tap(find.text(action));
        await tester.pump();
        expect(controller.isBusy, isFalse);
        release.complete(true);
        await tester.pumpAndSettle();
        expect(router.state.uri.path, destination);
        router.go('/home');
        await idle(tester);
        expect(native.preparations, 0);
        expect(native.requests, 0);
      },
    );
  }
}
