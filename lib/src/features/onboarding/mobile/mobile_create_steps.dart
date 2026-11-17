import 'package:flutter/widgets.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/l10n/locale_typography.dart';
import '../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../core/layout/mobile/mobile_sticky_bottom_action.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/liquid_metal.dart';
import '../../../core/widgets/mobile/mobile_surface_card.dart';
import '../../../core/widgets/svg_shape_image.dart';
import 'mobile_onboarding_progress.dart';
import 'mobile_onboarding_progress_scope.dart';
import 'mobile_onboarding_scaffold.dart';

/// Step 2 — Figma `New Wallet01` (9394:58807): "About Zcash" over the
/// citadel art, with the shield cast in liquid metal.
class MobileOnboardingIntroScreen extends StatelessWidget {
  const MobileOnboardingIntroScreen({
    super.key,
    this.onContinue,
    this.onBack,
    this.showProgress = true,
    this.actionsEnabled = true,
    this.onSkip,
    this.closingText,
  });

  final VoidCallback? onContinue;
  final VoidCallback? onBack;
  final bool showProgress;
  final bool actionsEnabled;
  final VoidCallback? onSkip;
  final String? closingText;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return MobileOnboardingStepScaffold(
      progress: OnboardingProgressPosition.start.value,
      showProgress: showProgress,
      onBack: onBack ?? () => Navigator.of(context).maybePop(),
      title: context.l10n.onboardingIntroTitleMobile,
      // Figma sets this title at 36, a step under the other steps' 40.
      titleStyle: AppTypography.displayLarge.copyWith(
        fontWeight: FontWeight.w500,
        fontSize: 36,
        height: 36 / 36,
      ),
      background: const MobileOnboardingCitadelBackground(),
      contentGap: AppSpacing.base,
      // Line break matches the Figma subtitle wrap.
      subtitle: context.l10n.onboardingIntroSubtitleMobile,
      bottomAreaPadding: const EdgeInsets.fromLTRB(
        kMobilePageMargin,
        AppSpacing.s,
        kMobilePageMargin,
        kMobileFooterGap,
      ),
      bottomArea: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppButton(
            key: const ValueKey('mobile_intro_continue'),
            expand: true,
            growWithContent: true,
            constrainContent: true,
            onPressed: !actionsEnabled
                ? null
                : onContinue ??
                      () => context.pushOnboarding('/onboarding/address-types'),
            trailing: const AppIcon(AppIcons.chevronForward),
            child: Text(
              context.l10n.onboardingTellMeHowZcashWorks,
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: AppSpacing.s),
          AppButton(
            key: const ValueKey('mobile_intro_skip'),
            variant: AppButtonVariant.ghost,
            expand: true,
            growWithContent: true,
            constrainContent: true,
            trailing: const AppIcon(AppIcons.skip),
            onPressed: !actionsEnabled
                ? null
                : onSkip ??
                      () => context.pushOnboarding(
                        '/onboarding/secret-passphrase',
                      ),
            child: Text(
              context.l10n.onboardingIKnowHowToUseZcash,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
      child: Column(
        children: [
          _DarkInfoCard(text: context.l10n.onboardingIntroCard),
          // 24 to the paragraph block, plus its own 8 inset.
          const SizedBox(height: AppSpacing.md + AppSpacing.xs),
          Padding(
            // Figma's 329 measure, so the sentence wraps where it does there.
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s),
            child: Text(
              closingText ?? context.l10n.onboardingIntroClosingMobile,
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(
                color: colors.text.accent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Step 3 — Figma `New Wallet02` (4752:24608).
class MobileAddressTypesScreen extends StatelessWidget {
  const MobileAddressTypesScreen({
    super.key,
    this.onContinue,
    this.onBack,
    this.showProgress = true,
    this.actionsEnabled = true,
  });

  final VoidCallback? onContinue;
  final VoidCallback? onBack;
  final bool showProgress;
  final bool actionsEnabled;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return MobileOnboardingStepScaffold(
      showProgress: showProgress,
      progress: !showProgress
          ? 0
          : MobileOnboardingProgressScope.of(
              context,
            ).at(OnboardingFlow.create, OnboardingStage.addressTypes).value,
      onBack: onBack ?? () => Navigator.of(context).maybePop(),
      title: context.l10n.onboardingAddressTypesTitle,
      contentGap: 32,
      bottomAreaPadding: _educationActionPadding(context),
      // Line break matches the Figma subtitle wrap.
      subtitle: context.l10n.onboardingAddressTypesSubtitle,
      bottomArea: AppButton(
        key: const ValueKey('mobile_address_types_continue'),
        expand: true,
        onPressed: !actionsEnabled
            ? null
            : onContinue ??
                  () => context.pushOnboarding('/onboarding/things-to-know'),
        trailing: const AppIcon(AppIcons.chevronForward),
        child: Text(context.l10n.commonContinue),
      ),
      child: _EducationSections(
        separateCards: true,
        sections: [
          _InfoSection(
            iconName: AppIcons.shieldKeyhole,
            iconColor: colors.icon.brandCrimson,
            title: context.l10n.onboardingAddressShieldedTitleMobile,
            trailing: const _AddressChip(
              prefix: 'u1',
              sample: 'vt42...',
              emphasized: true,
            ),
            body: context.l10n.onboardingAddressShieldedBodyMobile,
            boldRuns: const ['u1', 'zs'], // l10n-ignore: address prefixes
          ),
          _InfoSection(
            iconName: AppIcons.transparentBalance,
            iconColor: colors.icon.accent,
            title: context.l10n.onboardingAddressTransparentTitleMobile,
            trailing: const _AddressChip(prefix: 't', sample: 'vxr2...'),
            body: context.l10n.onboardingAddressTransparentDescription,
          ),
        ],
      ),
    );
  }
}

/// Step 4 — Figma `New Wallet03` (4752:24673).
class MobileThingsToKnowScreen extends StatelessWidget {
  const MobileThingsToKnowScreen({
    super.key,
    this.onContinue,
    this.onBack,
    this.showProgress = true,
    this.actionsEnabled = true,
  });

  final VoidCallback? onContinue;
  final VoidCallback? onBack;
  final bool showProgress;
  final bool actionsEnabled;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return MobileOnboardingStepScaffold(
      showProgress: showProgress,
      progress: !showProgress
          ? 0
          : MobileOnboardingProgressScope.of(
              context,
            ).at(OnboardingFlow.create, OnboardingStage.thingsToKnow).value,
      onBack: onBack ?? () => Navigator.of(context).maybePop(),
      title: context.l10n.onboardingThingsToKnow,
      contentGap: 32,
      bottomAreaPadding: _educationActionPadding(context),
      subtitle: context.l10n.onboardingThingsSubtitleMobile,
      bottomArea: AppButton(
        key: const ValueKey('mobile_things_to_know_continue'),
        expand: true,
        onPressed: !actionsEnabled
            ? null
            : onContinue ??
                  () => context.pushOnboarding('/onboarding/secret-passphrase'),
        trailing: const AppIcon(AppIcons.chevronForward),
        child: Text(context.l10n.commonContinue),
      ),
      child: _EducationSections(
        separateCards: false,
        sections: [
          _InfoSection(
            iconName: AppIcons.time,
            iconColor: colors.icon.accent,
            title: context.l10n.onboardingThingsTimeToSyncTitle,
            body: context.l10n.onboardingThingsTimeToSyncBody,
          ),
          _InfoSection(
            iconName: AppIcons.shieldKeyhole,
            iconColor: colors.icon.accent,
            title: context.l10n.onboardingThingsKeepPrivacyTitle,
            body: context.l10n.onboardingThingsKeepPrivacyBody,
          ),
        ],
      ),
    );
  }
}

class _DarkInfoCard extends StatelessWidget {
  const _DarkInfoCard({required this.text});

  final String text;

  /// Figma `Shield Fill` at 72, cast in the transaction records' metal.
  static const _shieldSize = 72.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      key: const ValueKey('mobile_intro_info_card'),
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.background.homeCard,
        borderRadius: BorderRadius.circular(AppRadii.large),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(
            child: SizedBox.square(
              key: const ValueKey('mobile_intro_info_card_shield'),
              dimension: _shieldSize,
              child: LiquidMetal(
                image: SvgShapeImage(
                  'assets/icons/${AppIcons.shieldKeyhole}.svg',
                ),
                // Only the shape shows; the card shows through around it.
                colorBack: const Color(0x00000000),
                softness: 1,
                scale: 1,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          // Figma wraps the text at 249 inside the card.
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 249),
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: AppTypography.bodyMediumStrong.copyWith(
                color: colors.text.homeCard,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoSection {
  const _InfoSection({
    required this.iconName,
    required this.iconColor,
    required this.title,
    required this.body,
    this.trailing,
    this.boldRuns = const [],
  });

  final String iconName;
  final Color iconColor;
  final String title;
  final String body;
  final Widget? trailing;

  /// Substrings of [body] rendered bold, e.g. the `u1` / `zs` address
  /// prefixes the Figma frame emphasizes. First occurrence only.
  final List<String> boldRuns;

  TextSpan bodySpan(TextStyle base) {
    var spans = <TextSpan>[TextSpan(text: body)];
    for (final run in boldRuns) {
      final next = <TextSpan>[];
      var applied = false;
      for (final span in spans) {
        final text = span.text!;
        final i = applied || span.style != null ? -1 : text.indexOf(run);
        if (i < 0) {
          next.add(span);
          continue;
        }
        applied = true;
        if (i > 0) next.add(TextSpan(text: text.substring(0, i)));
        next.add(
          TextSpan(
            text: run,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        );
        if (i + run.length < text.length) {
          next.add(TextSpan(text: text.substring(i + run.length)));
        }
      }
      spans = next;
    }
    return TextSpan(style: base, children: spans);
  }
}

// Include the device's safe area in the 48 px bottom margin, rather than
// adding it twice. Larger accessibility/system insets remain respected.
// The shared footer gap, as on every page.
EdgeInsets _educationActionPadding(BuildContext context) =>
    const EdgeInsets.fromLTRB(
      kMobilePageMargin,
      12,
      kMobilePageMargin,
      kMobileFooterGap,
    );

class _EducationSections extends StatelessWidget {
  const _EducationSections({
    required this.sections,
    required this.separateCards,
  });

  final List<_InfoSection> sections;
  final bool separateCards;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: separateCards ? 0 : 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < sections.length; i++) ...[
            if (i > 0) SizedBox(height: separateCards ? 16 : 24),
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(
                horizontal: 20,
                vertical: separateCards ? 36 : 4,
              ),
              decoration: separateCards
                  ? BoxDecoration(
                      color: colors.background.ground,
                      borderRadius: BorderRadius.circular(AppRadii.large),
                      boxShadow: mobileSurfaceShadows(colors),
                    )
                  : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      AppIcon(
                        sections[i].iconName,
                        size: 24,
                        color: sections[i].iconColor,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          sections[i].title,
                          style: AppTypography.bodyLarge.copyWith(
                            color: colors.text.accent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (sections[i].trailing != null) sections[i].trailing!,
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text.rich(
                    sections[i].bodySpan(
                      withLocaleFontFallback(
                        context,
                        AppTypography.bodyMedium.copyWith(
                          color: colors.text.primary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AddressChip extends StatelessWidget {
  const _AddressChip({
    required this.prefix,
    required this.sample,
    this.emphasized = false,
  });

  final String prefix;
  final String sample;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final bg = emphasized
        ? colors.background.inverse
        : colors.background.raised;
    // The prefix uses a crimson badge for shielded and an inverse badge
    // for transparent addresses.
    final badgeBg = emphasized
        ? colors.background.brandCrimsonStrong
        : colors.background.inverse;
    final textColor = emphasized ? colors.text.inverse : colors.text.primary;
    // Figma `Card Top` chip: 37 px pill, Code M address, 8 px inset.
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: badgeBg,
              borderRadius: BorderRadius.circular(AppRadii.xSmall - 2),
            ),
            child: Text(
              prefix,
              style: AppTypography.codeSmall.copyWith(
                color: emphasized ? colors.text.homeCard : colors.text.inverse,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xxs),
          Text(
            sample,
            style: AppTypography.codeMedium.copyWith(color: textColor),
          ),
        ],
      ),
    );
  }
}
