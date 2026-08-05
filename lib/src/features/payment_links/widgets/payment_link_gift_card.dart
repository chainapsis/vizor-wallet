import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';
import 'payment_link_action.dart';

/// Artwork choices exported from the Figma `_CARD BG IMAGE` component set.
enum PaymentLinkCardArtwork {
  knight('payment_link_card_knight.png', 'Knight'),
  chestLava('payment_link_card_chest_lava.png', 'Chest in lava cave'),
  chestCave('payment_link_card_chest_cave.png', 'Chest in crystal cave'),
  dragon('payment_link_card_dragon.png', 'Dragon'),
  knightMagic('payment_link_card_knight_magic.png', 'Magic knight'),
  gandalf('payment_link_card_gandalf.png', 'Wizard'),
  crystal('payment_link_card_crystal.png', 'Crystal'),
  diamond('payment_link_card_diamond.png', 'Diamond'),
  ruby('payment_link_card_ruby.png', 'Ruby'),
  coin('payment_link_card_coin.png', 'Zcash coin'),
  gift('payment_link_card_gift.png', 'Gift box');

  const PaymentLinkCardArtwork(this.fileName, this.semanticLabel);

  final String fileName;
  final String semanticLabel;

  String get assetPath => 'assets/illustrations/payment_links/$fileName';
}

/// Figma `_CARD` presentation component.
///
/// [amountText] selects the front state: null renders the default prompt,
/// an empty string renders the active caret state, and a non-empty string
/// renders the value state. [showBack] switches to the message side.
/// Input ownership remains with the parent; this widget only renders immutable
/// display values and forwards taps.
class PaymentLinkGiftCard extends StatelessWidget {
  const PaymentLinkGiftCard({
    required this.artwork,
    this.amountText,
    this.maxAmountText,
    this.supportingText,
    this.supportingLoading = false,
    this.currencySymbol = 'ZEC',
    this.emptyAmountLabel = 'Enter amount',
    this.showCaret = true,
    this.showBack = false,
    this.message = '',
    this.emptyMessageLabel = 'Start typing...',
    this.maxMessageLength = 128,
    this.messageCharacterCount,
    this.onTap,
    this.onDeleteMessage,
    this.semanticLabel,
    super.key,
  }) : assert(maxMessageLength > 0),
       assert(
         messageCharacterCount == null ||
             (messageCharacterCount >= 0 &&
                 messageCharacterCount <= maxMessageLength),
       );

  static const double width = 372;
  static const double height = 253;

  final PaymentLinkCardArtwork artwork;

  /// Null is the default state; empty is active; non-empty is the value state.
  final String? amountText;
  final String? maxAmountText;
  final String? supportingText;
  final bool supportingLoading;
  final String currencySymbol;
  final String emptyAmountLabel;
  final bool showCaret;

  final bool showBack;
  final String message;
  final String emptyMessageLabel;
  final int maxMessageLength;
  final int? messageCharacterCount;

  final VoidCallback? onTap;
  final VoidCallback? onDeleteMessage;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final card = SizedBox(
      width: width,
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.xLarge),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (showBack)
              const _PaymentLinkGiftCardBackBackground()
            else
              _PaymentLinkGiftCardFrontBackground(artwork: artwork),
            if (showBack)
              _PaymentLinkGiftCardBackContent(
                message: message,
                emptyMessageLabel: emptyMessageLabel,
                maxMessageLength: maxMessageLength,
                messageCharacterCount: messageCharacterCount,
                onDeleteMessage: onDeleteMessage,
              )
            else
              _PaymentLinkGiftCardFrontContent(
                amountText: amountText,
                maxAmountText: maxAmountText,
                supportingText: supportingText,
                supportingLoading: supportingLoading,
                currencySymbol: currencySymbol,
                emptyAmountLabel: emptyAmountLabel,
                showCaret: showCaret,
              ),
            const _PaymentLinkGiftCardBorder(),
          ],
        ),
      ),
    );

    final label =
        semanticLabel ??
        (showBack
            ? 'Gift card message'
            : 'Gift card, ${artwork.semanticLabel} design');
    if (onTap == null) {
      return Semantics(image: true, label: label, child: card);
    }
    return PaymentLinkAction(
      onPressed: onTap,
      semanticLabel: label,
      excludeChildSemantics: onDeleteMessage == null,
      builder: (context, _, focused) => Stack(
        clipBehavior: Clip.none,
        children: [
          card,
          if (focused)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadii.xLarge),
                    border: Border.all(
                      color: context.colors.state.focusRing,
                      width: 2,
                      strokeAlign: BorderSide.strokeAlignOutside,
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

class _PaymentLinkGiftCardFrontBackground extends StatelessWidget {
  const _PaymentLinkGiftCardFrontBackground({required this.artwork});

  final PaymentLinkCardArtwork artwork;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          artwork.assetPath,
          fit: BoxFit.cover,
          semanticLabel: artwork.semanticLabel,
        ),
        const DecoratedBox(
          key: ValueKey('payment_link_card_artwork_fade'),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(0, -0.05),
              end: Alignment.bottomCenter,
              colors: [Color(0x00000000), Color(0xB3000000)],
              stops: [0.48024, 0.73518],
            ),
          ),
        ),
      ],
    );
  }
}

