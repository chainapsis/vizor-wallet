// ignore_for_file: depend_on_referenced_packages
// Widgetbook is dev-only; every value in this file is deterministic fixture
// data and is intentionally isolated from payment-link services and storage.

import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../src/core/layout/app_desktop_shell.dart';
import '../src/core/profile_pictures.dart';
import '../src/core/theme/app_theme.dart';
import '../src/core/widgets/app_button.dart';
import '../src/core/widgets/app_icon.dart';
import '../src/core/widgets/app_profile_picture.dart';
import '../src/features/ledger/ledger_capability.dart';
import '../src/features/payment_links/models/vizor_payment_link.dart';
import '../src/features/payment_links/services/payment_link_service.dart';
import '../src/features/payment_links/widgets/payment_link_card_flip.dart';
import '../src/features/payment_links/widgets/payment_link_bulk_desktop_flow.dart';
import '../src/features/payment_links/widgets/payment_link_batch_detail_desktop_view.dart';
import '../src/features/payment_links/widgets/payment_link_card_motion.dart';
import '../src/features/payment_links/widgets/payment_link_confetti.dart';
import '../src/features/payment_links/widgets/payment_link_copy.dart';
import '../src/features/payment_links/widgets/payment_link_desktop_views.dart';
import '../src/features/payment_links/widgets/payment_link_gift_card.dart';
import '../src/features/payment_links/widgets/payment_link_long_sync_warning.dart';
import 'payment_link_amount_preview.dart';

const _previewWindowSize = Size(1080, 720);
const _message = 'Hey there! Welcome to the Shielded\nWorld ;)';
const kPaymentLinkPreviewFiatDelay = Duration(milliseconds: 1200);

final _previewGiftCardLink = VizorPaymentLink(
  network: 'main',
  address: 'u1previewgiftcardaddress',
  amountZatoshi: BigInt.from(445000000),
  mnemonic: List.filled(24, 'abandon').join(' '),
  birthdayHeight: 3000000,
  label: 'Payment link',
  createdAt: DateTime.utc(2026, 8, 6),
  presentation: const PaymentLinkPresentation(
    artworkId: 'diamond',
    message: 'A Gift Card for you!',
  ),
);

enum PaymentLinkPreviewState {
  empty,
  help,
  createEmpty,
  createFocused,
  createAmount,
  batchAmount,
  batchEmpty,
  batchCalculating,
  batchMinimum,
  batchMaximum,
  batchMixed,
  createSyncing,
  createInsufficient,
  createFiatLoading,
  createFiat,
  messageEmpty,
  messageFilled,
  review,
  reviewMessage,
  batchReview,
  batchReady,
  batchDetail,
  batchDetailMixed,
  batchPending,
  batchExport,
  readyWaiting,
  ready,
  cardsList,
  cardsListBatch,
  shareQr,
  cardsReceiving,
  cardsReceived,
  redeemPaste,
  redeemLongSyncWarning,
  redeemLoading,
  redeemInvalid,
  receivedWaiting,
  received,
  receivedChecking,
  receivedMessage,
}

Widget buildPaymentLinkEmptyUseCase(BuildContext context) =>
    const PaymentLinkDesktopPreview(state: PaymentLinkPreviewState.empty);

Widget buildPaymentLinkHelpUseCase(BuildContext context) =>
    const PaymentLinkDesktopPreview(state: PaymentLinkPreviewState.help);

Widget buildPaymentLinkCreateEmptyUseCase(BuildContext context) =>
    const PaymentLinkDesktopPreview(state: PaymentLinkPreviewState.createEmpty);

Widget buildPaymentLinkCreateFocusedUseCase(BuildContext context) =>
    const PaymentLinkDesktopPreview(
      state: PaymentLinkPreviewState.createFocused,
    );

Widget buildPaymentLinkCreateAmountUseCase(BuildContext context) =>
    const PaymentLinkDesktopPreview(
      state: PaymentLinkPreviewState.createAmount,
    );

Widget buildPaymentLinkBatchAmountUseCase(BuildContext context) =>
    const PaymentLinkDesktopPreview(state: PaymentLinkPreviewState.batchAmount);

Widget buildPaymentLinkLedgerEntryUseCase(BuildContext context) => ColoredBox(
  color: context.colors.background.window,
  child: PaymentLinksHomeDesktopView(
    isLedger: true,
    illustration: Image.asset(
      'assets/illustrations/payment_links/payment_link_empty_card.webp',
      width: 243,
      height: 162,
    ),
    onBack: _noop,
    onShowHelp: _noop,
    onCreate: _noop,
    onCreateMultiple: _noop,
    onRedeem: _noop,
  ),
);

Widget buildPaymentLinkLedgerBatchUseCase(BuildContext context) => ColoredBox(
  color: context.colors.background.window,
  child: const _PaymentLinkBulkPreview(isLedger: true, initialCount: 4),
);

Widget buildPaymentLinkLedgerBatchEmptyUseCase(BuildContext context) =>
    ColoredBox(
      color: context.colors.background.window,
      child: const _PaymentLinkBulkPreview(
        isLedger: true,
        initialCount: 2,
        initialAmount: '',
      ),
    );

Widget buildPaymentLinkLedgerBatchPreparingUseCase(BuildContext context) =>
    ColoredBox(
      color: context.colors.background.window,
      child: const _PaymentLinkBulkPreview(
        isLedger: true,
        initialCount: 4,
        initialPreparing: true,
      ),
    );

Widget buildPaymentLinkLedgerBatchErrorUseCase(BuildContext context) =>
    ColoredBox(
      color: context.colors.background.window,
      child: const _PaymentLinkBulkPreview(
        isLedger: true,
        initialCount: 4,
        error: 'Unable to calculate the fee. Try again.',
      ),
    );

Widget buildPaymentLinkBatchEmptyUseCase(BuildContext context) =>
    const PaymentLinkDesktopPreview(state: PaymentLinkPreviewState.batchEmpty);

