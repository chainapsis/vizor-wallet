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
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/features/address_book/models/address_book_contact.dart';
import 'package:zcash_wallet/src/features/address_book/providers/address_book_provider.dart';
import 'package:zcash_wallet/src/features/pay/models/pay_recent_recipients.dart';
import 'package:zcash_wallet/src/features/pay/screens/mobile/mobile_pay_screen.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_state_provider.dart';
import 'package:zcash_wallet/src/features/swap/screens/mobile/mobile_swap_review_screen.dart';
import 'package:zcash_wallet/src/features/swap/widgets/mobile/mobile_swap_asset_selector_modal.dart';
import 'package:zcash_wallet/src/features/swap/widgets/mobile/mobile_swap_slippage_stepper_modal.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

import '../../fakes/fake_sync_notifier.dart';

const _accountState = AccountState(
  accounts: [
    AccountInfo(
      uuid: 'account-1',
      name: 'Account1',
      order: 0,
      profilePictureId: kDefaultProfilePictureId,
    ),
  ],
  activeAccountUuid: 'account-1',
  activeAddress: 'u1payaddress',
);

AppBootstrapState _bootstrap() => AppBootstrapState(
  initialLocation: '/pay',
  initialAccountState: _accountState,
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.dark,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);

Widget _app({
  bool preservePreparedComposer = false,
  bool usePreparedComposer = false,
  SyncState? syncState,
}) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap()),
      if (usePreparedComposer)
        swapStateProvider.overrideWith(_PreparedPayNotifier.new),
      syncProvider.overrideWith(
        () => FakeSyncNotifier(
          syncState ??
              SyncState(
                accountUuid: 'account-1',
                hasAccountScopedData: true,
                orchardBalance: BigInt.from(14_312_000_000),
                spendableBalance: BigInt.from(14_312_000_000),
                totalBalance: BigInt.from(14_312_000_000),
              ),
        ),
      ),
    ],
    child: MaterialApp(
      home: AppTheme(
        data: AppThemeData.dark,
        child: MobilePayScreen(
          preservePreparedComposer: preservePreparedComposer,
        ),
      ),
    ),
  );
}

class _PreparedPayNotifier extends SwapNotifier {
  @override
  SwapState build() => const SwapState(
    direction: SwapDirection.zecToExternal,
    quoteMode: SwapQuoteMode.exactOutput,
    amountText: '',
    receiveAmountText: '25',
    destinationText: 'So11111111111111111111111111111111111111112',
    externalAsset: SwapAsset.sol,
    reviewVisible: false,
    intents: [],
    payMode: true,
  );
}

class _DelayedPayReviewNotifier extends SwapNotifier {
  _DelayedPayReviewNotifier({this.fail = false});

  final bool fail;
  final Completer<void> _quoteCompleter = Completer<void>();
  int _requestGeneration = 0;

  @override
  SwapState build() => const SwapState(
    direction: SwapDirection.zecToExternal,
    quoteMode: SwapQuoteMode.exactOutput,
    amountText: '0.025',
    receiveAmountText: '10',
    destinationText: '0x1111111111111111111111111111111111111111',
    externalAsset: SwapAsset.usdc,
    reviewVisible: false,
    intents: [],
    payMode: true,
  );

  @override
  Future<void> showReview({bool preserveCurrentReview = false}) async {
    final generation = ++_requestGeneration;
    state = state.copyWith(
      reviewVisible: false,
      quoteLoading: true,
      clearReview: true,
      clearQuoteError: true,
    );
    await _quoteCompleter.future;
    if (generation != _requestGeneration) return;

    if (fail) {
      state = state.copyWith(
        reviewVisible: false,
        quoteLoading: false,
        quoteError: 'Unable to fetch a quote. Try again.',
        clearReview: true,
      );
      return;
    }

    state = state.copyWith(
      reviewVisible: true,
      reviewQuote: SwapQuote.estimate(
        direction: SwapDirection.zecToExternal,
        externalAsset: SwapAsset.usdc,
        mode: SwapQuoteMode.exactOutput,
        amount: 10,
        externalPerZec: 400,
      ),
      reviewAddressPlan: const SwapAddressPlan(
        direction: SwapDirection.zecToExternal,
        externalAsset: SwapAsset.usdc,
        userExternalAddress: '0x1111111111111111111111111111111111111111',
        walletZecAddress: 'u1payreview',
        oneClickRecipient: '0x1111111111111111111111111111111111111111',
        oneClickRefundTo: 'u1payreview',
      ),
      reviewAccountUuid: 'account-1',
      quoteLoading: false,
      clearQuoteError: true,
    );
  }

