import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/formatting/zec_amount.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/comma_to_dot_input_formatter.dart';
import '../../../core/widgets/decimal_amount_input_formatter.dart';
import '../services/payment_link_service.dart';
import 'payment_link_action.dart';
import 'payment_link_batch_cost_summary.dart';
import 'payment_link_batch_deck.dart';
import 'payment_link_batch_inputs.dart';
import 'payment_link_card_selector_rail.dart';
import 'payment_link_gift_card.dart';
import 'payment_link_wizard_chrome.dart';

/// The desktop-only path for creating several cards from one funding action.
class PaymentLinkBulkDesktopFlow extends StatelessWidget {
  const PaymentLinkBulkDesktopFlow({
    required this.count,
    required this.maxCount,
    required this.amountController,
    required this.messageController,
    required this.artwork,
    required this.spendable,
    required this.quote,
    required this.preparing,
    required this.reviewing,
    required this.submitting,
    required this.retrySaving,
    required this.error,
    required this.onCountChanged,
    required this.onAmountChanged,
    required this.onMessageChanged,
    required this.onArtworkChanged,
    required this.onReview,
    required this.onEdit,
    required this.onCreate,
    required this.onBack,
    this.onRetry,
    this.waitingForSync = false,
    this.mixedArtworks,
    this.onMixChanged,
    super.key,
  });

  final int count;
  final int maxCount;
  final TextEditingController amountController;
  final TextEditingController messageController;
  final PaymentLinkCardArtwork artwork;

  /// The design of each card, in order, when the group mixes designs; null
  /// when every card takes [artwork].
  final List<PaymentLinkCardArtwork>? mixedArtworks;
  final ValueChanged<bool>? onMixChanged;
  final BigInt? spendable;
  final PaymentLinkBatchQuote? quote;
  final bool preparing;
  final bool reviewing;
  final bool submitting;
  final bool retrySaving;
  final String? error;
  final ValueChanged<int> onCountChanged;
  final ValueChanged<String> onAmountChanged;
  final ValueChanged<String> onMessageChanged;
  final ValueChanged<PaymentLinkCardArtwork> onArtworkChanged;
  final VoidCallback? onReview;

  /// Null once something was sent: the group can no longer be edited.
  final VoidCallback? onEdit;
  final VoidCallback? onCreate;
  final VoidCallback onBack;
  final VoidCallback? onRetry;

  /// The fee waits for wallet sync; shown as pending rather than an error.
  final bool waitingForSync;