Widget buildPaymentLinkBatchCalculatingUseCase(BuildContext context) =>
    const PaymentLinkDesktopPreview(
      state: PaymentLinkPreviewState.batchCalculating,
    );

Widget buildPaymentLinkBatchMinimumUseCase(BuildContext context) =>
    const PaymentLinkDesktopPreview(
      state: PaymentLinkPreviewState.batchMinimum,
    );

Widget buildPaymentLinkBatchMaximumUseCase(BuildContext context) =>
    const PaymentLinkDesktopPreview(
      state: PaymentLinkPreviewState.batchMaximum,
    );

Widget buildPaymentLinkCreateInsufficientUseCase(BuildContext context) =>
    const PaymentLinkDesktopPreview(
      state: PaymentLinkPreviewState.createInsufficient,
    );

Widget buildPaymentLinkCreateSyncingUseCase(BuildContext context) =>
    const PaymentLinkDesktopPreview(
      state: PaymentLinkPreviewState.createSyncing,
    );

Widget buildPaymentLinkCreateFiatLoadingUseCase(BuildContext context) =>
    const PaymentLinkDesktopPreview(
      state: PaymentLinkPreviewState.createFiatLoading,
    );

Widget buildPaymentLinkCreateFiatUseCase(BuildContext context) =>
    const PaymentLinkDesktopPreview(state: PaymentLinkPreviewState.createFiat);

Widget buildPaymentLinkInteractiveUseCase(BuildContext context) =>
    const PaymentLinkInteractiveDesktopPreview();

Widget buildPaymentLinkInteractiveFocusedUseCase(BuildContext context) =>
    const PaymentLinkInteractiveDesktopPreview(
      initialAmount: '4.45',
      focusAmount: true,
    );

Widget buildPaymentLinkMessageEmptyUseCase(BuildContext context) =>
    const PaymentLinkDesktopPreview(
      state: PaymentLinkPreviewState.messageEmpty,
    );

Widget buildPaymentLinkMessageFilledUseCase(BuildContext context) =>
    const PaymentLinkDesktopPreview(
      state: PaymentLinkPreviewState.messageFilled,
    );

Widget buildPaymentLinkMessageInteractiveUseCase(BuildContext context) =>
    const PaymentLinkInteractiveMessageDesktopPreview();

Widget buildPaymentLinkMessageEditingUseCase(BuildContext context) =>
    const PaymentLinkInteractiveMessageDesktopPreview(
      initialEditorRevealed: true,
    );

Widget buildPaymentLinkMessageTooLargeUseCase(BuildContext context) =>
    PaymentLinkInteractiveMessageDesktopPreview(
      initialEditorRevealed: true,
      initialMessage: List.filled(25, '👨‍👩‍👧‍👦').join(),
    );

Widget buildPaymentLinkReviewUseCase(BuildContext context) =>
    const PaymentLinkDesktopPreview(state: PaymentLinkPreviewState.review);

Widget buildPaymentLinkReviewMessageUseCase(BuildContext context) =>
    const PaymentLinkDesktopPreview(
      state: PaymentLinkPreviewState.reviewMessage,
    );

Widget buildPaymentLinkReadyWaitingUseCase(BuildContext context) =>
    const PaymentLinkDesktopPreview(
      state: PaymentLinkPreviewState.readyWaiting,
    );

Widget buildPaymentLinkReadyUseCase(BuildContext context) =>
    const PaymentLinkDesktopPreview(state: PaymentLinkPreviewState.ready);

Widget buildPaymentLinkBatchReviewUseCase(BuildContext context) =>
    const PaymentLinkDesktopPreview(state: PaymentLinkPreviewState.batchReview);

Widget buildPaymentLinkBatchReadyUseCase(BuildContext context) =>
    const PaymentLinkDesktopPreview(state: PaymentLinkPreviewState.batchReady);

Widget buildPaymentLinkBatchDetailUseCase(BuildContext context) =>
    const PaymentLinkDesktopPreview(state: PaymentLinkPreviewState.batchDetail);

Widget buildPaymentLinkBatchDetailMixedUseCase(BuildContext context) =>
    const PaymentLinkDesktopPreview(
      state: PaymentLinkPreviewState.batchDetailMixed,
    );

Widget buildPaymentLinkBatchMixedUseCase(BuildContext context) =>
    const PaymentLinkDesktopPreview(state: PaymentLinkPreviewState.batchMixed);

Widget buildPaymentLinkBatchExportUseCase(BuildContext context) =>
    const PaymentLinkDesktopPreview(state: PaymentLinkPreviewState.batchExport);

Widget buildPaymentLinkBatchPendingUseCase(BuildContext context) =>
    const PaymentLinkDesktopPreview(
      state: PaymentLinkPreviewState.batchPending,
    );

Widget buildPaymentLinkMotionHandoffUseCase(BuildContext context) =>
    const PaymentLinkMotionDesktopPreview();

Widget buildPaymentLinkCardsListUseCase(BuildContext context) =>
    const PaymentLinkDesktopPreview(state: PaymentLinkPreviewState.cardsList);

Widget buildPaymentLinkCardsListBatchUseCase(BuildContext context) =>
    const PaymentLinkDesktopPreview(
      state: PaymentLinkPreviewState.cardsListBatch,
    );

Widget buildPaymentLinkShareQrUseCase(BuildContext context) =>
    const PaymentLinkDesktopPreview(state: PaymentLinkPreviewState.shareQr);

Widget buildPaymentLinkCardsReceivingUseCase(BuildContext context) =>
    const PaymentLinkDesktopPreview(
      state: PaymentLinkPreviewState.cardsReceiving,
    );

Widget buildPaymentLinkCardsReceivedUseCase(BuildContext context) =>
    const PaymentLinkDesktopPreview(
      state: PaymentLinkPreviewState.cardsReceived,
    );

