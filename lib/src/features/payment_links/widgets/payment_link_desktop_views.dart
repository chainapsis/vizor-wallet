import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_modal_card.dart';
import '../../../core/widgets/app_pane_modal_overlay.dart';
import '../../../core/widgets/app_tooltip.dart';
import 'payment_link_action.dart';
import 'payment_link_card_motion.dart';
import 'payment_link_cards_layout.dart';
import 'payment_link_copy.dart';
import 'payment_link_gift_card.dart';
import 'payment_link_qr_share_card.dart';
import 'payment_link_wizard_chrome.dart';

export 'payment_link_cards_layout.dart'
    show PaymentLinkCardsSection, PaymentLinkCardsTab;

const kPaymentLinkMessageTooLargeText =
    'This message is too large. Try using fewer complex emoji.';
const _wizardCardTopSpacing = 78.0;

/// Static desktop states represented by the payment-link Figma flow.
///
/// These values describe presentation only. They deliberately do not mirror
/// payment-link persistence, sync, transaction, or claim state.
enum PaymentLinkAmountVisualState {
  empty,
  focused,
  amount,
  fiatLoading,
  fiatLoaded,
}

enum PaymentLinkMessageVisualState { empty, filled }

enum PaymentLinkReadyVisualState { waiting, ready }

enum PaymentLinkRedeemVisualState { paste, loading, invalid, unavailable }

/// Empty Gift Cards landing surface.
class PaymentLinksHomeDesktopView extends StatelessWidget {
  const PaymentLinksHomeDesktopView({
    required this.illustration,
    required this.onBack,
    required this.onShowHelp,
    required this.onCreate,
    required this.onRedeem,
    this.backLabel = 'Home',
    this.title = kPaymentLinkEmptyTitle,
    this.helpLabel = kPaymentLinkHowItWorksTitle,
    this.createLabel = 'Create new card',
    this.redeemLabel = kPaymentLinkRedeemCardLabel,
    super.key,
  });

  final Widget illustration;
  final VoidCallback onBack;
  final VoidCallback onShowHelp;
  final VoidCallback onCreate;
  final VoidCallback onRedeem;
  final String backLabel;
  final String title;
  final String helpLabel;
  final String createLabel;
  final String redeemLabel;

