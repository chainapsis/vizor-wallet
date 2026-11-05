import 'dart:math' as math;

import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_modal_card.dart';
import '../../../core/widgets/app_pane_modal_overlay.dart';
import '../../../core/widgets/app_tooltip.dart';
import 'payment_link_action.dart';
import 'payment_link_card_motion.dart';
import 'payment_link_cards_layout.dart';
import 'payment_link_received_desktop_view.dart';
export 'payment_link_received_desktop_view.dart';
import 'payment_link_gift_card.dart';
import 'payment_link_group_entry.dart';
import 'payment_link_qr_share_card.dart';
import 'payment_link_wizard_chrome.dart';
import '../../../core/l10n/l10n.dart';

export 'payment_link_cards_layout.dart'
    show PaymentLinkCardsSection, PaymentLinkCardsTab;

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

enum PaymentLinkReadyVisualState { checking, waiting, ready }

enum PaymentLinkRedeemVisualState { paste, loading, invalid }

/// Empty Gift Cards landing surface.
/// The pane width from which the **For a group** tile sits beside the
/// content instead of below it, on the empty home and the card list alike.
const _kGroupTileBesideMinWidth = 740.0;
// Keep a gap between the centered 390px list and the wider Ledger entry.
const _kLedgerListTileBesideMinWidth =
    390 +
    2 * (PaymentLinkGroupEntry.ledgerWidth + AppSpacing.base + AppSpacing.sm);

class PaymentLinksHomeDesktopView extends StatelessWidget {
  const PaymentLinksHomeDesktopView({
    required this.illustration,
    required this.onBack,
    required this.onShowHelp,
    required this.onCreate,
    required this.onRedeem,
    this.onCreateMultiple,
    this.isLedger = false,
    this.backLabel,
    this.title,
    this.helpLabel,
    this.createLabel,
    this.redeemLabel,
    super.key,
  });

  final Widget illustration;
  final VoidCallback onBack;
  final VoidCallback onShowHelp;
  final VoidCallback onCreate;
  final VoidCallback onRedeem;
  final VoidCallback? onCreateMultiple;
  final bool isLedger;
  final String? backLabel;
  final String? title;
  final String? helpLabel;
  final String? createLabel;
  final String? redeemLabel;

