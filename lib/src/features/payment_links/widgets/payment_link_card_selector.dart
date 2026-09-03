import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';
import 'payment_link_action.dart';
import 'payment_link_gift_card.dart';

/// Figma `Card Design Select` option (64×48, default/hover/selected).
class PaymentLinkCardSelector extends StatelessWidget {
  const PaymentLinkCardSelector({
    required this.artwork,
    required this.selected,
    required this.onSelected,
    this.itemWidth = width,
    this.itemHeight = height,
    this.artworkWidth = 60,
    this.artworkHeight = 44,
    this.inactiveOpacity = 0.5,
    this.semanticLabel,
    super.key,
  }) : assert(itemWidth > 0),
       assert(itemHeight > 0),
       assert(artworkWidth > 0 && artworkWidth <= itemWidth),
       assert(artworkHeight > 0 && artworkHeight <= itemHeight),
       assert(inactiveOpacity >= 0 && inactiveOpacity <= 1);

  static const double width = 64;
  static const double height = 48;

  static const double _selectionBorderWidth = 2;
  static const double _selectionBorderRadius = 10;
  static const double _selectedCheckSize = 20;

  final PaymentLinkCardArtwork artwork;
  final bool selected;
  final VoidCallback onSelected;
  final double itemWidth;
  final double itemHeight;
  final double artworkWidth;
  final double artworkHeight;
  final double inactiveOpacity;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return PaymentLinkAction(
      onPressed: onSelected,
      selected: selected,
      semanticLabel: semanticLabel ?? '${artwork.semanticLabel} card design',
      builder: (context, hovered, focused) {
        final active = selected || focused;
        final opacity = selected || hovered || focused ? 1.0 : inactiveOpacity;
        final artworkLeft = (itemWidth - artworkWidth) / 2;
        final artworkTop = (itemHeight - artworkHeight) / 2;
        return SizedBox(
          width: itemWidth,
          height: itemHeight,
          child: Stack(
            children: [
              Positioned(
                left: artworkLeft,
                top: artworkTop,
                width: artworkWidth,
                height: artworkHeight,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadii.xSmall),
                  child: AnimatedOpacity(
                    key: const ValueKey('payment_link_card_artwork'),
                    opacity: opacity,
                    duration: const Duration(milliseconds: 120),
                    curve: Curves.easeOut,
                    child: Image.asset(
                      artwork.assetPath,
                      fit: BoxFit.cover,
                      excludeFromSemantics: true,
                    ),
                  ),
                ),
              ),
              if (active)
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      key: const ValueKey('payment_link_card_focus_ring'),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(
                          _selectionBorderRadius,
                        ),
                        border: Border.all(
                          color: colors.state.focusRing,
                          width: _selectionBorderWidth,
                        ),
                      ),
                    ),
                  ),
                ),
              if (selected)
                Positioned(
                  right: 4,
                  bottom: 4,
                  child: Container(
                    key: const ValueKey('payment_link_card_check'),
                    width: _selectedCheckSize,
                    height: _selectedCheckSize,
                    decoration: BoxDecoration(
                      color: colors.background.inverse,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: AppIcon(
                        AppIcons.check,
                        size: AppIconSize.medium,
                        color: colors.icon.inverse,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
