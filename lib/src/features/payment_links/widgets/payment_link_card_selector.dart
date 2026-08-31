import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';
import 'payment_link_action.dart';
import 'payment_link_gift_card.dart';

/// Figma `Card Design Select` option (65×51, default/hover/selected).
class PaymentLinkCardSelector extends StatelessWidget {
  const PaymentLinkCardSelector({
    required this.artwork,
    required this.selected,
    required this.onSelected,
    this.itemWidth = width,
    this.itemHeight = height,
    this.artworkWidth = 60,
    this.artworkHeight = 44,
    this.selectionInset = const EdgeInsets.fromLTRB(1, 2, 0, 1),
    this.selectionBorderWidth = 2,
    this.selectionBorderRadius = 10,
    this.selectedCheckSize = 20,
    this.inactiveOpacity = 0.5,
    this.semanticLabel,
    super.key,
  }) : assert(itemWidth > 0),
       assert(itemHeight > 0),
       assert(artworkWidth > 0 && artworkWidth <= itemWidth),
       assert(artworkHeight > 0 && artworkHeight <= itemHeight),
       assert(selectionBorderWidth > 0),
       assert(selectionBorderRadius >= 0),
       assert(selectedCheckSize > 0),
       assert(inactiveOpacity >= 0 && inactiveOpacity <= 1);

  static const double width = 65;
  static const double height = 51;

  final PaymentLinkCardArtwork artwork;
  final bool selected;
  final VoidCallback onSelected;
  final double itemWidth;
  final double itemHeight;
  final double artworkWidth;
  final double artworkHeight;
  final EdgeInsets selectionInset;
  final double selectionBorderWidth;
  final double selectionBorderRadius;
  final double selectedCheckSize;
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
                Positioned(
                  left: selectionInset.left,
                  top: selectionInset.top,
                  right: selectionInset.right,
                  bottom: selectionInset.bottom,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      key: const ValueKey('payment_link_card_focus_ring'),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(
                          selectionBorderRadius,
                        ),
                        border: Border.all(
                          color: colors.state.focusRing,
                          width: selectionBorderWidth,
                        ),
                      ),
                    ),
                  ),
                ),
              if (selected)
                Positioned(
                  right: 4,
                  bottom: 5,
                  child: Container(
                    key: const ValueKey('payment_link_card_check'),
                    width: selectedCheckSize,
                    height: selectedCheckSize,
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
