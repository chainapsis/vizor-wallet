@Tags(['mobile'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/layout/mobile/mobile_top_nav.dart';
import 'package:zcash_wallet/src/core/navigation/mobile_routes.dart';
import 'package:zcash_wallet/src/core/profile_pictures.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/features/address_book/models/address_book_contact.dart';
import 'package:zcash_wallet/src/features/address_book/providers/address_book_provider.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_composer_preferences_store.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_state_provider.dart';
import 'package:zcash_wallet/src/features/home/screens/mobile/mobile_home_screen.dart';
import 'package:zcash_wallet/src/features/swap/screens/mobile/mobile_swap_screen.dart';
import 'package:zcash_wallet/src/features/swap/widgets/mobile/mobile_swap_review_content.dart';
import 'package:zcash_wallet/src/features/swap/widgets/mobile/mobile_swap_slippage_stepper_modal.dart';
import 'package:zcash_wallet/src/features/swap/widgets/mobile/mobile_swap_address_edit_modal.dart';
import 'package:zcash_wallet/src/features/address_scan/widgets/mobile_address_scan_card.dart';
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
  activeAddress: 'u1swapmodaladdress',
);

AppBootstrapState _bootstrap() => AppBootstrapState(
  initialLocation: '/home',
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
  _MobileDelayedQuoteSwapProvider? swapProvider,
  SwapComposerPreferencesStore? composerPreferencesStore,
  List<AddressBookContact> addressBookContacts = const [],
}) => ProviderScope(
  overrides: [
    appBootstrapProvider.overrideWithValue(_bootstrap()),
    addressBookRepositoryProvider.overrideWithValue(
      _FakeAddressBookRepository(addressBookContacts),
    ),
    if (swapProvider != null)
      swapIntentProvider.overrideWithValue(swapProvider),
    if (composerPreferencesStore != null)
      swapComposerPreferencesStoreProvider.overrideWithValue(
        composerPreferencesStore,
      ),
    syncProvider.overrideWith(
      () => FakeSyncNotifier(
        SyncState(
          accountUuid: 'account-1',
          hasAccountScopedData: true,
          orchardBalance: BigInt.from(100000000),
          spendableBalance: BigInt.from(100000000),
        ),
      ),
    ),
  ],
  child: MaterialApp.router(
    routerConfig: GoRouter(
      initialLocation: '/home',
      routes: buildMobileRoutes(entryRoutes: const []),
    ),
    builder: (_, child) => AppTheme(data: AppThemeData.dark, child: child!),
  ),
);