Widget buildPaymentLinkRedeemPasteUseCase(BuildContext context) =>
    const PaymentLinkDesktopPreview(state: PaymentLinkPreviewState.redeemPaste);

Widget buildPaymentLinkRedeemLongSyncWarningUseCase(BuildContext context) =>
    const PaymentLinkDesktopPreview(
      state: PaymentLinkPreviewState.redeemLongSyncWarning,
    );

Widget buildPaymentLinkRedeemLoadingUseCase(BuildContext context) =>
    const PaymentLinkDesktopPreview(
      state: PaymentLinkPreviewState.redeemLoading,
    );

Widget buildPaymentLinkRedeemInvalidUseCase(BuildContext context) =>
    const PaymentLinkDesktopPreview(
      state: PaymentLinkPreviewState.redeemInvalid,
    );

Widget buildPaymentLinkReceivedUseCase(BuildContext context) =>
    const PaymentLinkDesktopPreview(state: PaymentLinkPreviewState.received);

Widget buildPaymentLinkReceivedCheckingUseCase(BuildContext context) =>
    const PaymentLinkDesktopPreview(
      state: PaymentLinkPreviewState.receivedChecking,
    );

Widget buildPaymentLinkReceivedWaitingUseCase(BuildContext context) =>
    const PaymentLinkDesktopPreview(
      state: PaymentLinkPreviewState.receivedWaiting,
    );

Widget buildPaymentLinkReceivedMessageUseCase(BuildContext context) =>
    const PaymentLinkDesktopPreview(
      state: PaymentLinkPreviewState.receivedMessage,
    );

/// A deterministic desktop-only surface for Widgetbook and Figma capture.
///
/// This deliberately contains no provider, persistence, network, or Rust
/// dependency. Unsupported values such as messages and fees exist only in
/// this fixture layer.
class PaymentLinkDesktopPreview extends StatelessWidget {
  const PaymentLinkDesktopPreview({
    required this.state,
    this.content,
    super.key,
  });

  final PaymentLinkPreviewState state;
  final Widget? content;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: SizedBox.fromSize(
          size: _previewWindowSize,
          child: AppDesktopShell(
            sidebar: const _PaymentLinkPreviewSidebar(),
            pane: AppDesktopPane(
              padding: EdgeInsets.zero,
              child: content ?? _PaymentLinkPreviewPane(state: state),
            ),
          ),
        ),
      ),
    );
  }
}

class _PaymentLinkPreviewPane extends StatelessWidget {
  const _PaymentLinkPreviewPane({required this.state});

  final PaymentLinkPreviewState state;

