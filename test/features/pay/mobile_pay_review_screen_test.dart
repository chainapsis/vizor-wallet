@Tags(['mobile'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/profile_pictures.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/features/address_book/models/address_book_contact.dart';
import 'package:zcash_wallet/src/features/address_book/providers/address_book_provider.dart';
import 'package:zcash_wallet/src/features/pay/screens/mobile/mobile_pay_submitted_screen.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_state_provider.dart';
import 'package:zcash_wallet/src/features/swap/screens/mobile/mobile_swap_review_screen.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

import '../../fakes/fake_sync_notifier.dart';

const _recipient = '0x1111111111111111111111111111111111111111';

void main() {
  testWidgets('payment review expires when its countdown reaches zero', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(
      initialLocation: '/pay/review',
      routes: [
        GoRoute(
          path: '/pay/review',
          builder: (_, _) => const MobileSwapReviewScreen(payMode: true),
        ),
        GoRoute(path: '/pay', builder: (_, _) => const SizedBox.shrink()),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      _app(router, quoteLifetime: const Duration(seconds: 6)),
    );
    await tester.pump();

    final confirm = find.byKey(
      const ValueKey('mobile_pay_review_confirm_button'),
    );
    expect(confirm, findsOneWidget);
    expect(tester.widget<AppButton>(confirm).onPressed, isNotNull);
    expect(find.text('Quote expired'), findsNothing);

    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1100)),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Quote expired'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile_pay_review_refresh_quote_button')),
      findsOneWidget,
    );
    expect(confirm, findsNothing);
  });

  testWidgets('payment review opens expired inside the start safety window', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(
      initialLocation: '/pay/review',
      routes: [
        GoRoute(
          path: '/pay/review',
          builder: (_, _) => const MobileSwapReviewScreen(payMode: true),
        ),
        GoRoute(path: '/pay', builder: (_, _) => const SizedBox.shrink()),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      _app(router, quoteLifetime: const Duration(seconds: 4)),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Quote expired'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile_pay_review_refresh_quote_button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('mobile_pay_review_confirm_button')),
      findsNothing,
    );
  });

  testWidgets(
    'payment start blocks cancel, top back, and system back before handoff',
    (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final router = GoRouter(
        initialLocation: '/pay/review',
        routes: [
          GoRoute(
            path: '/pay/review',
            builder: (_, _) => const MobileSwapReviewScreen(payMode: true),
          ),
          GoRoute(
            path: '/pay/submitted/:intentId',
            builder: (_, state) => MobilePaySubmittedScreen(
              intentId: state.pathParameters['intentId'] ?? '',
            ),
          ),
        ],
      );
      addTearDown(router.dispose);

      late _DelayedStartingPayReviewNotifier swapNotifier;
      await tester.pumpWidget(
        _app(
          router,
          quoteLifetime: const Duration(minutes: 5),
          swapNotifier: () {
            swapNotifier = _DelayedStartingPayReviewNotifier();
            return swapNotifier;
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Back'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('mobile_pay_review_confirm_button')),
      );
      await tester.pump();

      final cancel = find.byKey(
        const ValueKey('mobile_pay_review_cancel_button'),
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('mobile_pay_review_confirm_button')),
          matching: find.text('Paying'),
        ),
        findsOneWidget,
      );
      expect(tester.widget<AppButton>(cancel).onPressed, isNull);
      expect(find.bySemanticsLabel('Back'), findsNothing);
      expect(
        tester.widget<PopScope<void>>(find.byType(PopScope<void>)).canPop,
        isFalse,
      );

      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        '/pay/review',
      );

      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        '/pay/review',
      );

      swapNotifier.completeStart(const SwapStartedActivity('intent-123'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.byType(MobilePaySubmittedScreen), findsOneWidget);
      expect(
        tester
            .widget<MobilePaySubmittedScreen>(
              find.byType(MobilePaySubmittedScreen),
            )
            .intentId,
        'intent-123',
      );
      expect(tester.takeException(), isNull);
    },
  );
}

Widget _app(
  GoRouter router, {
  required Duration quoteLifetime,
  SwapNotifier Function()? swapNotifier,
}) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap),
      addressBookRepositoryProvider.overrideWithValue(
        const _EmptyAddressBookRepository(),
      ),
      swapStateProvider.overrideWith(
        swapNotifier ?? () => _ExpiringPayReviewNotifier(quoteLifetime),
      ),
      syncProvider.overrideWith(
        () => FakeSyncNotifier(
          SyncState(
            accountUuid: 'account-1',
            hasAccountScopedData: true,
            spendableBalance: BigInt.from(10000000000),
            totalBalance: BigInt.from(10000000000),
          ),
        ),
      ),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (_, child) => AppTheme(data: AppThemeData.light, child: child!),
    ),
  );
}

final _bootstrap = AppBootstrapState(
  initialLocation: '/pay/review',
  initialAccountState: const AccountState(
    accounts: [
      AccountInfo(
        uuid: 'account-1',
        name: 'Account1',
        order: 0,
        profilePictureId: kDefaultProfilePictureId,
      ),
    ],
    activeAccountUuid: 'account-1',
    activeAddress: 'u1payreview',
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

class _ExpiringPayReviewNotifier extends SwapNotifier {
  _ExpiringPayReviewNotifier(this.quoteLifetime);

  final Duration quoteLifetime;

  @override
  SwapState build() {
    final quote = SwapQuote.estimate(
      direction: SwapDirection.zecToExternal,
      externalAsset: SwapAsset.usdc,
      mode: SwapQuoteMode.exactOutput,
      amount: 10,
      externalPerZec: 400,
      expiryLabel: '0:02',
      quoteExpiresAt: DateTime.now().add(quoteLifetime),
    );
    return const SwapState(
      direction: SwapDirection.zecToExternal,
      quoteMode: SwapQuoteMode.exactOutput,
      amountText: '0.025',
      receiveAmountText: '10',
      destinationText: _recipient,
      externalAsset: SwapAsset.usdc,
      reviewVisible: true,
      intents: [],
      payMode: true,
    ).copyWith(
      reviewQuote: quote,
      reviewAddressPlan: const SwapAddressPlan(
        direction: SwapDirection.zecToExternal,
        externalAsset: SwapAsset.usdc,
        userExternalAddress: _recipient,
        walletZecAddress: 'u1payreview',
        oneClickRecipient: _recipient,
        oneClickRefundTo: 'u1payreview',
      ),
      reviewAccountUuid: 'account-1',
    );
  }
}

class _DelayedStartingPayReviewNotifier extends _ExpiringPayReviewNotifier {
  _DelayedStartingPayReviewNotifier() : super(const Duration(minutes: 5));

  final _startCompleter = Completer<SwapStartResult?>();

  void completeStart(SwapStartResult result) {
    _startCompleter.complete(result);
  }

  @override
  Future<SwapStartResult?> startIntent() async {
    return _startCompleter.future;
  }
}

class _EmptyAddressBookRepository implements AddressBookRepository {
  const _EmptyAddressBookRepository();

  @override
  Future<List<AddressBookContact>> loadContacts() async => const [];

  @override
  Future<void> saveContacts(List<AddressBookContact> contacts) async {}
}