void main() {
  testWidgets('review actions use the mobile button height', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppTheme(
            data: AppThemeData.dark,
            child: Center(
              child: SizedBox(
                width: 329,
                child: MobileSwapReviewActions(
                  expired: false,
                  starting: false,
                  sendsZec: false,
                  onCancelReview: () {},
                  onReviewAgain: () {},
                  onStartIntent: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(
      tester.getSize(find.byKey(const ValueKey('swap_start_button'))).height,
      50,
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('swap_review_cancel_button')))
          .height,
      50,
    );
  });

  testWidgets('slippage stepper buttons use the mobile button height', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppTheme(
            data: AppThemeData.dark,
            child: MobileSwapSlippageStepperModal(
              slippageBps: 100,
              onSubmitted: (_) {},
              onCancel: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      tester.getSize(find.byKey(const ValueKey('mobile_swap_slippage_minus'))),
      const Size(60, 50),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('mobile_swap_slippage_plus'))),
      const Size(60, 50),
    );
  });

  testWidgets('slippage stepper changes by 0.1 percent per tap', (
    tester,
  ) async {
    var submittedBps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppTheme(
            data: AppThemeData.dark,
            child: MobileSwapSlippageStepperModal(
              slippageBps: 100,
              onSubmitted: (value) => submittedBps = value,
              onCancel: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    TextField field() =>
        tester.widget(find.byKey(const ValueKey('mobile_swap_slippage_value')));

    expect(field().controller!.text, '1');

    await tester.tap(find.byKey(const ValueKey('mobile_swap_slippage_plus')));
    await tester.pump();
    expect(field().controller!.text, '1.1');

    await tester.tap(find.byKey(const ValueKey('mobile_swap_slippage_minus')));
    await tester.pump();
    expect(field().controller!.text, '1');

    await tester.tap(find.byKey(const ValueKey('swap_slippage_update_button')));
    await tester.pump();
    expect(submittedBps, 0);

    await tester.tap(find.byKey(const ValueKey('mobile_swap_slippage_minus')));
    await tester.pump();
    expect(field().controller!.text, '0.9');

    await tester.tap(find.byKey(const ValueKey('swap_slippage_update_button')));
    await tester.pump();
    expect(submittedBps, 90);
  });

  testWidgets('swap composer CTA fits on narrow Android-sized screens', (
    tester,
  ) async {
    await _setNarrowMobileViewport(tester);
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Swap').last);
    await tester.pumpAndSettle();

    expect(find.byType(MobileSwapScreen), findsOneWidget);
    expect(find.text('Add recipient address'), findsOneWidget);
    expect(tester.takeException(), isNull);

    final screen = tester.getRect(find.byType(MaterialApp));
    final button = tester.getRect(
      find.byKey(const ValueKey('mobile_swap_review_button')),
    );
    expect(button.right, lessThanOrEqualTo(screen.right - AppSpacing.sm));
  });

  testWidgets('swap modal rides the root navigator and covers the whole '
      'screen, tab bar included', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Swap').last);
    await tester.pumpAndSettle();
    expect(find.byType(MobileSwapScreen), findsOneWidget);

    await tester.tap(find.text('Add recipient address'));
    await tester.pumpAndSettle();
    expect(find.byType(MobileSwapAddressEditModal), findsOneWidget);

    // The dialog barrier spans the full screen — including the status
    // bar strip at the very top and the floating tab bar at the bottom
    // (neither was covered by the old inline overlay).
    final screen = tester.getRect(find.byType(MaterialApp));
    final barrier = tester.getRect(find.byType(ModalBarrier).last);
    expect(barrier, screen);

    // A tap in the top strip — which the old inline overlay left
    // uncovered — now hits the barrier and dismisses the modal.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.byType(MobileSwapAddressEditModal), findsNothing);
    expect(find.byType(MobileSwapScreen), findsOneWidget);

    // The bottom strip — where the floating tab bar sits — is under the
    // barrier too. The modal card is bottom-anchored with a gap beneath
    // it, so a tap in that gap hits the barrier and dismisses the modal
    // instead of reaching the tab bar to switch branches.
    await tester.tap(find.text('Add recipient address'));
    await tester.pumpAndSettle();
    expect(find.byType(MobileSwapAddressEditModal), findsOneWidget);
    await tester.tapAt(Offset(screen.center.dx, screen.bottom - 4));
    await tester.pumpAndSettle();
    expect(find.byType(MobileSwapAddressEditModal), findsNothing);
    expect(find.byType(MobileSwapScreen), findsOneWidget);
  });

  testWidgets('matched contact shows in the editor and names the chip', (
    tester,
  ) async {
    const contactAddress = '0x52908400098527886e0f7030069857d2e4169ee7';
    await tester.pumpWidget(
      _app(
        addressBookContacts: const [
          AddressBookContact(
            id: 'treasury',
            label: 'Treasury',
            network: AddressBookNetwork.ethereum,
            address: contactAddress,
            profilePictureId: 'default',
            createdAtMs: 0,
            updatedAtMs: 0,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Swap').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add recipient address'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('swap_destination_field')),
      contactAddress,
    );
    await tester.pumpAndSettle();

    // Live match feedback in the editor's reserved message line.
    expect(
      find.byKey(const ValueKey('swap_destination_contact_match')),
      findsOneWidget,
    );
    expect(find.text('Treasury'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('swap_address_update_button')));
    await tester.pumpAndSettle();

    // The composer chip shows the contact name instead of the address.
    final chipText = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const ValueKey('swap_destination_value')),
        matching: find.byType(Text),
      ),
    );
    expect(chipText.data, 'Treasury');
  });

  testWidgets('cancel inside the address editor closes the modal route', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Swap').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add recipient address'));
    await tester.pumpAndSettle();
    expect(find.byType(MobileSwapAddressEditModal), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(MobileSwapAddressEditModal), findsNothing);
    expect(find.byType(MobileSwapScreen), findsOneWidget);
  });

  testWidgets('swap leading back button returns to the previously active '
      'tab', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    expect(find.byType(MobileHomeScreen), findsOneWidget);

    // Switch from Home to the Swap tab; the shell records Home as the
    // previous tab.
    await tester.tap(find.bySemanticsLabel('Swap').last);
    await tester.pumpAndSettle();
    expect(find.byType(MobileSwapScreen), findsOneWidget);

    // The composer's leading back button routes back to where the user
    // came from — the Swap tab is an indexedStack root with no pop stack.
    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(MobileSwapScreen), findsNothing);
    expect(find.byType(MobileHomeScreen), findsOneWidget);
  });

  testWidgets('typing an amount keeps the labels shown and the field intact', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Swap').last);
    await tester.pumpAndSettle();

    // The "You pay" / "You receive" labels stay pinned — they are no longer
    // hidden on input — and the focused amount field keeps the SAME
    // EditableText element across the keystroke rebuild (the title/amount/
    // bottom rows are keyed). Recreating the EditableText is exactly what
    // tears down the live platform text-input connection and dismisses the
    // keyboard on device, so we assert the element survives.
    expect(find.text('You receive'), findsOneWidget);
    final field = find.byKey(const ValueKey('swap_receive_amount_field'));
    final editableFinder = find.descendant(
      of: field,
      matching: find.byType(EditableText),
    );
    await tester.tap(field);
    await tester.pump();
    final EditableTextState stateBefore = tester.state(editableFinder);

    await tester.enterText(field, '5');
    await tester.pump();

    // The label stays put...
    expect(find.text('You receive'), findsOneWidget);
    // ...and the EditableText is the same element, not a recreated one.
    final EditableTextState stateAfter = tester.state(editableFinder);
    expect(identical(stateBefore, stateAfter), isTrue);
    expect(stateAfter.widget.focusNode.hasFocus, isTrue);
  });

  testWidgets(
    'review quote loading shows loader and disables slippage settings',
    (tester) async {
      final swapProvider = _MobileDelayedQuoteSwapProvider();
      await tester.pumpWidget(_app(swapProvider: swapProvider));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Swap').last);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('swap_amount_field')),
        '0.5',
      );
      await tester.tap(find.text('Add recipient address'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('swap_destination_field')),
        '0x52908400098527886e0f7030069857d2e4169ee7',
      );
      await tester.tap(
        find.byKey(const ValueKey('swap_address_update_button')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('mobile_swap_review_button')));
      await tester.pump();

      expect(find.text('Getting quote'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('mobile_swap_review_button')),
          matching: find.byWidgetPredicate(
            (widget) => widget is AppIcon && widget.name == AppIcons.loader,
          ),
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<AppButton>(
              find.byKey(const ValueKey('swap_settings_button')),
            )
            .onPressed,
        isNull,
      );

      await tester.tap(find.byKey(const ValueKey('swap_settings_button')));
      await tester.pump();
      expect(find.byType(MobileSwapSlippageStepperModal), findsNothing);

      swapProvider.completeQuote();
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    },
  );

  testWidgets('unsupported restored asset shows why review is unavailable', (
    tester,
  ) async {
    final baseUsdc = SwapAsset.live(
      assetId: 'removed-base-usdc',
      symbol: 'USDC',
      blockchain: 'base',
      decimals: 6,
    );
    await tester.pumpWidget(
      _app(
        swapProvider: _MobileDelayedQuoteSwapProvider(
          supportedAssets: const [],
        ),
        composerPreferencesStore: _MobileComposerPreferencesStore(
          SwapComposerPreferences(
            direction: SwapDirection.zecToExternal,
            externalAsset: baseUsdc,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Swap').last);
    await tester.pumpAndSettle();

    expect(
      find.text('USDC on Base is not currently supported.'),
      findsOneWidget,
    );
  });

  testWidgets('address editor remember toggle has no nickname or avatar form', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Swap').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add recipient address'));
    await tester.pumpAndSettle();
    expect(find.byType(MobileSwapAddressEditModal), findsOneWidget);

    // Toggling "Remember this address" must save hands-free (auto-named +
    // random avatar, like the desktop editor) — it must NOT reveal a nickname
    // field or an avatar picker.
    final remember = find.byKey(const ValueKey('swap_address_remember_toggle'));
    expect(remember, findsOneWidget);
    await tester.tap(remember);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('swap_address_nickname_field')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('swap_address_avatar_button')),
      findsNothing,
    );
  });

  testWidgets('QR scan returns to address editor before committing address', (
    tester,
  ) async {
    const scannedAddress = '0x52908400098527886e0f7030069857d2e4169ee7';

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Swap').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add recipient address'));
    await tester.pumpAndSettle();
    expect(find.byType(MobileSwapAddressEditModal), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('swap_address_scan_button')));
    await tester.pumpAndSettle();
    expect(find.byType(MobileAddressScanCard), findsOneWidget);

    tester
        .widget<MobileAddressScanCard>(find.byType(MobileAddressScanCard))
        .onScanned(scannedAddress);
    await tester.pumpAndSettle();

    expect(find.byType(MobileSwapAddressEditModal), findsOneWidget);
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('swap_destination_field')),
          )
          .controller
          ?.text,
      scannedAddress,
    );
    expect(
      find.byKey(const ValueKey('swap_address_remember_toggle')),
      findsOneWidget,
    );

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.byType(MobileSwapAddressEditModal), findsNothing);
    expect(find.text('Add recipient address'), findsOneWidget);

    await tester.tap(find.text('Add recipient address'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('swap_address_scan_button')));
    await tester.pumpAndSettle();
    tester
        .widget<MobileAddressScanCard>(find.byType(MobileAddressScanCard))
        .onScanned(scannedAddress);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('swap_address_update_button')));
    await tester.pumpAndSettle();

    expect(find.byType(MobileSwapAddressEditModal), findsNothing);
    expect(find.text('Add recipient address'), findsNothing);
  });

  // The screen-level morph (keyboardOpen ? cross : chevron) is driven by
  // MediaQuery.viewInsets, which the test environment doesn't inset the way a
  // real number-pad does — that wiring is verified on device. Here we cover
  // the MobileTopNav.back mechanism it relies on: a cross backIcon renders as
  // a "Close" affordance rather than the default "Back".
  testWidgets('MobileTopNav.back renders a close affordance for a cross '
      'backIcon', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (_, child) => AppTheme(data: AppThemeData.dark, child: child!),
        home: Builder(
          builder: (context) => MobileTopNav.back(
            title: 'Swap',
            backIcon: AppIcons.cross,
            onBack: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Close'), findsOneWidget);
    expect(find.bySemanticsLabel('Back'), findsNothing);
  });
}