  @override
  Widget build(BuildContext context) {
    return switch (state) {
      PaymentLinkPreviewState.empty => _home(),
      PaymentLinkPreviewState.help => PaymentLinkHowItWorksDesktopView(
        background: _home(),
        onClose: _noop,
      ),
      PaymentLinkPreviewState.createEmpty => const PaymentLinkAmountPreview(
        initialAmount: '',
        initialArtwork: PaymentLinkCardArtwork.gift,
      ),
      PaymentLinkPreviewState.createFocused => const PaymentLinkAmountPreview(
        initialAmount: '1',
        initialArtwork: PaymentLinkCardArtwork.gift,
        focusAmount: true,
      ),
      PaymentLinkPreviewState.createAmount => const PaymentLinkAmountPreview(
        initialAmount: '4.45',
      ),
      PaymentLinkPreviewState.batchAmount => const _PaymentLinkBulkPreview(),
      PaymentLinkPreviewState.batchEmpty => const _PaymentLinkBulkPreview(
        initialAmount: '',
      ),
      PaymentLinkPreviewState.batchCalculating => const _PaymentLinkBulkPreview(
        initialPreparing: true,
      ),
      PaymentLinkPreviewState.batchMinimum => const _PaymentLinkBulkPreview(
        initialCount: 2,
      ),
      PaymentLinkPreviewState.batchMaximum => const _PaymentLinkBulkPreview(
        initialCount: 50,
      ),
      PaymentLinkPreviewState.batchMixed => const _PaymentLinkBulkPreview(
        initialMixed: true,
      ),
      PaymentLinkPreviewState.createSyncing => const PaymentLinkAmountPreview(
        initialAmount: '4.45',
        initialArtwork: PaymentLinkCardArtwork.diamond,
        supportingText:
            'Card fee will be estimated when wallet sync completes.',
        enableContinue: false,
        showMax: false,
      ),
      PaymentLinkPreviewState.createInsufficient =>
        const PaymentLinkAmountPreview(
          initialAmount: '4.45',
          initialArtwork: PaymentLinkCardArtwork.diamond,
          supportingText: 'Above your maximum ZEC',
          supportingTextIsError: true,
          enableContinue: false,
        ),
      PaymentLinkPreviewState.createFiatLoading =>
        const PaymentLinkAmountPreview(
          initialAmount: '4.45',
          initialArtwork: PaymentLinkCardArtwork.ruby,
          priceAvailable: false,
          priceLoading: true,
        ),
      PaymentLinkPreviewState.createFiat => const PaymentLinkAmountPreview(
        initialAmount: '4.45',
        initialArtwork: PaymentLinkCardArtwork.ruby,
      ),
      PaymentLinkPreviewState.messageEmpty => PaymentLinkMessageDesktopView(
        state: PaymentLinkMessageVisualState.empty,
        card: const PaymentLinkGiftCard(
          artwork: PaymentLinkCardArtwork.ruby,
          showBack: true,
        ),
        onBack: _noop,
        onSkip: _noop,
      ),
      PaymentLinkPreviewState.messageFilled => PaymentLinkMessageDesktopView(
        state: PaymentLinkMessageVisualState.filled,
        card: const PaymentLinkGiftCard(
          artwork: PaymentLinkCardArtwork.ruby,
          showBack: true,
          message: _message,
          messageCharacterCount: 72,
          onDeleteMessage: _noop,
        ),
        onBack: _noop,
        onSkip: _noop,
        onContinue: _noop,
      ),
      PaymentLinkPreviewState.review => const _PaymentLinkReviewPreview(),
      PaymentLinkPreviewState.reviewMessage => const _PaymentLinkReviewPreview(
        initialShowBack: true,
      ),
      PaymentLinkPreviewState.batchReview => const _PaymentLinkBulkPreview(
        initialReviewing: true,
        initialMessage:
            'Thanks for coming to the Zcash meetup in Seoul! Claim your ZEC '
            'with this card and bring a friend to the next one.',
      ),
      PaymentLinkPreviewState.batchReady ||
      PaymentLinkPreviewState.batchDetail => _PaymentLinkBatchDetailPreview(
        justCreated: state == PaymentLinkPreviewState.batchReady,
      ),
      PaymentLinkPreviewState.batchDetailMixed =>
        const _PaymentLinkBatchDetailPreview(mixed: true),
      PaymentLinkPreviewState.batchPending =>
        const _PaymentLinkBatchDetailPreview(ready: false),
      PaymentLinkPreviewState.batchExport => const Stack(
        fit: StackFit.expand,
        children: [
          _PaymentLinkBatchDetailPreview(),
          PaymentLinkBatchExportModal(onConfirm: _noop, onCancel: _noop),
        ],
      ),
      PaymentLinkPreviewState.readyWaiting => PaymentLinkReadyDesktopView(
        state: PaymentLinkReadyVisualState.waiting,
        card: _readyCard(),
        decoration: const PaymentLinkConfetti(),
        onBack: _noop,
        onCopy: null,
      ),
      PaymentLinkPreviewState.receivedWaiting => PaymentLinkReadyDesktopView(
        state: PaymentLinkReadyVisualState.waiting,
        card: _readyCard(),
        onBack: _noop,
        onCopy: null,
        waitingHeading: 'Your Gift Card\nis almost ready!',
        waitingPrimaryText: kPaymentLinkClaimWaitingDescription,
        waitingSecondaryText: kPaymentLinkWaitingDescription,
        waitingStatusLabel: 'Wait 1:15 to claim',
      ),
      PaymentLinkPreviewState.ready => const _PaymentLinkReadyPreview(),
      PaymentLinkPreviewState.cardsList ||
      PaymentLinkPreviewState.cardsListBatch => PaymentLinkCardsDesktopView(
        sections: state == PaymentLinkPreviewState.cardsListBatch
            ? const [
                PaymentLinkCardsSection(
                  label: 'Groups',
                  cards: [
                    PaymentLinkBatchListRow(
                      thumbnail: _PaymentLinkThumbnail(
                        PaymentLinkCardArtwork.ruby,
                      ),
                      count: 20,
                      amountText: '0.1 ZEC',
                      dateText: 'July 2',
                      statusText: '3 of 20 used',
                      onOpen: _noop,
                    ),
                  ],
                ),
              ]
            : const [
                PaymentLinkCardsSection(
                  label: kPaymentLinkPendingSectionLabel,
                  cards: [
                    PaymentLinkCardListRow(
                      thumbnail: _PaymentLinkThumbnail(
                        PaymentLinkCardArtwork.dragon,
                      ),
                      amountText: '1.10 ZEC',
                      dateText: 'May 20',
                      statusText: 'Preparing…',
                      showLoader: true,
                    ),
                  ],
                ),
                PaymentLinkCardsSection(
                  label: kPaymentLinkUnusedSectionLabel,
                  cards: [
                    PaymentLinkCardListRow(
                      thumbnail: _PaymentLinkThumbnail(
                        PaymentLinkCardArtwork.ruby,
                      ),
                      amountText: '0.25 ZEC',
                      dateText: 'July 2',
                      showLinkActions: true,
                      onCopyLink: _noop,
                      onShowQr: _noop,
                    ),
                    PaymentLinkCardListRow(
                      thumbnail: _PaymentLinkThumbnail(
                        PaymentLinkCardArtwork.dragon,
                      ),
                      amountText: '1.10 ZEC',
                      dateText: 'May 20',
                      showLinkActions: true,
                      onCopyLink: _noop,
                      onShowQr: _noop,
                    ),
                  ],
                ),
                PaymentLinkCardsSection(
                  label: kPaymentLinkUsedSectionLabel,
                  cards: [
                    PaymentLinkCardListRow(
                      thumbnail: _PaymentLinkThumbnail(
                        PaymentLinkCardArtwork.chestLava,
                      ),
                      amountText: '2.5 ZEC',
                      dateText: 'July 20',
                      showLinkActions: true,
                      onCopyLink: _noop,
                      onShowQr: _noop,
                    ),
                    PaymentLinkCardListRow(
                      thumbnail: _PaymentLinkThumbnail(
                        PaymentLinkCardArtwork.chestLava,
                      ),
                      amountText: '2.5 ZEC',
                      dateText: 'July 20',
                      showLinkActions: true,
                      onCopyLink: _noop,
                      onShowQr: _noop,
                    ),
                    PaymentLinkCardListRow(
                      thumbnail: _PaymentLinkThumbnail(
                        PaymentLinkCardArtwork.chestLava,
                      ),
                      amountText: '2.5 ZEC',
                      dateText: 'July 20',
                      showLinkActions: true,
                      onCopyLink: _noop,
                      onShowQr: _noop,
                    ),
                    PaymentLinkCardListRow(
                      thumbnail: _PaymentLinkThumbnail(
                        PaymentLinkCardArtwork.chestLava,
                      ),
                      amountText: '2.5 ZEC',
                      dateText: 'July 20',
                      showLinkActions: true,
                      onCopyLink: _noop,
                      onShowQr: _noop,
                    ),
                  ],
                ),
              ],
        onBack: _noop,
        onCreate: _noop,
        onCreateMultiple: _noop,
        onRedeem: _noop,
      ),
      PaymentLinkPreviewState.shareQr => PaymentLinkShareQrDesktopView(
        artwork: PaymentLinkCardArtwork.diamond,
        qrData: _previewGiftCardLink.toUri().toString(),
        onBack: _noop,
        onSaveQr: _noop,
        onCopyLink: _noop,
      ),
      PaymentLinkPreviewState.cardsReceiving => _receivedCardsList(
        statusText: 'Receiving…',
      ),
      PaymentLinkPreviewState.cardsReceived => _receivedCardsList(
        statusText: 'Received',
      ),
      PaymentLinkPreviewState.redeemPaste => PaymentLinkRedeemDesktopView(
        state: PaymentLinkRedeemVisualState.paste,
        onBack: _noop,
        onPaste: _noop,
        onScan: _noop,
        subtitle: 'Copy the card link you’ve received, and paste it below.',
        pasteLabel: 'Paste card link',
      ),
      PaymentLinkPreviewState.redeemLongSyncWarning => Stack(
        fit: StackFit.expand,
        children: [
          PaymentLinkRedeemDesktopView(
            state: PaymentLinkRedeemVisualState.paste,
            onBack: _noop,
            onPaste: _noop,
            onScan: _noop,
            subtitle: 'Copy the card link you’ve received, and paste it below.',
            pasteLabel: 'Paste card link',
          ),
          const PaymentLinkLongSyncWarningModal(
            onConfirm: _noop,
            onCancel: _noop,
          ),
        ],
      ),
      PaymentLinkPreviewState.redeemLoading =>
        const PaymentLinkRedeemDesktopView(
          state: PaymentLinkRedeemVisualState.loading,
          onBack: _noop,
          subtitle: 'Copy the card link you’ve received, and paste it below.',
        ),
      PaymentLinkPreviewState.redeemInvalid => PaymentLinkRedeemDesktopView(
        state: PaymentLinkRedeemVisualState.invalid,
        onBack: _noop,
        onPaste: _noop,
        onScan: _noop,
        onClearClipboard: _noop,
        subtitle: 'Copy the card link you’ve received, and paste it below.',
        pasteLabel: 'Paste card link',
        clearLabel: 'Clear clipboard',
      ),
      PaymentLinkPreviewState.received => const _PaymentLinkReceivedPreview(
        hasMessage: false,
      ),
      PaymentLinkPreviewState.receivedChecking =>
        const _PaymentLinkReceivedPreview(hasMessage: false, checking: true),
      PaymentLinkPreviewState.receivedMessage =>
        const _PaymentLinkReceivedPreview(hasMessage: true),
    };
  }

