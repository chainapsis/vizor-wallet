@Tags(['mobile'])
library;

import 'package:flutter/material.dart'
    show BoxDecoration, MaterialApp, Scaffold, TextField;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/features/address_book/models/address_book_contact.dart';
import 'package:zcash_wallet/src/features/pay/models/pay_recent_recipients.dart';
import 'package:zcash_wallet/src/features/pay/widgets/mobile/mobile_pay_amount_step.dart';
import 'package:zcash_wallet/src/features/pay/widgets/mobile/mobile_pay_recipient_step.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';

const _recipient = '0x1111111111111111111111111111111111111111';
const _otherRecipient = '0x2222222222222222222222222222222222222222';
const _unknownRecipient = '0x3333333333333333333333333333333333333333';
const _solanaRecipient = '4Nd1mYQx4jJXAWe3zUKgnQz5pFa9qTqfjEBWWWk3tS9e';

const _amountState = SwapState(
  direction: SwapDirection.zecToExternal,
  quoteMode: SwapQuoteMode.exactOutput,
  amountText: '1.2',
  receiveAmountText: '12',
  receiveFiatText: '24.50',
  destinationText: '',
  externalAsset: SwapAsset.usdc,
  reviewVisible: false,
  intents: [],
);

final _contacts = [
  AddressBookContact(
    id: 'contact-1',
    label: 'Mike',
    network: AddressBookNetwork.ethereum,
    address: _recipient,
    profilePictureId: 'pfp-01',
    createdAtMs: 0,
    updatedAtMs: 0,
  ),
  AddressBookContact(
    id: 'contact-2',
    label: 'Alice',
    network: AddressBookNetwork.ethereum,
    address: _otherRecipient,
    profilePictureId: 'pfp-02',
    createdAtMs: 0,
    updatedAtMs: 0,
  ),
];

final _recents = [
  PayRecentRecipient(
    address: _recipient,
    amountText: '1.25 USDC',
    lastUsedAt: DateTime(2026, 7, 7),
  ),
  PayRecentRecipient(
    address: _otherRecipient,
    amountText: '4 USDC',
    lastUsedAt: DateTime(2026, 7, 1),
  ),
];