Future<void> _setNarrowMobileViewport(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(432, 960));
  addTearDown(() async {
    await tester.binding.setSurfaceSize(null);
  });
}

class _MobileDelayedQuoteSwapProvider implements SwapProvider {
  _MobileDelayedQuoteSwapProvider({this.supportedAssets = swapExternalAssets});

  final _quoteGate = Completer<void>();
  final List<SwapAsset> supportedAssets;

  void completeQuote() {
    if (!_quoteGate.isCompleted) _quoteGate.complete();
  }

  @override
  String get providerLabel => 'NEAR Intents';

  @override
  Future<List<SwapAsset>> listSupportedExternalAssets() async =>
      supportedAssets;

  @override
  Future<SwapQuote> quote(SwapQuoteRequest request) async {
    await _quoteGate.future;
    return SwapQuote.estimate(
      direction: request.direction,
      externalAsset: request.externalAsset,
      mode: request.mode,
      amount: request.amount,
      providerLabel: providerLabel,
      slippageBps: request.slippageBps ?? 50,
    );
  }

  @override
  Future<SwapIntentSnapshot> startSwap(SwapQuote quote) async {
    return SwapIntentSnapshot.fromQuote(quote);
  }

  @override
  Future<SwapIntentSnapshot> getStatus(
    String intentId, {
    String? depositMemo,
  }) async {
    final quote = SwapQuote.estimate(
      direction: SwapDirection.zecToExternal,
      externalAsset: SwapAsset.usdc,
      sellAmount: 1,
      providerLabel: providerLabel,
    );
    return SwapIntentSnapshot.fromQuote(quote, id: intentId);
  }

