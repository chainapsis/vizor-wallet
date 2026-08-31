import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/app_tooltip.dart';
import '../payment_link_action.dart';
import '../payment_link_card_motion.dart';
import '../payment_link_skeleton.dart';

const _referenceContentHeight = 773.0;
const _topInset = 12.0;
const _navHeight = 74.0;
const _sideInset = 16.0;
const _subtitleTop = 102.0;
const _cardTop = 207.0;
const _redeemCardTop = 231.0;
const _receivedCardTop = 221.0;
const kPaymentLinkMobileCardWidth = 361.0;
const kPaymentLinkMobileCardHeight = 225.625;
const _cardWidth = kPaymentLinkMobileCardWidth;
const _cardHeight = kPaymentLinkMobileCardHeight;
const _selectorTop = _cardTop + _cardHeight + AppSpacing.md;
const _selectorHeight = 80.0;
const _bottomInset = 12.0;
const _buttonHeight = 50.0;

enum PaymentLinkRedeemMobileState { paste, loading, invalid, unavailable }

enum PaymentLinkReadyMobileState { waiting, soon, ready }

class PaymentLinkHowItWorksMobileSheet extends StatelessWidget {
  const PaymentLinkHowItWorksMobileSheet({
    required this.onClose,
    this.title = 'How Gift Cards work',
    this.subtitle = 'A great way to celebrate anything.',
    super.key,
  });