  @override
  Widget build(BuildContext context) {
    return PaymentLinkPane(
      backLabel: backLabel,
      onBack: onBack,
      child: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: 420,
          height: 624,
          child: Stack(
            children: [
              Positioned(
                top: 95.5,
                left: 40,
                child: SizedBox(
                  width: 340,
                  height: 220,
                  child: Center(child: illustration),
                ),
              ),
              Positioned(
                top: 339.5,
                left: 0,
                right: 0,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: AppTypography.headlineLarge.copyWith(
                        color: context.colors.text.accent,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s),
                    PaymentLinkTextAction(
                      label: helpLabel,
                      onTap: onShowHelp,
                      trailing: AppIcon(
                        AppIcons.help,
                        size: 16,
                        color: context.colors.icon.regular,
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                top: 444.5,
                left: 0,
                right: 0,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppButton(
                      key: const ValueKey('payment_link_create_card_button'),
                      onPressed: onCreate,
                      size: AppButtonSize.mediumLarge,
                      leading: const AppIcon(
                        AppIcons.giftCard,
                        size: AppIconSize.medium,
                      ),
                      child: Text(createLabel),
                    ),
                    const SizedBox(height: AppSpacing.s),
                    PaymentLinkTextAction(label: redeemLabel, onTap: onRedeem),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Read-only Figma help overlay. Its body strings are fixture copy and must
/// not be treated as a protocol or security contract.
class PaymentLinkHowItWorksDesktopView extends StatelessWidget {
  const PaymentLinkHowItWorksDesktopView({
    required this.background,
    required this.onClose,
    this.title = kPaymentLinkHowItWorksTitle,
    this.subtitle = kPaymentLinkHowItWorksSubtitle,
    this.createDescription =
        'Enter amount to gift, pick a design, add a message (optional) '
        'and create your Card with a single click.',
    this.shareDescription =
        'After the card is created, you will get a unique Link containing its '
        'claim secret. Send it only to the intended recipient.',
    this.redeemDescription =
        'Recipient can redeem the Card in their Vizor wallet using the Link. '
        'The sender covers the deposit and redeem fees, so the recipient '
        'receives the full Card amount.',
    this.closeLabel = 'Close',
    super.key,
  });

  final Widget background;
  final VoidCallback onClose;
  final String title;
  final String subtitle;
  final String createDescription;
  final String shareDescription;
  final String redeemDescription;
  final String closeLabel;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        background,
        AppPaneModalOverlay(
          onDismiss: onClose,
          child: AppModalCard(
            highlight: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  title,
                  style: AppTypography.labelLarge.copyWith(
                    color: context.colors.text.accent,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  subtitle,
                  style: AppTypography.bodyMedium.copyWith(
                    color: context.colors.text.secondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                PaymentLinkHelpStep(
                  icon: AppIcons.giftCard,
                  text: createDescription,
                ),
                const SizedBox(height: AppSpacing.xs),
                PaymentLinkHelpStep(
                  icon: AppIcons.link,
                  text: shareDescription,
                ),
                const SizedBox(height: AppSpacing.xs),
                PaymentLinkHelpStep(
                  icon: AppIcons.arrowDownCircle,
                  text: redeemDescription,
                ),
                const SizedBox(height: AppSpacing.md),
                AppButton(
                  key: const ValueKey('payment_link_help_close_button'),
                  onPressed: onClose,
                  variant: AppButtonVariant.ghost,
                  size: AppButtonSize.mediumLarge,
                  expand: true,
                  child: Text(closeLabel),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Amount/design step. The card and design picker are independent slots so
/// this layout stays decoupled from card rendering and selection state.
class PaymentLinkAmountDesktopView extends StatelessWidget {
  const PaymentLinkAmountDesktopView({
    required this.state,
    required this.card,
    required this.cardSelector,
    required this.onBack,
    this.onCreate,
    this.onStepSelected,
    this.supportingText,
    this.supportingTextIsError = false,
    this.backLabel = 'Home',
    this.title = kPaymentLinkCreateGiftCardTitle,
    this.subtitle = 'Enter amount & select the design.',
    this.createLabel = 'Continue',
    this.emptyActionLabel = 'Continue',
    super.key,
  });

  final PaymentLinkAmountVisualState state;
  final Widget card;
  final Widget cardSelector;
  final VoidCallback onBack;
  final VoidCallback? onCreate;
  final ValueChanged<int>? onStepSelected;
  final String? supportingText;
  final bool supportingTextIsError;
  final String backLabel;
  final String title;
  final String subtitle;
  final String createLabel;
  final String emptyActionLabel;

  bool get _hasAmount => switch (state) {
    PaymentLinkAmountVisualState.amount ||
    PaymentLinkAmountVisualState.fiatLoading ||
    PaymentLinkAmountVisualState.fiatLoaded => true,
    PaymentLinkAmountVisualState.empty ||
    PaymentLinkAmountVisualState.focused => false,
  };

  @override
  Widget build(BuildContext context) {
    final canContinue = _hasAmount && onCreate != null;
    return PaymentLinkWizardPane(
      title: title,
      subtitle: subtitle,
      currentStep: 0,
      backLabel: backLabel,
      onBack: onBack,
      onStepSelected: onStepSelected,
      childSpacing: _wizardCardTopSpacing,
      action: AppButton(
        key: const ValueKey('payment_link_amount_continue_button'),
        onPressed: canContinue ? onCreate : null,
        minWidth: 196,
        size: AppButtonSize.large,
        trailing: canContinue ? const AppIcon(AppIcons.chevronForward) : null,
        child: Text(canContinue ? createLabel : emptyActionLabel),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          card,
          const SizedBox(height: AppSpacing.lg),
          cardSelector,
          if (supportingText case final message?) ...[
            const SizedBox(height: AppSpacing.s),
            Text(
              message,
              key: const ValueKey('payment_link_amount_supporting_text'),
              textAlign: TextAlign.center,
              style: AppTypography.labelLarge.copyWith(
                color: supportingTextIsError
                    ? context.colors.text.destructive
                    : context.colors.text.secondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Optional message step. The message-facing card remains a caller slot.
class PaymentLinkMessageDesktopView extends StatelessWidget {
  const PaymentLinkMessageDesktopView({
    required this.state,
    required this.card,
    required this.onBack,
    required this.onSkip,
    this.onContinue,
    this.onStepSelected,
    this.errorText,
    this.backLabel = 'Home',
    this.title = kPaymentLinkCreateGiftCardTitle,
    this.subtitle = 'Enter amount & select the design.',
    this.skipLabel = 'Skip message',
    this.emptyContinueLabel = 'Continue',
    this.continueLabel = 'Confirm & review',
    super.key,
  });

  final PaymentLinkMessageVisualState state;
  final Widget card;
  final VoidCallback onBack;
  final VoidCallback onSkip;
  final VoidCallback? onContinue;
  final ValueChanged<int>? onStepSelected;
  final String? errorText;
  final String backLabel;
  final String title;
  final String subtitle;
  final String skipLabel;
  final String emptyContinueLabel;
  final String continueLabel;

  @override
  Widget build(BuildContext context) {
    return PaymentLinkWizardPane(
      title: title,
      subtitle: subtitle,
      currentStep: 1,
      backLabel: backLabel,
      onBack: onBack,
      onStepSelected: onStepSelected,
      // Every wizard step keeps the card at the same visual anchor.
      childSpacing: _wizardCardTopSpacing,
      action: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PaymentLinkTextAction(label: skipLabel, onTap: onSkip),
          const SizedBox(height: AppSpacing.sm),
          AppButton(
            key: const ValueKey('payment_link_message_continue_button'),
            onPressed: state == PaymentLinkMessageVisualState.filled
                ? onContinue
                : null,
            minWidth: 210,
            size: AppButtonSize.large,
            trailing: const AppIcon(AppIcons.chevronForward),
            child: Text(
              state == PaymentLinkMessageVisualState.empty
                  ? emptyContinueLabel
                  : continueLabel,
            ),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          card,
          if (errorText case final message?) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              message,
              key: const ValueKey('payment_link_message_error_text'),
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(
                color: context.colors.text.destructive,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class PaymentLinkReviewDesktopView extends StatelessWidget {
  const PaymentLinkReviewDesktopView({
    required this.card,
    required this.onBack,
    required this.cardAmountText,
    required this.cardFeeText,
    required this.totalAmountText,
    this.onConfirm,
    this.onStepSelected,
    this.backLabel = 'Home',
    this.title = kPaymentLinkCreateGiftCardTitle,
    this.subtitle = 'Enter amount & select the design.',
    this.confirmLabel = 'Create card',
    super.key,
  });

  final Widget card;
  final VoidCallback onBack;
  final String cardAmountText;
  final String cardFeeText;
  final String totalAmountText;
  final VoidCallback? onConfirm;
  final ValueChanged<int>? onStepSelected;
  final String backLabel;
  final String title;
  final String subtitle;
  final String confirmLabel;

  @override
  Widget build(BuildContext context) {
    return PaymentLinkWizardPane(
      title: title,
      subtitle: subtitle,
      currentStep: 2,
      backLabel: backLabel,
      onBack: onBack,
      onStepSelected: onStepSelected,
      childSpacing: _wizardCardTopSpacing,
      action: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            key: const ValueKey('payment_link_review_summary'),
            width: 320,
            height: 136,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.s),
              child: Column(
                children: [
                  SizedBox(
                    height: AppSpacing.base,
                    child: _ReviewAmountRow(
                      label: 'Card amount',
                      value: cardAmountText,
                    ),
                  ),
                  SizedBox(
                    height: AppSpacing.base,
                    child: _ReviewAmountRow(
                      label: kPaymentLinkCardFeeLabel,
                      value: cardFeeText,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  SizedBox(
                    height: AppSpacing.base,
                    child: _ReviewAmountRow(
                      label: kPaymentLinkTotalDeductedLabel,
                      value: totalAmountText,
                      emphasized: true,
                      showHelp: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton(
            key: const ValueKey('payment_link_confirm_create_button'),
            onPressed: onConfirm,
            minWidth: 196,
            size: AppButtonSize.large,
            leading: const Center(
              child: AppIcon(AppIcons.giftCard, size: AppIconSize.medium),
            ),
            child: Text(confirmLabel),
          ),
        ],
      ),
      child: card,
    );
  }
}

class _ReviewAmountRow extends StatelessWidget {
  const _ReviewAmountRow({
    required this.label,
    required this.value,
    this.showHelp = false,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final bool showHelp;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final style = emphasized
        ? AppTypography.bodyMediumStrong
        : AppTypography.bodyMedium;
    return Padding(
      key: ValueKey('payment_link_review_row_$label'),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: style.copyWith(color: context.colors.text.secondary),
            ),
          ),
          Text(
            value,
            key: ValueKey('payment_link_review_value_$label'),
            style: AppTypography.bodyMediumStrong.copyWith(
              color: context.colors.text.primary,
            ),
          ),
          if (showHelp) ...[
            const SizedBox(width: AppSpacing.xxs),
            AppTooltip(
              message:
                  'Includes the fee to fund the Gift Card and the fee reserved '
                  'for the recipient to claim it.',
              preferBelow: true,
              child: Semantics(
                label: 'About the total Gift Card amount',
                child: AppIcon(
                  AppIcons.help,
                  size: 16,
                  color: context.colors.icon.muted,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class PaymentLinkReadyDesktopView extends StatelessWidget {
  const PaymentLinkReadyDesktopView({
    required this.state,
    required this.card,
    required this.onBack,
    required this.onCopy,
    this.decoration,
    this.onCardTap,
    this.onReturnHome,
    this.backLabel = 'Home',
    this.waitingStatusLabel = kPaymentLinkWaitingStatusLabel,
    this.waitingHeading = kPaymentLinkAlmostReadyHeading,
    this.waitingPrimaryText =
        'The link becomes shareable when funding reaches the network.',
    this.waitingSecondaryText =
        'If Vizor cannot confirm that yet, one confirmation is enough.\n'
        'This usually takes about 1 min 15 sec.',
    this.copyLabel = 'Copy link',
    this.returnLabel = 'Return home',
    super.key,
  });

  final PaymentLinkReadyVisualState state;
  final Widget card;
  final Widget? decoration;
  final VoidCallback onBack;
  final VoidCallback? onCopy;
  final VoidCallback? onCardTap;
  final VoidCallback? onReturnHome;
  final String backLabel;
  final String waitingStatusLabel;
  final String waitingHeading;
  final String waitingPrimaryText;
  final String waitingSecondaryText;
  final String copyLabel;
  final String returnLabel;

  @override
  Widget build(BuildContext context) {
    final waiting = state == PaymentLinkReadyVisualState.waiting;
    final canFlip = !waiting && onCardTap != null;
    final motionCard = PaymentLinkCardMotion(
      celebrate: !waiting,
      child: canFlip ? IgnorePointer(child: card) : card,
    );
    final cardContent = canFlip
        ? PaymentLinkAction(
            onPressed: onCardTap,
            semanticLabel: kPaymentLinkFlipCardSemanticLabel,
            builder: (context, _, focused) => PaymentLinkActionFocusRing(
              focused: focused,
              borderRadius: AppRadii.large,
              child: ExcludeSemantics(child: motionCard),
            ),
          )
        : motionCard;
    return PaymentLinkPane(
      backLabel: backLabel,
      onBack: onBack,
      child: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: 520,
          height: 624,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              if (decoration != null) Positioned.fill(child: decoration!),
              Positioned(
                top: 42.5,
                left: 0,
                right: 0,
                child: Text(
                  waiting ? waitingHeading : kPaymentLinkReadyHeading,
                  textAlign: TextAlign.center,
                  style: AppTypography.displayLarge.copyWith(
                    color: context.colors.text.accent,
                  ),
                ),
              ),
              Positioned(
                top: 186.5,
                left: 0,
                right: 0,
                child: Center(child: cardContent),
              ),
              Positioned(
                top: 434.5,
                left: 0,
                right: 0,
                child: Column(
                  children: [
                    if (waiting) ...[
                      Text(
                        waitingPrimaryText,
                        textAlign: TextAlign.center,
                        style: AppTypography.bodyMediumStrong.copyWith(
                          color: context.colors.text.accent,
                        ),
                      ),
                      Text(
                        waitingSecondaryText,
                        textAlign: TextAlign.center,
                        style: AppTypography.bodyMedium.copyWith(
                          color: context.colors.text.secondary,
                        ),
                      ),
                    ] else
                      Text(
                        'Share this link with the intended recipient so they\n'
                        'can claim the Card using their Vizor app.',
                        textAlign: TextAlign.center,
                        style: AppTypography.bodyMedium.copyWith(
                          color: context.colors.text.secondary,
                        ),
                      ),
                    const SizedBox(height: AppSpacing.lg),
                    if (waiting)
                      PaymentLinkDashedStatusPill(label: waitingStatusLabel)
                    else
                      AppButton(
                        key: const ValueKey('payment_link_copy_link_button'),
                        onPressed: onCopy,
                        size: AppButtonSize.mediumLarge,
                        leading: const AppIcon(AppIcons.copy),
                        child: Text(copyLabel),
                      ),
                    if (!waiting) ...[
                      const SizedBox(height: AppSpacing.xs),
                      PaymentLinkTextAction(
                        label: returnLabel,
                        onTap: onReturnHome ?? onBack,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PaymentLinkReceivedDesktopView extends StatelessWidget {
  const PaymentLinkReceivedDesktopView({
    required this.card,
    required this.onBack,
    this.onClaim,
    this.onRevealMessage,
    this.decoration,
    this.backLabel = 'Cards',
    this.title = 'You’ve received\na gift card!',
    this.messageTitle = kPaymentLinkMessageAttachedTitle,
    this.messageHint = 'Click on the card to reveal',
    this.claimLabel = 'Claim the Gift Card',
    this.cardActionLabel = kPaymentLinkRevealMessageSemanticLabel,
    super.key,
  });

  final Widget card;
  final Widget? decoration;
  final VoidCallback onBack;
  final VoidCallback? onClaim;
  final VoidCallback? onRevealMessage;
  final String backLabel;
  final String title;
  final String messageTitle;
  final String messageHint;
  final String claimLabel;
  final String cardActionLabel;

  @override
  Widget build(BuildContext context) {
    final canRevealMessage = onRevealMessage != null;
    final motionCard = PaymentLinkCardMotion(
      celebrate: true,
      child: canRevealMessage ? IgnorePointer(child: card) : card,
    );
    return PaymentLinkPane(
      backLabel: backLabel,
      onBack: onBack,
      child: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: 520,
          height: 624,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              if (decoration != null) Positioned.fill(child: decoration!),
              Positioned(
                top: 42.5,
                left: 0,
                right: 0,
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: AppTypography.displayLarge.copyWith(
                    color: context.colors.text.accent,
                  ),
                ),
              ),
              Positioned(
                top: 186.5,
                left: 0,
                right: 0,
                child: Center(
                  child: canRevealMessage
                      ? PaymentLinkAction(
                          key: const ValueKey(
                            'payment_link_reveal_message_action',
                          ),
                          onPressed: onRevealMessage,
                          semanticLabel: cardActionLabel,
                          builder: (context, _, focused) =>
                              PaymentLinkActionFocusRing(
                                focused: focused,
                                borderRadius: AppRadii.large,
                                child: ExcludeSemantics(child: motionCard),
                              ),
                        )
                      : motionCard,
                ),
              ),
              Positioned(
                top: 440,
                left: 0,
                right: 0,
                child: Center(
                  child: SizedBox(
                    key: const ValueKey('payment_link_received_message_block'),
                    width: 165,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (onRevealMessage != null) ...[
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: Center(
                              child: SvgPicture.asset(
                                'assets/illustrations/payment_links/'
                                'payment_link_envelope.svg',
                                key: const ValueKey(
                                  'payment_link_received_message_icon',
                                ),
                                width: 20,
                                height: 16,
                                semanticsLabel: kPaymentLinkGiftMessageLabel,
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            messageTitle,
                            textAlign: TextAlign.center,
                            style: AppTypography.bodyMediumStrong.copyWith(
                              color: context.colors.text.brandCrimson,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            messageHint,
                            textAlign: TextAlign.center,
                            style: AppTypography.bodyMedium.copyWith(
                              color: context.colors.text.secondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 558,
                left: 0,
                right: 0,
                child: Center(
                  child: AppButton(
                    key: const ValueKey('payment_link_claim_button'),
                    onPressed: onClaim,
                    size: AppButtonSize.mediumLarge,
                    child: Text(claimLabel),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Desktop Gift Card QR export screen from Figma node `8290:150634`.
class PaymentLinkShareQrDesktopView extends StatelessWidget {
  const PaymentLinkShareQrDesktopView({
    required this.artwork,
    required this.qrData,
    required this.onBack,
    required this.onSaveQr,
    required this.onCopyLink,
    this.shareCardKey,
    this.saveLabel = 'Save QR code',
    this.copyLabel = 'Copy link',
    super.key,
  });

  final PaymentLinkCardArtwork artwork;
  final String qrData;
  final VoidCallback onBack;
  final VoidCallback? onSaveQr;
  final VoidCallback? onCopyLink;
  final Key? shareCardKey;
  final String saveLabel;
  final String copyLabel;

  @override
  Widget build(BuildContext context) {
    return PaymentLinkPane(
      backLabel: 'Gift cards',
      onBack: onBack,
      child: Center(
        child: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Share Gift Card',
                style: AppTypography.headlineSmall.copyWith(
                  color: context.colors.text.accent,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              RepaintBoundary(
                key: shareCardKey,
                child: PaymentLinkQrShareCard(artwork: artwork, qrData: qrData),
              ),
              const SizedBox(height: AppSpacing.lg),
              AppButton(
                key: const ValueKey('payment_link_save_qr_button'),
                onPressed: onSaveQr,
                size: AppButtonSize.mediumLarge,
                leading: const AppIcon(AppIcons.share),
                child: Text(saveLabel),
              ),
              const SizedBox(height: AppSpacing.s),
              AppButton(
                key: const ValueKey('payment_link_share_copy_button'),
                onPressed: onCopyLink,
                variant: AppButtonVariant.ghost,
                size: AppButtonSize.mediumLarge,
                leading: const AppIcon(AppIcons.copy),
                child: Text(copyLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A desktop row used by [PaymentLinkCardsDesktopView].
class PaymentLinkCardListRow extends StatelessWidget {
  const PaymentLinkCardListRow({
    required this.thumbnail,
    required this.amountText,
    required this.dateText,
    this.statusText,
    this.onAction,
    this.showCopyIcon = false,
    this.showLoader = false,
    this.showLinkActions = false,
    this.onCopyLink,
    this.onShowQr,
    this.secondaryActionText,
    this.onSecondaryAction,
    super.key,
  }) : assert(
         statusText != null || showLinkActions,
         'A status or Gift Card link actions must be provided.',
       );

  final Widget thumbnail;
  final String amountText;
  final String dateText;
  final String? statusText;
  final VoidCallback? onAction;
  final bool showCopyIcon;
  final bool showLoader;
  final bool showLinkActions;
  final VoidCallback? onCopyLink;
  final VoidCallback? onShowQr;
  final String? secondaryActionText;
  final VoidCallback? onSecondaryAction;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 60,
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.small),
            child: SizedBox(width: 60, height: 44, child: thumbnail),
          ),
          const SizedBox(width: AppSpacing.s),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  amountText,
                  style: AppTypography.bodyMediumStrong.copyWith(
                    color: context.colors.text.primary,
                  ),
                ),
                Text(
                  dateText,
                  style: AppTypography.bodyMedium.copyWith(
                    color: context.colors.text.secondary,
                  ),
                ),
              ],
            ),
          ),
          if (secondaryActionText case final secondaryLabel?) ...[
            PaymentLinkTextAction(
              label: secondaryLabel,
              onTap: onSecondaryAction,
              enabled: onSecondaryAction != null,
            ),
            const SizedBox(width: AppSpacing.s),
          ],
          if (showLinkActions)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _CardListIconAction(
                  key: const ValueKey('payment_link_card_copy_action'),
                  icon: AppIcons.copy,
                  semanticLabel: kPaymentLinkCopyLinkSemanticLabel,
                  onPressed: onCopyLink,
                ),
                const SizedBox(width: AppSpacing.xxs),
                _CardListIconAction(
                  key: const ValueKey('payment_link_card_qr_action'),
                  icon: AppIcons.qr,
                  semanticLabel: 'Show Gift Card QR code',
                  onPressed: onShowQr,
                ),
              ],
            )
          else if (statusText case final label?)
            PaymentLinkTextAction(
              label: label,
              onTap: onAction,
              enabled: onAction != null,
              trailing: showLoader
                  ? AppIcon(
                      AppIcons.loader,
                      size: 16,
                      color: context.colors.icon.regular,
                    )
                  : showCopyIcon
                  ? AppIcon(
                      AppIcons.copy,
                      size: 16,
                      color: onAction == null
                          ? context.colors.icon.disabled
                          : context.colors.icon.regular,
                    )
                  : null,
            ),
        ],
      ),
    );
  }
}

class _CardListIconAction extends StatelessWidget {
  const _CardListIconAction({
    required this.icon,
    required this.semanticLabel,
    required this.onPressed,
    super.key,
  });

  final String icon;
  final String semanticLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return PaymentLinkAction(
      semanticLabel: semanticLabel,
      onPressed: onPressed,
      builder: (context, hovered, focused) => PaymentLinkActionFocusRing(
        focused: focused,
        borderRadius: AppRadii.xSmall,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: hovered
                ? context.colors.button.ghost.bgHover
                : context.colors.background.ground.withValues(alpha: 0),
            borderRadius: BorderRadius.circular(AppRadii.xSmall),
          ),
          child: Center(
            child: AppIcon(
              icon,
              size: 16,
              color: enabled
                  ? context.colors.icon.regular
                  : context.colors.icon.disabled,
            ),
          ),
        ),
      ),
    );
  }
}

class PaymentLinkCardsDesktopView extends StatefulWidget {
  const PaymentLinkCardsDesktopView({
    required this.sections,
    required this.onBack,
    required this.onCreate,
    required this.onRedeem,
    this.activeTab = PaymentLinkCardsTab.created,
    this.onTabSelected,
    this.backLabel = 'Home',
    this.title = 'Gift Cards',
    super.key,
  });

  final List<PaymentLinkCardsSection> sections;
  final VoidCallback onBack;
  final VoidCallback onCreate;
  final VoidCallback onRedeem;
  final PaymentLinkCardsTab activeTab;
  final ValueChanged<PaymentLinkCardsTab>? onTabSelected;
  final String backLabel;
  final String title;

  @override
  State<PaymentLinkCardsDesktopView> createState() =>
      _PaymentLinkCardsDesktopViewState();
}

class _PaymentLinkCardsDesktopViewState
    extends State<PaymentLinkCardsDesktopView> {
  final ScrollController _scrollController = ScrollController();
  bool _showTopFade = false;
  bool _showBottomFade = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_updateScrollEdgeFades);
    _scheduleScrollEdgeUpdate();
  }

  @override
  void didUpdateWidget(covariant PaymentLinkCardsDesktopView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleScrollEdgeUpdate();
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_updateScrollEdgeFades)
      ..dispose();
    super.dispose();
  }

  void _scheduleScrollEdgeUpdate() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateScrollEdgeFades();
    });
  }

  void _updateScrollEdgeFades() {
    if (!_scrollController.hasClients) return;
    final metrics = _scrollController.position;
    final showTop = metrics.extentBefore > 0.5;
    final showBottom = metrics.extentAfter > 0.5;
    if (_showTopFade == showTop && _showBottomFade == showBottom) return;
    setState(() {
      _showTopFade = showTop;
      _showBottomFade = showBottom;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PaymentLinkPane(
      backLabel: widget.backLabel,
      onBack: widget.onBack,
      scrollController: _scrollController,
      showTopScrollFade: _showTopFade,
      showBottomActionFade: _showBottomFade,
      actions: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppButton(
            key: const ValueKey('payment_link_create_card_button'),
            onPressed: widget.onCreate,
            size: AppButtonSize.mediumLarge,
            child: const Text(kPaymentLinkCreateCardLabel),
          ),
          const SizedBox(height: AppSpacing.s),
          PaymentLinkTextAction(
            label: kPaymentLinkRedeemCardLabel,
            onTap: widget.onRedeem,
          ),
        ],
      ),
      child: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: 390,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.title,
                textAlign: TextAlign.center,
                style: AppTypography.headlineLarge.copyWith(
                  color: context.colors.text.accent,
                ),
              ),
              const SizedBox(height: AppSpacing.s),
              Semantics(
                role: SemanticsRole.tabBar,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    PaymentLinkTabAction(
                      icon: AppIcons.plane,
                      label: kPaymentLinkCreatedTabLabel,
                      selected: widget.activeTab == PaymentLinkCardsTab.created,
                      onTap: widget.onTabSelected == null
                          ? null
                          : () => widget.onTabSelected!(
                              PaymentLinkCardsTab.created,
                            ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    PaymentLinkTabAction(
                      icon: AppIcons.arrowDownward,
                      label: kPaymentLinkReceivedTabLabel,
                      selected:
                          widget.activeTab == PaymentLinkCardsTab.received,
                      onTap: widget.onTabSelected == null
                          ? null
                          : () => widget.onTabSelected!(
                              PaymentLinkCardsTab.received,
                            ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.base),
              for (final (index, section) in widget.sections.indexed) ...[
                if (index > 0) const SizedBox(height: AppSpacing.sm),
                Text(
                  section.label,
                  style: AppTypography.bodyMedium.copyWith(
                    color: context.colors.text.secondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                ...section.cards,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class PaymentLinkRedeemDesktopView extends StatelessWidget {
  const PaymentLinkRedeemDesktopView({
    required this.state,
    required this.onBack,
    this.onPaste,
    this.onClearClipboard,
    this.loadingPlaceholder,
    this.backLabel = 'My Cards',
    this.title,
    this.subtitle = kPaymentLinkRedeemSubtitle,
    this.pasteLabel = kPaymentLinkPasteLabel,
    this.invalidTitle = kPaymentLinkInvalidTitle,
    this.invalidSubtitle = kPaymentLinkInvalidSubtitle,
    this.unavailableTitle = 'This Card has no available balance.',
    this.unavailableSubtitle = kPaymentLinkUnavailableSubtitle,
    this.clearLabel = kPaymentLinkClearClipboardLabel,
    super.key,
  });

  final PaymentLinkRedeemVisualState state;
  final VoidCallback onBack;
  final VoidCallback? onPaste;
  final VoidCallback? onClearClipboard;
  final Widget? loadingPlaceholder;
  final String backLabel;
  final String? title;
  final String subtitle;
  final String pasteLabel;
  final String invalidTitle;
  final String invalidSubtitle;
  final String unavailableTitle;
  final String unavailableSubtitle;
  final String clearLabel;

  @override
  Widget build(BuildContext context) {
    final loading = state == PaymentLinkRedeemVisualState.loading;
    final invalid = state == PaymentLinkRedeemVisualState.invalid;
    final unavailable = state == PaymentLinkRedeemVisualState.unavailable;
    final showError = invalid || unavailable;
    return PaymentLinkPane(
      backLabel: backLabel,
      onBack: onBack,
      child: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: 396,
          height: 624,
          child: Stack(
            children: [
              Positioned(
                top: 94,
                left: 0,
                right: 0,
                child: Text(
                  title ??
                      (loading
                          ? kPaymentLinkCheckingLabel
                          : kPaymentLinkRedeemTheCardTitle),
                  textAlign: TextAlign.center,
                  style: AppTypography.headlineLarge.copyWith(
                    color: context.colors.text.accent,
                  ),
                ),
              ),
              Positioned(
                top: 179,
                left: 18,
                child: loading
                    ? loadingPlaceholder ?? const PaymentLinkLoadingCard()
                    : PaymentLinkDashedDropZone(
                        child: showError
                            ? Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    invalid ? invalidTitle : unavailableTitle,
                                    textAlign: TextAlign.center,
                                    style: AppTypography.bodyMediumStrong
                                        .copyWith(
                                          color:
                                              context.colors.text.destructive,
                                        ),
                                  ),
                                  const SizedBox(height: AppSpacing.xs),
                                  Text(
                                    invalid
                                        ? invalidSubtitle
                                        : unavailableSubtitle,
                                    textAlign: TextAlign.center,
                                    style: AppTypography.bodyMedium.copyWith(
                                      color: context.colors.text.secondary,
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.sm),
                                  PaymentLinkPasteButton(
                                    label: pasteLabel,
                                    onPressed: onPaste,
                                  ),
                                ],
                              )
                            : PaymentLinkPasteButton(
                                label: pasteLabel,
                                onPressed: onPaste,
                              ),
                      ),
              ),
              Positioned(
                top: 462,
                left: 0,
                right: 0,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 260),
                    child: Text(
                      subtitle,
                      textAlign: TextAlign.center,
                      style: AppTypography.bodyMedium.copyWith(
                        color: context.colors.text.secondary,
                      ),
                    ),
                  ),
                ),
              ),
              if (showError)
                Positioned(
                  top: 545,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: PaymentLinkTextAction(
                      label: clearLabel,
                      onTap: onClearClipboard,
                      leading: const AppIcon(AppIcons.trash),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
