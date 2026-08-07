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
    this.semanticLabel,
    super.key,
  });

  static const double width = 65;
  static const double height = 51;

  final PaymentLinkCardArtwork artwork;
  final bool selected;
  final VoidCallback onSelected;
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
        final opacity = selected || hovered || focused ? 1.0 : 0.5;
        return SizedBox(
          width: PaymentLinkCardSelector.width,
          height: PaymentLinkCardSelector.height,
          child: Stack(
            children: [
              Positioned(
                left: 3,
                top: 4,
                width: 60,
                height: 44,
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
                  left: 1,
                  top: 2,
                  width: 64,
                  height: 48,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      key: const ValueKey('payment_link_card_focus_ring'),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: colors.state.focusRing,
                          width: 2,
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
                    width: 20,
                    height: 20,
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
