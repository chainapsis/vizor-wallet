import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:zcash_wallet/src/core/formatting/address_display.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/features/send/screens/mobile/mobile_send_screen.dart';
import 'package:zcash_wallet/src/features/send/screens/mobile/mobile_send_status_screen.dart';
import 'package:zcash_wallet/src/features/send/services/send_flow.dart';
import 'package:zcash_wallet/src/features/send/widgets/send_review_content_view.dart';
import 'package:zcash_wallet/src/features/send/widgets/send_review_layout.dart';
import 'package:zcash_wallet/src/features/send/widgets/send_status_content_view.dart';
import 'package:zcash_wallet/widgetbook/send_compose_view.dart';
import 'package:zcash_wallet/widgetbook/gallery/send_gallery.dart';
import 'package:zcash_wallet/widgetbook/payment_request_use_cases.dart';
import 'package:zcash_wallet/widgetbook/send_review_status_use_cases.dart';
import 'package:zcash_wallet/widgetbook/send_screen_use_cases.dart';
import 'package:zcash_wallet/widgetbook/send_use_cases.dart';
import 'package:zcash_wallet/widgetbook/support/wb_layout.dart';
import 'package:zcash_wallet/widgetbook/widgetbook_app.dart';

import 'support/wb_gallery_harness.dart';

/// The `Layout` knob values the folded send cases dispatch on. Sweeps pass one
/// explicitly so a case reaches the branch under test in either lane.
final Map<String, String> _desktop = {
  'Layout': wbLayoutLabel(WbLayout.desktop),
};
final Map<String, String> _mobile = {'Layout': wbLayoutLabel(WbLayout.mobile)};

/// The mobile send screen's `Layout` plus `Step` selection.
Map<String, String> _step(SendScreenMobileStep step) => {
  ..._mobile,
  'Step': sendScreenMobileStepLabel(step),
};

/// The state axes each mobile wizard step registers, and the desktop
/// composer's own axes: the folded case registers one set or the other.
const _desktopSendScreenAxes = <String>[
  'Wallet',
  'Balance',
  'Privacy mode',
  'Recipient',
  'Amount',
  'Contact picker',
];
const _mobileSendScreenStepAxes = <SendScreenMobileStep, List<String>>{
  SendScreenMobileStep.recipient: ['Address', 'Contacts', 'Field'],
  SendScreenMobileStep.amount: ['Amount', 'Unit'],
  SendScreenMobileStep.review: [
    'Fee',
    'Recipient identity',
    'Payment request',
    'Message',
  ],
  SendScreenMobileStep.qrScan: ['Camera', 'Scan outcome'],
};

