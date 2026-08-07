import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_pane_floating_bar.dart';
import '../../../core/layout/app_pane_scroll_scaffold.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_back_link.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_modal_card.dart';
import '../../../core/widgets/app_pane_modal_overlay.dart';
import '../../../core/widgets/app_tooltip.dart';
import 'payment_link_action.dart';
import 'payment_link_card_motion.dart';
import 'payment_link_gift_card.dart';
import 'payment_link_skeleton.dart';

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

enum PaymentLinkCardsTab { created, received }

/// Empty Gift Cards landing surface.
class PaymentLinksHomeDesktopView extends StatelessWidget {
  const PaymentLinksHomeDesktopView({
    required this.illustration,
    required this.onBack,
    required this.onShowHelp,
    required this.onCreate,
    required this.onRedeem,
    this.backLabel = 'Home',
    this.title = 'No Gift Cards yet',
    this.helpLabel = 'How Gift Cards work',
    this.createLabel = 'Create new card',
    this.redeemLabel = 'Redeem a card',
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
    return _PaymentLinkPane(
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
                    _TextAction(
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
                    _TextAction(label: redeemLabel, onTap: onRedeem),
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
    this.title = 'How Gift Cards work',
    this.subtitle = 'A great way to celebrate anything.',
    this.createDescription =
        'Enter amount to gift, pick a design, add a message (optional) '
        'and create your Card with a single click.',
    this.shareDescription =
        'After the card is created, you will get a uniquely generated Link. '
        'The Link contains its claim secret and is not encrypted, so send it '
        'only to the '
        'intended recipient.',
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
            child: SizedBox(
              height: 393,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
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
                          _HelpStep(
                            icon: AppIcons.giftCard,
                            text: createDescription,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          _HelpStep(
                            icon: AppIcons.link,
                            text: shareDescription,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          _HelpStep(
                            icon: AppIcons.arrowDownCircle,
                            text: redeemDescription,
                          ),
                          const SizedBox(height: AppSpacing.md),
                        ],
                      ),
                    ),
                  ),
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
    this.errorText,
    this.backLabel = 'Home',
    this.title = 'Create Gift Card',
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
  final String? errorText;
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
    return _PaymentLinkWizardPane(
      title: title,
      subtitle: subtitle,
      currentStep: 0,
      backLabel: backLabel,
      onBack: onBack,
      onStepSelected: onStepSelected,
      childSpacing: AppSpacing.lg + AppSpacing.base + AppSpacing.xs,
      action: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (errorText case final error?) ...[
            Text(
              error,
              key: const ValueKey('payment_link_amount_error'),
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(
                color: context.colors.text.destructive,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
          AppButton(
            key: const ValueKey('payment_link_amount_continue_button'),
            onPressed: canContinue ? onCreate : null,
            minWidth: 196,
            size: AppButtonSize.large,
            trailing: canContinue
                ? const AppIcon(AppIcons.chevronForward)
                : null,
            child: Text(_hasAmount ? createLabel : emptyActionLabel),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          card,
          const SizedBox(height: AppSpacing.base),
          cardSelector,
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
    this.backLabel = 'Home',
    this.title = 'Create Gift Card',
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
  final String backLabel;
  final String title;
  final String subtitle;
  final String skipLabel;
  final String emptyContinueLabel;
  final String continueLabel;

  @override
  Widget build(BuildContext context) {
    return _PaymentLinkWizardPane(
      title: title,
      subtitle: subtitle,
      currentStep: 1,
      backLabel: backLabel,
      onBack: onBack,
      onStepSelected: onStepSelected,
      // The amount and message cards share one visual anchor across steps.
      childSpacing: AppSpacing.lg + AppSpacing.base + AppSpacing.xs,
      action: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _TextAction(label: skipLabel, onTap: onSkip),
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
      child: card,
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
    this.title = 'Create Gift Card',
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
    return _PaymentLinkWizardPane(
      title: title,
      subtitle: subtitle,
      currentStep: 2,
      backLabel: backLabel,
      onBack: onBack,
      onStepSelected: onStepSelected,
      childSpacing: AppSpacing.lg + AppSpacing.xs,
      action: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: PaymentLinkGiftCard.width,
            child: Column(
              children: [
                _ReviewAmountRow(label: 'Card amount', value: cardAmountText),
                const SizedBox(height: AppSpacing.xs),
                _ReviewAmountRow(
                  label: 'Card fee (deposit + redeem)',
                  value: cardFeeText,
                  showHelp: true,
                ),
                const SizedBox(height: AppSpacing.sm),
                SizedBox(
                  key: const ValueKey('payment_link_review_divider'),
                  width: double.infinity,
                  height: 1,
                  child: ColoredBox(color: context.colors.border.regular),
                ),
                const SizedBox(height: AppSpacing.sm),
                _ReviewAmountRow(
                  label: 'Total amount deducted',
                  value: totalAmountText,
                  emphasized: true,
                ),
              ],
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
    return Row(
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
              label: 'About the Gift Card fee',
              child: AppIcon(
                AppIcons.help,
                size: 16,
                color: context.colors.icon.muted,
              ),
            ),
          ),
        ],
      ],
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
    this.waitingStatusLabel = 'Your link will be here',
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
            semanticLabel: 'Flip gift card',
            builder: (context, _, focused) => _ActionFocusRing(
              focused: focused,
              borderRadius: AppRadii.large,
              child: ExcludeSemantics(child: motionCard),
            ),
          )
        : motionCard;
    return _PaymentLinkPane(
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
                  waiting
                      ? 'Gift Card is\nalmost ready!'
                      : 'Your Gift Card\nis ready!',
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
                    Text(
                      waiting
                          ? 'The Gift Card takes time to be deposited.\n'
                                'You can return later. The link will be available\n'
                                'after 10 confirmations.'
                          : 'Share this link with the intended recipient so they\n'
                                'can claim the Card using their Vizor app.',
                      textAlign: TextAlign.center,
                      style: AppTypography.bodyMedium.copyWith(
                        color: context.colors.text.secondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    if (waiting)
                      _DashedStatusPill(label: waitingStatusLabel)
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
                      _TextAction(
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
    this.title = 'You’ve received a gift!',
    this.messageTitle = 'Message attached.',
    this.messageHint = 'Click on the card to reveal',
    this.claimLabel = 'Claim my gift',
    this.cardActionLabel = 'Reveal gift card message',
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
    return _PaymentLinkPane(
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
                top: 68,
                left: 0,
                right: 0,
                child: Center(
                  child: SizedBox(
                    width: AppSpacing.base,
                    height: AppSpacing.base,
                    child: Center(
                      child: SvgPicture.asset(
                        'assets/illustrations/payment_links/'
                        'payment_link_envelope.svg',
                        width: 27,
                        height: 22,
                        semanticsLabel: 'Gift message',
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 143.5,
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
                          builder: (context, _, focused) => _ActionFocusRing(
                            focused: focused,
                            borderRadius: AppRadii.large,
                            child: ExcludeSemantics(child: motionCard),
                          ),
                        )
                      : motionCard,
                ),
              ),
              Positioned(
                top: 364,
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
                    if (onRevealMessage != null) ...[
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        messageTitle,
                        style: AppTypography.bodyMediumStrong.copyWith(
                          color: context.colors.text.brandCrimson,
                        ),
                      ),
                      Text(
                        messageHint,
                        style: AppTypography.bodyMedium.copyWith(
                          color: context.colors.text.secondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Positioned(
                top: 524.5,
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

/// A desktop row used by [PaymentLinkCardsDesktopView].
class PaymentLinkCardListRow extends StatelessWidget {
  const PaymentLinkCardListRow({
    required this.thumbnail,
    required this.amountText,
    required this.dateText,
    required this.statusText,
    this.onAction,
    this.showCopyIcon = false,
    this.showLoader = false,
    this.secondaryActionText,
    this.onSecondaryAction,
    super.key,
  });

  final Widget thumbnail;
  final String amountText;
  final String dateText;
  final String statusText;
  final VoidCallback? onAction;
  final bool showCopyIcon;
  final bool showLoader;
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
            _TextAction(
              label: secondaryLabel,
              onTap: onSecondaryAction,
              enabled: onSecondaryAction != null,
            ),
            const SizedBox(width: AppSpacing.s),
          ],
          _TextAction(
            label: statusText,
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
    return _PaymentLinkPane(
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
            child: const Text('Create a card'),
          ),
          const SizedBox(height: AppSpacing.s),
          _TextAction(label: 'Redeem a card', onTap: widget.onRedeem),
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
                    _TabAction(
                      icon: AppIcons.plane,
                      label: 'Created',
                      selected: widget.activeTab == PaymentLinkCardsTab.created,
                      onTap: widget.onTabSelected == null
                          ? null
                          : () => widget.onTabSelected!(
                              PaymentLinkCardsTab.created,
                            ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    _TabAction(
                      icon: AppIcons.arrowDownward,
                      label: 'Received',
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

class PaymentLinkCardsSection {
  const PaymentLinkCardsSection({required this.label, required this.cards});

  final String label;
  final List<Widget> cards;
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
    this.subtitle = 'Copy the card link you’ve received, and paste it below.',
    this.pasteLabel = 'Paste card link',
    this.invalidTitle = 'The link doesn’t look legit.',
    this.invalidSubtitle = 'Copy the link & try again',
    this.unavailableTitle = 'This Card has no available balance.',
    this.unavailableSubtitle = 'It may have already been claimed.',
    this.clearLabel = 'Clear clipboard',
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
    return _PaymentLinkPane(
      backLabel: backLabel,
      onBack: onBack,
      child: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: 420,
          child: Column(
            children: [
              const SizedBox(
                height:
                    AppSpacing.lg +
                    AppSpacing.lg +
                    AppSpacing.base +
                    AppSpacing.sm,
              ),
              if (loading)
                loadingPlaceholder ?? const _PaymentLinkLoadingCard()
              else
                _DashedDropZone(
                  child: showError
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              invalid ? invalidTitle : unavailableTitle,
                              style: AppTypography.bodyMediumStrong.copyWith(
                                color: context.colors.text.destructive,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              invalid ? invalidSubtitle : unavailableSubtitle,
                              style: AppTypography.bodyMedium.copyWith(
                                color: context.colors.text.secondary,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            _PasteButton(label: pasteLabel, onPressed: onPaste),
                          ],
                        )
                      : _PasteButton(label: pasteLabel, onPressed: onPaste),
                ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                title ?? (loading ? 'Checking ...' : 'Redeem the Card'),
                textAlign: TextAlign.center,
                style: AppTypography.headlineLarge.copyWith(
                  color: context.colors.text.accent,
                ),
              ),
              const SizedBox(height: AppSpacing.s),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 260),
                child: Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: AppTypography.bodyMedium.copyWith(
                    color: context.colors.text.secondary,
                  ),
                ),
              ),
              if (showError) ...[
                const SizedBox(height: AppSpacing.lg + AppSpacing.sm),
                _TextAction(
                  label: clearLabel,
                  onTap: onClearClipboard,
                  leading: const AppIcon(AppIcons.trash),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PaymentLinkPane extends StatelessWidget {
  const _PaymentLinkPane({
    required this.backLabel,
    required this.onBack,
    required this.child,
    this.actions,
    this.scrollController,
    this.showTopScrollFade = false,
    this.showBottomActionFade = true,
  });

  final String backLabel;
  final VoidCallback onBack;
  final Widget child;
  final Widget? actions;
  final ScrollController? scrollController;
  final bool showTopScrollFade;
  final bool showBottomActionFade;

  @override
  Widget build(BuildContext context) {
    return AppPaneFloatingBar(
      visible: actions != null,
      fadeVisible: showBottomActionFade,
      overlayWidth: 420,
      bar: actions ?? const SizedBox.shrink(),
      builder: (context, bottomReserve) => Stack(
        fit: StackFit.expand,
        children: [
          AppPaneScrollScaffold(
            controller: scrollController,
            toolbar: AppPaneToolbar(
              leading: AppBackLink(
                label: backLabel,
                minWidth: 60,
                onTap: onBack,
              ),
            ),
            padding: EdgeInsets.fromLTRB(
              AppSpacing.s,
              AppSpacing.sm,
              AppSpacing.s,
              bottomReserve,
            ),
            child: child,
          ),
          if (showTopScrollFade)
            Positioned(
              top: AppPaneScrollScaffold.toolbarHeight,
              left: 0,
              right: 0,
              height: 40,
              child: Center(
                child: SizedBox(
                  width: 420,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      key: const ValueKey('payment_link_list_top_fade'),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            context.colors.macosUtility.window,
                            context.colors.macosUtility.windowTransparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PaymentLinkWizardPane extends StatelessWidget {
  const _PaymentLinkWizardPane({
    required this.title,
    required this.subtitle,
    required this.currentStep,
    required this.backLabel,
    required this.onBack,
    required this.child,
    required this.action,
    this.childSpacing = AppSpacing.lg + AppSpacing.md,
    this.onStepSelected,
  });

  final String title;
  final String subtitle;
  final int currentStep;
  final String backLabel;
  final VoidCallback onBack;
  final Widget child;
  final Widget action;
  final double childSpacing;
  final ValueChanged<int>? onStepSelected;

  @override
  Widget build(BuildContext context) {
    return _PaymentLinkPane(
      backLabel: backLabel,
      onBack: onBack,
      actions: action,
      child: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: 420,
          child: Column(
            children: [
              Text(
                title,
                textAlign: TextAlign.center,
                style: AppTypography.headlineSmall.copyWith(
                  color: context.colors.text.accent,
                ),
              ),
              const SizedBox(height: AppSpacing.s),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: AppTypography.bodyMedium.copyWith(
                  color: context.colors.text.secondary,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              _PaymentLinkWizardStepper(
                currentStep: currentStep,
                onStepSelected: onStepSelected,
              ),
              SizedBox(height: childSpacing),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _PaymentLinkWizardStepper extends StatelessWidget {
  const _PaymentLinkWizardStepper({
    required this.currentStep,
    this.onStepSelected,
  });

  final int currentStep;
  final ValueChanged<int>? onStepSelected;

  @override
  Widget build(BuildContext context) {
    const labels = ['Create', 'Add Message', 'Review'];
    return SizedBox(
      width: 365,
      height: 24,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var index = 0; index < labels.length; index++) ...[
              _WizardStep(
                index: index,
                label: labels[index],
                currentStep: currentStep,
                onTap: onStepSelected == null
                    ? null
                    : () => onStepSelected!(index),
              ),
              if (index != labels.length - 1) ...[
                const SizedBox(width: AppSpacing.s),
                AppIcon(
                  AppIcons.chevronForward,
                  size: 16,
                  color: context.colors.icon.muted,
                ),
                const SizedBox(width: AppSpacing.s),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _WizardStep extends StatelessWidget {
  const _WizardStep({
    required this.index,
    required this.label,
    required this.currentStep,
    this.onTap,
  });

  final int index;
  final String label;
  final int currentStep;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final completed = index < currentStep;
    final active = index == currentStep;
    final color = active
        ? context.colors.text.primary
        : context.colors.text.muted;
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active || completed
                ? context.colors.background.raised
                : context.colors.background.base,
          ),
          child: completed
              ? AppIcon(AppIcons.check, size: 14, color: color)
              : Text(
                  '${index + 1}',
                  style: AppTypography.labelMedium.copyWith(color: color),
                ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Text(label, style: AppTypography.labelLarge.copyWith(color: color)),
      ],
    );
    if (onTap == null) return content;
    return PaymentLinkAction(
      onPressed: onTap,
      selected: active,
      builder: (context, hovered, focused) => _ActionFocusRing(
        focused: focused,
        borderRadius: AppRadii.small,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          opacity: hovered ? 0.72 : 1,
          child: content,
        ),
      ),
    );
  }
}

class _HelpStep extends StatelessWidget {
  const _HelpStep({required this.icon, required this.text});

  final String icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          key: ValueKey('payment_link_help_icon_slot_$icon'),
          width: 32,
          height: 24,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xxs),
            child: Align(
              alignment: Alignment.topCenter,
              child: AppIcon(
                icon,
                size: AppIconSize.medium,
                color: context.colors.icon.accent,
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.xxs),
        Expanded(
          child: Text(
            text,
            style: AppTypography.bodyMedium.copyWith(
              color: context.colors.text.accent,
            ),
          ),
        ),
      ],
    );
  }
}

class _PasteButton extends StatelessWidget {
  const _PasteButton({required this.label, this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return AppButton(
      onPressed: onPressed,
      size: AppButtonSize.mediumLarge,
      leading: const AppIcon(AppIcons.paste),
      child: Text(label),
    );
  }
}

class _DashedDropZone extends StatelessWidget {
  const _DashedDropZone({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedBorderPainter(
        color: context.colors.border.medium,
        radius: AppRadii.xLarge,
      ),
      child: SizedBox(width: 323, height: 203, child: Center(child: child)),
    );
  }
}

class _DashedStatusPill extends StatelessWidget {
  const _DashedStatusPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      enabled: false,
      child: CustomPaint(
        painter: _DashedBorderPainter(
          color: context.colors.border.medium,
          radius: AppRadii.full,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 185, minHeight: 36),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIcon(
                  AppIcons.link,
                  size: 16,
                  color: context.colors.icon.muted,
                ),
                const SizedBox(width: AppSpacing.xxs),
                Text(
                  label,
                  style: AppTypography.bodyMedium.copyWith(
                    color: context.colors.text.secondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
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
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}

class _PaymentLinkLoadingCard extends StatefulWidget {
  const _PaymentLinkLoadingCard();

  @override
  State<_PaymentLinkLoadingCard> createState() =>
      _PaymentLinkLoadingCardState();
}

class _PaymentLinkLoadingCardState extends State<_PaymentLinkLoadingCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _motionEnabled = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shouldAnimate =
        !(MediaQuery.maybeOf(context)?.disableAnimations ?? false) &&
        TickerMode.valuesOf(context).enabled;
    if (shouldAnimate == _motionEnabled) return;
    _motionEnabled = shouldAnimate;
    if (shouldAnimate) {
      _controller.repeat();
    } else {
      _controller
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const cardRadius = BorderRadius.all(Radius.circular(AppRadii.large));
    final card = Container(
      key: const ValueKey('payment_link_loading_card'),
      width: 320,
      height: 200,
      decoration: BoxDecoration(
        color: context.colors.background.ground,
        borderRadius: cardRadius,
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            key: ValueKey('payment_link_loading_card_gradient'),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0x0D141818),
                  Color(0x594D5252),
                  Color(0x0D141818),
                ],
                stops: [0, 0.5, 1],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(
                    height: 16,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: PaymentLinkSkeletonBar(
                        key: ValueKey('payment_link_loading_label'),
                        width: 60,
                        height: 12,
                        shimmerKey: ValueKey(
                          'payment_link_loading_label_shimmer',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s),
                  const SizedBox(
                    height: 46,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: PaymentLinkSkeletonBar(
                        key: ValueKey('payment_link_loading_amount'),
                        width: 130,
                        height: 31,
                        shimmerKey: ValueKey(
                          'payment_link_loading_amount_shimmer',
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    return Semantics(
      label: 'Loading gift card',
      container: true,
      child: RepaintBoundary(
        child: ClipRRect(
          borderRadius: cardRadius,
          child: Stack(
            children: [
              card,
              if (_motionEnabled)
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedBuilder(
                      animation: _controller,
                      child: Transform.rotate(
                        angle: -0.18,
                        child: const SizedBox(
                          width: 76,
                          height: 320,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Color(0x00FFFFFF),
                                  Color(0x20FFFFFF),
                                  Color(0x00FFFFFF),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      builder: (context, child) {
                        return Transform.translate(
                          key: const ValueKey('payment_link_loading_shimmer'),
                          offset: Offset(-110 + (590 * _controller.value), 0),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: child,
                          ),
                        );
                      },
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

class _TabAction extends StatelessWidget {
  const _TabAction({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? context.colors.text.primary
        : context.colors.text.muted;
    return PaymentLinkAction(
      onPressed: onTap,
      selected: selected,
      role: SemanticsRole.tab,
      builder: (context, hovered, focused) => _ActionFocusRing(
        focused: focused,
        borderRadius: AppRadii.small,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          opacity: hovered ? 0.72 : 1,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIcon(icon, size: 16, color: color),
                const SizedBox(width: AppSpacing.xxs),
                Text(
                  label,
                  style: AppTypography.labelLarge.copyWith(color: color),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TextAction extends StatelessWidget {
  const _TextAction({
    required this.label,
    this.onTap,
    this.leading,
    this.trailing,
    this.enabled = true,
  });

  final String label;
  final VoidCallback? onTap;
  final Widget? leading;
  final Widget? trailing;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final active = enabled && onTap != null;
    final color = active
        ? context.colors.text.secondary
        : context.colors.text.muted;
    return PaymentLinkAction(
      onPressed: active ? onTap : null,
      builder: (context, hovered, focused) => _ActionFocusRing(
        key: ValueKey('payment_link_text_action_focus_ring_$label'),
        focused: focused,
        borderRadius: AppRadii.small,
        child: AnimatedOpacity(
          key: ValueKey('payment_link_text_action_hover_$label'),
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          opacity: hovered ? 0.72 : 1,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xxs,
              vertical: AppSpacing.xxs,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (leading != null) ...[
                  IconTheme(
                    data: IconThemeData(color: color, size: 16),
                    child: leading!,
                  ),
                  const SizedBox(width: AppSpacing.xxs),
                ],
                Text(
                  label,
                  style: AppTypography.bodyMedium.copyWith(color: color),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: AppSpacing.xxs),
                  trailing!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionFocusRing extends StatelessWidget {
  const _ActionFocusRing({
    required this.focused,
    required this.borderRadius,
    required this.child,
    super.key,
  });

  final bool focused;
  final double borderRadius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        border: focused
            ? Border.all(
                color: context.colors.state.focusRing,
                width: 2,
                strokeAlign: BorderSide.strokeAlignOutside,
              )
            : null,
      ),
      child: child,
    );
  }
}
