import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import 'mobile_onboarding_progress.dart';
import 'mobile_onboarding_progress_scope.dart';
import 'mobile_onboarding_scaffold.dart';

/// Step 2 — Figma `New Account` (8569:129347).
class MobileOnboardingIntroScreen extends StatelessWidget {
  const MobileOnboardingIntroScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return MobileOnboardingStepScaffold(
      progress: OnboardingProgressPosition.start.value,
      onBack: () => Navigator.of(context).maybePop(),
      title: 'The Shielded World',
      titleStyle: AppTypography.displayLarge.copyWith(
        fontWeight: FontWeight.w500,
      ),
      topNavHeight: 74,
      topNavProgressOffset: const Offset(-4.5, 0),
      topNavProgressTrackColor: colors.background.inverse.withValues(
        alpha: 0.35,
      ),
      contentGap: AppSpacing.base,
      // Line break matches the Figma subtitle wrap.
      subtitle: 'Zcash (ZEC) built around financial\nprivacy & self-custody.',
      bottomAreaPadding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.s,
        AppSpacing.sm,
        AppSpacing.md,
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
            onPressed: () =>
                context.pushOnboarding('/onboarding/address-types'),
            trailing: const AppIcon(AppIcons.chevronForward),
            child: const Text(
              'Tell me how Zcash works',
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
            onPressed: () =>
                context.pushOnboarding('/onboarding/secret-passphrase'),
            child: const Text(
              'I know how to use Zcash',
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
      child: Column(
        children: [
          _DarkInfoCard(
            iconName: AppIcons.shieldKeyhole,
            text:
                'Unlike Bitcoin or Ethereum, shielded Zcash transactions '
                'hide the sender, recipient, and amount — verified by '
                'cryptography, not trust.',
          ),
          // 32 to the paragraph block (plus its own 24 inset) per the
          // intro frame's vertical rhythm.
          const SizedBox(height: AppSpacing.base + AppSpacing.md),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Text(
              "You're a few steps away from your first private wallet. "
              "Let's get you set up.",
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
  const MobileAddressTypesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return MobileOnboardingStepScaffold(
      progress: MobileOnboardingProgressScope.of(
        context,
      ).at(OnboardingFlow.create, OnboardingStage.addressTypes).value,
      onBack: () => Navigator.of(context).maybePop(),
      title: 'Zcash Address Types',
      contentGap: 32,
      bottomAreaPadding: _educationActionPadding(context),
      // Line break matches the Figma subtitle wrap.
      subtitle:
          'Zcash has two addresses types.\nOne for Privacy, one for Transparency.',
      bottomArea: AppButton(
        key: const ValueKey('mobile_address_types_continue'),
        expand: true,
        onPressed: () => context.pushOnboarding('/onboarding/things-to-know'),
        trailing: const AppIcon(AppIcons.chevronForward),
        child: const Text('Continue'),
      ),
      child: _EducationSections(
        separateCards: true,
        sections: [
          _InfoSection(
            iconName: AppIcons.shieldKeyholeOutline,
            iconColor: colors.icon.brandCrimson,
            title: 'Shielded Address',
            trailing: const _AddressChip(
              prefix: 'u1',
              sample: 'vt42...',
              emphasized: true,
            ),
            body:
                'Address starts with u1 (or zs for legacy).\nOnly you can '
                'see your account balance and transaction history.',
            boldRuns: const ['u1', 'zs'],
          ),
          _InfoSection(
            iconName: AppIcons.transparentBalance,
            iconColor: colors.icon.accent,
            title: 'Transparent Address',
            trailing: const _AddressChip(prefix: 't', sample: 'vxr2...'),
            body:
                "Address starts with t, similar to Bitcoin, your address' "
                'balance and transaction history are publicly visible.',
          ),
        ],
      ),
    );
  }
}

/// Step 4 — Figma `New Wallet03` (4752:24673).
class MobileThingsToKnowScreen extends StatelessWidget {
  const MobileThingsToKnowScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return MobileOnboardingStepScaffold(
      progress: MobileOnboardingProgressScope.of(
        context,
      ).at(OnboardingFlow.create, OnboardingStage.thingsToKnow).value,
      onBack: () => Navigator.of(context).maybePop(),
      title: 'Things to know',
      contentGap: 32,
      bottomAreaPadding: _educationActionPadding(context),
      subtitle: 'Before you dive in.',
      bottomArea: AppButton(
        key: const ValueKey('mobile_things_to_know_continue'),
        expand: true,
        onPressed: () =>
            context.pushOnboarding('/onboarding/secret-passphrase'),
        trailing: const AppIcon(AppIcons.chevronForward),
        child: const Text('Continue'),
      ),
      child: _EducationSections(
        separateCards: false,
        sections: [
          _InfoSection(
            iconName: AppIcons.time,
            iconColor: colors.icon.accent,
            title: 'Time to sync',
            body:
                'Your wallet syncs directly with the Zcash network instead '
                'of relying on a server. This protects your privacy, but '
                'takes a moment. Your funds are safe while the app catches '
                'up.',
          ),
          _InfoSection(
            iconName: AppIcons.shieldKeyholeOutline,
            iconColor: colors.icon.accent,
            title: 'How to keep privacy',
            body:
                "Some exchanges can't send to shielded addresses. If "
                "you're withdrawing from an exchange, use your transparent "
                'address. You can shield your ZEC after it arrives.',
          ),
        ],
      ),
    );
  }
}

class _DarkInfoCard extends StatelessWidget {
  const _DarkInfoCard({required this.iconName, required this.text});

  final String iconName;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      key: const ValueKey('mobile_intro_info_card'),
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 175),
      decoration: BoxDecoration(
        color: colors.background.homeCard,
        borderRadius: BorderRadius.circular(AppRadii.large),
      ),
      foregroundDecoration: BoxDecoration(
        border: Border.all(color: const Color(0x26FFFFFF)),
        borderRadius: BorderRadius.circular(AppRadii.large),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) => Stack(
          children: [
            // Figma `Card Pattern` (8569:129370) overflows its 397×163
            // frame and is clipped by the card. Keep the complete SVG so
            // the outlines also continue through the bottom of the card.
            Positioned(
              top: -566.5,
              left: (constraints.maxWidth - 397) / 2 + 1 - 345.24,
              width: 1086.34,
              height: 1220.5,
              child: Opacity(
                opacity: 0.15,
                child: SvgPicture.asset(
                  'assets/illustrations/mobile_onboarding_intro_pattern.svg',
                  excludeFromSemantics: true,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.base,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppIcon(iconName, size: 24, color: colors.text.homeCard),
                  const SizedBox(height: AppSpacing.s),
                  Text(
                    text,
                    textAlign: TextAlign.center,
                    style: AppTypography.bodyMedium.copyWith(
                      color: colors.text.homeCard,
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
EdgeInsets _educationActionPadding(BuildContext context) => EdgeInsets.fromLTRB(
  16,
  12,
  16,
  48 - MediaQuery.paddingOf(context).bottom.clamp(0, 34),
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
                      AppTypography.bodyMedium.copyWith(
                        color: colors.text.primary,
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