  @override
  void cancelReviewQuote() {
    _requestGeneration++;
    state = state.copyWith(
      reviewVisible: false,
      quoteLoading: false,
      clearReview: true,
      clearQuoteError: true,
    );
  }

  void completeQuote() => _quoteCompleter.complete();

  bool get quoteLoading => state.quoteLoading;
  bool get reviewVisible => state.reviewVisible;
}

class _RefreshFailPayReviewNotifier extends SwapNotifier {
  var _reviewRequestCount = 0;
  bool preserveCurrentReviewRequested = false;

  @override
  SwapState build() => const SwapState(
    direction: SwapDirection.zecToExternal,
    quoteMode: SwapQuoteMode.exactOutput,
    amountText: '0.025',
    receiveAmountText: '10',
    destinationText: '0x1111111111111111111111111111111111111111',
    externalAsset: SwapAsset.usdc,
    reviewVisible: false,
    intents: [],
    payMode: true,
  );

  @override
  Future<void> showReview({bool preserveCurrentReview = false}) async {
    _reviewRequestCount++;
    if (_reviewRequestCount == 1) {
      state = state.copyWith(
        reviewVisible: true,
        reviewQuote: SwapQuote.estimate(
          direction: SwapDirection.zecToExternal,
          externalAsset: SwapAsset.usdc,
          mode: SwapQuoteMode.exactOutput,
          amount: 10,
          externalPerZec: 400,
          quoteExpiresAt: DateTime.now().add(const Duration(seconds: 4)),
        ),
        reviewAddressPlan: const SwapAddressPlan(
          direction: SwapDirection.zecToExternal,
          externalAsset: SwapAsset.usdc,
          userExternalAddress: '0x1111111111111111111111111111111111111111',
          walletZecAddress: 'u1payreview',
          oneClickRecipient: '0x1111111111111111111111111111111111111111',
          oneClickRefundTo: 'u1payreview',
        ),
        reviewAccountUuid: 'account-1',
        quoteLoading: false,
        clearQuoteError: true,
      );
      return;
    }

    preserveCurrentReviewRequested = preserveCurrentReview;
    state = state.copyWith(
      reviewVisible: false,
      quoteLoading: false,
      quoteError: 'Unable to fetch a quote. Try again.',
      clearReview: true,
    );
  }
}

const _torBlockedPayMessage =
    'Pay is unavailable over Tor because the service blocked this '
    'connection.\nTurn off Tor in Settings to pay.';

class _TorBlockablePayNotifier extends SwapNotifier {
  @override
  SwapState build() => const SwapState(
    direction: SwapDirection.zecToExternal,
    quoteMode: SwapQuoteMode.exactOutput,
    amountText: '0.025',
    receiveAmountText: '10',
    destinationText: '0x1111111111111111111111111111111111111111',
    externalAsset: SwapAsset.usdc,
    reviewVisible: false,
    intents: [],
    payMode: true,
  );

  void blockTokenListOverTor() {
    state = state.copyWith(supportedAssetsError: _torBlockedPayMessage);
  }
}

