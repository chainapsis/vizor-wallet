import 'package:flutter/material.dart' show Material, MaterialApp, TextField;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/features/pay/screens/pay_screen.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';

void main() {
  testWidgets('pay composer is payment-first exact-output UI', (tester) async {
    await tester.pumpWidget(
      _payComposerHarness(
        width: 488,
        selectedNetworkId: 'eth',
        selectedAssetKey: SwapAsset.usdc.identityKey,
        state: const SwapState(
          direction: SwapDirection.zecToExternal,
          quoteMode: SwapQuoteMode.exactOutput,
          amountText: '',
          receiveAmountText: '25',
          destinationText: '0x1111111111111111111111111111111111111111',
          externalAsset: SwapAsset.usdc,
          reviewVisible: false,
          intents: [],
        ),
      ),
    );

    expect(find.byKey(const ValueKey('pay_composer')), findsOneWidget);
    expect(find.byKey(const ValueKey('pay_page_title')), findsOneWidget);
    expect(
      tester.widget<AppIcon>(find.byKey(const ValueKey('pay_page_icon'))).size,
      20,
    );
    expect(find.text('Pay'), findsOneWidget);
    expect(find.text('Recipient address'), findsOneWidget);
    expect(find.text('Recipient network'), findsOneWidget);
    expect(find.text('Token'), findsNothing);
    expect(find.text('How much should they receive?'), findsNothing);
    expect(find.text("You'll pay from Shielded ZEC"), findsNothing);
    expect(find.text('Continue'), findsOneWidget);
    expect(find.text('Get quote'), findsNothing);
    expect(find.text('Review payment'), findsNothing);
    expect(find.text('Review swap'), findsNothing);

    final addressRect = tester.getRect(
      find.byKey(const ValueKey('pay_recipient_address_field')),
    );
    final addressMessageRect = tester.getRect(
      find.text('Network and token unlock after this address.'),
    );
    final networkRect = tester.getRect(
      find.byKey(const ValueKey('pay_recipient_network_step')),
    );
    final continueRect = tester.getRect(
      find.byKey(const ValueKey('pay_continue_button')),
    );

    expect(addressRect.top, lessThan(networkRect.top));
    expect(
      networkRect.top - addressRect.bottom,
      greaterThanOrEqualTo(AppSpacing.sm),
    );
    expect(
      networkRect.top - addressMessageRect.bottom,
      greaterThanOrEqualTo(AppSpacing.sm),
    );
    expect(
      continueRect.top - networkRect.bottom,
      greaterThanOrEqualTo(AppSpacing.md),
    );

    await tester.tap(find.byKey(const ValueKey('pay_continue_button')));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('pay_recipient_address_field')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('pay_recipient_network_step')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('pay_recipient_summary_panel')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('pay_amount_step_label')), findsOneWidget);
    expect(find.byKey(const ValueKey('pay_token_picker')), findsOneWidget);
    expect(find.text('Token'), findsOneWidget);
    expect(find.text('How much should they receive?'), findsOneWidget);
    expect(find.text("You'll pay from Shielded ZEC"), findsNothing);
    expect(find.byKey(const ValueKey('pay_zec_summary_panel')), findsNothing);
    expect(find.text('Get quote'), findsOneWidget);
    expect(find.text('Review payment'), findsNothing);
    expect(find.byKey(const ValueKey('pay_rate_hint')), findsOneWidget);
    expect(find.textContaining('1 ZEC ='), findsOneWidget);
    expect(
      find.byKey(const ValueKey('pay_amount_mode_toggle')),
      findsOneWidget,
    );

    final stepLabelRect = tester.getRect(
      find.byKey(const ValueKey('pay_amount_step_label')),
    );
    final tokenRect = tester.getRect(
      find.byKey(const ValueKey('pay_token_picker')),
    );
    final amountRect = tester.getRect(
      find.byKey(const ValueKey('pay_recipient_amount_field')),
    );
    expect(
      find.byKey(const ValueKey('pay_recipient_amount_shell')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('pay_recipient_amount_symbol')),
      findsOneWidget,
    );
    final amountDisplayRect = tester.getRect(
      find.byKey(const ValueKey('pay_recipient_amount_display')),
    );
    final amountInput = tester.widget<TextField>(
      find.byKey(const ValueKey('pay_recipient_amount_input')),
    );
    final rateRect = tester.getRect(
      find.byKey(const ValueKey('pay_rate_hint')),
    );
    final quoteRect = tester.getRect(
      find.byKey(const ValueKey('pay_get_quote_button')),
    );

    expect(stepLabelRect.top, lessThan(tokenRect.top));
    expect(tokenRect.top, lessThan(amountRect.top));
    expect(amountRect.top, lessThan(quoteRect.top));
    expect(amountDisplayRect.bottom, lessThan(rateRect.top));
    expect(amountDisplayRect.height, greaterThanOrEqualTo(70));
    expect(amountDisplayRect.height, greaterThan(tokenRect.height));
    expect(amountInput.style?.fontSize, AppTypography.displayLarge.fontSize);
    expect(amountInput.textAlign, TextAlign.right);
    expect(
      tokenRect.top - stepLabelRect.bottom,
      greaterThanOrEqualTo(AppSpacing.s),
    );
    expect(
      amountRect.top - tokenRect.bottom,
      greaterThanOrEqualTo(AppSpacing.sm),
    );
    expect(
      quoteRect.top - amountRect.bottom,
      greaterThanOrEqualTo(AppSpacing.md),
    );
  });

  testWidgets('pay recipient field exposes contact scan and clear actions', (
    tester,
  ) async {
    String? destination;
    var contactsOpened = false;
    var scannerOpened = false;

    await tester.pumpWidget(
      _payComposerHarness(
        width: 488,
        selectedNetworkId: 'eth',
        selectedAssetKey: SwapAsset.usdc.identityKey,
        state: const SwapState(
          direction: SwapDirection.zecToExternal,
          quoteMode: SwapQuoteMode.exactOutput,
          amountText: '',
          receiveAmountText: '',
          destinationText: '0x1111111111111111111111111111111111111111',
          externalAsset: SwapAsset.usdc,
          reviewVisible: false,
          intents: [],
        ),
        onDestinationChanged: (value) => destination = value,
        onOpenContactPicker: () => contactsOpened = true,
        onOpenAddressScanner: () => scannerOpened = true,
      ),
    );

    expect(
      find.byKey(const ValueKey('pay_recipient_clear_button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('pay_recipient_contacts_button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('pay_recipient_scan_button')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('pay_recipient_clear_button')));
    expect(destination, '');

    await tester.tap(
      find.byKey(const ValueKey('pay_recipient_contacts_button')),
    );
    expect(contactsOpened, isTrue);

    await tester.tap(find.byKey(const ValueKey('pay_recipient_scan_button')));
    expect(scannerOpened, isTrue);
  });

  testWidgets('pay composer does not overlap on narrow widths', (tester) async {
    await tester.pumpWidget(
      _payComposerHarness(
        width: 320,
        selectedNetworkId: 'eth',
        selectedAssetKey: SwapAsset.usdc.identityKey,
        state: const SwapState(
          direction: SwapDirection.zecToExternal,
          quoteMode: SwapQuoteMode.exactOutput,
          amountText: '',
          receiveAmountText: '123456.78',
          destinationText: '0x1111111111111111111111111111111111111111',
          externalAsset: SwapAsset.usdc,
          reviewVisible: false,
          intents: [],
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('pay_continue_button')));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('pay_token_picker')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('pay_recipient_amount_field')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('pay_get_quote_button')), findsOneWidget);
  });

  testWidgets(
    'pay composer requires network selection after address inference',
    (tester) async {
      String? selectedNetworkId;

      await tester.pumpWidget(
        _payComposerHarness(
          width: 488,
          state: const SwapState(
            direction: SwapDirection.zecToExternal,
            quoteMode: SwapQuoteMode.exactOutput,
            amountText: '',
            receiveAmountText: '',
            destinationText: 'So11111111111111111111111111111111111111112',
            externalAsset: SwapAsset.usdc,
            reviewVisible: false,
            intents: [],
          ),
          onNetworkSelected: (value) => selectedNetworkId = value,
        ),
      );

      expect(find.text('Choose one of the detected networks.'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('pay_network_option_sol')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('pay_token_picker')), findsNothing);
      expect(
        find.byKey(const ValueKey('pay_recipient_amount_field')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('pay_continue_button')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('pay_network_option_sol')));

      expect(selectedNetworkId, 'sol');
    },
  );

  testWidgets('pay composer shows the amount wireframe after continue', (
    tester,
  ) async {
    await tester.pumpWidget(
      _payComposerHarness(
        width: 488,
        selectedNetworkId: 'eth',
        state: const SwapState(
          direction: SwapDirection.zecToExternal,
          quoteMode: SwapQuoteMode.exactOutput,
          amountText: '',
          receiveAmountText: '',
          destinationText: '0x1111111111111111111111111111111111111111',
          externalAsset: SwapAsset.usdc,
          reviewVisible: false,
          intents: [],
        ),
      ),
    );

    expect(find.byKey(const ValueKey('pay_token_picker')), findsNothing);
    expect(
      find.byKey(const ValueKey('pay_recipient_amount_field')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('pay_get_quote_button')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('pay_continue_button')));
    await tester.pump();

    expect(find.byKey(const ValueKey('pay_token_picker')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('pay_recipient_amount_field')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('pay_get_quote_button')), findsOneWidget);

    await tester.pumpWidget(
      _payComposerHarness(
        width: 488,
        selectedNetworkId: 'eth',
        selectedAssetKey: SwapAsset.usdc.identityKey,
        state: const SwapState(
          direction: SwapDirection.zecToExternal,
          quoteMode: SwapQuoteMode.exactOutput,
          amountText: '',
          receiveAmountText: '',
          destinationText: '0x1111111111111111111111111111111111111111',
          externalAsset: SwapAsset.usdc,
          reviewVisible: false,
          intents: [],
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('pay_recipient_amount_field')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('pay_get_quote_button')), findsOneWidget);
  });

  testWidgets('pay amount input switches between token and USD modes', (
    tester,
  ) async {
    SwapAmountInputSide? toggledSide;
    String? tokenInput;
    String? fiatInput;

    await tester.pumpWidget(
      _payComposerHarness(
        width: 488,
        selectedNetworkId: 'eth',
        selectedAssetKey: SwapAsset.usdc.identityKey,
        state: const SwapState(
          direction: SwapDirection.zecToExternal,
          quoteMode: SwapQuoteMode.exactOutput,
          amountText: '',
          receiveAmountText: '25',
          receiveFiatText: '',
          destinationText: '0x1111111111111111111111111111111111111111',
          externalAsset: SwapAsset.usdc,
          reviewVisible: false,
          intents: [],
        ),
        onAmountChanged: (value) => tokenInput = value,
        onReceiveAmountFiatChanged: (value) => fiatInput = value,
        onToggleFiatInputMode: (side) => toggledSide = side,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('pay_continue_button')));
    await tester.pump();

    var amountInput = tester.widget<TextField>(
      find.byKey(const ValueKey('pay_recipient_amount_input')),
    );
    var amountSymbol = tester.widget<Text>(
      find.byKey(const ValueKey('pay_recipient_amount_symbol')),
    );

    expect(amountInput.controller?.text, '25');
    expect(amountSymbol.data, 'USDC');

    await tester.enterText(
      find.byKey(const ValueKey('pay_recipient_amount_input')),
      '26',
    );

    expect(tokenInput, '26');
    expect(fiatInput, isNull);

    await tester.tap(find.byKey(const ValueKey('pay_amount_mode_usd')));

    expect(toggledSide, SwapAmountInputSide.receive);

    await tester.pumpWidget(
      _payComposerHarness(
        width: 488,
        selectedNetworkId: 'eth',
        selectedAssetKey: SwapAsset.usdc.identityKey,
        state: const SwapState(
          direction: SwapDirection.zecToExternal,
          quoteMode: SwapQuoteMode.exactOutput,
          amountText: '',
          amountInputMode: SwapAmountInputMode.fiat,
          receiveAmountText: '100',
          receiveAmountInputMode: SwapAmountInputMode.fiat,
          receiveFiatText: '100',
          destinationText: '0x1111111111111111111111111111111111111111',
          externalAsset: SwapAsset.usdc,
          reviewVisible: false,
          intents: [],
        ),
        onAmountChanged: (value) => tokenInput = value,
        onReceiveAmountFiatChanged: (value) => fiatInput = value,
        onToggleFiatInputMode: (side) => toggledSide = side,
      ),
    );
    await tester.pump();

    amountInput = tester.widget<TextField>(
      find.byKey(const ValueKey('pay_recipient_amount_input')),
    );
    amountSymbol = tester.widget<Text>(
      find.byKey(const ValueKey('pay_recipient_amount_symbol')),
    );

    expect(amountInput.controller?.text, '100');
    expect(amountSymbol.data, 'USD');

    await tester.enterText(
      find.byKey(const ValueKey('pay_recipient_amount_input')),
      '125.50',
    );

    expect(fiatInput, '125.50');

    await tester.tap(find.byKey(const ValueKey('pay_amount_mode_token')));

    expect(toggledSide, SwapAmountInputSide.receive);
  });

  testWidgets('pay token picker opens the full asset selector', (tester) async {
    var selectorOpened = false;

    await tester.pumpWidget(
      _payComposerHarness(
        width: 488,
        selectedNetworkId: 'eth',
        selectedAssetKey: SwapAsset.usdc.identityKey,
        state: const SwapState(
          direction: SwapDirection.zecToExternal,
          quoteMode: SwapQuoteMode.exactOutput,
          amountText: '',
          receiveAmountText: '25',
          destinationText: '0x1111111111111111111111111111111111111111',
          externalAsset: SwapAsset.usdc,
          slippageBps: 100,
          reviewVisible: false,
          intents: [],
        ),
        onOpenAssetSelector: () => selectorOpened = true,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('pay_continue_button')));
    await tester.pump();

    expect(find.byKey(const ValueKey('pay_token_more_button')), findsOneWidget);
    expect(find.byKey(const ValueKey('pay_token_option_wbtc')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('pay_token_more_button')));

    expect(selectorOpened, isTrue);
  });

  testWidgets('pay token picker keeps a selected overflow token visible', (
    tester,
  ) async {
    await tester.pumpWidget(
      _payComposerHarness(
        width: 488,
        selectedNetworkId: 'eth',
        selectedAssetKey: SwapAsset.wbtc.identityKey,
        state: const SwapState(
          direction: SwapDirection.zecToExternal,
          quoteMode: SwapQuoteMode.exactOutput,
          amountText: '',
          receiveAmountText: '0.01',
          destinationText: '0x1111111111111111111111111111111111111111',
          externalAsset: SwapAsset.wbtc,
          reviewVisible: false,
          intents: [],
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('pay_continue_button')));
    await tester.pump();

    expect(find.byKey(const ValueKey('pay_token_option_wbtc')), findsOneWidget);
    expect(find.byKey(const ValueKey('pay_token_more_button')), findsOneWidget);
  });
}

Widget _payComposerHarness({
  required double width,
  required SwapState state,
  String? selectedNetworkId,
  String? selectedAssetKey,
  ValueChanged<String>? onAmountChanged,
  ValueChanged<String>? onReceiveAmountFiatChanged,
  ValueChanged<String>? onNetworkSelected,
  ValueChanged<String>? onDestinationChanged,
  ValueChanged<SwapAmountInputSide>? onToggleFiatInputMode,
  VoidCallback? onOpenAssetSelector,
  VoidCallback? onOpenAddressScanner,
  VoidCallback? onOpenContactPicker,
}) {
  return MaterialApp(
    home: AppTheme(
      data: AppThemeData.light,
      child: Material(
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: SingleChildScrollView(
            child: Center(
              child: SizedBox(
                width: width,
                child: PayComposer(
                  state: state,
                  selectedNetworkId: selectedNetworkId,
                  selectedAssetKey: selectedAssetKey,
                  zecAvailableZatoshi: BigInt.from(14_312_000_000),
                  onAmountChanged: onAmountChanged ?? (_) {},
                  onReceiveAmountFiatChanged:
                      onReceiveAmountFiatChanged ?? (_) {},
                  onToggleFiatInputMode: onToggleFiatInputMode ?? (_) {},
                  onDestinationChanged: onDestinationChanged ?? (_) {},
                  onNetworkSelected: onNetworkSelected ?? (_) {},
                  onAssetSelected: (_) {},
                  onOpenAssetSelector: onOpenAssetSelector ?? () {},
                  onOpenAddressScanner: onOpenAddressScanner ?? () {},
                  onOpenContactPicker: onOpenContactPicker ?? () {},
                  onReviewPayment: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
