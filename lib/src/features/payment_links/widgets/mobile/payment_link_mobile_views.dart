import 'package:flutter/widgets.dart';

import '../../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/app_tooltip.dart';

const _referenceContentHeight = 773.0;
const _topInset = 12.0;
const _navHeight = 74.0;
const _sideInset = 16.0;
const _subtitleTop = 102.0;
const _cardTop = 207.0;
const _cardWidth = 361.0;
const _cardHeight = 225.625;
const _selectorTop = _cardTop + _cardHeight + AppSpacing.md;
const _selectorHeight = 80.0;
const _bottomInset = 12.0;
const _buttonHeight = 50.0;

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
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            top: 207,
            left: _sideInset,
            right: _sideInset,
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
                AppButton(
                  key: const ValueKey('payment_links_mobile_help_action'),
                  onPressed: onShowHelp,
                  variant: AppButtonVariant.ghost,
                  size: AppButtonSize.mediumLarge,
                  height: 36,
                  constrainContent: true,
                  trailing: AppIcon(
                    AppIcons.help,
                    size: 16,
                    color: context.colors.icon.regular,
                  ),
                  child: Text(
                    helpLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: _sideInset,
            right: _sideInset,
            bottom: 0,
            child: Column(
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
          ),
        ],
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
    this.title = 'Review Gift Card',
    this.subtitle = 'Review amount and fees.',
    this.continueLabel = 'Create card',
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
                    emphasized: true,
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
    this.emphasized = false,
  });

  final String label;
  final String value;
  final VoidCallback? onHelp;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final labelStyle = emphasized
        ? AppTypography.bodyMediumStrong
        : AppTypography.bodyMedium;
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
          size: 16,
          color: context.colors.icon.muted,
        ),
      ),
    );

    return SizedBox(
      height: 32,
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    label,
                    style: labelStyle.copyWith(
                      color: context.colors.text.secondary,
                    ),
                  ),
                ),
                if (label.startsWith('Card fee')) ...[
                  const SizedBox(width: AppSpacing.xxs),
                  Listener(
                    key: const ValueKey('payment_link_mobile_fee_help'),
                    onPointerUp: onHelp == null ? null : (_) => onHelp!(),
                    child: help,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            value,
            key: ValueKey('payment_link_mobile_review_value_$label'),
            textAlign: TextAlign.right,
            style: AppTypography.bodyMediumStrong.copyWith(
              color: context.colors.text.primary,
            ),
          ),
        ],
      ),
    );
  }
}