  PaymentLinksHomeDesktopView _home() {
    return PaymentLinksHomeDesktopView(
      illustration: Image.asset(
        'assets/illustrations/payment_links/payment_link_empty_card.webp',
        width: 243,
        height: 162,
        fit: BoxFit.contain,
        semanticLabel: 'Gift box',
      ),
      onBack: _noop,
      onShowHelp: _noop,
      onCreate: _noop,
      onCreateMultiple: _noop,
      onRedeem: _noop,
    );
  }

  PaymentLinkCardsDesktopView _receivedCardsList({required String statusText}) {
    return PaymentLinkCardsDesktopView(
      sections: [
        PaymentLinkCardsSection(
          label: 'Received',
          cards: [
            PaymentLinkCardListRow(
              thumbnail: const _PaymentLinkThumbnail(
                PaymentLinkCardArtwork.ruby,
              ),
              amountText: '4.45 ZEC',
              dateText: 'August 7',
              statusText: statusText,
              showLoader: statusText == 'Receiving…',
            ),
          ],
        ),
      ],
      onBack: _noop,
      onCreate: _noop,
      onCreateMultiple: _noop,
      onRedeem: _noop,
      activeTab: PaymentLinkCardsTab.received,
    );
  }

  static Widget _readyCard() {
    return const PaymentLinkGiftCard(
      artwork: PaymentLinkCardArtwork.ruby,
      amountText: '4.45',
      supportingText: r'$1,210.20',
      showCaret: false,
    );
  }
}

class _PaymentLinkBatchDetailPreview extends StatelessWidget {
  const _PaymentLinkBatchDetailPreview({
    this.justCreated = false,
    this.ready = true,
    this.mixed = false,
  });

  final bool justCreated;
  final bool ready;
  final bool mixed;

  /// A group a few days after it was handed out; a just-created group cannot
  /// have been claimed yet.
  static const _used = {1, 2, 3, 5};
  static const _detected = {8, 11};

  @override
  Widget build(BuildContext context) {
    final artworks = mixed
        ? paymentLinkMixedArtworks(20, random: Random(7))
        : List.filled(20, PaymentLinkCardArtwork.ruby);
    PaymentLinkBatchMemberRow row(int index) {
      final detected = !justCreated && _detected.contains(index);
      final used = detected || (!justCreated && _used.contains(index));
      return PaymentLinkBatchMemberRow(
        index: index,
        artwork: artworks[index - 1],
        statusLabel: detected
            ? 'Use detected'
            : used
            ? 'Used'
            : 'Unused',
        used: used,
        note: detected ? 'Use detected' : null,
        onCopyLink: _noop,
        onShowQr: _noop,
      );
    }

    final rows = [for (var index = 1; index <= 20; index++) row(index)];
    return PaymentLinkBatchDetailDesktopView(
      count: 20,
      amountPerCardText: '0.1',
      artwork: artworks.first,
      backArtworks: mixed ? artworks.sublist(1) : const [],
      dateText: 'September 23',
      ready: ready,
      justCreated: justCreated,
      onBack: _noop,
      onExport: _noop,
      onCheckStatus: _noop,
      usageActivity: const PaymentLinkBatchUsageActivity(
        checkedText: 'Checked just now',
      ),
      sections: [
        PaymentLinkCardsSection(
          label: kPaymentLinkUnusedSectionLabel,
          cards: [
            for (final row in rows)
              if (!row.used) row,
          ],
        ),
        PaymentLinkCardsSection(
          label: kPaymentLinkUsedSectionLabel,
          cards: [
            for (final row in rows)
              if (row.used) row,
          ],
        ),
      ],
    );
  }
}