class _PaymentLinkGiftCardFrontContent extends StatelessWidget {
  const _PaymentLinkGiftCardFrontContent({
    required this.amountText,
    required this.maxAmountText,
    required this.supportingText,
    required this.supportingLoading,
    required this.currencySymbol,
    required this.emptyAmountLabel,
    required this.showCaret,
  });

  final String? amountText;
  final String? maxAmountText;
  final String? supportingText;
  final bool supportingLoading;
  final String currencySymbol;
  final String emptyAmountLabel;
  final bool showCaret;

  @override
  Widget build(BuildContext context) {
    final cardTextColor = context.colors.text.homeCard;
    final amount = amountText;
    if (amount == null) {
      return Positioned(
        left: AppSpacing.md,
        right: AppSpacing.md,
        bottom: AppSpacing.md,
        child: Text(
          emptyAmountLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.displayLarge.copyWith(
            color: cardTextColor.withValues(alpha: 0.55),
          ),
        ),
      );
    }

    return Positioned(
      left: AppSpacing.md,
      right: AppSpacing.md,
      bottom: AppSpacing.md,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (supportingLoading) ...[
            Semantics(
              label: 'Fiat value loading',
              child: ExcludeSemantics(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      r'$',
                      style: AppTypography.labelLarge.copyWith(
                        color: cardTextColor,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Container(
                      key: const ValueKey(
                        'payment_link_fiat_loading_placeholder',
                      ),
                      width: 48,
                      height: 12,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(AppRadii.full),
                        gradient: LinearGradient(
                          colors: [
                            cardTextColor,
                            cardTextColor.withValues(alpha: 0.15),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.s),
          ] else if (supportingText ??
                  (maxAmountText == null ? null : 'Use max: $maxAmountText')
              case final supporting?) ...[
            Text(
              supporting,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.labelLarge.copyWith(color: cardTextColor),
            ),
            const SizedBox(height: AppSpacing.s),
          ],
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (amount.isNotEmpty) ...[
                Flexible(
                  child: Text(
                    amount,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.displayLarge.copyWith(
                      color: cardTextColor,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.s),
              ],
              if (showCaret) ...[
                Container(
                  width: 3,
                  height: 48,
                  decoration: BoxDecoration(
                    color: cardTextColor,
                    borderRadius: BorderRadius.circular(AppRadii.full),
                  ),
                ),
                if (currencySymbol.isNotEmpty)
                  const SizedBox(width: AppSpacing.s),
              ],
              if (currencySymbol.isNotEmpty)
                Text(
                  currencySymbol,
                  maxLines: 1,
                  style: AppTypography.displayLarge.copyWith(
                    color: cardTextColor.withValues(alpha: 0.65),
                    fontSize: 40,
                    height: 48 / 40,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PaymentLinkGiftCardBackBackground extends StatelessWidget {
  const _PaymentLinkGiftCardBackBackground();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(color: context.colors.background.brandCrimsonStrong);
  }
}

class _PaymentLinkGiftCardBackContent extends StatelessWidget {
  const _PaymentLinkGiftCardBackContent({
    required this.message,
    required this.emptyMessageLabel,
    required this.maxMessageLength,
    required this.messageCharacterCount,
    required this.onDeleteMessage,
  });

  final String message;
  final String emptyMessageLabel;
  final int maxMessageLength;
  final int? messageCharacterCount;
  final VoidCallback? onDeleteMessage;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final cardTextColor = colors.text.homeCard;
    final characterCount =
        messageCharacterCount ??
        message.runes.length.clamp(0, maxMessageLength);

    return Stack(
      children: [
        Positioned(
          left: 56,
          right: 56,
          top: 46.5,
          height: 160,
          child: Center(
            child: Text(
              message.isEmpty ? emptyMessageLabel : message,
              textAlign: TextAlign.center,
              maxLines: 7,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.bodyMedium.copyWith(color: cardTextColor),
            ),
          ),
        ),
        Positioned(
          left: 20,
          bottom: 20,
          child: Text(
            '$characterCount/$maxMessageLength',
            style: AppTypography.labelLarge.copyWith(
              color: cardTextColor.withValues(alpha: 0.5),
            ),
          ),
        ),
        if (onDeleteMessage != null)
          Positioned(
            right: AppSpacing.s,
            bottom: AppSpacing.s,
            child: PaymentLinkAction(
              onPressed: onDeleteMessage,
              semanticLabel: 'Delete gift card message',
              builder: (context, _, focused) => SizedBox(
                width: 36,
                height: 36,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: colors.background.homeCard,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: AppIcon(
                            AppIcons.trash,
                            size: AppIconSize.medium,
                            color: cardTextColor,
                          ),
                        ),
                      ),
                    ),
                    if (focused)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: colors.state.focusRing,
                                width: 2,
                                strokeAlign: BorderSide.strokeAlignOutside,
                              ),
                            ),
                          ),
                        ),
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

class _PaymentLinkGiftCardBorder extends StatelessWidget {
  const _PaymentLinkGiftCardBorder();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadii.xLarge),
          border: Border.all(
            color: context.colors.text.homeCard.withValues(alpha: 0.55),
            width: 2.5,
          ),
        ),
      ),
    );
  }
}
