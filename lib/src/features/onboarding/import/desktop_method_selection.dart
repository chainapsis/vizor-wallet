import 'dart:ui' as ui;

import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';

const double _contentAreaWidth = 420;
const double _cardHeight = 80;
const double _footerButtonWidth = 210;
const double _backgroundLeftOverflow = 264;
const double _backgroundHeight = 520;
const double _backgroundFadeStart = 143;
const double _backgroundFadeEnd = 529;

/// Shared full-window presentation for the desktop import method pickers.
///
/// The background and geometry follow the Figma import and hardware selection
/// frames. Callers own the methods and navigation so unsupported choices never
/// appear as inert design-only cards.
class DesktopMethodSelectionScaffold extends StatelessWidget {
  const DesktopMethodSelectionScaffold({
    required this.title,
    required this.subtitle,
    required this.cards,
    required this.footerLabel,
    required this.onFooterPressed,
    super.key,
  });

  final String title;
  final String subtitle;
  final List<Widget> cards;
  final String footerLabel;
  final VoidCallback onFooterPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Scaffold(
      backgroundColor: colors.background.window,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            left: -_backgroundLeftOverflow,
            right: 0,
            top: 0,
            height: _backgroundHeight,
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (_) => ui.Gradient.linear(
                const Offset(0, _backgroundFadeStart),
                const Offset(0, _backgroundFadeEnd),
                const [Color(0x26FFFFFF), Color(0x00FFFFFF)],
              ),
              child: Image.asset(
                'assets/illustrations/desktop/donation_success_background.webp',
                key: const ValueKey('desktop_method_selection_background'),
                fit: BoxFit.cover,
                alignment: Alignment.center,
                excludeFromSemantics: true,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 48),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _contentAreaWidth),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s,
                    vertical: AppSpacing.sm,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _TitleBlock(title: title, subtitle: subtitle),
                      const SizedBox(height: AppSpacing.md),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.sm,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: _withCardGaps(cards),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Center(
                        child: AppButton(
                          key: const ValueKey(
                            'desktop_method_selection_footer_button',
                          ),
                          onPressed: onFooterPressed,
                          variant: AppButtonVariant.ghost,
                          minWidth: _footerButtonWidth,
                          child: Text(footerLabel),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static List<Widget> _withCardGaps(List<Widget> cards) => [
    for (var index = 0; index < cards.length; index++) ...[
      if (index > 0) const SizedBox(height: AppSpacing.s),
      cards[index],
    ],
  ];
}

class DesktopMethodSelectionCard extends StatelessWidget {
  const DesktopMethodSelectionCard({
    required this.iconName,
    required this.title,
    required this.description,
    required this.onPressed,
    super.key,
  });

  final String iconName;
  final String title;
  final String description;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Semantics(
      button: true,
      child: AppButton(
        onPressed: onPressed,
        variant: AppButtonVariant.secondary,
        height: _cardHeight,
        expand: true,
        constrainContent: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s,
          vertical: AppSpacing.s,
        ),
        borderRadius: BorderRadius.circular(AppRadii.large),
        enabledBackgroundColor: colors.background.ground,
        pressedBackgroundColor: colors.background.raised,
        enabledLabelColor: colors.text.accent,
        pressedLabelColor: colors.text.accent,
        child: Row(
          children: [
            Container(
              key: const ValueKey('desktop_method_selection_icon_wrap'),
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: colors.background.inverse,
                borderRadius: BorderRadius.circular(AppRadii.medium),
              ),
              alignment: Alignment.center,
              child: AppIcon(
                iconName,
                size: AppIconSize.large,
                color: colors.icon.inverse,
              ),
            ),
            const SizedBox(width: AppSpacing.s),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.labelLarge.copyWith(
                      color: colors.text.accent,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodyMedium.copyWith(
                      color: colors.text.secondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TitleBlock extends StatelessWidget {
  const _TitleBlock({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: AppTypography.displayLarge.copyWith(color: colors.text.accent),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: AppTypography.bodyMediumStrong.copyWith(
            color: colors.text.primary,
          ),
        ),
      ],
    );
  }
}