// Lane-agnostic: nothing here asserts a token metric, and the payment-request
// layout axis is driven by explicit query params rather than the compiled
// lane, so both test lanes exercise the same combinations.
void main() {
  testWidgets('every send gallery case builds at its knob defaults', (
    tester,
  ) async {
    final useCases = widgetbookUseCases(sendGalleryNodes).toList();
    expect(useCases.length, 11);

    for (final useCase in useCases) {
      await pumpUseCase(tester, useCase.builder);
      expect(tester.takeException(), isNull, reason: useCase.name);
    }
    await disposeTree(tester);
    await drainSendReviewDiscard(tester);
  });

  testWidgets('send compose covers every prop axis', (tester) async {
    for (final sweep in <String, List<String>>{
      'Pool route': SendPoolRoute.values.map(sendComposeRouteLabel).toList(),
      'Unit': SendComposeUnit.values.map(sendComposeUnitLabel).toList(),
      'Price': SendComposePrice.values.map(sendComposePriceLabel).toList(),
      'Amount focused': const ['false', 'true'],
      'Amount error': SendComposeAmountError.values
          .map(sendComposeAmountErrorLabel)
          .toList(),
      'Message': SendComposeMessage.values
          .map(sendComposeMessageLabel)
          .toList(),
      'Review enabled': const ['false', 'true'],
    }.entries) {
      await expectKnobOptionsRenderDistinctly(
        tester,
        buildSendComposeGalleryCase,
        label: sweep.key,
        optionLabels: sweep.value,
      );
    }
  });

  testWidgets('send compose keeps the over-limit message copy', (tester) async {
    await pumpUseCase(
      tester,
      buildSendComposeGalleryCase,
      knobs: {'Message': sendComposeMessageLabel(SendComposeMessage.tooLong)},
    );

    expect(tester.takeException(), isNull);
    expect(find.text(kSendComposeFixtureMemoError), findsOneWidget);
    expect(find.text(kSendComposeFixtureMemoCounter), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('send review covers every prop axis', (tester) async {
    for (final sweep in <String, List<String>>{
      'Recipient': SendReviewPanelRecipient.values
          .map(sendReviewPanelRecipientLabel)
          .toList(),
      // Only a raw address carries the pool badge; a contact keeps its
      // truncated-address sub-line instead.
      'Recipient pool': SendReviewPanelPool.values
          .map(sendReviewPanelPoolLabel)
          .toList(),
      'Payment request': SendReviewPanelRequest.values
          .map(sendReviewPanelRequestLabel)
          .toList(),
      'Message': SendReviewPanelMessage.values
          .map(sendReviewPanelMessageLabel)
          .toList(),
      'Fiat row': const ['false', 'true'],
      'Confirm': SendReviewPanelConfirm.values
          .map(sendReviewPanelConfirmLabel)
          .toList(),
      'Confirm state': SendReviewPanelConfirmState.values
          .map(sendReviewPanelConfirmStateLabel)
          .toList(),
    }.entries) {
      await expectKnobOptionsRenderDistinctly(
        tester,
        buildSendReviewGalleryCase,
        label: sweep.key,
        optionLabels: sweep.value,
      );
    }
  });

  testWidgets('send review names the Keystone confirmation', (tester) async {
    await pumpUseCase(
      tester,
      buildSendReviewGalleryCase,
      knobs: {
        'Confirm': sendReviewPanelConfirmLabel(SendReviewPanelConfirm.keystone),
      },
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Confirm with Keystone'), findsOneWidget);

    await pumpUseCase(
      tester,
      buildSendReviewGalleryCase,
      knobs: {
        'Confirm state': sendReviewPanelConfirmStateLabel(
          SendReviewPanelConfirmState.cancelling,
        ),
      },
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Cancelling…'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('send status covers every prop axis', (tester) async {
    for (final sweep in <String, List<String>>{
      'Phase': SendStatusPhase.values.map(sendStatusPhaseLabel).toList(),
      'Notice': SendStatusPanelNotice.values
          .map(sendStatusPanelNoticeLabel)
          .toList(),
      'Transaction hash': const ['false', 'true'],
      'Fiat row': const ['false', 'true'],
      'Message': SendStatusPanelMessage.values
          .map(sendStatusPanelMessageLabel)
          .toList(),
      'Title': SendStatusPanelTitle.values
          .map(sendStatusPanelTitleLabel)
          .toList(),
    }.entries) {
      await expectKnobOptionsRenderDistinctly(
        tester,
        buildSendStatusGalleryCase,
        label: sweep.key,
        optionLabels: sweep.value,
      );
    }
  });

  testWidgets('send status retitles the donation receipt', (tester) async {
    await pumpUseCase(
      tester,
      buildSendStatusGalleryCase,
      knobs: {
        'Title': sendStatusPanelTitleLabel(SendStatusPanelTitle.donation),
      },
    );

    expect(tester.takeException(), isNull);
    expect(
      find.text(sendStatusDonationTitleFor(SendStatusPhase.inProgress)),
      findsOneWidget,
    );
    expect(find.text('Donating to'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('verify address covers both layouts', (tester) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSendVerifyAddressGalleryCase,
      label: 'Layout',
      optionLabels: WbLayout.values.map(wbLayoutLabel).toList(),
    );
  });

  testWidgets('verify address covers every desktop recipient', (tester) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSendVerifyAddressGalleryCase,
      label: 'Recipient',
      optionLabels: SendVerifyAddressRecipient.values
          .map(sendVerifyAddressRecipientLabel)
          .toList(),
      otherKnobs: _desktop,
    );

    // The kind only reaches the header of an unknown recipient, and the
    // count only the sub-line of a saved one.
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSendVerifyAddressGalleryCase,
      label: 'Address kind',
      optionLabels: SendVerifyAddressKind.values
          .map(sendVerifyAddressKindLabel)
          .toList(),
      otherKnobs: {
        ..._desktop,
        'Recipient': sendVerifyAddressRecipientLabel(
          SendVerifyAddressRecipient.unknown,
        ),
      },
    );

    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSendVerifyAddressGalleryCase,
      label: 'Previous transactions',
      optionLabels: SendVerifyAddressHistory.values
          .map(sendVerifyAddressHistoryLabel)
          .toList(),
      otherKnobs: {
        ..._desktop,
        'Recipient': sendVerifyAddressRecipientLabel(
          SendVerifyAddressRecipient.savedContact,
        ),
      },
    );

    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSendVerifyAddressGalleryCase,
      label: 'Address',
      optionLabels: SendVerifyAddressContent.values
          .map(sendVerifyAddressContentLabel)
          .toList(),
      otherKnobs: _desktop,
    );
  });

  testWidgets('verify address registers the modal axes on desktop only', (
    tester,
  ) async {
    final desktop = await pumpUseCase(
      tester,
      buildSendVerifyAddressGalleryCase,
      knobs: _desktop,
    );
    expect(
      desktop.knobs.keys,
      containsAll(<String>[
        'Layout',
        'Recipient',
        'Address kind',
        'Previous transactions',
        'Address',
      ]),
    );

    // The sheet header's title and leading come from the caller, so the kind
    // and the count have nothing to drive on the mobile layout.
    final mobile = await pumpUseCase(
      tester,
      buildSendVerifyAddressGalleryCase,
      knobs: _mobile,
    );
    expect(
      mobile.knobs.keys,
      containsAll(<String>['Layout', 'Recipient', 'Address']),
    );
    expect(mobile.knobs.keys, isNot(contains('Address kind')));
    expect(mobile.knobs.keys, isNot(contains('Previous transactions')));
    await disposeTree(tester);
  });

  testWidgets('verify address names each header and transaction count', (
    tester,
  ) async {
    const headers = {
      SendVerifyAddressKind.shielded: 'Unknown shielded address',
      SendVerifyAddressKind.transparent: 'Unknown transparent address',
      SendVerifyAddressKind.external: 'Recipient address',
    };
    for (final entry in headers.entries) {
      await pumpUseCase(
        tester,
        buildSendVerifyAddressGalleryCase,
        knobs: {
          ..._desktop,
          'Address kind': sendVerifyAddressKindLabel(entry.key),
        },
      );
      expect(tester.takeException(), isNull, reason: entry.value);
      expect(find.text(entry.value), findsOneWidget, reason: entry.value);
    }

    const counts = {
      SendVerifyAddressHistory.hidden: null,
      SendVerifyAddressHistory.one: '1 previous transaction',
      SendVerifyAddressHistory.many: '12 previous transactions',
    };
    for (final entry in counts.entries) {
      await pumpUseCase(
        tester,
        buildSendVerifyAddressGalleryCase,
        knobs: {
          ..._desktop,
          'Recipient': sendVerifyAddressRecipientLabel(
            SendVerifyAddressRecipient.savedContact,
          ),
          'Previous transactions': sendVerifyAddressHistoryLabel(entry.key),
        },
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Mike'), findsOneWidget);
      final line = entry.value;
      if (line == null) {
        expect(find.textContaining('previous transaction'), findsNothing);
      } else {
        expect(find.text(line), findsOneWidget);
      }
    }
    await disposeTree(tester);
  });

  testWidgets('verify address mobile sheet covers recipient and address', (
    tester,
  ) async {
    for (final sweep in <String, List<String>>{
      'Recipient': SendVerifyAddressRecipient.values
          .map(sendVerifyAddressRecipientLabel)
          .toList(),
      'Address': SendVerifyAddressContent.values
          .map(sendVerifyAddressContentLabel)
          .toList(),
    }.entries) {
      await expectKnobOptionsRenderDistinctly(
        tester,
        buildSendVerifyAddressGalleryCase,
        label: sweep.key,
        optionLabels: sweep.value,
        otherKnobs: _mobile,
      );
    }

    await pumpUseCase(
      tester,
      buildSendVerifyAddressGalleryCase,
      knobs: {
        ..._mobile,
        'Recipient': sendVerifyAddressRecipientLabel(
          SendVerifyAddressRecipient.savedContact,
        ),
      },
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Mike'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('verify address overlay covers recipient and pool', (
    tester,
  ) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSendVerifyAddressOverlayGalleryCase,
      label: 'Recipient',
      optionLabels: SendVerifyOverlayRecipient.values
          .map(sendVerifyOverlayRecipientLabel)
          .toList(),
    );

    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSendVerifyAddressOverlayGalleryCase,
      label: 'Address kind',
      optionLabels: SendVerifyOverlayKind.values
          .map(sendVerifyOverlayKindLabel)
          .toList(),
    );
  });

  testWidgets('verify address overlay resolves each recipient identity', (
    tester,
  ) async {
    await pumpUseCase(
      tester,
      buildSendVerifyAddressOverlayGalleryCase,
      knobs: {
        'Recipient': sendVerifyOverlayRecipientLabel(
          SendVerifyOverlayRecipient.contact,
        ),
      },
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Blue Door Coffee'), findsOneWidget);

    await pumpUseCase(
      tester,
      buildSendVerifyAddressOverlayGalleryCase,
      knobs: {
        'Recipient': sendVerifyOverlayRecipientLabel(
          SendVerifyOverlayRecipient.ownAccount,
        ),
      },
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Savings'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('sapling params prompt covers both form factors', (tester) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSendSaplingParamsGalleryCase,
      label: 'Layout',
      optionLabels: WbLayout.values.map(wbLayoutLabel).toList(),
    );

    for (final layout in WbLayout.values) {
      await pumpUseCase(
        tester,
        buildSendSaplingParamsGalleryCase,
        knobs: {'Layout': wbLayoutLabel(layout)},
      );
      expect(tester.takeException(), isNull, reason: layout.name);
      expect(find.text('Download Required'), findsOneWidget);
      expect(find.text('Download'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    }
    await disposeTree(tester);
  });

  testWidgets('payment request card covers every request in both layouts', (
    tester,
  ) async {
    for (final layout in WbLayout.values) {
      await expectKnobOptionsRenderDistinctly(
        tester,
        buildSendPaymentRequestGalleryCase,
        label: 'Request',
        optionLabels: PaymentRequestFixture.values
            .map(sendPaymentRequestFixtureLabel)
            .toList(),
        otherKnobs: {'Layout': wbLayoutLabel(layout)},
      );
    }

    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSendPaymentRequestGalleryCase,
      label: 'Layout',
      optionLabels: WbLayout.values.map(wbLayoutLabel).toList(),
    );
  });

  testWidgets('payment request card marks a whitespace-only memo', (
    tester,
  ) async {
    await pumpUseCase(
      tester,
      buildSendPaymentRequestGalleryCase,
      knobs: {
        'Request': sendPaymentRequestFixtureLabel(
          PaymentRequestFixture.whitespaceMemo,
        ),
      },
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Transaction memo'), findsOneWidget);
    expect(find.text(kWhitespaceOnlyMemoPlaceholder), findsOneWidget);

    // The requester block keeps its name summary with nothing to disclose.
    await pumpUseCase(
      tester,
      buildSendPaymentRequestGalleryCase,
      knobs: {
        'Request': sendPaymentRequestFixtureLabel(
          PaymentRequestFixture.requesterNameOnly,
        ),
      },
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Blue Door Coffee'), findsWidgets);
    expect(find.text('Transaction memo'), findsNothing);
    await disposeTree(tester);
  });

  testWidgets('payment request card covers the presentation axes', (
    tester,
  ) async {
    // The long-values request is the only fixture with both a collapsible
    // address and a message long enough to expand.
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSendPaymentRequestGalleryCase,
      label: 'Expanded',
      optionLabels: PaymentRequestExpansion.values
          .map(sendPaymentRequestExpansionLabel)
          .toList(),
      otherKnobs: {
        'Request': sendPaymentRequestFixtureLabel(
          PaymentRequestFixture.longValues,
        ),
      },
    );

    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSendPaymentRequestGalleryCase,
      label: 'Text scale 1.5x',
      optionLabels: const ['false', 'true'],
    );

    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSendPaymentRequestGalleryCase,
      label: 'RTL mirror',
      optionLabels: const ['false', 'true'],
    );
  });

  testWidgets('payment request delegates keep their fixture parameters', (
    tester,
  ) async {
    // The failed card is the one fixture with a status message of its own,
    // so it is the parameter the extraction could have dropped.
    await pumpUseCase(tester, buildPaymentRequestFailedUseCase);

    expect(tester.takeException(), isNull);
    expect(
      find.text("Couldn't check this request — try again or edit the details"),
      findsOneWidget,
    );
    await disposeTree(tester);
  });

  testWidgets('mobile send recipient covers address, contacts and focus', (
    tester,
  ) async {
    final step = _step(SendScreenMobileStep.recipient);
    // Valid pool types share the same production composer presentation until
    // the reviewer continues, so inspect the real field's seeded value rather
    // than requiring an artificial visual label for each address protocol.
    for (final address in MobileSendRecipientAddressCase.values) {
      await pumpUseCase(
        tester,
        buildSendScreenGalleryCase,
        knobs: {...step, 'Address': sendMobileRecipientAddressLabel(address)},
      );
      final field = tester.widget<TextField>(
        find.byKey(const ValueKey('mobile_send_address_input')),
      );
      expect(
        field.controller!.text,
        mobileSendRecipientAddressFor(address) ?? '',
      );
    }
    await disposeTree(tester);

    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSendScreenGalleryCase,
      label: 'Contacts',
      optionLabels: SendMobileContacts.values
          .map(sendMobileContactsLabel)
          .toList(),
      otherKnobs: step,
    );

    // The focus overlay only reads with the field empty, which is where the
    // recipient step opens.
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSendScreenGalleryCase,
      label: 'Field',
      optionLabels: SendMobileField.values.map(sendMobileFieldLabel).toList(),
      otherKnobs: step,
    );
  });

  testWidgets('mobile send recipient names the address type it rejected', (
    tester,
  ) async {
    await pumpUseCase(
      tester,
      buildSendScreenGalleryCase,
      knobs: {
        ..._step(SendScreenMobileStep.recipient),
        'Address': sendMobileRecipientAddressLabel(
          MobileSendRecipientAddressCase.wrongNetwork,
        ),
      },
    );
    expect(tester.takeException(), isNull);
    expect(find.text(kWrongNetworkAddressMessage), findsOneWidget);

    await pumpUseCase(
      tester,
      buildSendScreenGalleryCase,
      knobs: {
        ..._step(SendScreenMobileStep.recipient),
        'Address': sendMobileRecipientAddressLabel(
          MobileSendRecipientAddressCase.invalid,
        ),
      },
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Invalid address'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('mobile send amount covers value and unit', (tester) async {
    final step = _step(SendScreenMobileStep.amount);
    for (final unit in MobileSendAmountInputMode.values) {
      await expectKnobOptionsRenderDistinctly(
        tester,
        buildSendScreenGalleryCase,
        label: 'Amount',
        optionLabels: MobileSendAmountCase.values
            .map(sendMobileAmountLabel)
            .toList(),
        otherKnobs: {...step, 'Unit': sendMobileAmountUnitLabel(unit)},
      );
    }

    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSendScreenGalleryCase,
      label: 'Unit',
      optionLabels: MobileSendAmountInputMode.values
          .map(sendMobileAmountUnitLabel)
          .toList(),
      otherKnobs: step,
    );
  });

  testWidgets('mobile send review covers fee, identity, request and message', (
    tester,
  ) async {
    final step = _step(SendScreenMobileStep.review);
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSendScreenGalleryCase,
      label: 'Fee',
      optionLabels: MobileSendReviewFeeCase.values
          .map(sendMobileReviewFeeLabel)
          .toList(),
      otherKnobs: step,
    );

    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSendScreenGalleryCase,
      label: 'Recipient identity',
      optionLabels: MobileSendReviewIdentityCase.values
          .map(sendMobileReviewIdentityLabel)
          .toList(),
      otherKnobs: step,
    );

    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSendScreenGalleryCase,
      label: 'Payment request',
      optionLabels: MobileSendReviewRequestCase.values
          .map(sendMobileReviewRequestLabel)
          .toList(),
      otherKnobs: step,
    );

    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSendScreenGalleryCase,
      label: 'Message',
      optionLabels: const ['false', 'true'],
      otherKnobs: step,
    );
  });

  testWidgets('mobile send review states each fee outcome in words', (
    tester,
  ) async {
    const notices = {
      MobileSendReviewFeeCase.notEnough: 'Not enough ZEC',
      MobileSendReviewFeeCase.syncing:
          'Finishing wallet sync. Try again shortly.',
      MobileSendReviewFeeCase.unavailable: 'Fee unavailable. Try again.',
    };
    for (final entry in notices.entries) {
      await pumpUseCase(
        tester,
        buildSendScreenGalleryCase,
        knobs: {
          ..._step(SendScreenMobileStep.review),
          'Fee': sendMobileReviewFeeLabel(entry.key),
        },
      );
      expect(tester.takeException(), isNull, reason: entry.value);
      expect(
        find.byKey(const ValueKey('mobile_send_review_fee_notice')),
        findsOneWidget,
      );
      expect(find.text(entry.value), findsOneWidget, reason: entry.value);
    }
    await disposeTree(tester);
  });

  testWidgets('mobile send review retitles a payment request', (tester) async {
    await pumpUseCase(
      tester,
      buildSendScreenGalleryCase,
      knobs: {
        ..._step(SendScreenMobileStep.review),
        'Payment request': sendMobileReviewRequestLabel(
          MobileSendReviewRequestCase.differentAmount,
        ),
      },
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Review Payment'), findsOneWidget);
    expect(find.text('Requested by'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile_send_review_requested')),
      findsOneWidget,
    );
    await disposeTree(tester);
  });

  testWidgets('mobile send QR scan covers camera and rejected scans', (
    tester,
  ) async {
    final step = _step(SendScreenMobileStep.qrScan);
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSendScreenGalleryCase,
      label: 'Camera',
      optionLabels: SendScanCamera.values.map(sendScanCameraLabel).toList(),
      otherKnobs: step,
    );

    // The card prints a rejection in place of its caption, and only over a
    // live camera.
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSendScreenGalleryCase,
      label: 'Scan outcome',
      optionLabels: SendScanOutcome.values.map(sendScanOutcomeLabel).toList(),
      otherKnobs: {
        ...step,
        'Camera': sendScanCameraLabel(SendScanCamera.active),
      },
    );
  });

  testWidgets('mobile send status covers phase, message and account', (
    tester,
  ) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSendStatusScreenGalleryCase,
      label: 'Phase',
      optionLabels: SendMobileStatusPhase.values
          .map(sendMobileStatusPhaseLabel)
          .toList(),
      otherKnobs: _mobile,
    );
    await drainSendStatusHaptics(tester);

    // Only the queued receipt swaps its own copy for the server's.
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSendStatusScreenGalleryCase,
      label: 'Status message',
      optionLabels: SendMobileStatusMessage.values
          .map(sendMobileStatusMessageLabel)
          .toList(),
      otherKnobs: {
        ..._mobile,
        'Phase': sendMobileStatusPhaseLabel(SendMobileStatusPhase.queued),
      },
    );
    await drainSendStatusHaptics(tester);
  });

  testWidgets('mobile send status keeps a Keystone receipt on every phase', (
    tester,
  ) async {
    for (final phase in SendMobileStatusPhase.values) {
      await pumpUseCase(
        tester,
        buildSendStatusScreenGalleryCase,
        knobs: {
          ..._mobile,
          'Phase': sendMobileStatusPhaseLabel(phase),
          'Keystone account': 'true',
        },
      );
      expect(tester.takeException(), isNull, reason: phase.name);
      expect(
        find.byKey(ValueKey('mobile_send_status_${_statusPhaseKey(phase)}')),
        findsOneWidget,
        reason: phase.name,
      );
    }
    await disposeTree(tester);
    await drainSendStatusHaptics(tester);
  });

  testWidgets('mobile Keystone sign covers rounds and prepare failures', (
    tester,
  ) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSendMobileKeystoneSignGalleryCase,
      label: 'Preparation',
      optionLabels: SendMobileKeystonePreparation.values
          .map(sendMobileKeystonePreparationLabel)
          .toList(),
    );
    await drainSendReviewDiscard(tester);

    // The QR page heads both rounds 'Step 1/2', so the round title is only on
    // screen once preparation failed.
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSendMobileKeystoneSignGalleryCase,
      label: 'Round',
      optionLabels: SendMobileKeystoneRound.values
          .map(sendMobileKeystoneRoundLabel)
          .toList(),
      otherKnobs: {
        'Preparation': sendMobileKeystonePreparationLabel(
          SendMobileKeystonePreparation.failed,
        ),
      },
    );
    await drainSendReviewDiscard(tester);

    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSendMobileKeystoneSignGalleryCase,
      label: 'Error',
      optionLabels: MobileKeystoneSignFailure.values
          .map(sendMobileKeystoneFailureLabel)
          .toList(),
      otherKnobs: {
        'Preparation': sendMobileKeystonePreparationLabel(
          SendMobileKeystonePreparation.failed,
        ),
      },
    );
    await drainSendReviewDiscard(tester);
  });

  testWidgets('mobile Keystone sign titles the two TEX rounds', (tester) async {
    await pumpUseCase(
      tester,
      buildSendMobileKeystoneSignGalleryCase,
      knobs: {
        'Round': sendMobileKeystoneRoundLabel(
          SendMobileKeystoneRound.texTwoRounds,
        ),
        'Preparation': sendMobileKeystonePreparationLabel(
          SendMobileKeystonePreparation.failed,
        ),
      },
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Confirm transaction 1 of 2'), findsOneWidget);
    await disposeTree(tester);
    await drainSendReviewDiscard(tester);
  });

  testWidgets('send screen covers both layouts and every mobile step', (
    tester,
  ) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSendScreenGalleryCase,
      label: 'Layout',
      optionLabels: WbLayout.values.map(wbLayoutLabel).toList(),
    );

    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSendScreenGalleryCase,
      label: 'Step',
      optionLabels: SendScreenMobileStep.values
          .map(sendScreenMobileStepLabel)
          .toList(),
      otherKnobs: _mobile,
    );
  });

  testWidgets('send screen registers one axis set per layout and step', (
    tester,
  ) async {
    final desktop = await pumpUseCase(
      tester,
      buildSendScreenGalleryCase,
      knobs: _desktop,
    );
    expect(desktop.knobs.keys, containsAll(_desktopSendScreenAxes));
    expect(desktop.knobs.keys, isNot(contains('Price')));
    expect(desktop.knobs.keys, isNot(contains('Contacts')));
    expect(desktop.knobs.keys, isNot(contains('Step')));

    // Each mobile step registers its own axes and none of the composer's.
    for (final entry in _mobileSendScreenStepAxes.entries) {
      final state = await pumpUseCase(
        tester,
        buildSendScreenGalleryCase,
        knobs: _step(entry.key),
      );
      expect(
        state.knobs.keys,
        containsAll(<String>['Layout', 'Step', ...entry.value]),
        reason: entry.key.name,
      );
      expect(
        state.knobs.keys,
        isNot(contains('Wallet')),
        reason: entry.key.name,
      );
    }
    await disposeTree(tester);
  });

  testWidgets('desktop send screen covers wallet, balance and privacy', (
    tester,
  ) async {
    // The desktop branch is `WbLaneOnly(desktop)`, so this sweep only has
    // distinct renders in the desktop lane.
    if (wbCompiledLaneLayout != WbLayout.desktop) return;

    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSendScreenGalleryCase,
      label: 'Wallet',
      optionLabels: SendScreenWallet.values.map(sendScreenWalletLabel).toList(),
      otherKnobs: _desktop,
    );

    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSendScreenGalleryCase,
      label: 'Balance',
      optionLabels: SendScreenBalance.values
          .map(sendScreenBalanceLabel)
          .toList(),
      otherKnobs: _desktop,
    );

    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSendScreenGalleryCase,
      label: 'Privacy mode',
      optionLabels: const ['false', 'true'],
      otherKnobs: _desktop,
    );
  });

  testWidgets('desktop send screen covers its composer axes', (tester) async {
    if (wbCompiledLaneLayout != WbLayout.desktop) return;

    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSendScreenGalleryCase,
      label: 'Recipient',
      optionLabels: SendScreenRecipient.values
          .map(sendScreenRecipientLabel)
          .toList(),
      otherKnobs: _desktop,
    );

    final entered = await pumpUseCase(
      tester,
      buildSendScreenGalleryCase,
      knobs: {
        ..._desktop,
        'Amount': sendScreenAmountLabel(SendScreenAmount.entered),
      },
    );
    expect(entered.knobs.keys, contains('Price'));

    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSendScreenGalleryCase,
      label: 'Amount',
      optionLabels: SendScreenAmount.values.map(sendScreenAmountLabel).toList(),
      otherKnobs: _desktop,
    );

    final pickerOpen = await pumpUseCase(
      tester,
      buildSendScreenGalleryCase,
      knobs: {
        ..._desktop,
        'Contact picker': sendScreenContactPickerLabel(
          SendScreenContactPicker.open,
        ),
      },
    );
    expect(pickerOpen.knobs.keys, contains('Contacts'));

    // The conversion line only has something to convert once an amount is
    // entered, so a missing price is invisible on an empty field.
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSendScreenGalleryCase,
      label: 'Price',
      optionLabels: SendScreenPrice.values.map(sendScreenPriceLabel).toList(),
      otherKnobs: {
        ..._desktop,
        'Amount': sendScreenAmountLabel(SendScreenAmount.entered),
      },
    );

    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSendScreenGalleryCase,
      label: 'Contact picker',
      optionLabels: SendScreenContactPicker.values
          .map(sendScreenContactPickerLabel)
          .toList(),
      otherKnobs: _desktop,
    );

    // The address book only reaches the screen through the picker's list.
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSendScreenGalleryCase,
      label: 'Contacts',
      optionLabels: SendScreenContacts.values
          .map(sendScreenContactsLabel)
          .toList(),
      otherKnobs: {
        ..._desktop,
        'Contact picker': sendScreenContactPickerLabel(
          SendScreenContactPicker.open,
        ),
      },
    );
  });

  testWidgets('desktop send screen states each composer outcome in words', (
    tester,
  ) async {
    if (wbCompiledLaneLayout != WbLayout.desktop) return;

    // The gallery validator accepts the seeded address without Rust, while the
    // amount still exercises the screen's real balance guard.
    await pumpUseCase(
      tester,
      buildSendScreenGalleryCase,
      knobs: {
        ..._desktop,
        'Recipient': sendScreenRecipientLabel(SendScreenRecipient.validAddress),
        'Amount': sendScreenAmountLabel(SendScreenAmount.overBalance),
      },
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Address validation failed'), findsNothing);
    expect(find.text('Insufficient shielded balance'), findsOneWidget);

    // A contact-name prefix in a focused field opens the autocomplete list.
    await pumpUseCase(
      tester,
      buildSendScreenGalleryCase,
      knobs: {
        ..._desktop,
        'Recipient': sendScreenRecipientLabel(
          SendScreenRecipient.contactSuggestions,
        ),
      },
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Blue Door Coffee'), findsWidgets);

    await pumpUseCase(
      tester,
      buildSendScreenGalleryCase,
      knobs: {
        ..._desktop,
        'Contact picker': sendScreenContactPickerLabel(
          SendScreenContactPicker.open,
        ),
      },
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Contacts Zcash'), findsOneWidget);
    expect(find.text('Blue Door Coffee'), findsWidgets);

    await pumpUseCase(
      tester,
      buildSendScreenGalleryCase,
      knobs: {
        ..._desktop,
        'Contact picker': sendScreenContactPickerLabel(
          SendScreenContactPicker.open,
        ),
        'Contacts': sendScreenContactsLabel(SendScreenContacts.none),
      },
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('No Zcash contacts'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('desktop send screen reacts to a knob change without a remount', (
    tester,
  ) async {
    if (wbCompiledLaneLayout != WbLayout.desktop) return;

    // The running widgetbook rebuilds the case in place on a knob change, so
    // the mount driver only fires again if the fixture re-keys itself.
    await _pumpSendScreenInPlace(tester, {
      ..._desktop,
      'Contact picker': sendScreenContactPickerLabel(
        SendScreenContactPicker.closed,
      ),
    });
    expect(find.text('Contacts Zcash'), findsNothing);

    await _pumpSendScreenInPlace(tester, {
      ..._desktop,
      'Contact picker': sendScreenContactPickerLabel(
        SendScreenContactPicker.open,
      ),
    });
    expect(tester.takeException(), isNull);
    expect(find.text('Contacts Zcash'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('desktop send preview types, reviews and returns without Rust', (
    tester,
  ) async {
    if (wbCompiledLaneLayout != WbLayout.desktop) return;

    await pumpUseCase(tester, buildSendScreenGalleryCase, knobs: _desktop);
    await tester.enterText(
      _editableIn('send_address_field'),
      kSendScreenFixtureAddress,
    );
    await tester.enterText(_editableIn('send_amount_field'), '12.5');
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    final reviewButton = find.byKey(const ValueKey('send_review_button'));
    expect(tester.widget<AppButton>(reviewButton).onPressed, isNotNull);
    await tester.tap(reviewButton);
    await tester.pumpAndSettle();
    final review = tester.widget<SendReviewContentView>(
      find.byType(SendReviewContentView),
    );
    expect(
      (review.recipient as SendReviewAddressRecipient).address,
      kSendScreenFixtureAddress,
    );
    expect(
      find.text(truncatedAddress(kSendScreenFixtureAddress)),
      findsOneWidget,
    );
    expect(find.text('12.50 ZEC'), findsOneWidget);
    expect(find.textContaining('0.01 ZEC'), findsOneWidget);
    expect(find.text('Confirm & send'), findsOneWidget);
    expect(
      tester
          .widget<AppButton>(find.byKey(const ValueKey('send_confirm_button')))
          .onPressed,
      isNotNull,
    );

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('send_review_button')), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('desktop send screen can continue to a simulated result', (
    tester,
  ) async {
    if (wbCompiledLaneLayout != WbLayout.desktop) return;

    await pumpUseCase(tester, buildSendScreenGalleryCase, knobs: _desktop);
    await tester.enterText(
      _editableIn('send_address_field'),
      kSendScreenFixtureAddress,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use Max'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<EditableText>(_editableIn('send_amount_field'))
          .controller
          .text,
      '143.0212',
    );
    await tester.tap(find.byKey(const ValueKey('send_review_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('send_confirm_button')));
    await tester.pumpAndSettle();
    expect(find.text('Sent successfully'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('send_simulated_result_notice')),
      findsOneWidget,
    );
    await tester.tap(find.text('Back to review'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('send_confirm_button')), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('send_review_button')), findsOneWidget);
  });

  testWidgets('mobile send screen uses the connected production journey', (
    tester,
  ) async {
    await pumpUseCase(
      tester,
      buildSendScreenGalleryCase,
      knobs: _mobile,
      canvasSize: const Size(520, 932),
    );
    await tester.enterText(
      find.byKey(const ValueKey('mobile_send_address_input')),
      'u1garbage',
    );
    await tester.pumpAndSettle();
    expect(find.text('Invalid address'), findsOneWidget);
    expect(
      tester
          .widget<AppButton>(find.byKey(const ValueKey('mobile_send_continue')))
          .onPressed,
      isNull,
    );

    await tester.enterText(
      find.byKey(const ValueKey('mobile_send_address_input')),
      kSendScreenFixtureAddress,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mobile_send_continue')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mobile_send_max_button')));
    await tester.pumpAndSettle();
    expect(find.text('143.0212'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('mobile_send_review_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mobile_send_confirm')));
    await tester.pumpAndSettle();
    expect(find.byType(MobileSendStatusScreen), findsOneWidget);
    expect(
      find.byKey(const ValueKey('send_simulated_result_notice')),
      findsOneWidget,
    );
  });

  testWidgets('desktop send review covers its send-flow axes', (tester) async {
    // The three desktop screen cases are `WbLaneOnly(desktop)`, so this
    // sweep only has distinct renders in the desktop lane.
    if (wbCompiledLaneLayout != WbLayout.desktop) return;

    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSendReviewScreenGalleryCase,
      label: 'Flow',
      optionLabels: SendFlowKind.values.map(sendReviewScreenFlowLabel).toList(),
    );
    await drainSendReviewDiscard(tester);

    // Every remaining axis belongs to the send flow: the donation review has
    // no recipient, request or message row of its own.
    for (final sweep in <String, List<String>>{
      'Keystone account': const ['false', 'true'],
      'Recipient': SendReviewScreenRecipient.values
          .map(sendReviewScreenRecipientLabel)
          .toList(),
      'Recipient pool': SendReviewScreenPool.values
          .map(sendReviewScreenPoolLabel)
          .toList(),
      'Payment request': SendReviewScreenRequest.values
          .map(sendReviewScreenRequestLabel)
          .toList(),
      'Message': const ['false', 'true'],
    }.entries) {
      await expectKnobOptionsRenderDistinctly(
        tester,
        buildSendReviewScreenGalleryCase,
        label: sweep.key,
        optionLabels: sweep.value,
        otherKnobs: {'Flow': sendReviewScreenFlowLabel(SendFlowKind.send)},
      );
      await drainSendReviewDiscard(tester);
    }
  });

  testWidgets('send status screen covers both layouts', (tester) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSendStatusScreenGalleryCase,
      label: 'Layout',
      optionLabels: WbLayout.values.map(wbLayoutLabel).toList(),
    );
    await drainSendStatusHaptics(tester);
  });

  testWidgets('send status screen registers one axis set per layout', (
    tester,
  ) async {
    final desktop = await pumpUseCase(
      tester,
      buildSendStatusScreenGalleryCase,
      knobs: _desktop,
    );
    expect(
      desktop.knobs.keys,
      containsAll(<String>[
        'Layout',
        'Phase',
        'Keystone account',
        'Transaction hash',
        'Notice',
      ]),
    );
    expect(desktop.knobs.keys, isNot(contains('Status message')));

    // The mobile receipt has no Tx ID row and no notice line of its own; its
    // queued copy can come from the server instead.
    final mobile = await pumpUseCase(
      tester,
      buildSendStatusScreenGalleryCase,
      knobs: _mobile,
    );
    expect(
      mobile.knobs.keys,
      containsAll(<String>[
        'Layout',
        'Phase',
        'Status message',
        'Keystone account',
      ]),
    );
    expect(mobile.knobs.keys, isNot(contains('Transaction hash')));
    expect(mobile.knobs.keys, isNot(contains('Notice')));
    await disposeTree(tester);
    await drainSendStatusHaptics(tester);
  });

  testWidgets('desktop send status covers phase, account and notice', (
    tester,
  ) async {
    // The desktop branch is `WbLaneOnly(desktop)`, so this sweep only has
    // distinct renders in the desktop lane.
    if (wbCompiledLaneLayout != WbLayout.desktop) return;

    // The sending and queued phases share the in-progress visuals, so the
    // sweep keeps the Tx ID row on to tell them apart.
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSendStatusScreenGalleryCase,
      label: 'Phase',
      optionLabels: SendStatusScreenPhase.values
          .map(sendStatusScreenPhaseLabel)
          .toList(),
      otherKnobs: {..._desktop, 'Transaction hash': 'true'},
    );

    // Only the sending phase swaps in the Keystone submitting screen.
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSendStatusScreenGalleryCase,
      label: 'Keystone account',
      optionLabels: const ['false', 'true'],
      otherKnobs: {
        ..._desktop,
        'Phase': sendStatusScreenPhaseLabel(SendStatusScreenPhase.sending),
      },
    );

    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSendStatusScreenGalleryCase,
      label: 'Transaction hash',
      optionLabels: const ['false', 'true'],
      otherKnobs: {
        ..._desktop,
        'Phase': sendStatusScreenPhaseLabel(SendStatusScreenPhase.sent),
      },
    );

    // Guidance reads on a send that can still land; a reason only replaces
    // the default failure line once the send failed.
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSendStatusScreenGalleryCase,
      label: 'Notice',
      optionLabels: [
        sendStatusScreenNoticeLabel(SendStatusScreenNotice.none),
        sendStatusScreenNoticeLabel(SendStatusScreenNotice.broadcastGuidance),
      ],
      otherKnobs: {
        ..._desktop,
        'Phase': sendStatusScreenPhaseLabel(SendStatusScreenPhase.queued),
      },
    );

    await expectKnobOptionsRenderDistinctly(
      tester,
      buildSendStatusScreenGalleryCase,
      label: 'Notice',
      optionLabels: [
        sendStatusScreenNoticeLabel(SendStatusScreenNotice.none),
        sendStatusScreenNoticeLabel(SendStatusScreenNotice.failureReason),
      ],
      otherKnobs: {
        ..._desktop,
        'Phase': sendStatusScreenPhaseLabel(SendStatusScreenPhase.failed),
      },
    );
  });
}

/// `SendReviewScreen.dispose` releases its proposal through Rust, which is not
/// linked in a widget test: the call fails and retries on 100/200 ms timers.
/// Drain them so a swept case does not end the test with a pending timer.
Future<void> drainSendReviewDiscard(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

/// The phase name `MobileSendStatusScreen` builds its title key from.
String _statusPhaseKey(SendMobileStatusPhase phase) {
  return switch (phase) {
    SendMobileStatusPhase.sending => 'sending',
    SendMobileStatusPhase.queued => 'pendingBroadcast',
    SendMobileStatusPhase.sent => 'succeeded',
    SendMobileStatusPhase.failed => 'failed',
  };
}

/// A terminal receipt fires `AppHaptics.sendSuccess` / `sendFailure`, whose
/// non-iOS fallback chains 160/110 ms delays. Drain them so a swept case does
/// not end the test with a pending timer.
Future<void> drainSendStatusHaptics(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
}

/// Pumps the desktop send-screen case without the harness's unmount, so a
/// second call reuses the element tree the way a live knob change does.
Future<void> _pumpSendScreenInPlace(
  WidgetTester tester,
  Map<String, String> knobs,
) async {
  tester.view.physicalSize = const Size(1600, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: WidgetbookScope(
        state: WidgetbookState(
          root: WidgetbookRoot(children: []),
          queryParams: {'knobs': FieldCodec.encodeQueryGroup(knobs)},
        ),
        child: AppTheme(
          data: AppThemeData.dark,
          child: Material(
            type: MaterialType.transparency,
            child: Builder(builder: buildSendScreenGalleryCase),
          ),
        ),
      ),
    ),
  );
  // The mount driver reaches the contacts button over a few post-frame passes.
  for (var i = 0; i < 6; i++) {
    await tester.pump();
  }
}

Finder _editableIn(String key) => find.descendant(
  of: find.byKey(ValueKey(key)),
  matching: find.byType(EditableText),
);