class _PaymentLinkReviewPreview extends StatefulWidget {
  const _PaymentLinkReviewPreview({this.initialShowBack = false});

  final bool initialShowBack;

  @override
  State<_PaymentLinkReviewPreview> createState() =>
      _PaymentLinkReviewPreviewState();
}

class _PaymentLinkReviewPreviewState extends State<_PaymentLinkReviewPreview> {
  late bool _showBack = widget.initialShowBack;

  @override
  Widget build(BuildContext context) {
    return PaymentLinkReviewDesktopView(
      card: PaymentLinkCardFlip(
        showBack: _showBack,
        front: PaymentLinkGiftCard(
          artwork: PaymentLinkCardArtwork.ruby,
          amountText: '4.45',
          supportingText: r'$1,210.20',
          showCaret: false,
          onTap: () => setState(() => _showBack = true),
          semanticLabel: 'Reveal gift card message',
        ),
        back: PaymentLinkGiftCard(
          artwork: PaymentLinkCardArtwork.ruby,
          showBack: true,
          message: _message,
          onTap: () => setState(() => _showBack = false),
          semanticLabel: 'Show gift card front',
        ),
      ),
      onBack: _noop,
      onConfirm: _noop,
      cardAmountText: '4.45 ZEC',
      cardFeeText: '0.04 ZEC',
      totalAmountText: '4.49 ZEC',
    );
  }
}

class _PaymentLinkBulkPreview extends StatefulWidget {
  const _PaymentLinkBulkPreview({
    this.initialReviewing = false,
    this.initialCount = 20,
    this.initialAmount = '0.1',
    this.initialPreparing = false,
    this.initialMixed = false,
    this.initialMessage = '',
    this.isLedger = false,
    this.error,
  });

  final bool initialReviewing;
  final int initialCount;
  final String initialAmount;
  final bool initialPreparing;
  final bool initialMixed;
  final String initialMessage;
  final bool isLedger;
  final String? error;

  @override
  State<_PaymentLinkBulkPreview> createState() =>
      _PaymentLinkBulkPreviewState();
}

class _PaymentLinkBulkPreviewState extends State<_PaymentLinkBulkPreview> {
  late final _amount = TextEditingController(text: widget.initialAmount);
  late final _message = TextEditingController(text: widget.initialMessage);
  late int _count = widget.initialCount;
  var _artwork = PaymentLinkCardArtwork.ruby;
  // Seeded so captures stay deterministic.
  late List<PaymentLinkCardArtwork>? _mixed = widget.initialMixed
      ? paymentLinkMixedArtworks(50, random: Random(7))
      : null;
  late bool _reviewing = widget.initialReviewing;

  @override
  void dispose() {
    _amount.dispose();
    _message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PaymentLinkBulkDesktopFlow(
    count: _count,
    maxCount: widget.isLedger ? kLedgerMaxExternalShieldedOutputs : 50,
    isLedger: widget.isLedger,
    amountController: _amount,
    messageController: _message,
    artwork: _artwork,
    mixedArtworks: _mixed?.take(_count).toList(),
    onMixChanged: (mixed) => setState(
      () => _mixed = mixed
          ? paymentLinkMixedArtworks(50, random: Random(7))
          : null,
    ),
    spendable: BigInt.from(_count > 30 ? 1000000000 : 400000000),
    quote:
        widget.initialPreparing || widget.error != null || _amount.text.isEmpty
        ? null
        : PaymentLinkBatchQuote(
            sourceAccountUuid: 'preview-account',
            count: _count,
            recipientAmountZatoshi: BigInt.from(10000000),
            fundingFeeZatoshi: BigInt.from(150000),
          ),
    preparing: widget.initialPreparing,
    reviewing: _reviewing,
    submitting: false,
    retrySaving: false,
    error: widget.error,
    onRetry: widget.error == null ? null : _noop,
    onCountChanged: (count) => setState(() => _count = count),
    onAmountChanged: (_) => setState(() {}),
    onMessageChanged: (_) => setState(() {}),
    onArtworkChanged: (artwork) => setState(() {
      _artwork = artwork;
      _mixed = null;
    }),
    onReview:
        widget.initialPreparing || widget.error != null || _amount.text.isEmpty
        ? null
        : () => setState(() => _reviewing = true),
    onEdit: () => setState(() => _reviewing = false),
    onCreate: _noop,
    onBack: _noop,
  );
}

class _PaymentLinkReadyPreview extends StatefulWidget {
  const _PaymentLinkReadyPreview();

  @override
  State<_PaymentLinkReadyPreview> createState() =>
      _PaymentLinkReadyPreviewState();
}

class _PaymentLinkReadyPreviewState extends State<_PaymentLinkReadyPreview> {
  bool _showBack = false;

  void _toggleCardSide() => setState(() => _showBack = !_showBack);

  @override
  Widget build(BuildContext context) {
    return PaymentLinkReadyDesktopView(
      state: PaymentLinkReadyVisualState.ready,
      card: PaymentLinkCardFlip(
        showBack: _showBack,
        front: const PaymentLinkGiftCard(
          artwork: PaymentLinkCardArtwork.ruby,
          amountText: '4.45',
          supportingText: r'$1,210.20',
          showCaret: false,
        ),
        back: const PaymentLinkGiftCard(
          artwork: PaymentLinkCardArtwork.ruby,
          showBack: true,
          message: _message,
          messageCharacterCount: 72,
        ),
      ),
      decoration: const PaymentLinkConfetti(),
      onBack: _noop,
      onCopy: _noop,
      onCardTap: _toggleCardSide,
    );
  }
}

/// Local-only motion playground for replaying the designer handoff without
/// wallet state, network calls, storage, or Rust initialization.
class PaymentLinkMotionDesktopPreview extends StatefulWidget {
  const PaymentLinkMotionDesktopPreview({super.key});