  @override
  Widget build(BuildContext context) {
    final helpLabel =
        this.helpLabel ?? context.l10n.paymentLinkHowGiftCardsWork;
    final createLabel =
        this.createLabel ?? context.l10n.paymentLinkCreateNewCard;
    final backLabel = this.backLabel ?? context.l10n.navHome;
    final title = this.title ?? context.l10n.paymentLinkEmptyTitle;
    final redeemLabel =
        this.redeemLabel ?? context.l10n.paymentLinkRedeemCardLabel;
    final heading = Column(
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
    );
    final actions = _PaymentLinkDesktopCreateActions(
      onCreate: onCreate,
      onRedeem: onRedeem,
      createLabel: createLabel,
      redeemLabel: redeemLabel,
      showGiftIcon: true,
    );
    final art = SizedBox(
      width: 340,
      height: 220,
      child: Center(child: illustration),
    );
    final largeText = paymentLinkUsesLargeText(context);
    final body = SizedBox(
      width: 420,
      // Large text flows and scrolls instead of clipping the Figma frame.
      child: largeText
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                art,
                const SizedBox(height: AppSpacing.md),
                heading,
                const SizedBox(height: AppSpacing.md),
                actions,
                const SizedBox(height: AppSpacing.md),
              ],
            )
          : SizedBox(
              height: 624,
              child: Stack(
                children: [
                  Positioned(top: 95.5, left: 40, child: art),
                  Positioned(top: 339.5, left: 0, right: 0, child: heading),
                  Positioned(top: 444.5, left: 0, right: 0, child: actions),
                ],
              ),
            ),
    );
    final onCreateGroup = onCreateMultiple;
    return PaymentLinkPane(
      backLabel: backLabel,
      onBack: onBack,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (onCreateGroup == null) {
            return Align(alignment: Alignment.topCenter, child: body);
          }
          if (constraints.maxWidth < _kGroupTileBesideMinWidth || largeText) {
            return Column(
              children: [
                Center(child: body),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.sm,
                    0,
                    AppSpacing.sm,
                    AppSpacing.md,
                  ),
                  child: PaymentLinkGroupEntry(
                    fullWidth: true,
                    onPressed: onCreateGroup,
                    isLedger: isLedger,
                  ),
                ),
              ],
            );
          }
          return SizedBox(
            height: 624,
            child: Stack(
              children: [
                Align(alignment: Alignment.topCenter, child: body),
                Positioned(
                  top: 208,
                  right: AppSpacing.base,
                  child: PaymentLinkGroupEntry(
                    onPressed: onCreateGroup,
                    isLedger: isLedger,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _PaymentLinkDesktopCreateActions extends StatelessWidget {
  const _PaymentLinkDesktopCreateActions({
    required this.onCreate,
    required this.onRedeem,
    required this.createLabel,
    required this.redeemLabel,
    this.showGiftIcon = false,
  });

  final VoidCallback onCreate;
  final VoidCallback onRedeem;
  final String createLabel;
  final String redeemLabel;
  final bool showGiftIcon;

  @override
  Widget build(BuildContext context) {
    final largeText = paymentLinkUsesLargeText(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppButton(
          key: const ValueKey('payment_link_create_card_button'),
          onPressed: onCreate,
          size: AppButtonSize.mediumLarge,
          growWithContent: largeText,
          constrainContent: largeText,
          leading: showGiftIcon
              ? const AppIcon(AppIcons.giftCard, size: AppIconSize.medium)
              : null,
          child: Text(createLabel),
        ),
        const SizedBox(height: AppSpacing.s),
        PaymentLinkTextAction(label: redeemLabel, onTap: onRedeem),
      ],
    );
  }
}

/// Read-only Figma help overlay. Its body strings are fixture copy and must
/// not be treated as a protocol or security contract.
class PaymentLinkHowItWorksDesktopView extends StatelessWidget {
  const PaymentLinkHowItWorksDesktopView({
    required this.background,
    required this.onClose,
    this.title,
    this.subtitle,
    this.createDescription,
    this.shareDescription,
    this.redeemDescription,
    this.closeLabel,
    super.key,
  });

  final Widget background;
  final VoidCallback onClose;
  final String? title;
  final String? subtitle;
  final String? createDescription;
  final String? shareDescription;
  final String? redeemDescription;
  final String? closeLabel;

  @override
  Widget build(BuildContext context) {
    final createDescription =
        this.createDescription ?? context.l10n.paymentLinkHowDesktopStepCreate;
    final shareDescription =
        this.shareDescription ?? context.l10n.paymentLinkHowDesktopStepShare;
    final redeemDescription =
        this.redeemDescription ?? context.l10n.paymentLinkHowDesktopStepRedeem;
    final closeLabel = this.closeLabel ?? context.l10n.commonClose;
    final title = this.title ?? context.l10n.paymentLinkHowItWorksTitle;
    final subtitle =
        this.subtitle ?? context.l10n.paymentLinkHowItWorksSubtitle;
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
    this.backLabel,
    this.title,
    this.subtitle,
    this.createLabel,
    this.emptyActionLabel,
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
  final String? backLabel;
  final String? title;
  final String? subtitle;
  final String? createLabel;
  final String? emptyActionLabel;

  bool get _hasAmount => switch (state) {
    PaymentLinkAmountVisualState.amount ||
    PaymentLinkAmountVisualState.fiatLoading ||
    PaymentLinkAmountVisualState.fiatLoaded => true,
    PaymentLinkAmountVisualState.empty ||
    PaymentLinkAmountVisualState.focused => false,
  };

  @override
  Widget build(BuildContext context) {
    final subtitle =
        this.subtitle ?? context.l10n.paymentLinkAmountStepSubtitleDesktop;
    final backLabel = this.backLabel ?? context.l10n.navHome;
    final createLabel = this.createLabel ?? context.l10n.commonContinue;
    final emptyActionLabel =
        this.emptyActionLabel ?? context.l10n.commonContinue;
    final title = this.title ?? context.l10n.paymentLinkCreateGiftCardTitle;
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
    this.backLabel,
    this.title,
    this.subtitle,
    this.skipLabel,
    this.emptyContinueLabel,
    this.continueLabel,
    super.key,
  });

  final PaymentLinkMessageVisualState state;
  final Widget card;
  final VoidCallback onBack;
  final VoidCallback onSkip;
  final VoidCallback? onContinue;
  final ValueChanged<int>? onStepSelected;
  final String? errorText;
  final String? backLabel;
  final String? title;
  final String? subtitle;
  final String? skipLabel;
  final String? emptyContinueLabel;
  final String? continueLabel;

  @override
  Widget build(BuildContext context) {
    final subtitle =
        this.subtitle ?? context.l10n.paymentLinkAmountStepSubtitleDesktop;
    final skipLabel = this.skipLabel ?? context.l10n.paymentLinkSkipMessage;
    final continueLabel =
        this.continueLabel ?? context.l10n.paymentLinkReviewAndConfirm;
    final backLabel = this.backLabel ?? context.l10n.navHome;
    final emptyContinueLabel =
        this.emptyContinueLabel ?? context.l10n.commonContinue;
    final title = this.title ?? context.l10n.paymentLinkCreateGiftCardTitle;
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
    this.backLabel,
    this.title,
    this.subtitle,
    this.confirmLabel,
    super.key,
  });

  final Widget card;
  final VoidCallback onBack;
  final String cardAmountText;
  final String cardFeeText;
  final String totalAmountText;
  final VoidCallback? onConfirm;
  final ValueChanged<int>? onStepSelected;
  final String? backLabel;
  final String? title;
  final String? subtitle;
  final String? confirmLabel;

  @override
  Widget build(BuildContext context) {
    final subtitle =
        this.subtitle ?? context.l10n.paymentLinkAmountStepSubtitleDesktop;
    final confirmLabel =
        this.confirmLabel ?? context.l10n.paymentLinkCreateCardButton;
    final backLabel = this.backLabel ?? context.l10n.navHome;
    final title = this.title ?? context.l10n.paymentLinkCreateGiftCardTitle;
    // Preserve the standard window's geometry while letting scaled text grow
    // the content. The card and summary must never compete for the same space.
    return LayoutBuilder(
      builder: (context, constraints) => PaymentLinkPane(
        backLabel: backLabel,
        onBack: onBack,
        child: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: 420,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: math.max(640, constraints.maxHeight - 64),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.s,
                  0,
                  AppSpacing.s,
                  AppSpacing.sm,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          textAlign: TextAlign.center,
                          style: AppTypography.bodyLarge.copyWith(
                            fontWeight: FontWeight.w600,
                            color: context.colors.text.accent,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          subtitle,
                          textAlign: TextAlign.center,
                          style: AppTypography.bodyMedium.copyWith(
                            color: context.colors.text.secondary,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        PaymentLinkWizardStepper(
                          currentStep: 2,
                          onStepSelected: onStepSelected,
                        ),
                        const SizedBox(height: AppSpacing.md + 53),
                        card,
                        const SizedBox(height: AppSpacing.sm),
                      ],
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          key: const ValueKey('payment_link_review_summary'),
                          width: 320,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.s,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    minHeight: AppSpacing.base,
                                  ),
                                  child: _ReviewAmountRow(
                                    label:
                                        context.l10n.paymentLinkCardAmountLabel,
                                    value: cardAmountText,
                                  ),
                                ),
                                ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    minHeight: AppSpacing.base,
                                  ),
                                  child: _ReviewAmountRow(
                                    label: context.l10n.paymentLinkCardFeeLabel,
                                    value: cardFeeText,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.sm),
                                ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    minHeight: AppSpacing.base,
                                  ),
                                  child: _ReviewAmountRow(
                                    label: context
                                        .l10n
                                        .paymentLinkTotalDeductedLabel,
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
                          key: const ValueKey(
                            'payment_link_confirm_create_button',
                          ),
                          onPressed: onConfirm,
                          minWidth: 196,
                          size: AppButtonSize.large,
                          leading: const Center(
                            child: AppIcon(
                              AppIcons.giftCard,
                              size: AppIconSize.medium,
                            ),
                          ),
                          child: Text(confirmLabel),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
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
              message: context.l10n.paymentLinkFeeHelpTextLong,
              preferBelow: true,
              child: Semantics(
                label: context.l10n.paymentLinkTotalAmountHelpSemantic,
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
    this.usageStatus,
    this.onCardTap,
    this.onReturnHome,
    this.backLabel,
    this.waitingStatusLabel,
    this.waitingHeading,
    this.waitingPrimaryText,
    this.waitingSecondaryText,
    this.copyLabel,
    this.returnLabel,
    super.key,
  });

  final PaymentLinkReadyVisualState state;
  final Widget card;
  final Widget? usageStatus;
  final Widget? decoration;
  final VoidCallback onBack;
  final VoidCallback? onCopy;
  final VoidCallback? onCardTap;
  final VoidCallback? onReturnHome;
  final String? backLabel;
  final String? waitingStatusLabel;
  final String? waitingHeading;
  final String? waitingPrimaryText;
  final String? waitingSecondaryText;
  final String? copyLabel;
  final String? returnLabel;

  @override
  Widget build(BuildContext context) {
    final copyLabel = this.copyLabel ?? context.l10n.paymentLinkCopyLink;
    final backLabel = this.backLabel ?? context.l10n.navHome;
    final waitingStatusLabel =
        this.waitingStatusLabel ?? context.l10n.paymentLinkWaitingStatusLabel;
    final waitingHeading =
        this.waitingHeading ?? context.l10n.paymentLinkAlmostReadyHeading;
    final waitingPrimaryText =
        this.waitingPrimaryText ??
        context.l10n.paymentLinkShareWaitingDescription;
    final waitingSecondaryText =
        this.waitingSecondaryText ?? context.l10n.paymentLinkWaitingDescription;
    final checking = state == PaymentLinkReadyVisualState.checking;
    final waiting = state != PaymentLinkReadyVisualState.ready;
    final canFlip = !waiting && onCardTap != null;
    final motionCard = PaymentLinkCardMotion(
      celebrate: !waiting,
      child: canFlip ? IgnorePointer(child: card) : card,
    );
    final cardContent = canFlip
        ? PaymentLinkAction(
            onPressed: onCardTap,
            semanticLabel: context.l10n.paymentLinkFlipCardSemanticLabel,
            builder: (context, _, focused) => PaymentLinkActionFocusRing(
              focused: focused,
              borderRadius: AppRadii.large,
              child: ExcludeSemantics(child: motionCard),
            ),
          )
        : motionCard;
    if (checking) {
      return PaymentLinkReceivedDesktopView(
        state: PaymentLinkClaimDesktopState.checking,
        card: card,
        onBack: onBack,
        backLabel: backLabel,
        waitingStatusLabel: waitingStatusLabel,
      );
    }
    return PaymentLinkPane(
      backLabel: backLabel,
      onBack: onBack,
      child: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: 520,
          height: usageStatus == null ? 624 : 688,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              if (decoration != null) Positioned.fill(child: decoration!),
              Positioned(
                top: 42.5,
                left: 0,
                right: 0,
                child: Text(
                  waiting
                      ? waitingHeading
                      : context.l10n.paymentLinkReadyHeading,
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
                    ?usageStatus,
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
                    ] else ...[
                      Text(
                        context.l10n.paymentLinkShareLinkInstructionDesktop,
                        textAlign: TextAlign.center,
                        style: AppTypography.bodyMedium.copyWith(
                          color: context.colors.text.secondary,
                        ),
                      ),
                      // Fit the guidance into the original action gap, while
                      // allowing wrapped or scaled text to use more space.
                      ConstrainedBox(
                        constraints: const BoxConstraints(
                          minHeight: AppSpacing.lg,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.only(
                            top: AppSpacing.xs,
                            bottom: AppSpacing.sm,
                          ),
                          child: Text(
                            context.l10n.paymentLinkCopyLinkAgainHint,
                            textAlign: TextAlign.center,
                            style: AppTypography.bodyMedium.copyWith(
                              color: context.colors.text.secondary,
                            ),
                          ),
                        ),
                      ),
                    ],
                    if (waiting) const SizedBox(height: AppSpacing.lg),
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
                        label: returnLabel ?? context.l10n.commonReturnHome,
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

/// Desktop Gift Card QR export screen from Figma node `8290:150634`.
class PaymentLinkShareQrDesktopView extends StatelessWidget {
  const PaymentLinkShareQrDesktopView({
    required this.artwork,
    required this.qrData,
    required this.onBack,
    required this.onSaveQr,
    required this.onCopyLink,
    this.shareCardKey,
    this.saveLabel,
    this.copyLabel,
    super.key,
  });

  final PaymentLinkCardArtwork artwork;
  final String qrData;
  final VoidCallback onBack;
  final VoidCallback? onSaveQr;
  final VoidCallback? onCopyLink;
  final Key? shareCardKey;
  final String? saveLabel;
  final String? copyLabel;

  @override
  Widget build(BuildContext context) {
    final saveLabel = this.saveLabel ?? context.l10n.paymentLinkSaveQrCode;
    final copyLabel = this.copyLabel ?? context.l10n.paymentLinkCopyLink;
    return PaymentLinkPane(
      backLabel: context.l10n.paymentLinkGiftCardsLowerBreadcrumb,
      onBack: onBack,
      child: Center(
        child: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                context.l10n.paymentLinkShareGiftCardTitle,
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
    this.usageStatus,
    this.actionLabel,
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

  final Widget? usageStatus;
  final Widget thumbnail;
  final String amountText;
  final String dateText;
  final String? statusText;
  final String? actionLabel;
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
      height: actionLabel == null ? 60 : 84,
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
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodyMediumStrong.copyWith(
                    color: context.colors.text.primary,
                  ),
                ),
                if (actionLabel != null)
                  Text(
                    statusText!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodyMedium.copyWith(
                      color: context.colors.text.secondary,
                    ),
                  ),
                Text(
                  dateText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
          if (usageStatus != null) ...[
            SizedBox(width: 112, child: usageStatus),
            const SizedBox(width: AppSpacing.xs),
          ],
          if (showLinkActions)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                PaymentLinkIconAction(
                  key: const ValueKey('payment_link_card_copy_action'),
                  icon: AppIcons.copy,
                  semanticLabel: context.l10n.paymentLinkCopyLinkSemanticLabel,
                  onPressed: onCopyLink,
                ),
                const SizedBox(width: AppSpacing.xxs),
                PaymentLinkIconAction(
                  key: const ValueKey('payment_link_card_qr_action'),
                  icon: AppIcons.qr,
                  semanticLabel: context.l10n.paymentLinkShowQrSemantic,
                  onPressed: onShowQr,
                ),
              ],
            )
          else if (statusText case final label?)
            PaymentLinkTextAction(
              label: actionLabel ?? label,
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

/// One batch in the created list; opens the batch detail. It matches the
/// single-card rows: the amount over the date beside the thumbnail, and the
/// status centred at the trailing edge.
class PaymentLinkBatchListRow extends StatelessWidget {
  const PaymentLinkBatchListRow({
    required this.thumbnail,
    required this.count,
    required this.amountText,
    required this.dateText,
    required this.statusText,
    required this.onOpen,
    this.backThumbnail,
    this.showLoader = false,
    super.key,
  });

  final Widget thumbnail;

  /// Shown on the card behind [thumbnail] when the group mixes designs.
  final Widget? backThumbnail;
  final int count;

  /// The amount of each card, for example "0.1 ZEC".
  final String amountText;
  final String dateText;
  final String statusText;
  final VoidCallback onOpen;
  final bool showLoader;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final largeText = paymentLinkUsesLargeText(context);
    final secondaryStyle = AppTypography.bodyMedium.copyWith(
      color: colors.text.secondary,
    );
    final amount = Text(
      '$amountText × $count',
      style: AppTypography.bodyMediumStrong.copyWith(
        color: colors.text.primary,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
    final date = Text(dateText, style: secondaryStyle);
    final status = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            statusText,
            textAlign: largeText ? TextAlign.start : TextAlign.end,
            style: secondaryStyle.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        if (showLoader) ...[
          const SizedBox(width: AppSpacing.xxs),
          AppIcon(AppIcons.loader, size: 16, color: colors.icon.regular),
        ],
      ],
    );
    return PaymentLinkAction(
      semanticLabel: [
        context.l10n.paymentLinkOpenGroupSemantic(count),
        context.l10n.paymentLinkOpenGroupEach(amountText),
        context.l10n.paymentLinkOpenGroupCreated(dateText),
        if (statusText.isNotEmpty) statusText,
        if (showLoader) context.l10n.paymentLinkOpenGroupChecking,
      ].join(', '),
      onPressed: onOpen,
      builder: (context, hovered, focused) => Stack(
        clipBehavior: Clip.none,
        children: [
          // The hover fill and focus ring bleed past the row so the
          // thumbnail keeps the same inset as the single-card rows.
          Positioned(
            left: -AppSpacing.xs,
            right: -AppSpacing.xs,
            top: 0,
            bottom: 0,
            child: AnimatedContainer(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 120),
              curve: Curves.easeOut,
              decoration: BoxDecoration(
                color: hovered
                    ? colors.button.ghost.bgHover
                    : colors.background.ground.withValues(alpha: 0),
                borderRadius: BorderRadius.circular(AppRadii.small),
                border: focused
                    ? Border.all(
                        color: colors.state.focusRing,
                        width: 2,
                        strokeAlign: BorderSide.strokeAlignOutside,
                      )
                    : null,
              ),
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 60),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
              child: Row(
                children: [
                  _BatchThumbnail(
                    thumbnail: thumbnail,
                    backThumbnail: backThumbnail,
                  ),
                  const SizedBox(width: AppSpacing.s),
                  // Text wraps rather than truncates; large text moves the
                  // status under the date.
                  // The amount and date keep the larger share; a long status
                  // wraps on its side, within the row's two lines.
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [amount, date, if (largeText) status],
                    ),
                  ),
                  if (!largeText) ...[
                    const SizedBox(width: AppSpacing.sm),
                    // Ends at the chevron, centred like a single card's
                    // status, whatever its length.
                    Expanded(
                      flex: 2,
                      child: Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: status,
                      ),
                    ),
                  ],
                  const SizedBox(width: AppSpacing.xs),
                  AppIcon(
                    AppIcons.chevronForward,
                    size: 16,
                    color: colors.icon.regular,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A card thumbnail with one plate behind it, in the single-row footprint.
class _BatchThumbnail extends StatelessWidget {
  const _BatchThumbnail({required this.thumbnail, this.backThumbnail});

  final Widget thumbnail;
  final Widget? backThumbnail;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 60,
    height: 44,
    child: Stack(
      children: [
        Positioned(
          top: 0,
          right: 0,
          width: 54,
          height: 40,
          child: switch (backThumbnail) {
            final back? => ClipRRect(
              borderRadius: BorderRadius.circular(AppRadii.xSmall),
              child: back,
            ),
            null => DecoratedBox(
              decoration: BoxDecoration(
                color: context.colors.background.raised,
                borderRadius: BorderRadius.circular(AppRadii.xSmall),
                border: Border.all(color: context.colors.border.regular),
              ),
            ),
          },
        ),
        Positioned(
          left: 0,
          bottom: 0,
          width: 54,
          height: 40,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.xSmall),
            child: thumbnail,
          ),
        ),
      ],
    ),
  );
}

class PaymentLinkCardsDesktopView extends StatefulWidget {
  const PaymentLinkCardsDesktopView({
    required this.sections,
    required this.onBack,
    required this.onCreate,
    required this.onRedeem,
    this.onCreateMultiple,
    this.isLedger = false,
    this.activeTab = PaymentLinkCardsTab.created,
    this.onTabSelected,
    this.backLabel,
    this.title,
    super.key,
  });

  final List<PaymentLinkCardsSection> sections;
  final VoidCallback onBack;
  final VoidCallback onCreate;
  final VoidCallback onRedeem;
  final VoidCallback? onCreateMultiple;
  final bool isLedger;
  final PaymentLinkCardsTab activeTab;
  final ValueChanged<PaymentLinkCardsTab>? onTabSelected;
  final String? backLabel;
  final String? title;

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
      backLabel: widget.backLabel ?? context.l10n.navHome,
      onBack: widget.onBack,
      scrollController: _scrollController,
      showTopScrollFade: _showTopFade,
      showBottomActionFade: _showBottomFade,
      actionFadeEndFraction: 0.25,
      actions: _PaymentLinkDesktopCreateActions(
        onCreate: widget.onCreate,
        onRedeem: widget.onRedeem,
        createLabel: context.l10n.paymentLinkCreateCardLabel,
        redeemLabel: context.l10n.paymentLinkRedeemCardLabel,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) => Column(
          children: [
            Text(
              widget.title ?? context.l10n.paymentLinkGiftCardsTitle,
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
                    label: context.l10n.paymentLinkCreatedTabLabel,
                    selected: widget.activeTab == PaymentLinkCardsTab.created,
                    onTap: widget.onTabSelected == null
                        ? null
                        : () => widget.onTabSelected!(
                            PaymentLinkCardsTab.created,
                          ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  PaymentLinkTabAction(
                    icon: AppIcons.importWallet,
                    label: context.l10n.paymentLinkReceivedTabLabel,
                    selected: widget.activeTab == PaymentLinkCardsTab.received,
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
            if (widget.onCreateMultiple case final onCreateGroup?
                when constraints.maxWidth >=
                        (widget.isLedger
                            ? _kLedgerListTileBesideMinWidth
                            : _kGroupTileBesideMinWidth) &&
                    !paymentLinkUsesLargeText(context))
              Stack(
                children: [
                  Align(
                    alignment: Alignment.topCenter,
                    child: SizedBox(width: 390, child: _sections(context)),
                  ),
                  Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.base),
                      child: PaymentLinkGroupEntry(
                        onPressed: onCreateGroup,
                        isLedger: widget.isLedger,
                      ),
                    ),
                  ),
                ],
              )
            else ...[
              if (widget.onCreateMultiple case final onCreateGroup?)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.base),
                  child: SizedBox(
                    width: math.min(390, constraints.maxWidth),
                    child: PaymentLinkGroupEntry(
                      fullWidth: true,
                      onPressed: onCreateGroup,
                      isLedger: widget.isLedger,
                    ),
                  ),
                ),
              SizedBox(
                width: math.min(390, constraints.maxWidth),
                child: _sections(context),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _sections(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final (index, section) in widget.sections.indexed) ...[
        if (index > 0) const SizedBox(height: AppSpacing.sm),
        section.header ??
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
  );
}

class PaymentLinkRedeemDesktopView extends StatelessWidget {
  const PaymentLinkRedeemDesktopView({
    required this.state,
    required this.onBack,
    this.onPaste,
    this.onScan,
    this.scanEnabled = true,
    this.onClearClipboard,
    this.loadingPlaceholder,
    this.statusContent,
    this.secondaryAction,
    this.backLabel,
    this.title,
    this.subtitle,
    this.pasteLabel,
    this.invalidTitle,
    this.invalidSubtitle,
    this.clearLabel,
    super.key,
  });

  final PaymentLinkRedeemVisualState state;
  final VoidCallback onBack;
  final VoidCallback? onPaste;
  final VoidCallback? onScan;
  final bool scanEnabled;
  final VoidCallback? onClearClipboard;
  final Widget? loadingPlaceholder;
  final Widget? statusContent;
  final Widget? secondaryAction;
  final String? backLabel;
  final String? title;
  final String? subtitle;
  final String? pasteLabel;
  final String? invalidTitle;
  final String? invalidSubtitle;
  final String? clearLabel;

  @override
  Widget build(BuildContext context) {
    final backLabel = this.backLabel ?? context.l10n.paymentLinkMyCards;
    final subtitle = this.subtitle ?? context.l10n.paymentLinkRedeemSubtitle;
    final pasteLabel = this.pasteLabel ?? context.l10n.paymentLinkPasteLabel;
    final invalidTitle =
        this.invalidTitle ?? context.l10n.paymentLinkInvalidTitle;
    final invalidSubtitle =
        this.invalidSubtitle ?? context.l10n.paymentLinkInvalidSubtitle;
    final clearLabel =
        this.clearLabel ?? context.l10n.paymentLinkClearClipboardLabel;
    final loading = state == PaymentLinkRedeemVisualState.loading;
    final invalid = state == PaymentLinkRedeemVisualState.invalid;
    if (loading) {
      return PaymentLinkReceivedDesktopView(
        state: PaymentLinkClaimDesktopState.loading,
        card: loadingPlaceholder ?? const PaymentLinkLoadingCard(),
        onBack: onBack,
        backLabel: backLabel,
      );
    }

    return PaymentLinkPane(
      backLabel: backLabel,
      onBack: onBack,
      child: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: 396,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 94),
              Text(
                title ??
                    (loading
                        ? context.l10n.paymentLinkCheckingLabel
                        : context.l10n.paymentLinkRedeemTheCardTitle),
                textAlign: TextAlign.center,
                style: AppTypography.headlineLarge.copyWith(
                  color: context.colors.text.accent,
                ),
              ),
              const SizedBox(height: 52),
              SizedBox(
                height: 445,
                child: Stack(
                  children: [
                    Positioned(
                      top: 0,
                      left: 18,
                      child: loading
                          ? loadingPlaceholder ?? const PaymentLinkLoadingCard()
                          : PaymentLinkDashedDropZone(
                              child:
                                  statusContent ??
                                  (invalid
                                      ? Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              invalidTitle,
                                              textAlign: TextAlign.center,
                                              style: AppTypography
                                                  .bodyMediumStrong
                                                  .copyWith(
                                                    color: context
                                                        .colors
                                                        .text
                                                        .destructive,
                                                  ),
                                            ),
                                            const SizedBox(
                                              height: AppSpacing.xs,
                                            ),
                                            Text(
                                              invalidSubtitle,
                                              textAlign: TextAlign.center,
                                              style: AppTypography.bodyMedium
                                                  .copyWith(
                                                    color: context
                                                        .colors
                                                        .text
                                                        .secondary,
                                                  ),
                                            ),
                                            const SizedBox(
                                              height: AppSpacing.sm,
                                            ),
                                            PaymentLinkPasteButton(
                                              label: pasteLabel,
                                              onPressed: onPaste,
                                            ),
                                            if (onScan != null) ...[
                                              const SizedBox(
                                                height: AppSpacing.s,
                                              ),
                                              _scanButton(context),
                                            ],
                                          ],
                                        )
                                      : Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            PaymentLinkPasteButton(
                                              label: pasteLabel,
                                              onPressed: onPaste,
                                            ),
                                            if (onScan != null) ...[
                                              const SizedBox(
                                                height: AppSpacing.s,
                                              ),
                                              _scanButton(context),
                                            ],
                                          ],
                                        )),
                            ),
                    ),
                    Positioned(
                      top: 283,
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
                    if (secondaryAction != null || invalid)
                      Positioned(
                        top: secondaryAction != null
                            ? PaymentLinkGiftCard.height + AppSpacing.md
                            : 366,
                        left: 0,
                        right: 0,
                        child: Center(
                          child:
                              secondaryAction ??
                              PaymentLinkTextAction(
                                label: clearLabel,
                                onTap: onClearClipboard,
                                leading: const AppIcon(AppIcons.trash),
                              ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _scanButton(BuildContext context) => AppButton(
    key: const ValueKey('payment_link_desktop_scan_button'),
    onPressed: scanEnabled ? onScan : null,
    size: AppButtonSize.mediumLarge,
    variant: AppButtonVariant.secondary,
    leading: const AppIcon(AppIcons.qr),
    child: Text(context.l10n.paymentLinkScanQrCode),
  );
}
