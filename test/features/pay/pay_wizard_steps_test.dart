import 'package:flutter/material.dart' show Material, MaterialApp, TextField;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon_hover_button.dart';
import 'package:zcash_wallet/src/core/widgets/app_profile_picture.dart';
import 'package:zcash_wallet/src/features/address_book/models/address_book_contact.dart';
import 'package:zcash_wallet/src/features/pay/models/pay_recent_recipients.dart';
import 'package:zcash_wallet/src/features/pay/widgets/pay_add_contact_modal.dart';
import 'package:zcash_wallet/src/features/pay/widgets/pay_amount_step.dart';
import 'package:zcash_wallet/src/features/pay/widgets/pay_recipient_step.dart';
import 'package:zcash_wallet/src/features/pay/widgets/pay_review_step.dart';
import 'package:zcash_wallet/src/features/pay/widgets/pay_wizard_stepper.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';

const _contactAddress = '0x52908400098527886E0F7030069857D2E4169EE7';
const _recentAddress = '0x1111111111111111111111111111111111111111';
const _unknownAddress = '0x2222222222222222222222222222222222222222';
const _solanaAddress = '4Nd1mYQx4jJXAWe3zUKgnQz5pFa9qTqfjEBWWWk3tS9e';

final _contact = AddressBookContact(
  id: 'mike',
  label: 'Mike',
  network: AddressBookNetwork.ethereum,
  address: _contactAddress,
  profilePictureId: 'pfp-01',
  createdAtMs: 0,
  updatedAtMs: 0,
);

final _recentContact = AddressBookContact(
  id: 'recent-mike',
  label: 'Recent Mike',
  network: AddressBookNetwork.ethereum,
  address: _recentAddress,
  profilePictureId: 'pfp-02',
  createdAtMs: 0,
  updatedAtMs: 0,
);

Widget _harness(Widget child) {
  return MaterialApp(
    home: AppTheme(
      data: AppThemeData.light,
      child: Material(
        child: SingleChildScrollView(
          child: Center(child: SizedBox(width: 396, child: child)),
        ),
      ),
    ),
  );
}

Widget _recipientStep({
  String typedAddress = '',
  String? addressError,
  List<AddressBookContact> contacts = const [],
  List<PayRecentRecipient> recents = const [],
  ValueChanged<String>? onChooseRecipient,
  VoidCallback? onSelectRecipient,
  VoidCallback? onAddToContacts,
  String? quoteError,
  bool actionsEnabled = true,
}) {
  final step = PayRecipientStep(
    controller: TextEditingController(text: typedAddress),
    typedAddress: typedAddress,
    addressError: addressError,
    contacts: contacts,
    recents: recents,
    busy: false,
    onAddressChanged: (_) {},
    onOpenScanner: () {},
    onChooseRecipient: onChooseRecipient ?? (_) {},
  );
  final actions = PayRecipientActions(
    typedAddress: typedAddress,
    addressError: addressError,
    contacts: contacts,
    busy: false,
    enabled: actionsEnabled,
    quoteError: quoteError,
    onSelectRecipient: onSelectRecipient ?? () {},
    onAddToContacts: onAddToContacts ?? () {},
  );
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [step, if (actions.visible) actions],
  );
}

SwapQuote _payQuote() {
  return SwapQuote.estimate(
    direction: SwapDirection.zecToExternal,
    externalAsset: SwapAsset.usdc,
    mode: SwapQuoteMode.exactOutput,
    amount: 990,
  );
}

const _amountState = SwapState(
  direction: SwapDirection.zecToExternal,
  quoteMode: SwapQuoteMode.exactOutput,
  amountText: '0.25',
  receiveAmountText: '25',
  receiveFiatText: '25.00',
  destinationText: '',
  externalAsset: SwapAsset.usdc,
  reviewVisible: false,
  intents: [],
  payMode: true,
);

