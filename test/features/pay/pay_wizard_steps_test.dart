import 'package:flutter/material.dart' show Material, MaterialApp;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/address_book/models/address_book_contact.dart';
import 'package:zcash_wallet/src/features/pay/models/pay_recent_recipients.dart';
import 'package:zcash_wallet/src/features/pay/widgets/pay_recipient_step.dart';
import 'package:zcash_wallet/src/features/pay/widgets/pay_review_step.dart';
import 'package:zcash_wallet/src/features/pay/widgets/pay_wizard_stepper.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';

const _contactAddress = '0x52908400098527886E0F7030069857D2E4169EE7';
const _recentAddress = '0x1111111111111111111111111111111111111111';
const _unknownAddress = '0x2222222222222222222222222222222222222222';

final _contact = AddressBookContact(
  id: 'mike',
  label: 'Mike',
  network: AddressBookNetwork.ethereum,
  address: _contactAddress,
  profilePictureId: 'pfp-01',
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
}) {
  return PayRecipientStep(
    controller: TextEditingController(text: typedAddress),
    typedAddress: typedAddress,
    addressError: addressError,
    contacts: contacts,
    recents: recents,
    busy: false,
    onAddressChanged: (_) {},
    onOpenScanner: () {},
    onChooseRecipient: onChooseRecipient ?? (_) {},
    onSelectRecipient: onSelectRecipient ?? () {},
    onAddToContacts: onAddToContacts ?? () {},
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

void main() {
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
    testWidgets('empty input shows recents and contacts, no CTA', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          _recipientStep(
            contacts: [_contact],
            recents: const [PayRecentRecipient(address: _recentAddress)],
          ),
        ),
      );

      expect(
        find.byKey(const ValueKey('pay_recent_recipients_card')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('pay_contacts_card')), findsOneWidget);
      expect(find.text('Mike'), findsOneWidget);
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

    testWidgets('tapping a contact row chooses that recipient', (tester) async {
      String? chosen;
      await tester.pumpWidget(
        _harness(
          _recipientStep(
            contacts: [_contact],
            onChooseRecipient: (address) => chosen = address,
          ),
        ),
      );

      await tester.tap(find.text('Mike'));
      expect(chosen, _contactAddress);
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
      expect(find.text('Confirm & Pay'), findsOneWidget);
    });

    testWidgets('unknown recipient shows the wallet placeholder copy', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(reviewStep()));
      expect(find.text('Unknown address'), findsOneWidget);
    });

    testWidgets('show full address toggle reveals the address', (tester) async {
      await tester.pumpWidget(_harness(reviewStep()));

      expect(
        find.byKey(const ValueKey('pay_review_full_address')),
        findsNothing,
      );
      await tester.tap(
        find.byKey(const ValueKey('pay_review_show_full_address')),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('pay_review_full_address')),
        findsOneWidget,
      );
      expect(find.text('Hide full address'), findsOneWidget);
    });

    testWidgets('expired quote swaps the CTA for review again', (tester) async {
      var reviewedAgain = false;
      await tester.pumpWidget(
        _harness(
          reviewStep(expired: true, onReviewAgain: () => reviewedAgain = true),
        ),
      );

      expect(find.text('Quote expired'), findsOneWidget);
      await tester.tap(find.text('Review again'));
      expect(reviewedAgain, isTrue);
    });

    testWidgets('blocked start disables the CTA with the balance label', (
      tester,
    ) async {
      var confirmed = false;
      await tester.pumpWidget(
        _harness(
          reviewStep(
            startBlockedReason: 'not enough',
            onConfirm: () => confirmed = true,
          ),
        ),
      );

      await tester.tap(find.text('Not enough ZEC'), warnIfMissed: false);
      expect(confirmed, isFalse);
    });
  });
}