  @override
  Widget build(BuildContext context) {
    return PaymentLinkPane(
      backLabel: reviewing && onEdit != null ? 'Edit cards' : 'Gift Cards',
      onBack: reviewing ? onEdit ?? onBack : onBack,
      actions: _primaryAction(context),
      // Top-anchored at a fixed start, never centred: content can grow
      // downward while typing, but nothing above it moves.
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 840),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(context),
                const SizedBox(height: AppSpacing.md),
                AnimatedSwitcher(
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 180),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeOut,
                  layoutBuilder: (current, previous) => Stack(
                    alignment: Alignment.topCenter,
                    children: [
                      for (final child in previous) IgnorePointer(child: child),
                      ?current,
                    ],
                  ),
                  child: KeyedSubtree(
                    key: ValueKey(reviewing),
                    child: reviewing
                        ? _review(context)
                        // The same content offset as the one-card wizard.
                        : Padding(
                            padding: const EdgeInsets.only(top: AppSpacing.lg),
                            child: _configure(context),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Centred in the same display style as the other Gift Cards pages.
  Widget _header(BuildContext context) => Text(
    reviewing ? 'Review $count cards' : 'Create cards for a group',
    textAlign: TextAlign.center,
    style: AppTypography.headlineLarge.copyWith(
      color: context.colors.text.accent,
    ),
  );

  Widget _configure(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final side = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _fields(context),
          const SizedBox(height: AppSpacing.md),
          _costSummary(),
        ],
      );
      if (constraints.maxWidth < 700 || paymentLinkUsesLargeText(context)) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _cardStage(context),
            const SizedBox(height: AppSpacing.md),
            side,
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _cardStage(context)),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: side),
        ],
      );
    },
  );

  /// One column, like the one-card review: the deck, then what it costs.
  Widget _review(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: _deck(maxWidth: 320)),
          const SizedBox(height: AppSpacing.sm),
          _costSummary(),
        ],
      ),
    ),
  );

  Widget _primaryAction(BuildContext context) {
    final String label;
    if (submitting) {
      label = retrySaving ? 'Saving…' : 'Creating…';
    } else if (retrySaving) {
      label = 'Try saving again';
    } else {
      label = reviewing ? 'Create $count cards' : 'Review $count cards';
    }
    final onPressed = reviewing ? onCreate : onReview;
    return AppButton(
      key: const ValueKey('payment_link_bulk_primary_button'),
      onPressed: onPressed,
      minWidth: 196,
      size: AppButtonSize.large,
      growWithContent: paymentLinkUsesLargeText(context),
      leading: reviewing && !submitting
          ? const Center(
              child: AppIcon(AppIcons.giftCard, size: AppIconSize.medium),
            )
          : null,
      trailing: !reviewing && onPressed != null
          ? const AppIcon(AppIcons.chevronForward)
          : null,
      child: Text(label),
    );
  }

  TextStyle _labelStyle(BuildContext context) =>
      AppTypography.labelLarge.copyWith(color: context.colors.text.secondary);

  /// The amount, with the balance it draws from, and an optional message.
  Widget _fields(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTextField(
          key: const ValueKey('payment_link_bulk_amount'),
          label: 'Amount per card',
          labelStyle: _labelStyle(context),
          rightSlot: _available(context),
          controller: amountController,
          hintText: '0.00',
          leading: AppIcon(
            AppIcons.zcash,
            size: 20,
            color: colors.icon.regular,
          ),
          inlineSuffixText: 'ZEC',
          inlineSuffixStyle: AppTypography.labelLarge.copyWith(
            color: colors.text.secondary,
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            CommaToDotInputFormatter(),
            DecimalAmountInputFormatter(maxFractionDigits: 8),
          ],
          onChanged: onAmountChanged,
        ),
        const SizedBox(height: AppSpacing.sm),
        PaymentLinkBatchMessageField(
          controller: messageController,
          labelStyle: _labelStyle(context),
          onChanged: onMessageChanged,
        ),
      ],
    );
  }

  Widget _available(BuildContext context) {
    final colors = context.colors;
    return Row(
      key: const ValueKey('payment_link_bulk_available'),
      mainAxisSize: MainAxisSize.min,
      children: [
        AppIcon(AppIcons.wallet, size: 16, color: colors.icon.regular),
        const SizedBox(width: AppSpacing.xxs),
        Semantics(
          label: spendable == null
              ? 'Balance loading'
              : '${formatZecAmount(spendable!)} ZEC available',
          child: ExcludeSemantics(
            child: Text(
              spendable == null ? '…' : '${formatZecAmount(spendable!)} ZEC',
              style: _labelStyle(
                context,
              ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ),
        ),
      ],
    );
  }

  /// The deck is the preview and the quantity: its controls sit right under
  /// it, followed by the design choice that applies to every card.
  Widget _cardStage(BuildContext context) => Column(
    children: [
      Center(
        child: SizedBox(
          key: const ValueKey('payment_link_bulk_preview'),
          child: _deck(maxWidth: 320),
        ),
      ),
      const SizedBox(height: AppSpacing.sm),
      Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AppSpacing.s,
        runSpacing: AppSpacing.xs,
        children: [
          PaymentLinkBatchCountStepper(
            count: count,
            maxCount: maxCount,
            onChanged: onCountChanged,
          ),
          Wrap(
            spacing: AppSpacing.xxs,
            runSpacing: AppSpacing.xxs,
            children: [
              for (final preset in {10, 20, maxCount})
                if (preset <= maxCount) _countPreset(preset),
            ],
          ),
        ],
      ),
      const SizedBox(height: AppSpacing.sm),
      Semantics(
        container: true,
        label: 'Card design',
        child: LayoutBuilder(
          builder: (context, constraints) => Center(
            child: PaymentLinkCardSelectorRail(
              loop: true,
              inactiveOpacity: 1,
              artworks: PaymentLinkCardArtwork.values,
              // No single design is chosen while the cards differ.
              selected: mixedArtworks == null ? artwork : null,
              onSelected: onArtworkChanged,
              width: math.min(
                PaymentLinkCardSelectorRail.defaultWidth,
                constraints.maxWidth,
              ),
            ),
          ),
        ),
      ),
      if (onMixChanged case final onMix?) ...[
        const SizedBox(height: AppSpacing.xs),
        Center(
          child: _MixDesignsCheckbox(
            checked: mixedArtworks != null,
            onChanged: onMix,
          ),
        ),
      ],
    ],
  );

  Widget _costSummary() => PaymentLinkBatchCostSummary(
    count: count,
    amountText: amountController.text,
    messageText: messageController.text,
    spendable: spendable,
    quote: quote,
    preparing: preparing,
    waitingForSync: waitingForSync,
    reviewing: reviewing,
    error: error,
    onRetry: onRetry,
  );

  Widget _deck({required double maxWidth}) {
    final width = math.min(maxWidth, PaymentLinkBatchDeck.width);
    return SizedBox(
      width: width,
      height: width * PaymentLinkBatchDeck.height / PaymentLinkBatchDeck.width,
      child: PaymentLinkBatchDeck(
        backArtworks: [...?mixedArtworks?.skip(1).take(count - 1)],
        card: PaymentLinkGiftCard(
          artwork: mixedArtworks?.first ?? artwork,
          amountText: amountController.text.isEmpty
              ? '0'
              : amountController.text,
          showCaret: false,
        ),
        count: count,
        playReveal: false,
        animateCount: true,
      ),
    );
  }

  Widget _countPreset(int value) => Semantics(
    selected: count == value,
    child: AppButton(
      key: ValueKey('payment_link_bulk_preset_$value'),
      onPressed: () => onCountChanged(value),
      variant: count == value
          ? AppButtonVariant.secondary
          : AppButtonVariant.ghost,
      size: AppButtonSize.medium,
      child: Text('$value', semanticsLabel: '$value cards'),
    ),
  );
}