  @override
  Future<SwapIntentSnapshot> submitDepositTransaction({
    required String depositAddress,
    required String txHash,
    String? depositMemo,
    String? nearSenderAccount,
  }) async {
    final quote = SwapQuote.estimate(
      direction: SwapDirection.zecToExternal,
      externalAsset: SwapAsset.usdc,
      sellAmount: 1,
      providerLabel: providerLabel,
    );
    return SwapIntentSnapshot.fromQuote(quote, id: depositAddress);
  }
}

class _MobileComposerPreferencesStore implements SwapComposerPreferencesStore {
  _MobileComposerPreferencesStore(this.preferences);

  SwapComposerPreferences? preferences;

  @override
  Future<SwapComposerPreferences?> loadPreferences({
    required String accountUuid,
  }) async => preferences;

  @override
  Future<void> savePreferences({
    required String accountUuid,
    required SwapComposerPreferences preferences,
  }) async {
    this.preferences = preferences;
  }
}

class _FakeAddressBookRepository implements AddressBookRepository {
  _FakeAddressBookRepository(List<AddressBookContact> contacts)
    : contacts = [...contacts];

  final List<AddressBookContact> contacts;

  @override
  Future<List<AddressBookContact>> loadContacts() async => [...contacts];

  @override
  Future<void> saveContacts(List<AddressBookContact> contacts) async {
    this.contacts
      ..clear()
      ..addAll(contacts);
  }
}
