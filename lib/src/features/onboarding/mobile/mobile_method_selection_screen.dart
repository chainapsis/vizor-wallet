import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';
import 'mobile_onboarding_progress.dart';

const double _methodCardHeight = 90;
const double _regularArtWidth = 135;
const double _regularArtHeight = 90;
const double _bleedArtWidth = 140;
const double _bleedArtHeight = 113;
const double _bleedArtTopOverflow = 24;
const double _methodCardBorderWidth = 1.5;

/// Second onboarding step — Figma `Method Selection` (4752:26334): the
/// "Welcome to Vizor" title over four illustrated cards (create /
/// import / desktop link / Keystone), reached from the Welcome screen's "Get started"
/// button. Keeps the `mobile_welcome_*` keys so the onboarding flow
/// helpers route through here unchanged.
///
/// Unlike the scrolling step scaffold, the Figma frame pins the title to
/// the top and the legal line to the bottom, then vertically centres the
/// cards in the space between. The layout
/// below mirrors that: a fixed top nav + title block, an [Expanded] that
/// centres the cards, and a pinned footer.
class MobileMethodSelectionScreen extends StatelessWidget {
  const MobileMethodSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = context.appTheme == AppThemeData.dark;
    return Scaffold(
      backgroundColor: colors.background.window,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Welcome has no track, so method selection is the first visible
            // fill after one completed create-flow screen.
            MobileTopNav.steps(
              progress: mobileCreateProgress(2),
              onBack: () => context.pop(),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'Welcome to Vizor',
                      textAlign: TextAlign.center,
                      style: AppTypography.displayLarge.copyWith(
                        color: colors.text.accent,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Select the method you want.',
                      textAlign: TextAlign.center,
                      style: AppTypography.bodyMediumStrong.copyWith(
                        color: colors.text.primary,
                      ),
                    ),
                    // Cards centred in the space between title and footer.
                    Expanded(
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _MethodCard(
                              buttonKey: const ValueKey(
                                'mobile_welcome_create',
                              ),
                              iconName: AppIcons.addNew,
                              label: 'Create wallet',
                              illustration:
                                  'assets/illustrations/method_create_dark.png',
                              // The create knight is taller than the card and
                              // bleeds above its top edge in Figma (4752:26357).
                              bleed: true,
                              emphasized: true,
                              onTap: () => context.push('/onboarding/intro'),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            _MethodCard(
                              buttonKey: const ValueKey(
                                'mobile_welcome_import',
                              ),
                              iconName: AppIcons.importWallet,
                              label: 'Import wallet',
                              illustration:
                                  'assets/illustrations/method_import_dark.png',
                              onTap: () => context.push('/import'),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            _MethodCard(
                              buttonKey: const ValueKey(
                                'mobile_welcome_link_desktop',
                              ),
                              iconName: AppIcons.monitor,
                              label: 'Link Vizor Desktop',
                              illustration:
                                  'assets/illustrations/method_import_dark.png',
                              onTap: () =>
                                  context.push('/onboarding/link-desktop'),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            _MethodCard(
                              buttonKey: const ValueKey(
                                'mobile_welcome_keystone',
                              ),
                              iconName: AppIcons.qr,
                              label: 'Connect Keystone',
                              illustration: isDark
                                  ? 'assets/illustrations/method_keystone_dark.png'
                                  : 'assets/illustrations/method_keystone_light.png',
                              onTap: () => context.push('/onboarding/keystone'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const ExcludeSemantics(
                      key: ValueKey('mobile_method_legal_footer_semantics'),
                      child: IgnorePointer(
                        key: ValueKey('mobile_method_legal_footer_pointer'),
                        child: Opacity(
                          key: ValueKey('mobile_method_legal_footer_hidden'),
                          opacity: 0,
                          child: _MethodLegalFooter(),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MethodCard extends StatelessWidget {
  const _MethodCard({
    required this.buttonKey,
    required this.iconName,
    required this.label,
    required this.illustration,
    required this.onTap,
    this.bleed = false,
    this.emphasized = false,
  });

  final Key buttonKey;
  final String iconName;
  final String label;
  final String illustration;
  final VoidCallback onTap;
  final bool emphasized;

  /// The create knight is rendered at 186×151 and bleeds 31px above the
  /// card; the masked import/Keystone art is 180×120 and stays inside the
  /// rounded card. Both assets are exact 3× of their target box so a
  /// BoxFit.fill is pixel-accurate.
  final bool bleed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isLight = context.appTheme == AppThemeData.light;
    final cardBackgroundColor = emphasized && isLight
        ? colors.background.homeCard
        : colors.background.raised;
    final contentColor = emphasized ? colors.text.homeCard : colors.text.accent;
    final cardRadius = BorderRadius.circular(AppRadii.large);
    final keySuffix = label.toLowerCase().replaceAll(' ', '_');
    // Compact mobile method cards keep the artwork right-aligned and masked.
    final artImage = Image.asset(
      illustration,
      key: ValueKey('mobile_method_${keySuffix}_art'),
      fit: BoxFit.fill,
    );
    final art = bleed
        ? Positioned(
            top: -_bleedArtTopOverflow,
            left: 0,
            right: 0,
            height: _methodCardHeight + _bleedArtTopOverflow,
            child: ClipPath(
              key: ValueKey('mobile_method_${keySuffix}_art_clip'),
              clipper: const _TopBleedOnlyClipper(
                topBleed: _bleedArtTopOverflow,
                cardRadius: AppRadii.large,
                rightInset: _methodCardBorderWidth,
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    top: 0,
                    right: 0,
                    width: _bleedArtWidth,
                    height: _bleedArtHeight,
                    child: artImage,
                  ),
                ],
              ),
            ),
          )
        : Positioned(
            top: 0,
            right: 0,
            width: _regularArtWidth,
            height: _regularArtHeight,
            child: artImage,
          );
    final border = Positioned.fill(
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: cardRadius,
            border: Border.all(
              color: colors.border.subtle,
              width: _methodCardBorderWidth,
            ),
          ),
        ),
      ),
    );
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        key: buttonKey,
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          height: _methodCardHeight,
          // clipBehavior none lets the create knight bleed above the card;
          // expand keeps the rounded card filling the full 120 box.
          child: Stack(
            fit: StackFit.expand,
            clipBehavior: Clip.none,
            children: [
              ClipRRect(
                borderRadius: cardRadius,
                child: DecoratedBox(
                  decoration: BoxDecoration(color: cardBackgroundColor),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [if (!bleed) art],
                  ),
                ),
              ),
              if (bleed) border,
              if (bleed) art,
              if (!bleed) border,
              _MethodCardContent(
                key: ValueKey('mobile_method_${keySuffix}_content'),
                iconName: iconName,
                label: label,
                color: contentColor,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBleedOnlyClipper extends CustomClipper<Path> {
  const _TopBleedOnlyClipper({
    required this.topBleed,
    required this.cardRadius,
    required this.rightInset,
  });

  final double topBleed;
  final double cardRadius;
  final double rightInset;

  @override
  Path getClip(Size size) {
    final clippedWidth = (size.width - rightInset).clamp(0.0, size.width);
    return Path()
      ..addRect(Rect.fromLTWH(0, 0, clippedWidth, topBleed))
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, topBleed, clippedWidth, size.height - topBleed),
          Radius.circular(cardRadius),
        ),
      );
  }

  @override
  bool shouldReclip(_TopBleedOnlyClipper oldClipper) {
    return topBleed != oldClipper.topBleed ||
        cardRadius != oldClipper.cardRadius ||
        rightInset != oldClipper.rightInset;
  }
}

class _MethodCardContent extends StatelessWidget {
  const _MethodCardContent({
    super.key,
    required this.iconName,
    required this.label,
    required this.color,
  });

  final String iconName;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Figma insets the icon/label 14.5 from the card edge (~sm).
      padding: const EdgeInsets.all(AppSpacing.s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppIcon(iconName, size: 20, color: color),
          const Spacer(),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodyLarge.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _MethodLegalFooter extends StatelessWidget {
  const _MethodLegalFooter();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final base = AppTypography.bodySmall.copyWith(color: colors.text.muted);
    // Figma underlines Terms/Privacy in text/primary (#c2c3c3). The legal
    // documents aren't ready yet, so they match the design visually but
    // carry no tap target (product decision, 2026-06).
    final emphasis = AppTypography.bodySmall.copyWith(
      color: colors.text.primary,
      decoration: TextDecoration.underline,
      decorationColor: colors.text.primary,
    );
    return Center(
      child: SizedBox(
        width: 193,
        child: Text.rich(
          TextSpan(
            style: base,
            children: [
              const TextSpan(text: 'By using Vizor you agree to our '),
              TextSpan(text: 'Terms', style: emphasis),
              const TextSpan(text: ' and '),
              TextSpan(text: 'Privacy', style: emphasis),
            ],
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
