import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';
import 'payment_link_action.dart';
import 'payment_link_gift_card.dart';

/// A compact entry beside the Gift Cards content that opens the desktop group
/// flow directly. [fullWidth] lays it out as a row for narrow panes.
class PaymentLinkGroupEntry extends StatelessWidget {
  const PaymentLinkGroupEntry({
    required this.onPressed,
    this.fullWidth = false,
    super.key,
  });

  static const double width = 144;

  final VoidCallback onPressed;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    return PaymentLinkAction(
      key: const ValueKey('payment_link_create_batch_button'),
      semanticLabel: 'Create cards for a group',
      onPressed: onPressed,
      builder: (context, hovered, focused) => TweenAnimationBuilder<double>(
        tween: Tween(end: hovered ? 1 : 0),
        duration: reducedMotion
            ? Duration.zero
            : const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        builder: (context, hover, _) {
          // Reduced motion keeps the colour change and drops the movement.
          final motion = reducedMotion ? 0.0 : hover;
          final label = Text(
            'For a group',
            style: AppTypography.bodyMediumStrong.copyWith(
              color: colors.text.accent,
            ),
          );
          final chevron = Transform.translate(
            offset: Offset(2 * motion, 0),
            child: AppIcon(
              AppIcons.chevronForward,
              size: 16,
              color: colors.icon.brandCrimson,
            ),
          );
          final stack = _GroupCardStack(spread: motion);
          return Transform.translate(
            offset: Offset(0, -2 * motion),
            child: Container(
              width: fullWidth ? double.infinity : width,
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color.lerp(
                      colors.background.raised,
                      colors.background.brandCrimsonSubtle,
                      hover * .5,
                    )!,
                    colors.background.brandCrimsonSubtle,
                  ],
                ),
                borderRadius: BorderRadius.circular(AppRadii.large),
                border: Border.all(
                  color: Color.lerp(
                    colors.border.regular,
                    colors.border.brandCrimsonStrong,
                    .35 + .65 * hover,
                  )!,
                ),
                // A brand glow keeps the tile visible beside the centred
                // content, and grows on hover.
                boxShadow: [
                  BoxShadow(
                    color: colors.background.brandCrimsonAlpha.withValues(
                      alpha:
                          colors.background.brandCrimsonAlpha.a *
                          (.45 + .55 * hover),
                    ),
                    blurRadius: 16 + 8 * hover,
                    offset: Offset(0, 2 + 4 * motion),
                  ),
                ],
              ),
              // Drawn over the border so focus does not shift the layout.
              foregroundDecoration: focused
                  ? BoxDecoration(
                      borderRadius: BorderRadius.circular(AppRadii.large),
                      border: Border.all(
                        color: colors.state.focusRing,
                        width: 2,
                      ),
                    )
                  : null,
              child: fullWidth
                  ? Row(
                      children: [
                        stack,
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(child: label),
                        chevron,
                      ],
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        stack,
                        const SizedBox(height: AppSpacing.xs),
                        Row(
                          children: [
                            Expanded(child: label),
                            chevron,
                          ],
                        ),
                      ],
                    ),
            ),
          );
        },
      ),
    );
  }
}

class _GroupCardStack extends StatelessWidget {
  const _GroupCardStack({required this.spread});

  /// 0 at rest, 1 fully fanned out on hover.
  final double spread;

  static const _rest = [
    (0.0, 16.0, -0.16),
    (11.0, 8.0, -0.04),
    (22.0, 2.0, 0.10),
  ];
  static const _fanned = [
    (-8.0, 18.0, -0.34),
    (11.0, 5.0, -0.04),
    (30.0, -3.0, 0.24),
  ];

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox(
        width: 92,
        height: 62,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            for (var index = 0; index < _rest.length; index++)
              Positioned(
                left: _lerp(_rest[index].$1, _fanned[index].$1),
                top: _lerp(_rest[index].$2, _fanned[index].$2),
                child: Transform.rotate(
                  angle: _lerp(_rest[index].$3, _fanned[index].$3),
                  child: Container(
                    width: 62,
                    height: 40,
                    decoration: BoxDecoration(
                      color: context.colors.background.raised,
                      borderRadius: BorderRadius.circular(AppRadii.xSmall),
                      border: Border.all(color: context.colors.border.regular),
                      boxShadow: appSurfaceShadow(context.colors),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Opacity(
                      opacity: index == 2 ? 1 : (index == 1 ? .65 : .4),
                      child: Image.asset(
                        PaymentLinkCardArtwork.ruby.assetPath,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  double _lerp(double rest, double fanned) => rest + (fanned - rest) * spread;
}