/// Says in words what mixing does, rather than leaving it to a picture.
class _MixDesignsCheckbox extends StatelessWidget {
  const _MixDesignsCheckbox({required this.checked, required this.onChanged});

  final bool checked;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return PaymentLinkAction(
      key: const ValueKey('payment_link_bulk_mix'),
      button: false,
      checked: checked,
      semanticLabel: 'Different design on each card',
      onPressed: () => onChanged(!checked),
      builder: (context, hovered, focused) => PaymentLinkActionFocusRing(
        focused: focused,
        borderRadius: AppRadii.small,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xxs,
            vertical: AppSpacing.xxs,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                curve: Curves.easeOut,
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: checked
                      ? colors.background.inverse
                      : colors.background.inverse.withValues(alpha: 0),
                  border: Border.all(
                    color: checked || hovered
                        ? colors.border.strong
                        : colors.border.regular,
                    width: 1.5,
                  ),
                  borderRadius: BorderRadius.circular(AppRadii.xSmall),
                ),
                child: checked
                    ? AppIcon(
                        AppIcons.check,
                        size: 12,
                        color: colors.icon.inverse,
                      )
                    : null,
              ),
              const SizedBox(width: AppSpacing.xs),
              Flexible(
                child: Text(
                  'Different design on each card',
                  style: AppTypography.bodyMedium.copyWith(
                    color: colors.text.primary,
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