Widget _routedPayApp(
  GoRouter router,
  SwapNotifier notifier, {
  List<AddressBookContact> contacts = const [],
  AddressBookRepository? addressBookRepository,
}) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap()),
      addressBookRepositoryProvider.overrideWithValue(
        addressBookRepository ?? _FakeAddressBookRepository(contacts),
      ),
      swapStateProvider.overrideWith(() => notifier),
      syncProvider.overrideWith(
        () => FakeSyncNotifier(
          SyncState(
            accountUuid: 'account-1',
            hasAccountScopedData: true,
            orchardBalance: BigInt.from(14_312_000_000),
            spendableBalance: BigInt.from(14_312_000_000),
            totalBalance: BigInt.from(14_312_000_000),
          ),
        ),
      ),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (context, child) => AppTheme(
        data: AppThemeData.dark,
        child: child ?? const SizedBox.shrink(),
      ),
    ),
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

class _DelayedAddressBookRepository implements AddressBookRepository {
  final _contacts = Completer<List<AddressBookContact>>();

  void complete(List<AddressBookContact> contacts) {
    _contacts.complete(contacts);
  }

  @override
  Future<List<AddressBookContact>> loadContacts() => _contacts.future;

  @override
  Future<void> saveContacts(List<AddressBookContact> contacts) async {}
}