  @override
  State<PaymentLinkMotionDesktopPreview> createState() =>
      _PaymentLinkMotionDesktopPreviewState();
}

class _PaymentLinkMotionDesktopPreviewState
    extends State<PaymentLinkMotionDesktopPreview> {
  int _playback = 0;
  bool _showBack = false;

  void _replay() {
    setState(() {
      _playback += 1;
      _showBack = false;
    });
  }

  void _flip() => setState(() => _showBack = !_showBack);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox.fromSize(
        size: _previewWindowSize,
        child: ColoredBox(
          color: context.colors.background.window,
          child: Column(
            children: [
              const SizedBox(height: AppSpacing.xl),
              Text(
                'Gift Card motion handoff',
                style: AppTypography.displayMedium.copyWith(
                  color: context.colors.text.accent,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Replay the reveal, flip the card, or move the pointer over it.',
                style: AppTypography.bodyMedium.copyWith(
                  color: context.colors.text.secondary,
                ),
              ),
              Expanded(
                child: Center(
                  child: SizedBox(
                    width: 680,
                    height: 505,
                    child: Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.center,
                      children: [
                        PaymentLinkConfetti(
                          key: ValueKey('motion-confetti-$_playback'),
                          alignment: Alignment.center,
                        ),
                        PaymentLinkCardMotion(
                          key: ValueKey('motion-card-$_playback'),
                          celebrate: true,
                          child: PaymentLinkCardFlip(
                            showBack: _showBack,
                            front: const PaymentLinkGiftCard(
                              artwork: PaymentLinkCardArtwork.ruby,
                              amountText: '4.45',
                              supportingText: r'$1,210.20',
                              showCaret: false,
                            ),
                            back: const PaymentLinkGiftCard(
                              artwork: PaymentLinkCardArtwork.ruby,
                              showBack: true,
                              message: _message,
                              messageCharacterCount: 72,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AppButton(
                    key: const ValueKey('payment_link_motion_replay'),
                    onPressed: _replay,
                    size: AppButtonSize.mediumLarge,
                    child: const Text('Replay animation'),
                  ),
                  const SizedBox(width: AppSpacing.s),
                  AppButton(
                    key: const ValueKey('payment_link_motion_flip'),
                    onPressed: _flip,
                    size: AppButtonSize.mediumLarge,
                    child: Text(_showBack ? 'Show artwork' : 'Show message'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
            ],
          ),
        ),
      ),
    );
  }
}

/// Interactive message-entry surface kept separate from the deterministic
/// empty and filled Figma fixtures.
class PaymentLinkInteractiveMessageDesktopPreview extends StatefulWidget {
  const PaymentLinkInteractiveMessageDesktopPreview({
    this.initialEditorRevealed = false,
    this.initialMessage = '',
    super.key,
  });

  final bool initialEditorRevealed;
  final String initialMessage;

  @override
  State<PaymentLinkInteractiveMessageDesktopPreview> createState() =>
      _PaymentLinkInteractiveMessageDesktopPreviewState();
}

class _PaymentLinkInteractiveMessageDesktopPreviewState
    extends State<PaymentLinkInteractiveMessageDesktopPreview> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();
  late bool _editorRevealed;
  bool get _hasMessage => _controller.text.isNotEmpty;
  bool get _messageExceedsByteLimit =>
      !PaymentLinkPresentation.isMessageWithinUtf8ByteLimit(_controller.text);

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialMessage);
    _editorRevealed = widget.initialEditorRevealed;
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _clearMessage() {
    _controller.clear();
    _focusNode.requestFocus();
    setState(() {});
  }

  void _revealEditor() {
    if (_editorRevealed) {
      _focusNode.requestFocus();
      return;
    }
    setState(() => _editorRevealed = true);
  }

  void _focusVisibleEditor(bool showingBack) {
    if (!showingBack || !mounted || !_editorRevealed) return;
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox.fromSize(
        size: _previewWindowSize,
        child: AppDesktopShell(
          sidebar: const _PaymentLinkPreviewSidebar(),
          pane: AppDesktopPane(
            padding: EdgeInsets.zero,
            child: PaymentLinkMessageDesktopView(
              state: _hasMessage
                  ? PaymentLinkMessageVisualState.filled
                  : PaymentLinkMessageVisualState.empty,
              card: PaymentLinkCardFlip(
                showBack: _editorRevealed,
                front: PaymentLinkGiftCard(
                  artwork: PaymentLinkCardArtwork.ruby,
                  showBack: true,
                  message: _controller.text,
                  onTap: _revealEditor,
                  semanticLabel: 'Start writing gift card message',
                ),
                back: PaymentLinkGiftCard(
                  artwork: PaymentLinkCardArtwork.ruby,
                  showBack: true,
                  messageController: _controller,
                  messageFocusNode: _focusNode,
                  messageEditorKey: const ValueKey(
                    'payment_link_interactive_message_editor',
                  ),
                  messageInputFormatters: [
                    LengthLimitingTextInputFormatter(128),
                  ],
                  onMessageChanged: (_) => setState(() {}),
                  onDeleteMessage: _hasMessage ? _clearMessage : null,
                  semanticLabel: 'Gift card message input',
                ),
                onVisibleSideChanged: _focusVisibleEditor,
              ),
              onBack: _noop,
              onSkip: _clearMessage,
              onContinue: _hasMessage && !_messageExceedsByteLimit
                  ? _noop
                  : null,
              errorText: _messageExceedsByteLimit
                  ? kPaymentLinkMessageTooLargeText
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

class _PaymentLinkReceivedPreview extends StatefulWidget {
  const _PaymentLinkReceivedPreview({
    required this.hasMessage,
    this.checking = false,
  });

  final bool hasMessage;
  final bool checking;

  @override
  State<_PaymentLinkReceivedPreview> createState() =>
      _PaymentLinkReceivedPreviewState();
}

class _PaymentLinkReceivedPreviewState
    extends State<_PaymentLinkReceivedPreview> {
  late bool _showBack;

  @override
  void initState() {
    super.initState();
    _showBack = false;
  }

  void _toggleCardSide() => setState(() => _showBack = !_showBack);

  @override
  Widget build(BuildContext context) {
    if (widget.checking) {
      return PaymentLinkReadyDesktopView(
        state: PaymentLinkReadyVisualState.checking,
        card: const PaymentLinkGiftCard(
          artwork: PaymentLinkCardArtwork.ruby,
          amountText: '4.45',
          supportingText: r'$1,210.20',
          showCaret: false,
        ),
        onBack: _noop,
        onCopy: null,
        waitingStatusLabel: 'Checking the gift… 50%',
      );
    }
    if (!widget.hasMessage) {
      return PaymentLinkReceivedDesktopView(
        card: const PaymentLinkGiftCard(
          artwork: PaymentLinkCardArtwork.ruby,
          amountText: '4.45',
          supportingText: r'$1,210.20',
          showCaret: false,
        ),
        decoration: const PaymentLinkConfetti(),
        onBack: _noop,
        onClaim: _noop,
      );
    }
    return PaymentLinkReceivedDesktopView(
      card: PaymentLinkCardFlip(
        showBack: _showBack,
        front: const PaymentLinkGiftCard(
          artwork: PaymentLinkCardArtwork.ruby,
          amountText: '4.45',
          supportingText: r'$1,210.20',
          showCaret: false,
        ),
        back: const PaymentLinkGiftCard(
          artwork: PaymentLinkCardArtwork.ruby,
          showBack: true,
          message: _message,
          messageCharacterCount: 72,
        ),
      ),
      decoration: const PaymentLinkConfetti(),
      onBack: _noop,
      onClaim: _noop,
      onRevealMessage: _toggleCardSide,
      cardActionLabel: _showBack
          ? 'Show gift card artwork'
          : 'Reveal gift card message',
    );
  }
}

/// An interactive, local-only amount and artwork simulator for Widgetbook.
///
/// It deliberately uses a fixed fake conversion rate and a local timer so it
/// never reaches payment-link providers, storage, network, or Rust code.
class PaymentLinkInteractiveDesktopPreview extends StatelessWidget {
  const PaymentLinkInteractiveDesktopPreview({
    this.initialAmount = '',
    this.focusAmount = false,
    super.key,
  });

  final String initialAmount;
  final bool focusAmount;

  @override
  Widget build(BuildContext context) => PaymentLinkDesktopPreview(
    state: PaymentLinkPreviewState.createAmount,
    content: PaymentLinkAmountPreview(
      initialAmount: initialAmount,
      initialArtwork: PaymentLinkCardArtwork.gift,
      focusAmount: focusAmount,
      priceDelay: kPaymentLinkPreviewFiatDelay,
    ),
  );
}

class _PaymentLinkThumbnail extends StatelessWidget {
  const _PaymentLinkThumbnail(this.artwork);

  final PaymentLinkCardArtwork artwork;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      artwork.assetPath,
      fit: BoxFit.cover,
      excludeFromSemantics: true,
    );
  }
}

class _PaymentLinkPreviewSidebar extends StatelessWidget {
  const _PaymentLinkPreviewSidebar();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AppDesktopSidebarSurface(
      glass: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _PaymentLinkPreviewAccountHeader(),
            const SizedBox(height: AppSpacing.md),
            const AppSidebarItem(
              label: 'Home',
              iconName: AppIcons.home,
              active: true,
            ),
            const SizedBox(height: AppSpacing.xs),
            AppSidebarItem(
              label: 'Swap',
              iconName: AppIcons.swapArrows,
              onTap: _noop,
            ),
            const SizedBox(height: AppSpacing.xs),
            AppSidebarItem(
              label: 'Vote',
              iconName: AppIcons.scroll,
              onTap: _noop,
            ),
            const SizedBox(height: AppSpacing.xs),
            AppSidebarItem(
              label: 'Activity',
              iconName: AppIcons.history,
              onTap: _noop,
            ),
            const Spacer(),
            AppSidebarItem(
              label: 'Settings',
              iconName: AppIcons.cog,
              onTap: _noop,
            ),
            const SizedBox(height: AppSpacing.xs),
            AppSidebarItem(
              label: 'Sign out',
              iconName: AppIcons.logOut,
              onTap: _noop,
            ),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              height: 20,
              child: Row(
                children: [
                  Container(
                    width: 5,
                    decoration: BoxDecoration(
                      color: colors.sync.lightSuccess,
                      borderRadius: const BorderRadius.horizontal(
                        right: Radius.circular(AppRadii.full),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    '34% Syncing...',
                    style: AppTypography.labelLarge.copyWith(
                      color: colors.sync.textSyncing,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaymentLinkPreviewAccountHeader extends StatelessWidget {
  const _PaymentLinkPreviewAccountHeader();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          const AppProfilePicture(
            profilePictureId: kDefaultProfilePictureId,
            size: AppProfilePictureSize.large,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Username',
                  style: AppTypography.labelLarge.copyWith(
                    color: colors.text.accent,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  '142.23 ZEC',
                  style: AppTypography.labelLarge.copyWith(
                    fontWeight: FontWeight.w400,
                    color: colors.text.secondary,
                  ),
                ),
              ],
            ),
          ),
          AppIcon(AppIcons.copy, size: 16, color: colors.icon.muted),
        ],
      ),
    );
  }
}

void _noop() {}
