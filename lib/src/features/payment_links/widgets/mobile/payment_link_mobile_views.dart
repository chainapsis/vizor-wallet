import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/app_tooltip.dart';
import '../../../../core/widgets/mobile/mobile_surface_card.dart';
import '../payment_link_action.dart';
import '../payment_link_card_motion.dart';
import '../payment_link_cards_layout.dart';
import '../payment_link_copy.dart';
import '../payment_link_dashed_border_painter.dart';
import '../payment_link_skeleton.dart';

export '../payment_link_cards_layout.dart'
    show PaymentLinkCardsSection, PaymentLinkCardsTab;

const _referenceContentHeight = 773.0;
// The top nav sits where every other pushed mobile page puts it: flush with
// the safe area, at the shared height. The absolute tops below are the Figma
// frame values shifted up by the 14px that difference used to add.
const _topInset = 0.0;
const _navHeight = kMobileTopNavHeight;
const _sideInset = 16.0;
const _subtitleTop = 88.0;
const _cardTop = 193.0;
const _redeemSurfaceTop = 218.0;
const _redeemCheckingCardWidth = 320.0;
const _redeemCheckingCardHeight = 200.0;
const kPaymentLinkMobileReceivedCardTop = 221.0;
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
    this.title = kPaymentLinkHowItWorksTitle,
    this.subtitle = kPaymentLinkHowItWorksSubtitle,
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
                'Once funding reaches the network, copy the unique link and '
                'send it only to the intended recipient.',
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
    this.title = kPaymentLinkEmptyTitle,
    this.helpLabel = 'How the Gift Card works',
    this.createLabel = kPaymentLinkCreateCardLabel,
    this.redeemLabel = kPaymentLinkRedeemCardLabel,
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
                    AppIcons.giftCardOutline,
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

/// The mobile Gift Card list.
///
/// This is the mobile counterpart of `PaymentLinkCardsDesktopView`: the same
/// two tabs over the same created/received sections, so a funded Card link
/// stays reachable after the user leaves the Ready page and received Cards
/// are visible at all. The Create/Redeem footer keeps the geometry of
/// [PaymentLinksHomeMobileView] so the buttons do not move when the empty
/// home turns into the list.
///
/// Rows are mobile-shaped ([PaymentLinkCardListMobileRow]); the state machine
/// deciding which row is copyable lives in the screen, shared with desktop.
class PaymentLinkCardsMobileView extends StatelessWidget {
  const PaymentLinkCardsMobileView({
    required this.sections,
    required this.onBack,
    required this.onCreate,
    required this.onRedeem,
    this.activeTab = PaymentLinkCardsTab.created,
    this.onTabSelected,
    this.emptyLabel,
    this.screenTitle = 'Gift Cards',
    this.createLabel = kPaymentLinkCreateCardLabel,
    this.redeemLabel = kPaymentLinkRedeemCardLabel,
    super.key,
  });

  final List<PaymentLinkCardsSection> sections;
  final VoidCallback onBack;
  final VoidCallback onCreate;
  final VoidCallback onRedeem;
  final PaymentLinkCardsTab activeTab;
  final ValueChanged<PaymentLinkCardsTab>? onTabSelected;

  /// Shown centered when the selected tab has no rows.
  final String? emptyLabel;
  final String screenTitle;
  final String createLabel;
  final String redeemLabel;

  @override
  Widget build(BuildContext context) {
    final hasCards = sections.any((section) => section.cards.isNotEmpty);
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
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: AppSpacing.s),
            Semantics(
              role: SemanticsRole.tabBar,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _MobileCardsTab(
                    key: const ValueKey('payment_links_mobile_created_tab'),
                    icon: AppIcons.plane,
                    label: kPaymentLinkCreatedTabLabel,
                    selected: activeTab == PaymentLinkCardsTab.created,
                    onTap: onTabSelected == null
                        ? null
                        : () => onTabSelected!(PaymentLinkCardsTab.created),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  _MobileCardsTab(
                    key: const ValueKey('payment_links_mobile_received_tab'),
                    icon: AppIcons.arrowDownward,
                    label: kPaymentLinkReceivedTabLabel,
                    selected: activeTab == PaymentLinkCardsTab.received,
                    onTap: onTabSelected == null
                        ? null
                        : () => onTabSelected!(PaymentLinkCardsTab.received),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.base),
            Expanded(
              child: hasCards
                  ? ListView(
                      key: const ValueKey('payment_links_mobile_cards_list'),
                      padding: const EdgeInsets.only(bottom: AppSpacing.base),
                      children: [
                        for (final (index, section) in sections.indexed)
                          if (section.cards.isNotEmpty) ...[
                            if (index > 0)
                              const SizedBox(height: AppSpacing.sm),
                            Text(
                              section.label,
                              style: AppTypography.bodyMedium.copyWith(
                                color: context.colors.text.secondary,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xxs),
                            MobileSurfaceCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  for (final (rowIndex, card)
                                      in section.cards.indexed) ...[
                                    if (rowIndex > 0)
                                      const SizedBox(height: AppSpacing.xxs),
                                    card,
                                  ],
                                ],
                              ),
                            ),
                          ],
                      ],
                    )
                  : Center(
                      child: Text(
                        emptyLabel ?? kPaymentLinkNoReceivedCardsText,
                        key: const ValueKey(
                          'payment_links_mobile_cards_empty_label',
                        ),
                        textAlign: TextAlign.center,
                        style: AppTypography.bodyMedium.copyWith(
                          color: context.colors.text.secondary,
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: AppSpacing.base),
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
                AppIcons.giftCardOutline,
                size: AppIconSize.medium,
              ),
              child: Text(createLabel),
            ),
          ],
        ),
      ),
    );
  }
}