Future<void> _setMobileViewport(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets(
    'mobile pay amount uses the completed spendable snapshot during sync',
    (tester) async {
      await _setMobileViewport(tester, const Size(393, 852));
      await tester.pumpWidget(
        _app(
          syncState: SyncState(
            accountUuid: 'account-1',
            hasAccountScopedData: true,
            spendableBalance: BigInt.zero,
            displaySpendableBalance: BigInt.from(100000000),
            displaySpendableFreshness:
                SpendableBalanceFreshness.lastCompletedSync,
            totalBalance: BigInt.from(100000000),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('mobile_pay_amount_input')),
        '10',
      );
      await tester.pump();

      expect(find.text('Not enough ZEC'), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey('mobile_pay_amount_continue_button')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('mobile_pay_recipient_step')),
        findsOneWidget,
      );
    },
  );

  testWidgets('mobile pay follows the amount to recipient flow', (
    tester,
  ) async {
    await _setMobileViewport(tester, const Size(393, 852));
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(MobilePayScreen), findsOneWidget);
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(
      scaffold.backgroundColor,
      AppThemeData.dark.colors.background.window,
    );
    expect(find.text('Pay in USDC'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile_pay_amount_step')),
      findsOneWidget,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('mobile_pay_amount_card'))),
      const Size(361, 240),
    );
    expect(
      tester.getRect(find.byKey(const ValueKey('mobile_pay_amount_card'))).top,
      closeTo(100, 0.01),
    );
    expect(
      find.byKey(const ValueKey('mobile_pay_amount_continue_button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('mobile_pay_recipient_step')),
      findsNothing,
    );

    await tester.enterText(
      find.byKey(const ValueKey('mobile_pay_amount_input')),
      '10',
    );
    await tester.pump();
    expect(tester.takeException(), isNull);

    await tester.tap(
      find.byKey(const ValueKey('mobile_pay_amount_continue_button')),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    expect(find.text('Select Recipient'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile_pay_recipient_step')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('mobile_pay_recipient_field')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('mobile_pay_amount_step')), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('mobile_pay_recipient_input')),
      '0x1111111111111111111111111111111111111111',
    );
    await tester.pump();
    expect(tester.takeException(), isNull);

    expect(
      find.byKey(const ValueKey('mobile_pay_recipient_error')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('mobile_pay_new_address_notice')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('mobile_pay_add_to_contacts_button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('mobile_pay_recipient_continue_button')),
      findsOneWidget,
    );

    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.tap(
      find.byKey(const ValueKey('mobile_pay_add_to_contacts_button')),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('mobile_pay_add_contact_card')),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const ValueKey('mobile_pay_add_contact_label')),
      'Mike',
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(
      tester
          .getRect(find.byKey(const ValueKey('mobile_pay_add_contact_save')))
          .bottom,
      lessThanOrEqualTo(552),
    );

    tester.view.resetViewInsets();
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('mobile_pay_add_contact_card')),
      findsNothing,
    );

    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    expect(find.text('Pay in USDC'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile_pay_amount_step')),
      findsOneWidget,
    );
    final amountInput = tester.widget<TextField>(
      find.byKey(const ValueKey('mobile_pay_amount_input')),
    );
    expect(amountInput.controller?.text, '10');
  });

  testWidgets('contact row selects the clicked identity before review', (
    tester,
  ) async {
    await _setMobileViewport(tester, const Size(393, 852));
    const address = '0x1111111111111111111111111111111111111111';
    const contacts = [
      AddressBookContact(
        id: 'first',
        label: 'First',
        network: AddressBookNetwork.ethereum,
        address: address,
        profilePictureId: 'pfp-01',
        createdAtMs: 0,
        updatedAtMs: 0,
      ),
      AddressBookContact(
        id: 'second',
        label: 'Second',
        network: AddressBookNetwork.ethereum,
        address: address,
        profilePictureId: 'pfp-02',
        createdAtMs: 1,
        updatedAtMs: 1,
      ),
    ];
    Object? reviewExtra;
    final router = GoRouter(
      initialLocation: '/pay',
      routes: [
        GoRoute(
          path: '/pay',
          builder: (_, _) =>
              const MobilePayScreen(preservePreparedComposer: true),
        ),
        GoRoute(
          path: '/pay/review',
          builder: (_, state) {
            reviewExtra = state.extra;
            return const Text('Review route');
          },
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      _routedPayApp(
        router,
        _RefreshFailPayReviewNotifier(),
        contacts: contacts,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('mobile_pay_amount_continue_button')),
    );
    await tester.pumpAndSettle();

    expect(find.text('2 contacts'), findsOneWidget);
    await tester.tap(find.text('Second'));
    await tester.pumpAndSettle();

    expect(find.text('Review route'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('mobile_pay_contact_second')),
        matching: find.byWidgetPredicate(
          (widget) => widget is AppIcon && widget.name == AppIcons.check,
        ),
      ),
      findsOneWidget,
    );
    final firstSelectionSlot = find.byKey(
      const ValueKey('mobile_pay_contact_selection_slot_first'),
    );
    final secondSelectionSlot = find.byKey(
      const ValueKey('mobile_pay_contact_selection_slot_second'),
    );
    expect(firstSelectionSlot, findsOneWidget);
    expect(secondSelectionSlot, findsOneWidget);
    expect(tester.getSize(firstSelectionSlot), const Size.square(18));
    expect(tester.getSize(secondSelectionSlot), const Size.square(18));
    expect(
      tester.getRect(firstSelectionSlot).center.dx,
      tester.getRect(secondSelectionSlot).center.dx,
    );
    expect(
      find.descendant(
        of: firstSelectionSlot,
        matching: find.byWidgetPredicate(
          (widget) => widget is AppIcon && widget.name == AppIcons.check,
        ),
      ),
      findsNothing,
    );
    expect(
      tester.widget(
        find.byKey(const ValueKey('mobile_pay_contact_row_surface_second')),
      ),
      isA<SizedBox>(),
    );
    expect(
      tester.widget<Text>(find.text('Second')).style?.fontWeight,
      tester.widget<Text>(find.text('First')).style?.fontWeight,
    );
    expect(
      find.byKey(const ValueKey('mobile_pay_recipient_continue_button')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('mobile_pay_recipient_continue_button')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Review route'), findsOneWidget);
    expect(reviewExtra, isA<PayRecipientSelection>());
    expect((reviewExtra! as PayRecipientSelection).contactId, 'second');
  });

  testWidgets('recipient actions wait for the initial address book load', (
    tester,
  ) async {
    await _setMobileViewport(tester, const Size(393, 852));
    final repository = _DelayedAddressBookRepository();
    final router = GoRouter(
      initialLocation: '/pay',
      routes: [
        GoRoute(
          path: '/pay',
          builder: (_, _) =>
              const MobilePayScreen(preservePreparedComposer: true),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      _routedPayApp(
        router,
        _RefreshFailPayReviewNotifier(),
        addressBookRepository: repository,
      ),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('mobile_pay_amount_continue_button')),
    );
    await tester.pump();

    var continueButton = tester.widget<AppButton>(
      find.byKey(const ValueKey('mobile_pay_recipient_continue_button')),
    );
    expect(continueButton.onPressed, isNull);

    repository.complete(const []);
    await tester.pumpAndSettle();

    continueButton = tester.widget<AppButton>(
      find.byKey(const ValueKey('mobile_pay_recipient_continue_button')),
    );
    expect(continueButton.onPressed, isNotNull);
  });

  testWidgets(
    'failed review refresh returns to the preserved Pay recipient draft',
    (tester) async {
      await _setMobileViewport(tester, const Size(393, 852));
      final notifier = _RefreshFailPayReviewNotifier();
      final router = GoRouter(
        initialLocation: '/pay',
        routes: [
          GoRoute(
            path: '/pay',
            builder: (_, _) =>
                const MobilePayScreen(preservePreparedComposer: true),
          ),
          GoRoute(
            path: '/pay/review',
            builder: (_, _) => const MobileSwapReviewScreen(payMode: true),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(_routedPayApp(router, notifier));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('mobile_pay_amount_continue_button')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('mobile_pay_recipient_step')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('mobile_pay_recipient_continue_button')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(MobileSwapReviewScreen), findsOneWidget);
      expect(
        find.byKey(const ValueKey('mobile_pay_review_refresh_quote_button')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('mobile_pay_review_refresh_quote_button')),
      );
      await tester.pumpAndSettle();

      expect(notifier.preserveCurrentReviewRequested, isTrue);
      expect(router.routerDelegate.currentConfiguration.uri.path, '/pay');
      expect(
        find.byKey(const ValueKey('mobile_pay_recipient_step')),
        findsOneWidget,
      );
      expect(find.text('Unable to fetch a quote. Try again.'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('mobile_pay_recipient_input')),
            )
            .controller
            ?.text,
        '0x1111111111111111111111111111111111111111',
      );

      await tester.tap(find.bySemanticsLabel('Back'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('mobile_pay_amount_input')),
            )
            .controller
            ?.text,
        '10',
      );
    },
  );

  testWidgets('Pay reuses the Swap asset and slippage sheets', (tester) async {
    await _setMobileViewport(tester, const Size(393, 852));
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('mobile_pay_asset_selector')));
    await tester.pump();
    expect(find.byType(MobileSwapAssetSelectorModal), findsOneWidget);

    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    expect(find.byType(MobileSwapAssetSelectorModal), findsNothing);

    await tester.tap(find.byKey(const ValueKey('mobile_pay_slippage_button')));
    await tester.pump();
    expect(find.byType(MobileSwapSlippageStepperModal), findsOneWidget);

    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    expect(find.byType(MobileSwapSlippageStepperModal), findsNothing);
  });

  testWidgets('prepared Pay retry keeps its amount, asset, and recipient', (
    tester,
  ) async {
    await _setMobileViewport(tester, const Size(393, 852));
    await tester.pumpWidget(
      _app(preservePreparedComposer: true, usePreparedComposer: true),
    );
    await tester.pump();
    await tester.pump();

    final input = tester.widget<TextField>(
      find.byKey(const ValueKey('mobile_pay_amount_input')),
    );
    expect(input.controller?.text, '25');
    expect(find.text('SOL'), findsWidgets);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(MobilePayScreen)),
      listen: false,
    );
    final state = container.read(swapStateProvider);
    expect(state.externalAsset, SwapAsset.sol);
    expect(state.receiveAmountText, '25');
    expect(
      state.destinationText,
      'So11111111111111111111111111111111111111112',
    );
  });

  testWidgets('changing the payout chain clears the previous recipient', (
    tester,
  ) async {
    await _setMobileViewport(tester, const Size(393, 852));
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(MobilePayScreen)),
      listen: false,
    );
    container
        .read(swapStateProvider.notifier)
        .updateDestination('0x1111111111111111111111111111111111111111');
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('mobile_pay_asset_selector')));
    await tester.pump();
    await tester.tap(
      find.byKey(ValueKey('swap_asset_row_${SwapAsset.sol.identityKey}')),
    );
    await tester.pump();

    final state = container.read(swapStateProvider);
    expect(state.externalAsset, SwapAsset.sol);
    expect(state.destinationText, isEmpty);
  });

  testWidgets('leaving recipient while quote loads cannot open review later', (
    tester,
  ) async {
    await _setMobileViewport(tester, const Size(393, 852));
    final notifier = _DelayedPayReviewNotifier();
    final router = GoRouter(
      initialLocation: '/pay',
      routes: [
        GoRoute(
          path: '/pay',
          builder: (_, _) =>
              const MobilePayScreen(preservePreparedComposer: true),
        ),
        GoRoute(
          path: '/pay/review',
          builder: (_, _) => const Scaffold(body: Text('Pay review route')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(_routedPayApp(router, notifier));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('mobile_pay_amount_continue_button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('mobile_pay_recipient_continue_button')),
    );
    await tester.pump();

    expect(find.text('Fetching quote'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('mobile_pay_recipient_continue_button')),
        matching: find.byWidgetPredicate(
          (widget) => widget is AppIcon && widget.name == AppIcons.loader,
        ),
      ),
      findsOneWidget,
    );
    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.pump();
    expect(find.text('Pay in USDC'), findsOneWidget);

    notifier.completeQuote();
    await tester.pumpAndSettle();

    expect(find.text('Pay review route'), findsNothing);
    expect(
      find.byKey(const ValueKey('mobile_pay_amount_step')),
      findsOneWidget,
    );
    expect(notifier.quoteLoading, isFalse);
    expect(notifier.reviewVisible, isFalse);
  });

  testWidgets('quote failures are shown on the active recipient step', (
    tester,
  ) async {
    await _setMobileViewport(tester, const Size(393, 852));
    final notifier = _DelayedPayReviewNotifier(fail: true);
    final router = GoRouter(
      initialLocation: '/pay',
      routes: [
        GoRoute(
          path: '/pay',
          builder: (_, _) =>
              const MobilePayScreen(preservePreparedComposer: true),
        ),
        GoRoute(
          path: '/pay/review',
          builder: (_, _) => const Scaffold(body: Text('Pay review route')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(_routedPayApp(router, notifier));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('mobile_pay_amount_continue_button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('mobile_pay_recipient_continue_button')),
    );
    await tester.pump();

    notifier.completeQuote();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('mobile_pay_recipient_quote_error')),
      findsOneWidget,
    );
    expect(find.text('Unable to fetch a quote. Try again.'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
    expect(find.text('Pay review route'), findsNothing);
  });

  testWidgets('a Tor-blocked token list closes the recipient CTA', (
    tester,
  ) async {
    await _setMobileViewport(tester, const Size(393, 852));
    final notifier = _TorBlockablePayNotifier();
    final router = GoRouter(
      initialLocation: '/pay',
      routes: [
        GoRoute(
          path: '/pay',
          builder: (_, _) =>
              const MobilePayScreen(preservePreparedComposer: true),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(_routedPayApp(router, notifier));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('mobile_pay_amount_continue_button')),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<AppButton>(
            find.byKey(const ValueKey('mobile_pay_recipient_continue_button')),
          )
          .onPressed,
      isNotNull,
    );

    notifier.blockTokenListOverTor();
    await tester.pumpAndSettle();

    expect(find.text(_torBlockedPayMessage), findsOneWidget);
    expect(
      tester
          .widget<AppButton>(
            find.byKey(const ValueKey('mobile_pay_recipient_continue_button')),
          )
          .onPressed,
      isNull,
    );
  });
}