void main() {
  group('MobilePayAmountStep', () {
    testWidgets('matches the mobile amount card and pinned action geometry', (
      tester,
    ) async {
      final controller = TextEditingController(text: '12');
      final focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);

      var assetOpened = false;
      var slippageOpened = false;
      var continued = false;

      await _pumpStep(
        tester,
        MobilePayAmountStep(
          state: _amountState,
          controller: controller,
          focusNode: focusNode,
          zecAvailableZatoshi: BigInt.from(10 * 100000000),
          onAmountChanged: (_) {},
          onFiatAmountChanged: (_) {},
          onToggleFiatInputMode: () {},
          onOpenAssetSelector: () => assetOpened = true,
          slippageLabel: '0.5%',
          onOpenSlippage: () => slippageOpened = true,
          onContinue: () => continued = true,
        ),
      );

      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byKey(const ValueKey('mobile_pay_amount_card'))),
        const Size(361, 240),
      );
      expect(
        tester
            .getRect(find.byKey(const ValueKey('mobile_pay_amount_card')))
            .top,
        16,
      );
      final card = tester.widget<Container>(
        find.byKey(const ValueKey('mobile_pay_amount_card')),
      );
      expect((card.decoration! as BoxDecoration).boxShadow, isNull);
      expect(find.text('Paying in'), findsOneWidget);
      expect(find.text('USDC'), findsNWidgets(2));
      expect(find.text('Ethereum'), findsOneWidget);
      expect(find.text('Estimated:'), findsOneWidget);
      expect(find.text('1.2'), findsOneWidget);
      expect(find.text('Shielded'), findsOneWidget);

      final amountInput = tester.widget<TextField>(
        find.byKey(const ValueKey('mobile_pay_amount_input')),
      );
      expect(amountInput.controller?.text, '12');
      expect(amountInput.textAlign, TextAlign.center);
      expect(amountInput.cursorWidth, 3);
      expect(amountInput.cursorRadius, const Radius.circular(AppRadii.full));

      expect(
        tester.getSize(
          find.byKey(const ValueKey('mobile_pay_slippage_button')),
        ),
        const Size(90, 50),
      );
      expect(
        tester
            .getRect(find.byKey(const ValueKey('mobile_pay_amount_actions')))
            .bottom,
        closeTo(675, 0.01),
      );

      await tester.tap(find.byKey(const ValueKey('mobile_pay_asset_selector')));
      await tester.tap(
        find.byKey(const ValueKey('mobile_pay_slippage_button')),
      );
      await tester.tap(
        find.byKey(const ValueKey('mobile_pay_amount_continue_button')),
      );
      expect(assetOpened, isTrue);
      expect(slippageOpened, isTrue);
      expect(continued, isTrue);
    });

    testWidgets('routes amount editing and shows zero values before input', (
      tester,
    ) async {
      final controller = TextEditingController();
      final focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);

      String? tokenAmount;
      String? fiatAmount;
      var toggled = false;
      await _pumpStep(
        tester,
        MobilePayAmountStep(
          state: _amountState.copyWith(
            amountText: '',
            receiveAmountText: '',
            receiveFiatText: '',
            pricingLoading: true,
          ),
          controller: controller,
          focusNode: focusNode,
          zecAvailableZatoshi: BigInt.from(10 * 100000000),
          onAmountChanged: (value) => tokenAmount = value,
          onFiatAmountChanged: (value) => fiatAmount = value,
          onToggleFiatInputMode: () => toggled = true,
          onOpenAssetSelector: () {},
          slippageLabel: '0.5%',
          onOpenSlippage: () {},
          onContinue: () {},
        ),
      );

      final continueButton = tester.widget<AppButton>(
        find.byKey(const ValueKey('mobile_pay_amount_continue_button')),
      );
      expect(continueButton.onPressed, isNull);
      expect(find.text(r'$ 0'), findsOneWidget);
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('mobile_pay_estimated_zec')),
            )
            .data,
        '0',
      );
      expect(
        find.byKey(const ValueKey('mobile_pay_amount_counterpart_skeleton')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('mobile_pay_estimated_skeleton')),
        findsNothing,
      );

      await tester.enterText(
        find.byKey(const ValueKey('mobile_pay_amount_input')),
        '3.5',
      );
      await tester.tap(
        find.byKey(const ValueKey('mobile_pay_amount_mode_toggle')),
      );
      expect(tokenAmount, '3.5');
      expect(fiatAmount, isNull);
      expect(toggled, isTrue);
    });

    testWidgets(
      'shows conversion skeletons and disables continue while pricing refreshes',
      (tester) async {
        final controller = TextEditingController(text: '12');
        final focusNode = FocusNode();
        addTearDown(controller.dispose);
        addTearDown(focusNode.dispose);

        await _pumpStep(
          tester,
          MobilePayAmountStep(
            state: _amountState.copyWith(pricingLoading: true),
            controller: controller,
            focusNode: focusNode,
            zecAvailableZatoshi: BigInt.from(10 * 100000000),
            onAmountChanged: (_) {},
            onFiatAmountChanged: (_) {},
            onToggleFiatInputMode: () {},
            onOpenAssetSelector: () {},
            slippageLabel: '0.5%',
            onOpenSlippage: () {},
            onContinue: () {},
          ),
        );

        expect(
          find.byKey(const ValueKey('mobile_pay_amount_counterpart_skeleton')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('mobile_pay_estimated_skeleton')),
          findsOneWidget,
        );
        expect(
          tester
              .widget<AppButton>(
                find.byKey(const ValueKey('mobile_pay_amount_continue_button')),
              )
              .onPressed,
          isNull,
        );
      },
    );

    testWidgets('keeps settled values during review quote loading', (
      tester,
    ) async {
      final controller = TextEditingController(text: '12');
      final focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);

      await _pumpStep(
        tester,
        MobilePayAmountStep(
          state: _amountState.copyWith(quoteLoading: true),
          controller: controller,
          focusNode: focusNode,
          zecAvailableZatoshi: BigInt.from(10 * 100000000),
          onAmountChanged: (_) {},
          onFiatAmountChanged: (_) {},
          onToggleFiatInputMode: () {},
          onOpenAssetSelector: () {},
          slippageLabel: '0.5%',
          onOpenSlippage: () {},
          onContinue: () {},
        ),
      );

      expect(
        find.byKey(const ValueKey('mobile_pay_amount_counterpart_skeleton')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('mobile_pay_estimated_skeleton')),
        findsNothing,
      );
      expect(find.text(r'$24.50'), findsOneWidget);
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('mobile_pay_estimated_zec')),
            )
            .data,
        '1.2',
      );
      expect(
        tester
            .widget<AppButton>(
              find.byKey(const ValueKey('mobile_pay_amount_continue_button')),
            )
            .onPressed,
        isNull,
      );
    });
  });

  group('MobilePayRecipientStep', () {
    testWidgets('renders the flat recent and contact lists from Figma', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await _pumpStep(
        tester,
        MobilePayRecipientStep(
          controller: controller,
          typedAddress: '',
          addressError: null,
          contacts: _contacts,
          recents: _recents,
          busy: false,
          externalAsset: SwapAsset.usdc,
          onAddressChanged: (_) {},
          onOpenScanner: () {},
          onChooseRecipient: (_) {},
          onSelectRecipient: () {},
          onAddToContacts: () {},
        ),
      );

      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(
          find.byKey(const ValueKey('mobile_pay_recipient_field')),
        ),
        const Size(361, 60),
      );
      expect(find.text('Ethereum address'), findsOneWidget);
      expect(
        tester
            .getSize(find.byKey(const ValueKey('mobile_pay_recipient_qr_row')))
            .height,
        44,
      );
      expect(find.text('Scan a QR code'), findsOneWidget);
      expect(find.text('Recently sent'), findsOneWidget);
      expect(find.text('-1.25 USDC'), findsOneWidget);
      expect(find.text('2 contacts'), findsOneWidget);
      expect(find.text('Mike'), findsNWidgets(2));
      expect(find.text('Alice'), findsNWidgets(2));
      expect(
        find.byKey(const ValueKey('mobile_pay_recipient_continue_button')),
        findsNothing,
      );
    });

    testWidgets('new address shows the notice and two pinned actions', (
      tester,
    ) async {
      final controller = TextEditingController(text: _unknownRecipient);
      addTearDown(controller.dispose);

      var added = false;
      var continued = false;
      await _pumpStep(
        tester,
        MobilePayRecipientStep(
          controller: controller,
          typedAddress: _unknownRecipient,
          addressError: null,
          contacts: _contacts,
          recents: _recents,
          busy: false,
          externalAsset: SwapAsset.usdc,
          onAddressChanged: (_) {},
          onOpenScanner: () {},
          onChooseRecipient: (_) {},
          onSelectRecipient: () => continued = true,
          onAddToContacts: () => added = true,
        ),
      );

      expect(
        find.byKey(const ValueKey('mobile_pay_new_address_notice')),
        findsOneWidget,
      );
      expect(find.text('New address detected.'), findsOneWidget);
      expect(
        find.text("You haven't interacted with this address before."),
        findsOneWidget,
      );
      expect(find.text('Recently sent'), findsNothing);
      expect(find.text('2 contacts'), findsNothing);
      expect(
        tester
            .getRect(find.byKey(const ValueKey('mobile_pay_recipient_actions')))
            .bottom,
        closeTo(675, 0.01),
      );

      await tester.tap(
        find.byKey(const ValueKey('mobile_pay_add_to_contacts_button')),
      );
      await tester.tap(
        find.byKey(const ValueKey('mobile_pay_recipient_continue_button')),
      );
      expect(added, isTrue);
      expect(continued, isTrue);
    });

    testWidgets('known recent address keeps one row and only Continue', (
      tester,
    ) async {
      final controller = TextEditingController(text: _recipient);
      addTearDown(controller.dispose);

      await _pumpStep(
        tester,
        MobilePayRecipientStep(
          controller: controller,
          typedAddress: _recipient,
          addressError: null,
          contacts: const [],
          recents: [_recents.first],
          busy: false,
          externalAsset: SwapAsset.usdc,
          onAddressChanged: (_) {},
          onOpenScanner: () {},
          onChooseRecipient: (_) {},
          onSelectRecipient: () {},
          onAddToContacts: () {},
        ),
      );

      expect(find.text('Recently sent'), findsOneWidget);
      expect(find.text('-1.25 USDC'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('mobile_pay_add_to_contacts_button')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('mobile_pay_recipient_continue_button')),
        findsOneWidget,
      );
    });

    testWidgets('replaces Continue while the payment quote is loading', (
      tester,
    ) async {
      final controller = TextEditingController(text: _recipient);
      addTearDown(controller.dispose);

      await _pumpStep(
        tester,
        MobilePayRecipientStep(
          controller: controller,
          typedAddress: _recipient,
          addressError: null,
          contacts: const [],
          recents: [_recents.first],
          busy: true,
          externalAsset: SwapAsset.usdc,
          onAddressChanged: (_) {},
          onOpenScanner: () {},
          onChooseRecipient: (_) {},
          onSelectRecipient: () {},
          onAddToContacts: () {},
        ),
      );

      final continueButton = find.byKey(
        const ValueKey('mobile_pay_recipient_continue_button'),
      );
      expect(find.text('Fetching quote'), findsOneWidget);
      expect(find.text('Continue'), findsNothing);
      expect(tester.widget<AppButton>(continueButton).onPressed, isNull);
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('mobile_pay_recipient_input')),
            )
            .enabled,
        isFalse,
      );
    });

    testWidgets('Solana recipient matching remains case-sensitive', (
      tester,
    ) async {
      final typed = _solanaRecipient.toLowerCase();
      final controller = TextEditingController(text: typed);
      addTearDown(controller.dispose);

      await _pumpStep(
        tester,
        MobilePayRecipientStep(
          controller: controller,
          typedAddress: typed,
          addressError: null,
          contacts: const [
            AddressBookContact(
              id: 'sol-contact',
              label: 'Sol friend',
              network: AddressBookNetwork.solana,
              address: _solanaRecipient,
              profilePictureId: 'pfp-01',
              createdAtMs: 0,
              updatedAtMs: 0,
            ),
          ],
          recents: const [PayRecentRecipient(address: _solanaRecipient)],
          busy: false,
          externalAsset: SwapAsset.sol,
          onAddressChanged: (_) {},
          onOpenScanner: () {},
          onChooseRecipient: (_) {},
          onSelectRecipient: () {},
          onAddToContacts: () {},
        ),
      );

      expect(
        find.byKey(const ValueKey('mobile_pay_new_address_notice')),
        findsOneWidget,
      );
      expect(find.text('Sol friend'), findsNothing);
      expect(
        find.byKey(const ValueKey('mobile_pay_add_to_contacts_button')),
        findsOneWidget,
      );
    });
  });
}

Future<void> _pumpStep(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(393, 699);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: AppTheme(
        data: AppThemeData.light,
        child: Scaffold(body: SizedBox(width: 393, height: 699, child: child)),
      ),
    ),
  );
  await tester.pump();
}