void main() {
  test('recipient contact lookup preserves case-sensitive addresses', () {
    final contact = AddressBookContact(
      id: 'solana',
      label: 'Solana contact',
      network: AddressBookNetwork.solana,
      address: _solanaAddress,
      profilePictureId: 'pfp-01',
      createdAtMs: 0,
      updatedAtMs: 0,
    );

    expect(
      payRecipientContactForAddress(
        [contact],
        _solanaAddress.replaceFirst('N', 'n'),
      ),
      isNull,
    );
  });

  group('PayAddContactModal', () {
    testWidgets('uses one generated picture for the preview and save', (
      tester,
    ) async {
      String? savedPicture;
      var generatorCalls = 0;
      await tester.pumpWidget(
        _harness(
          PayAddContactModal(
            network: AddressBookNetwork.ethereum,
            address: _unknownAddress,
            onCancel: () {},
            onSave: (_, picture) async => savedPicture = picture,
            profilePictureIdGenerator: () {
              generatorCalls += 1;
              return 'pfp-09';
            },
          ),
        ),
      );

      expect(generatorCalls, 1);
      expect(
        tester
            .widget<AppProfilePicture>(find.byType(AppProfilePicture))
            .profilePictureId,
        'pfp-09',
      );

      await tester.enterText(
        find.byKey(const ValueKey('pay_add_contact_label_field')),
        'Mike',
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('pay_add_contact_save_button')),
      );
      await tester.pump();

      expect(savedPicture, 'pfp-09');
      expect(generatorCalls, 1);
    });

    testWidgets('waits for persistence and recovers from a save failure', (
      tester,
    ) async {
      var attempts = 0;
      await tester.pumpWidget(
        _harness(
          PayAddContactModal(
            network: AddressBookNetwork.ethereum,
            address: _unknownAddress,
            onCancel: () {},
            onSave: (_, _) async {
              attempts += 1;
              throw StateError('save failed');
            },
          ),
        ),
      );

      await tester.enterText(
        find.byKey(const ValueKey('pay_add_contact_label_field')),
        'Mike',
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('pay_add_contact_save_button')),
      );
      await tester.pumpAndSettle();

      expect(attempts, 1);
      expect(
        find.text("Couldn't save this contact. Try again."),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('pay_add_contact_save_button')),
        findsOneWidget,
      );
    });
  });

  group('PayAmountStep', () {
    testWidgets('shows zero values without loading skeletons before input', (
      tester,
    ) async {
      final controller = TextEditingController();
      final focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(
        _harness(
          PayAmountStep(
            state: _amountState.copyWith(
              amountText: '',
              receiveAmountText: '',
              receiveFiatText: '',
              pricingLoading: true,
            ),
            controller: controller,
            focusNode: focusNode,
            onAmountChanged: (_) {},
            onFiatAmountChanged: (_) {},
            onToggleFiatInputMode: () {},
            onOpenAssetSelector: () {},
          ),
        ),
      );

      expect(find.text(r'$ 0'), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('pay_estimated_spend')))
            .data,
        '0',
      );
      expect(
        find.byKey(const ValueKey('pay_amount_counterpart_loading')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('pay_estimated_spend_loading')),
        findsNothing,
      );
    });

    testWidgets(
      'animates conversion placeholders while the pricing snapshot refreshes',
      (tester) async {
        final controller = TextEditingController(text: '25');
        final focusNode = FocusNode();
        addTearDown(controller.dispose);
        addTearDown(focusNode.dispose);

        await tester.pumpWidget(
          _harness(
            PayAmountStep(
              state: _amountState.copyWith(pricingLoading: true),
              controller: controller,
              focusNode: focusNode,
              onAmountChanged: (_) {},
              onFiatAmountChanged: (_) {},
              onToggleFiatInputMode: () {},
              onOpenAssetSelector: () {},
            ),
          ),
        );

        expect(
          find.byKey(const ValueKey('pay_amount_counterpart_loading')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('pay_estimated_spend_loading')),
          findsOneWidget,
        );
        final firstPainter = tester
            .widget<CustomPaint>(
              find.descendant(
                of: find.byKey(
                  const ValueKey('pay_amount_counterpart_loading'),
                ),
                matching: find.byType(CustomPaint),
              ),
            )
            .painter;

        await tester.pump(const Duration(milliseconds: 100));

        final nextPainter = tester
            .widget<CustomPaint>(
              find.descendant(
                of: find.byKey(
                  const ValueKey('pay_amount_counterpart_loading'),
                ),
                matching: find.byType(CustomPaint),
              ),
            )
            .painter;
        expect(identical(firstPainter, nextPainter), isFalse);
      },
    );

    testWidgets('does not use review quote loading for amount placeholders', (
      tester,
    ) async {
      final controller = TextEditingController(text: '25');
      final focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(
        _harness(
          PayAmountStep(
            state: _amountState.copyWith(quoteLoading: true),
            controller: controller,
            focusNode: focusNode,
            onAmountChanged: (_) {},
            onFiatAmountChanged: (_) {},
            onToggleFiatInputMode: () {},
            onOpenAssetSelector: () {},
          ),
        ),
      );

      expect(
        find.byKey(const ValueKey('pay_amount_counterpart_loading')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('pay_estimated_spend_loading')),
        findsNothing,
      );
      expect(find.text(r'$25.00'), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('pay_estimated_spend')))
            .data,
        '0.25',
      );
    });

    testWidgets('matches the desktop amount card geometry and typography', (
      tester,
    ) async {
      final controller = TextEditingController(text: '25');
      final focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(
        _harness(
          PayAmountStep(
            state: _amountState,
            controller: controller,
            focusNode: focusNode,
            onAmountChanged: (_) {},
            onFiatAmountChanged: (_) {},
            onToggleFiatInputMode: () {},
            onOpenAssetSelector: () {},
          ),
        ),
      );

      expect(
        tester.getSize(find.byKey(const ValueKey('pay_amount_card'))).height,
        316,
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('pay_amount_step'))).height,
        416,
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('pay_amount_input')))
            .style
            ?.fontSize,
        AppTypography.displayLarge.fontSize,
      );
    });

    testWidgets('uses the fixed-width action and shared validation contract', (
      tester,
    ) async {
      var continued = false;
      await tester.pumpWidget(
        _harness(
          Center(
            child: PayAmountAction(
              state: _amountState,
              onContinue: () => continued = true,
            ),
          ),
        ),
      );

      expect(
        tester
            .getSize(find.byKey(const ValueKey('pay_amount_continue_button')))
            .width,
        196,
      );
      await tester.tap(
        find.byKey(const ValueKey('pay_amount_continue_button')),
      );
      expect(continued, isTrue);
    });
  });

  group('PayWizardStepper', () {
    testWidgets('marks completed, active, and upcoming steps', (tester) async {
      var tapped = -1;
      await tester.pumpWidget(
        _harness(
          PayWizardStepper(currentIndex: 1, onStepSelected: (i) => tapped = i),
        ),
      );

      expect(find.text('Amount'), findsOneWidget);
      expect(find.text('Recipient'), findsOneWidget);
      expect(find.text('Review'), findsOneWidget);
      // Completed step renders a check instead of its number.
      expect(find.text('1'), findsNothing);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      final activeIcon = tester.widget<Container>(
        find.byKey(const ValueKey('pay_wizard_step_icon_1')),
      );
      expect(
        (activeIcon.decoration! as BoxDecoration).color,
        AppThemeData.light.colors.background.raised,
      );

      await tester.tap(find.byKey(const ValueKey('pay_wizard_step_back_0')));
      expect(tapped, 0);
    });

    testWidgets('does not make upcoming steps tappable', (tester) async {
      await tester.pumpWidget(
        _harness(PayWizardStepper(currentIndex: 0, onStepSelected: (_) {})),
      );
      expect(
        find.byKey(const ValueKey('pay_wizard_step_back_1')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('pay_wizard_step_back_2')),
        findsNothing,
      );
    });
  });

  group('PayRecipientStep', () {
    testWidgets('empty input decorates recent contacts and shows no CTA', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          _recipientStep(
            contacts: [_contact, _recentContact],
            recents: const [
              PayRecentRecipient(
                address: _recentAddress,
                amountText: '-24 USDC',
              ),
            ],
          ),
        ),
      );

      expect(
        find.byKey(const ValueKey('pay_recent_recipients_card')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('pay_contacts_card')), findsOneWidget);
      expect(find.text('Mike'), findsOneWidget);
      expect(find.text('Recent Mike'), findsWidgets);
      expect(find.text('-24 USDC'), findsOneWidget);
      final userIcon = tester.widget<AppIcon>(
        find.descendant(
          of: find.byKey(const ValueKey('pay_recipient_search_field')),
          matching: find.byWidgetPredicate(
            (widget) => widget is AppIcon && widget.name == AppIcons.user,
          ),
        ),
      );
      expect(userIcon.color, AppThemeData.light.colors.icon.regular);
      final scanButton = tester.widget<AppIconHoverButton>(
        find.byKey(const ValueKey('pay_recipient_scan_button')),
      );
      expect(scanButton.iconColor, AppThemeData.light.colors.icon.regular);
      expect(
        find.byKey(const ValueKey('pay_select_recipient_button')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('pay_add_to_contacts_button')),
        findsNothing,
      );
    });

    testWidgets('contact match filters to the contact and hides add action', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          _recipientStep(
            typedAddress: _contactAddress,
            contacts: [_contact],
            recents: const [PayRecentRecipient(address: _recentAddress)],
          ),
        ),
      );

      expect(find.byKey(const ValueKey('pay_contacts_card')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('pay_recent_recipients_card')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('pay_add_to_contacts_button')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('pay_select_recipient_button')),
        findsOneWidget,
      );
    });

    testWidgets('recents match keeps the recent row and offers add action', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          _recipientStep(
            typedAddress: _recentAddress,
            contacts: [_contact],
            recents: const [PayRecentRecipient(address: _recentAddress)],
          ),
        ),
      );

      expect(
        find.byKey(const ValueKey('pay_recent_recipients_card')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('pay_contacts_card')), findsNothing);
      expect(
        find.byKey(const ValueKey('pay_add_to_contacts_button')),
        findsOneWidget,
      );
    });

    testWidgets(
      'recent result wins over the same contact and bypasses eager validation',
      (tester) async {
        await tester.pumpWidget(
          _harness(
            _recipientStep(
              typedAddress: 'recent mike',
              addressError: 'Not a valid Ethereum address.',
              contacts: [_recentContact],
              recents: const [
                PayRecentRecipient(
                  address: _recentAddress,
                  amountText: '-24 USDC',
                ),
              ],
            ),
          ),
        );

        expect(
          find.byKey(const ValueKey('pay_recent_recipients_card')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('pay_contacts_card')), findsNothing);
        expect(find.text('Recent Mike'), findsOneWidget);
        expect(find.text('-24 USDC'), findsOneWidget);
        expect(find.text('Not a valid Ethereum address.'), findsNothing);
        expect(
          find.byKey(const ValueKey('pay_select_recipient_button')),
          findsNothing,
        );
      },
    );

    testWidgets('exact recent contact keeps recent selected state', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          _recipientStep(
            typedAddress: _recentAddress,
            contacts: [_recentContact],
            recents: const [
              PayRecentRecipient(
                address: _recentAddress,
                amountText: '-24 USDC',
              ),
            ],
          ),
        ),
      );

      expect(
        find.byKey(const ValueKey('pay_recent_recipients_card')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('pay_contacts_card')), findsNothing);
      expect(
        find.byKey(const ValueKey('pay_add_to_contacts_button')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('pay_select_recipient_button')),
        findsOneWidget,
      );
    });

    testWidgets('unknown valid address shows the new-address notice', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          _recipientStep(
            typedAddress: _unknownAddress,
            contacts: [_contact],
            recents: const [PayRecentRecipient(address: _recentAddress)],
          ),
        ),
      );

      expect(
        find.byKey(const ValueKey('pay_recipient_new_address_notice')),
        findsOneWidget,
      );
      expect(find.text('New address detected.'), findsOneWidget);
      expect(
        find.text("You haven't interacted with this address before."),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('pay_add_to_contacts_button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('pay_select_recipient_button')),
        findsOneWidget,
      );
    });

    testWidgets('invalid address disables continue and shows the error', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          _recipientStep(
            typedAddress: 'nonsense',
            addressError: 'Not a valid Ethereum address.',
          ),
        ),
      );

      expect(find.text('Not a valid Ethereum address.'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('pay_select_recipient_button')),
        findsNothing,
      );
    });

    testWidgets('quote failures stay visible beside the recipient actions', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          _recipientStep(
            typedAddress: _unknownAddress,
            quoteError: 'Unable to fetch a quote. Try again.',
          ),
        ),
      );

      expect(
        find.byKey(const ValueKey('pay_recipient_quote_error')),
        findsOneWidget,
      );
      expect(find.text('Unable to fetch a quote. Try again.'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('pay_select_recipient_button')),
        findsOneWidget,
      );
    });

    testWidgets('unsupported asset disables recipient review with an error', (
      tester,
    ) async {
      var reviewRequested = false;
      await tester.pumpWidget(
        _harness(
          _recipientStep(
            typedAddress: _unknownAddress,
            quoteError: 'USDC on Base is not currently supported.',
            actionsEnabled: false,
            onSelectRecipient: () => reviewRequested = true,
          ),
        ),
      );

      expect(
        find.text('USDC on Base is not currently supported.'),
        findsOneWidget,
      );
      final button = tester.widget<AppButton>(
        find.byKey(const ValueKey('pay_select_recipient_button')),
      );
      expect(button.onPressed, isNull);
      expect(reviewRequested, isFalse);
    });

    testWidgets('row selection does not request review until the CTA', (
      tester,
    ) async {
      String? chosen;
      var reviewRequested = false;
      await tester.pumpWidget(
        _harness(
          _recipientStep(
            typedAddress: _contactAddress,
            contacts: [_contact],
            onChooseRecipient: (address) => chosen = address,
            onSelectRecipient: () => reviewRequested = true,
          ),
        ),
      );

      await tester.tap(find.text('Mike'));
      expect(chosen, _contactAddress);
      expect(reviewRequested, isFalse);

      await tester.tap(
        find.byKey(const ValueKey('pay_select_recipient_button')),
      );
      expect(reviewRequested, isTrue);
    });
  });

  group('PayReviewStep', () {
    Widget reviewStep({
      AddressBookContact? contact,
      String? expiresInText = '1:30',
      bool expired = false,
      bool starting = false,
      String? startBlockedReason,
      VoidCallback? onConfirm,
      VoidCallback? onReviewAgain,
    }) {
      return PayReviewStep(
        quote: _payQuote(),
        recipientAddress: _contactAddress,
        recipientContact: contact,
        payingFiatText: r'$100.10',
        convertedFiatText: r'$100.10',
        expiresInText: expiresInText,
        expired: expired,
        starting: starting,
        startBlockedReason: startBlockedReason,
        startError: null,
        onShowFullAddress: () {},
        onConfirm: onConfirm ?? () {},
        onReviewAgain: onReviewAgain ?? () {},
      );
    }

    testWidgets('shows paying, recipient, countdown, and converted rows', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(reviewStep(contact: _contact)));

      expect(find.text('Paying'), findsOneWidget);
      expect(find.text('To'), findsOneWidget);
      expect(find.text('Mike'), findsOneWidget);
      expect(find.text('Converted amount'), findsOneWidget);
      expect(find.textContaining('Quote expires in'), findsOneWidget);
      expect(find.textContaining('1:30'), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const ValueKey('pay_review_step'))).height,
        428,
      );
    });

    testWidgets('unknown recipient shows the wallet placeholder copy', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(reviewStep()));
      expect(find.text('Unknown address'), findsOneWidget);
    });

    testWidgets('show full address delegates to the screen overlay', (
      tester,
    ) async {
      var opened = false;
      await tester.pumpWidget(
        _harness(
          PayReviewStep(
            quote: _payQuote(),
            recipientAddress: _contactAddress,
            recipientContact: null,
            payingFiatText: r'$100.10',
            convertedFiatText: r'$100.10',
            expiresInText: '1:30',
            expired: false,
            starting: false,
            startBlockedReason: null,
            startError: null,
            onShowFullAddress: () => opened = true,
            onConfirm: () {},
            onReviewAgain: () {},
          ),
        ),
      );

      expect(find.text(_contactAddress), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey('pay_review_show_full_address')),
      );
      expect(opened, isTrue);
    });

    testWidgets('expired quote uses refresh treatment', (tester) async {
      var reviewedAgain = false;
      await tester.pumpWidget(
        _harness(
          Column(
            children: [
              reviewStep(expired: true),
              PayReviewAction(
                expired: true,
                starting: false,
                startBlockedReason: null,
                onConfirm: () {},
                onReviewAgain: () => reviewedAgain = true,
              ),
            ],
          ),
        ),
      );

      expect(find.text('Quote expired'), findsOneWidget);
      expect(
        tester
            .widget<Opacity>(
              find.byKey(const ValueKey('pay_review_converted_opacity')),
            )
            .opacity,
        0.5,
      );
      await tester.tap(find.text('Refresh the quote'));
      expect(reviewedAgain, isTrue);
    });

    testWidgets('blocked start disables the CTA with the balance label', (
      tester,
    ) async {
      var confirmed = false;
      await tester.pumpWidget(
        _harness(
          Column(
            children: [
              reviewStep(startBlockedReason: 'not enough'),
              PayReviewAction(
                expired: false,
                starting: false,
                startBlockedReason: 'not enough',
                onConfirm: () => confirmed = true,
                onReviewAgain: () {},
              ),
            ],
          ),
        ),
      );

      expect(find.text('not enough'), findsOneWidget);
      await tester.tap(find.text('Not enough ZEC'), warnIfMissed: false);
      expect(confirmed, isFalse);
    });
  });
}