/// One Gift Card row on the mobile list.
///
/// Same information as the desktop `PaymentLinkCardListRow` — artwork,
/// amount, date, and either a status or the copy-link action — on the mobile
/// 64px row pitch with a touch-sized copy target. The mobile list has no QR
/// page, so the link actions collapse to copy alone.
class PaymentLinkCardListMobileRow extends StatelessWidget {
  const PaymentLinkCardListMobileRow({
    required this.thumbnail,
    required this.amountText,
    required this.dateText,
    this.statusText,
    this.onAction,
    this.showLoader = false,
    this.showCopyAction = false,
    this.onCopyLink,
    super.key,
  }) : assert(
         statusText != null || showCopyAction,
         'A status or the Gift Card copy action must be provided.',
       );

  final Widget thumbnail;
  final String amountText;
  final String dateText;
  final String? statusText;
  final VoidCallback? onAction;
  final bool showLoader;
  final bool showCopyAction;
  final VoidCallback? onCopyLink;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      height: 64,
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
                    color: colors.text.primary,
                  ),
                ),
                Text(
                  dateText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodyMedium.copyWith(
                    color: colors.text.secondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          if (showCopyAction)
            PaymentLinkAction(
              key: const ValueKey('payment_link_mobile_card_copy_action'),
              semanticLabel: kPaymentLinkCopyLinkSemanticLabel,
              onPressed: onCopyLink,
              builder: (context, _, focused) => DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadii.xSmall),
                  border: focused
                      ? Border.all(color: colors.state.focusRing, width: 2)
                      : null,
                ),
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: Center(
                    child: AppIcon(
                      AppIcons.copy,
                      size: AppIconSize.medium,
                      color: onCopyLink == null
                          ? colors.icon.disabled
                          : colors.icon.regular,
                    ),
                  ),
                ),
              ),
            )
          else if (statusText case final label?)
            _MobileCardStatus(
              label: label,
              onTap: onAction,
              showLoader: showLoader,
            ),
        ],
      ),
    );
  }
}

class _MobileCardStatus extends StatelessWidget {
  const _MobileCardStatus({
    required this.label,
    required this.showLoader,
    this.onTap,
  });

  final String label;
  final bool showLoader;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = onTap == null ? colors.text.muted : colors.text.secondary;
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          key: ValueKey('payment_link_mobile_card_status_$label'),
          style: AppTypography.bodyMedium.copyWith(color: color),
        ),
        if (showLoader) ...[
          const SizedBox(width: AppSpacing.xxs),
          AppIcon(AppIcons.loader, size: 16, color: colors.icon.regular),
        ],
      ],
    );
    if (onTap == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
        child: content,
      );
    }
    return PaymentLinkAction(
      onPressed: onTap,
      semanticLabel: label,
      builder: (context, _, focused) => DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadii.xSmall),
          border: focused
              ? Border.all(color: colors.state.focusRing, width: 2)
              : null,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xs,
            vertical: AppSpacing.xs,
          ),
          child: content,
        ),
      ),
    );
  }
}