  final VoidCallback onClose;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.base,
        AppSpacing.sm,
        AppSpacing.base,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: AppTypography.bodyLarge.copyWith(
              color: context.colors.text.accent,
              fontWeight: FontWeight.w600,
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
          const _MobileHelpStep(
            icon: AppIcons.giftCard,
            text:
                'Enter an amount, pick a design, and add an optional message.',
          ),
          const SizedBox(height: AppSpacing.xs),
          const _MobileHelpStep(
            icon: AppIcons.link,
            text:
                'After 6 confirmations, copy the unique link and send it only '
                'to the intended recipient.',
          ),
          const SizedBox(height: AppSpacing.xs),
          const _MobileHelpStep(
            icon: AppIcons.arrowDownCircle,
            text:
                'The recipient opens the link in Vizor and claims the full '
                'card amount. The sender covers both fees.',
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton(
            key: const ValueKey('payment_link_mobile_help_close_button'),
            onPressed: onClose,
            variant: AppButtonVariant.secondary,
            size: AppButtonSize.large,
            expand: true,
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _MobileHelpStep extends StatelessWidget {
  const _MobileHelpStep({required this.icon, required this.text});

  final String icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 32,
          height: 24,
          child: Center(
            child: AppIcon(
              icon,
              size: AppIconSize.medium,
              color: context.colors.icon.accent,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.xxs),
        Expanded(
          child: Text(
            text,
            style: AppTypography.bodyMedium.copyWith(
              color: context.colors.text.primary,
            ),
          ),
        ),
      ],
    );
  }
}

/// Empty Gift Cards landing view for the mobile form factor.
class PaymentLinksHomeMobileView extends StatelessWidget {
  const PaymentLinksHomeMobileView({
    required this.illustration,
    required this.onBack,
    required this.onShowHelp,
    required this.onCreate,
    required this.onRedeem,
    this.screenTitle = 'Gift Cards',
    this.title = 'No Gift Cards yet',
    this.helpLabel = 'How the Gift Card works',
    this.createLabel = 'Create a card',
    this.redeemLabel = 'Redeem a card',
    super.key,
  });

  final Widget illustration;
  final VoidCallback onBack;
  final VoidCallback onShowHelp;
  final VoidCallback onCreate;
  final VoidCallback onRedeem;
  final String screenTitle;
  final String title;
  final String helpLabel;
  final String createLabel;
  final String redeemLabel;

  @override
  Widget build(BuildContext context) {
    return _MobilePaymentLinkFrame(
      title: screenTitle,
      onBack: onBack,
      body: Padding(
        padding: const EdgeInsets.only(
          top: _topInset + _navHeight,
          left: _sideInset,
          right: _sideInset,
        ),
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.base),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 340,
                        height: 220,
                        child: Center(
                          child: SizedBox(
                            key: const ValueKey(
                              'payment_links_mobile_empty_illustration',
                            ),
                            width: 300,
                            height: 200,
                            child: illustration,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.base),
                      Text(
                        title,
                        key: const ValueKey('payment_links_mobile_empty_title'),
                        textAlign: TextAlign.center,
                        style: AppTypography.headlineLarge.copyWith(
                          color: context.colors.text.accent,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              helpLabel,
                              key: const ValueKey(
                                'payment_links_mobile_help_label',
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.bodyMedium.copyWith(
                                color: context.colors.text.secondary,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xxs),
                          SizedBox(
                            width: 20,
                            height: 36,
                            child: PaymentLinkAction(
                              key: const ValueKey(
                                'payment_links_mobile_help_action',
                              ),
                              onPressed: onShowHelp,
                              semanticLabel: 'Show how Gift Cards work',
                              builder: (context, _, focused) => Center(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: focused
                                        ? Border.all(
                                            color:
                                                context.colors.state.focusRing,
                                            width: 2,
                                          )
                                        : null,
                                  ),
                                  child: AppIcon(
                                    AppIcons.help,
                                    size: 16,
                                    color: context.colors.icon.regular,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppButton(
                  key: const ValueKey('payment_links_mobile_redeem_button'),
                  onPressed: onRedeem,
                  variant: AppButtonVariant.ghost,
                  size: AppButtonSize.large,
                  height: _buttonHeight,
                  expand: true,
                  child: Text(redeemLabel),
                ),
                const SizedBox(height: AppSpacing.s),
                AppButton(
                  key: const ValueKey('payment_links_mobile_create_button'),
                  onPressed: onCreate,
                  size: AppButtonSize.large,
                  height: _buttonHeight,
                  expand: true,
                  leading: const AppIcon(
                    AppIcons.giftCard,
                    size: AppIconSize.medium,
                  ),
                  child: Text(createLabel),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Amount entry and artwork selection state from the completed mobile flow.
class PaymentLinkAmountMobileView extends StatelessWidget {
  const PaymentLinkAmountMobileView({
    required this.card,
    required this.cardSelector,
    required this.onBack,
    this.onContinue,
    this.supportingText,
    this.supportingTextIsError = false,
    this.title = 'Create Gift Card',
    this.subtitle = 'Enter amount & pick a design.',
    this.continueLabel = 'Continue',
    super.key,
  });

  final Widget card;
  final Widget cardSelector;
  final VoidCallback onBack;
  final VoidCallback? onContinue;
  final String? supportingText;
  final bool supportingTextIsError;
  final String title;
  final String subtitle;
  final String continueLabel;

  @override
  Widget build(BuildContext context) {
    return _MobilePaymentLinkWizardFrame(
      title: title,
      subtitle: subtitle,
      onBack: onBack,
      card: card,
      selector: cardSelector,
      supportingText: supportingText,
      supportingTextIsError: supportingTextIsError,
      action: AppButton(
        key: const ValueKey('payment_link_mobile_amount_continue_button'),
        onPressed: onContinue,
        size: AppButtonSize.large,
        height: _buttonHeight,
        expand: true,
        child: Text(continueLabel),
      ),
    );
  }
}

/// Optional encrypted memo state. The single CTA also handles an empty memo.
class PaymentLinkMessageMobileView extends StatelessWidget {
  const PaymentLinkMessageMobileView({
    required this.card,
    required this.onBack,
    this.onContinue,
    this.onSkip,
    this.errorText,
    this.title = 'Enter a message',
    this.subtitle = 'Attach a short encrypted memo (optional).',
    this.continueLabel = 'Continue',
    super.key,
  });

  final Widget card;
  final VoidCallback onBack;
  final VoidCallback? onContinue;

  /// Used by the same Continue CTA only when the caller models an empty memo
  /// as a separate skip action. It never adds a second visible action.
  final VoidCallback? onSkip;
  final String? errorText;
  final String title;
  final String subtitle;
  final String continueLabel;

  @override
  Widget build(BuildContext context) {
    return _MobilePaymentLinkWizardFrame(
      title: title,
      subtitle: subtitle,
      onBack: onBack,
      card: card,
      supportingText: errorText,
      supportingTextIsError: errorText != null,
      action: AppButton(
        key: const ValueKey('payment_link_mobile_message_continue_button'),
        onPressed: onContinue ?? onSkip,
        size: AppButtonSize.large,
        height: _buttonHeight,
        expand: true,
        child: Text(continueLabel),
      ),
    );
  }
}

/// Mobile fee review state. Amounts are supplied by the transaction layer.
class PaymentLinkReviewMobileView extends StatelessWidget {
  const PaymentLinkReviewMobileView({
    required this.card,
    required this.onBack,
    required this.cardAmountText,
    required this.cardFeeText,
    required this.totalAmountText,
    this.onContinue,
    this.onFeeHelp,
    this.title = 'Review a Card',
    this.subtitle = 'Attach a short encrypted memo (optional).',
    this.continueLabel = 'Approve & create',
    super.key,
  });

  final Widget card;
  final VoidCallback onBack;
  final String cardAmountText;
  final String cardFeeText;
  final String totalAmountText;
  final VoidCallback? onContinue;
  final VoidCallback? onFeeHelp;
  final String title;
  final String subtitle;
  final String continueLabel;

  @override
  Widget build(BuildContext context) {
    return _MobilePaymentLinkFrame(
      title: title,
      onBack: onBack,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            top: _subtitleTop,
            left: _sideInset,
            right: _sideInset,
            child: Text(
              subtitle,
              key: const ValueKey('payment_link_mobile_review_subtitle'),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.bodyMediumStrong.copyWith(
                color: context.colors.text.secondary,
              ),
            ),
          ),
          Positioned(
            top: _cardTop,
            left: _sideInset,
            right: _sideInset,
            child: _MobileCardSlot(card: card),
          ),
          Positioned(
            top: 456.625,
            left: _sideInset,
            right: _sideInset,
            child: Container(
              key: const ValueKey('payment_link_mobile_review_summary'),
              width: double.infinity,
              height: 193,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.base,
              ),
              decoration: BoxDecoration(
                color: context.colors.background.ground,
                borderRadius: BorderRadius.circular(AppRadii.large),
              ),
              child: Column(
                children: [
                  _MobileReviewRow(label: 'Card amount', value: cardAmountText),
                  _MobileReviewRow(
                    label: 'Card fee (deposit + redeem)',
                    value: cardFeeText,
                    onHelp: onFeeHelp,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  SizedBox(
                    key: const ValueKey('payment_link_mobile_review_divider'),
                    width: double.infinity,
                    height: 1,
                    child: ColoredBox(color: context.colors.border.regular),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _MobileReviewRow(
                    label: 'Total amount deducted',
                    value: totalAmountText,
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: _sideInset,
            right: _sideInset,
            bottom: _bottomInset,
            child: AppButton(
              key: const ValueKey('payment_link_mobile_review_continue_button'),
              onPressed: onContinue,
              size: AppButtonSize.large,
              height: _buttonHeight,
              expand: true,
              child: Text(continueLabel),
            ),
          ),
        ],
      ),
    );
  }
}

/// Mobile deposited-card state from Figma `7828:69021` / `7828:70405`.
class PaymentLinkReadyMobileView extends StatelessWidget {
  const PaymentLinkReadyMobileView({
    required this.state,
    required this.card,
    required this.onHome,
    this.onCopy,
    this.onCardTap,
    this.decoration,
    this.waitingStatusLabel = 'Wait 7:30 to get the link',
    this.copyLabel = 'Copy link',
    this.homeLabel = 'Go home',
    super.key,
  });

  final PaymentLinkReadyMobileState state;
  final Widget card;
  final VoidCallback onHome;
  final VoidCallback? onCopy;
  final VoidCallback? onCardTap;
  final Widget? decoration;
  final String waitingStatusLabel;
  final String copyLabel;
  final String homeLabel;

  @override
  Widget build(BuildContext context) {
    final ready = state == PaymentLinkReadyMobileState.ready;
    final canFlip = ready && onCardTap != null;
    final motionCard = ready
        ? PaymentLinkCardMotion(
            celebrate: true,
            child: canFlip ? IgnorePointer(child: card) : card,
          )
        : card;
    final cardContent = canFlip
        ? PaymentLinkAction(
            onPressed: onCardTap,
            semanticLabel: 'Flip gift card',
            builder: (context, _, focused) => DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadii.large),
                border: focused
                    ? Border.all(
                        color: context.colors.state.focusRing,
                        width: 2,
                      )
                    : null,
              ),
              child: ExcludeSemantics(child: motionCard),
            ),
          )
        : motionCard;

    return SizedBox.expand(
      key: const ValueKey('payment_link_mobile_ready_view'),
      child: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.none,
        children: [
          if (decoration != null) Positioned.fill(child: decoration!),
          Positioned(
            top: 12,
            left: 40,
            right: 40,
            child: Text(
              ready
                  ? 'Your Gift Card\nis ready!'
                  : 'Gift Card is\nalmost ready!',
              textAlign: TextAlign.center,
              style: AppTypography.displayLarge.copyWith(
                color: context.colors.text.accent,
              ),
            ),
          ),
          Positioned(
            top: 190,
            left: _sideInset,
            right: _sideInset,
            child: _MobileCardSlot(card: cardContent),
          ),
          Positioned(
            top: 474,
            left: 0,
            right: 0,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 328),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      ready
                          ? 'Share this link with the intended recipient so '
                                'they can claim the Card using their Vizor app.'
                          : 'The link becomes shareable after 6 confirmations.\n'
                                'This usually takes about 7 min 30 sec. We will let you know '
                                'when the card is ready to be shared.',
                      textAlign: TextAlign.center,
                      style: AppTypography.bodyMedium.copyWith(
                        color: context.colors.text.primary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    if (ready)
                      AppButton(
                        key: const ValueKey('payment_link_mobile_copy_button'),
                        onPressed: onCopy,
                        size: AppButtonSize.mediumLarge,
                        leading: const AppIcon(AppIcons.copy),
                        child: Text(copyLabel),
                      )
                    else
                      _MobileDashedStatusPill(
                        label: waitingStatusLabel,
                        icon: state == PaymentLinkReadyMobileState.soon
                            ? AppIcons.link
                            : AppIcons.giftCard,
                      ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: _sideInset,
            right: _sideInset,
            bottom: _bottomInset,
            child: AppButton(
              key: const ValueKey('payment_link_mobile_ready_home_button'),
              onPressed: onHome,
              size: AppButtonSize.large,
              height: _buttonHeight,
              expand: true,
              child: Text(homeLabel),
            ),
          ),
        ],
      ),
    );
  }
}

/// Mobile payment-link intake states from Figma `Redeem a Card`
/// (`7828:70675`) and its checking/error variants.
class PaymentLinkRedeemMobileView extends StatelessWidget {
  const PaymentLinkRedeemMobileView({
    required this.state,
    required this.onBack,
    this.onPaste,
    this.onClearClipboard,
    this.title = 'Redeem the Card',
    this.subtitle = 'Copy the card link you’ve received, and paste it below.',
    this.pasteLabel = 'Paste card link',
    this.invalidTitle = 'The link doesn’t look legit.',
    this.invalidSubtitle = 'Copy the link & try again',
    this.unavailableTitle = 'This card has no available balance.',
    this.unavailableSubtitle = 'It may have already been claimed.',
    this.clearLabel = 'Clear clipboard',
    super.key,
  });

  final PaymentLinkRedeemMobileState state;
  final VoidCallback onBack;
  final VoidCallback? onPaste;
  final VoidCallback? onClearClipboard;
  final String title;
  final String subtitle;
  final String pasteLabel;
  final String invalidTitle;
  final String invalidSubtitle;
  final String unavailableTitle;
  final String unavailableSubtitle;
  final String clearLabel;

  @override
  Widget build(BuildContext context) {
    final loading = state == PaymentLinkRedeemMobileState.loading;
    final invalid = state == PaymentLinkRedeemMobileState.invalid;
    final unavailable = state == PaymentLinkRedeemMobileState.unavailable;
    final showError = invalid || unavailable;

    return _MobilePaymentLinkFrame(
      title: title,
      onBack: onBack,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            top: _subtitleTop,
            left: 48,
            right: 48,
            child: Text(
              subtitle,
              key: const ValueKey('payment_link_mobile_redeem_subtitle'),
              textAlign: TextAlign.center,
              style: AppTypography.bodyMediumStrong.copyWith(
                color: context.colors.text.secondary,
              ),
            ),
          ),
          Positioned(
            top: _redeemCardTop,
            left: _sideInset,
            right: _sideInset,
            child: loading
                ? const _PaymentLinkLoadingMobileCard()
                : _PaymentLinkMobileDropZone(
                    child: showError
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                invalid ? invalidTitle : unavailableTitle,
                                textAlign: TextAlign.center,
                                style: AppTypography.bodyMediumStrong.copyWith(
                                  color: context.colors.text.destructive,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              Text(
                                invalid ? invalidSubtitle : unavailableSubtitle,
                                textAlign: TextAlign.center,
                                style: AppTypography.bodyMedium.copyWith(
                                  color: context.colors.text.secondary,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              _MobilePasteButton(
                                label: pasteLabel,
                                onPressed: onPaste,
                              ),
                            ],
                          )
                        : _MobilePasteButton(
                            label: pasteLabel,
                            onPressed: onPaste,
                          ),
                  ),
          ),
          if (loading)
            Positioned(
              top: _redeemCardTop + _cardHeight + AppSpacing.md,
              left: 0,
              right: 0,
              child: Text(
                'Checking ...',
                key: const ValueKey('payment_link_mobile_redeem_checking'),
                textAlign: TextAlign.center,
                style: AppTypography.bodyMediumStrong.copyWith(
                  color: context.colors.text.secondary,
                ),
              ),
            ),
          if (showError)
            Positioned(
              top: _redeemCardTop + _cardHeight + AppSpacing.lg,
              left: 0,
              right: 0,
              child: Center(
                child: AppButton(
                  key: const ValueKey(
                    'payment_link_mobile_clear_clipboard_button',
                  ),
                  onPressed: onClearClipboard,
                  variant: AppButtonVariant.ghost,
                  size: AppButtonSize.mediumLarge,
                  leading: const AppIcon(AppIcons.trash, size: 20),
                  child: Text(clearLabel),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Mobile received-card surface from Figma `Redeem a Card — Success`
/// (`7861:10257`). Claim execution remains owned by the caller.
class PaymentLinkReceivedMobileView extends StatelessWidget {
  const PaymentLinkReceivedMobileView({
    required this.card,
    required this.hasMessage,
    required this.onClose,
    this.onClaim,
    this.onRevealMessage,
    this.decoration,
    this.title = 'You’ve received a gift!',
    this.messageTitle = 'Message attached.',
    this.messageHint = 'Tap on the card to reveal\nthe message.',
    this.claimLabel = 'Claim the gift',
    super.key,
  });

  final Widget card;
  final bool hasMessage;
  final VoidCallback onClose;
  final VoidCallback? onClaim;
  final VoidCallback? onRevealMessage;
  final Widget? decoration;
  final String title;
  final String messageTitle;
  final String messageHint;
  final String claimLabel;

  @override
  Widget build(BuildContext context) {
    final motionCard = PaymentLinkCardMotion(
      celebrate: true,
      child: hasMessage && onRevealMessage != null
          ? IgnorePointer(child: card)
          : card,
    );
    return SizedBox(
      key: const ValueKey('payment_link_mobile_received_view'),
      width: double.infinity,
      height: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.none,
        children: [
          if (decoration != null) Positioned.fill(child: decoration!),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: MobileTopNav.back(
              key: const ValueKey('payment_link_mobile_close_button'),
              title: '',
              onBack: onClose,
              backIcon: AppIcons.cross,
            ),
          ),
          if (hasMessage)
            Positioned(
              top: 100,
              left: 0,
              right: 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SvgPicture.asset(
                    'assets/illustrations/payment_links/'
                    'payment_link_envelope.svg',
                    width: 27,
                    height: 22,
                    semanticsLabel: 'Gift message',
                  ),
                  const SizedBox(height: AppSpacing.s),
                  Text(
                    messageTitle,
                    style: AppTypography.labelLarge.copyWith(
                      color: context.colors.text.brandCrimson,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          Positioned(
            top: _receivedCardTop,
            left: _sideInset,
            right: _sideInset,
            child: _MobileCardSlot(
              card: hasMessage && onRevealMessage != null
                  ? PaymentLinkAction(
                      onPressed: onRevealMessage,
                      semanticLabel: 'Reveal gift card message',
                      builder: (context, _, focused) => DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(AppRadii.large),
                          border: focused
                              ? Border.all(
                                  color: context.colors.state.focusRing,
                                  width: 2,
                                )
                              : null,
                        ),
                        child: ExcludeSemantics(child: motionCard),
                      ),
                    )
                  : motionCard,
            ),
          ),
          Positioned(
            top: 516,
            left: _sideInset,
            right: _sideInset,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  key: const ValueKey('payment_link_mobile_received_title'),
                  textAlign: TextAlign.center,
                  style: AppTypography.displayLarge.copyWith(
                    color: context.colors.text.accent,
                  ),
                ),
                if (hasMessage) ...[
                  const SizedBox(height: AppSpacing.s),
                  Text(
                    messageHint,
                    textAlign: TextAlign.center,
                    style: AppTypography.bodyMediumStrong.copyWith(
                      color: context.colors.text.secondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Positioned(
            left: _sideInset,
            right: _sideInset,
            bottom: _bottomInset,
            child: AppButton(
              key: const ValueKey('payment_link_mobile_claim_button'),
              onPressed: onClaim,
              size: AppButtonSize.large,
              height: _buttonHeight,
              expand: true,
              child: Text(claimLabel),
            ),
          ),
        ],
      ),
    );
  }
}

class _MobilePasteButton extends StatelessWidget {
  const _MobilePasteButton({required this.label, this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return AppButton(
      key: const ValueKey('payment_link_mobile_paste_button'),
      onPressed: onPressed,
      size: AppButtonSize.mediumLarge,
      height: 36,
      leading: const AppIcon(AppIcons.paste, size: 20),
      child: Text(label),
    );
  }
}

class _PaymentLinkMobileDropZone extends StatelessWidget {
  const _PaymentLinkMobileDropZone({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      key: const ValueKey('payment_link_mobile_redeem_drop_zone'),
      painter: _MobileDashedBorderPainter(
        color: context.colors.border.medium,
        radius: AppRadii.xLarge,
      ),
      child: SizedBox(
        width: _cardWidth,
        height: _cardHeight,
        child: Center(child: child),
      ),
    );
  }
}

class _MobileDashedBorderPainter extends CustomPainter {
  const _MobileDashedBorderPainter({
    required this.color,
    required this.radius,
    this.strokeWidth = 3,
  });

  final Color color;
  final double radius;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
      );
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(metric.extractPath(distance, distance + 6), paint);
        distance += 12;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MobileDashedBorderPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.radius != radius ||
      oldDelegate.strokeWidth != strokeWidth;
}

class _PaymentLinkLoadingMobileCard extends StatelessWidget {
  const _PaymentLinkLoadingMobileCard();

  @override
  Widget build(BuildContext context) {
    final skeletonColor = context.colors.text.secondary;
    return Container(
      key: const ValueKey('payment_link_mobile_loading_card'),
      width: _cardWidth,
      height: _cardHeight,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.colors.background.ground,
        borderRadius: BorderRadius.circular(AppRadii.large),
        gradient: LinearGradient(
          colors: [
            skeletonColor.withValues(alpha: 0.08),
            skeletonColor.withValues(alpha: 0.35),
            skeletonColor.withValues(alpha: 0.08),
          ],
          stops: const [0, 0.5, 1],
        ),
      ),
      child: Align(
        alignment: Alignment.bottomLeft,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PaymentLinkSkeletonBar(
              width: 60,
              height: 12,
              colors: [
                skeletonColor.withValues(alpha: 0.08),
                skeletonColor.withValues(alpha: 0.55),
              ],
            ),
            const SizedBox(height: AppSpacing.s),
            PaymentLinkSkeletonBar(
              width: 130,
              height: 31,
              colors: [
                skeletonColor.withValues(alpha: 0.08),
                skeletonColor.withValues(alpha: 0.55),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileDashedStatusPill extends StatelessWidget {
  const _MobileDashedStatusPill({required this.label, required this.icon});

  final String label;
  final String icon;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _MobileDashedBorderPainter(
        color: context.colors.border.medium,
        radius: AppRadii.full,
        strokeWidth: 2,
      ),
      child: SizedBox(
        height: 36,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(icon, size: 20, color: context.colors.text.primary),
              const SizedBox(width: AppSpacing.xxs),
              Text(
                label,
                style: AppTypography.labelLarge.copyWith(
                  color: context.colors.text.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MobilePaymentLinkWizardFrame extends StatelessWidget {
  const _MobilePaymentLinkWizardFrame({
    required this.title,
    required this.subtitle,
    required this.onBack,
    required this.card,
    required this.action,
    this.selector,
    this.supportingText,
    this.supportingTextIsError = false,
  });

  final String title;
  final String subtitle;
  final VoidCallback onBack;
  final Widget card;
  final Widget action;
  final Widget? selector;
  final String? supportingText;
  final bool supportingTextIsError;

  @override
  Widget build(BuildContext context) {
    return _MobilePaymentLinkFrame(
      title: title,
      onBack: onBack,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            top: _subtitleTop,
            left: _sideInset,
            right: _sideInset,
            child: Text(
              subtitle,
              key: const ValueKey('payment_link_mobile_step_subtitle'),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.bodyMediumStrong.copyWith(
                color: context.colors.text.secondary,
              ),
            ),
          ),
          Positioned(
            top: _cardTop,
            left: _sideInset,
            right: _sideInset,
            child: _MobileCardSlot(card: card),
          ),
          if (selector case final selector?)
            Positioned(
              top: _selectorTop,
              left: 0,
              right: 0,
              height: _selectorHeight,
              child: Center(child: selector),
            ),
          Positioned(
            left: _sideInset,
            right: _sideInset,
            bottom: _bottomInset,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (supportingText case final message?) ...[
                  Text(
                    message,
                    key: const ValueKey('payment_link_mobile_supporting_text'),
                    textAlign: TextAlign.center,
                    style: AppTypography.bodySmall.copyWith(
                      color: supportingTextIsError
                          ? context.colors.text.destructive
                          : context.colors.text.secondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                ],
                SizedBox(width: double.infinity, child: action),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MobilePaymentLinkFrame extends StatelessWidget {
  const _MobilePaymentLinkFrame({
    required this.title,
    required this.onBack,
    required this.body,
  });

  final String title;
  final VoidCallback onBack;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : _referenceContentHeight;
        return SizedBox(
          key: const ValueKey('payment_link_mobile_view'),
          width: double.infinity,
          height: height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              body,
              Positioned(
                top: _topInset,
                left: 0,
                right: 0,
                height: _navHeight,
                child: MobileTopNav.back(
                  title: title,
                  onBack: onBack,
                  height: _navHeight,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MobileCardSlot extends StatelessWidget {
  const _MobileCardSlot({required this.card});

  final Widget card;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        key: const ValueKey('payment_link_mobile_card_slot'),
        width: _cardWidth,
        height: _cardHeight,
        child: card,
      ),
    );
  }
}

class _MobileReviewRow extends StatelessWidget {
  const _MobileReviewRow({
    required this.label,
    required this.value,
    this.onHelp,
  });

  final String label;
  final String value;
  final VoidCallback? onHelp;

  @override
  Widget build(BuildContext context) {
    final help = AppTooltip(
      message:
          'Includes the fee to fund the Gift Card and the fee reserved for '
          'the recipient to claim it.',
      preferBelow: true,
      tapToShow: true,
      child: Semantics(
        label: 'About the Gift Card fee',
        button: onHelp != null,
        onTap: onHelp,
        child: AppIcon(
          AppIcons.help,
          size: AppIconSize.medium,
          color: context.colors.icon.muted,
        ),
      ),
    );

    return SizedBox(
      height: 32,
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xxs),
              child: Text(
                label,
                style: AppTypography.labelLarge.copyWith(
                  color: context.colors.text.secondary,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xs,
              AppSpacing.xxs,
              AppSpacing.xxs,
              AppSpacing.xxs,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  key: ValueKey('payment_link_mobile_review_value_$label'),
                  textAlign: TextAlign.right,
                  style: AppTypography.labelLarge.copyWith(
                    color: context.colors.text.primary,
                  ),
                ),
                if (onHelp != null) ...[
                  const SizedBox(width: AppSpacing.xxs),
                  Listener(
                    key: const ValueKey('payment_link_mobile_fee_help'),
                    onPointerUp: (_) => onHelp!(),
                    child: help,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