class _MobileCardsTab extends StatelessWidget {
  const _MobileCardsTab({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
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
      semanticLabel: label,
      builder: (context, _, focused) => DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadii.small),
          border: focused
              ? Border.all(color: context.colors.state.focusRing, width: 2)
              : null,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xs,
            vertical: AppSpacing.xs,
          ),
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
    this.title = kPaymentLinkCreateGiftCardTitle,
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
                    label: kPaymentLinkCardFeeLabel,
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
                    label: kPaymentLinkTotalDeductedLabel,
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
    this.waitingStatusLabel = kPaymentLinkWaitingStatusLabel,
    this.waitingHeading = kPaymentLinkAlmostReadyHeading,
    this.waitingDescription =
        'The link becomes shareable when funding reaches the network.\n'
        'If Vizor cannot confirm that yet, one confirmation is enough.',
    this.waitingIcon,
    this.cardTop = 190,
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
  final String waitingHeading;
  final String waitingDescription;
  final String? waitingIcon;
  final double cardTop;
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
            semanticLabel: kPaymentLinkFlipCardSemanticLabel,
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
              ready ? kPaymentLinkReadyHeading : waitingHeading,
              textAlign: TextAlign.center,
              style: AppTypography.displayLarge.copyWith(
                color: context.colors.text.accent,
              ),
            ),
          ),
          Positioned(
            top: cardTop,
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
                          : waitingDescription,
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
                        icon:
                            waitingIcon ??
                            (state == PaymentLinkReadyMobileState.soon
                                ? AppIcons.link
                                : AppIcons.giftCard),
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
    this.title = kPaymentLinkRedeemTheCardTitle,
    this.subtitle = kPaymentLinkRedeemSubtitle,
    this.pasteLabel = kPaymentLinkPasteLabel,
    this.invalidTitle = kPaymentLinkInvalidTitle,
    this.invalidSubtitle = kPaymentLinkInvalidSubtitle,
    this.unavailableTitle = 'This card has no available balance.',
    this.unavailableSubtitle = kPaymentLinkUnavailableSubtitle,
    this.clearLabel = kPaymentLinkClearClipboardLabel,
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

    final cardContent = switch (state) {
      PaymentLinkRedeemMobileState.paste => _MobileRedeemDropZone(
        child: AppButton(
          key: const ValueKey('payment_link_mobile_paste_button'),
          onPressed: onPaste,
          size: AppButtonSize.mediumLarge,
          leading: const AppIcon(AppIcons.paste, size: 20),
          child: Text(pasteLabel),
        ),
      ),
      PaymentLinkRedeemMobileState.invalid ||
      PaymentLinkRedeemMobileState.unavailable => _MobileRedeemDropZone(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              invalid ? invalidTitle : unavailableTitle,
              textAlign: TextAlign.center,
              style: AppTypography.bodyMediumStrong.copyWith(
                color: context.colors.text.destructive,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              invalid ? invalidSubtitle : unavailableSubtitle,
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(
                color: context.colors.text.secondary,
              ),
            ),
            const SizedBox(height: AppSpacing.base),
            AppButton(
              key: const ValueKey('payment_link_mobile_paste_button'),
              onPressed: onPaste,
              size: AppButtonSize.mediumLarge,
              leading: const AppIcon(AppIcons.paste, size: 20),
              child: Text(pasteLabel),
            ),
          ],
        ),
      ),
      PaymentLinkRedeemMobileState.loading =>
        const _PaymentLinkLoadingMobileCard(),
    };

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
              style: AppTypography.bodyMedium.copyWith(
                color: context.colors.text.secondary,
              ),
            ),
          ),
          Positioned(
            top: _redeemSurfaceTop,
            left: _sideInset,
            right: _sideInset,
            child: Center(child: cardContent),
          ),
          if (loading)
            Positioned(
              top:
                  _redeemSurfaceTop + _redeemCheckingCardHeight + AppSpacing.md,
              left: 0,
              right: 0,
              child: Text(
                kPaymentLinkCheckingLabel,
                key: const ValueKey('payment_link_mobile_redeem_checking'),
                textAlign: TextAlign.center,
                style: AppTypography.bodyMediumStrong.copyWith(
                  color: context.colors.text.secondary,
                ),
              ),
            ),
          if (showError)
            Positioned(
              top: _redeemSurfaceTop + _cardHeight + AppSpacing.md,
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
    this.messageTitle = kPaymentLinkMessageAttachedTitle,
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
                    semanticsLabel: kPaymentLinkGiftMessageLabel,
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
            top: kPaymentLinkMobileReceivedCardTop,
            left: _sideInset,
            right: _sideInset,
            child: _MobileCardSlot(
              card: hasMessage && onRevealMessage != null
                  ? PaymentLinkAction(
                      onPressed: onRevealMessage,
                      semanticLabel: kPaymentLinkRevealMessageSemanticLabel,
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

class _PaymentLinkLoadingMobileCard extends StatelessWidget {
  const _PaymentLinkLoadingMobileCard();

  @override
  Widget build(BuildContext context) {
    final skeletonColor = context.colors.text.secondary;
    return Container(
      key: const ValueKey('payment_link_mobile_loading_card'),
      width: _redeemCheckingCardWidth,
      height: _redeemCheckingCardHeight,
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

class _MobileRedeemDropZone extends StatelessWidget {
  const _MobileRedeemDropZone({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      key: const ValueKey('payment_link_mobile_redeem_drop_zone'),
      painter: PaymentLinkDashedBorderPainter(
        color: context.colors.border.regular,
        radius: AppRadii.large,
        strokeWidth: 3,
      ),
      child: SizedBox(
        width: _cardWidth,
        height: _cardHeight,
        child: Center(child: child),
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
      painter: PaymentLinkDashedBorderPainter(
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
