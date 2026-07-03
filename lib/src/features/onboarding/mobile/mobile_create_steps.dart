import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import 'mobile_onboarding_progress.dart';
import 'mobile_onboarding_scaffold.dart';

/// Step 3 — Figma `Onboarding 1 Intro` (4394:78213).
class MobileOnboardingIntroScreen extends StatelessWidget {
  const MobileOnboardingIntroScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return MobileOnboardingStepScaffold(
      progress: mobileCreateProgress(3),
      onBack: () => Navigator.of(context).maybePop(),
      title: 'The Shielded World',
      // Line break matches the Figma subtitle wrap.
      subtitle: 'Zcash (ZEC) built around financial\nprivacy & self-custody.',
      bottomArea: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppButton(
            key: const ValueKey('mobile_intro_continue'),
            expand: true,
            onPressed: () => context.push('/onboarding/address-types'),
            trailing: const AppIcon(AppIcons.chevronForward),
            child: const Text('Tell me how Zcash works'),
          ),
          const SizedBox(height: AppSpacing.s),
          _TextLinkButton(
            key: const ValueKey('mobile_intro_skip'),
            label: 'I know how to use Zcash',
            trailingIconName: AppIcons.skip,
            onTap: () => context.push('/onboarding/secret-passphrase'),
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
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Text(
              "You're a few steps away from your first private wallet. "
              "Let's get you set up.",
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(
                color: colors.text.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Step 4 — Figma `Onboarding 2 Address Type` (4394:81701).
class MobileAddressTypesScreen extends StatelessWidget {
  const MobileAddressTypesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return MobileOnboardingStepScaffold(
      progress: mobileCreateProgress(4),
      onBack: () => Navigator.of(context).maybePop(),
      title: 'Zcash Address Types',
      // Line break matches the Figma subtitle wrap.
      subtitle:
          'Zcash has two addresses types.\nOne for Privacy, one for Transparency.',
      bottomArea: AppButton(
        key: const ValueKey('mobile_address_types_continue'),
        expand: true,
        onPressed: () => context.push('/onboarding/things-to-know'),
        trailing: const AppIcon(AppIcons.chevronForward),
        child: const Text('Continue'),
      ),
      child: _SurfaceInfoCard(
        sections: [
          _InfoSection(
            iconName: AppIcons.shieldKeyhole,
            iconColor: colors.icon.brandCrimson,
            title: 'Shielded Address',
            trailing: const _AddressChip(
              prefix: 'u1',
              sample: 'vt42...',
              emphasized: true,
            ),
            // Line break after "legacy)." matches the frame's wrap.
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

/// Step 5 — Figma `Onboarding 3 Things to know` (4394:81851).
class MobileThingsToKnowScreen extends StatelessWidget {
  const MobileThingsToKnowScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return MobileOnboardingStepScaffold(
      progress: mobileCreateProgress(5),
      onBack: () => Navigator.of(context).maybePop(),
      title: 'Things to know',
      subtitle: 'Before you dive in.',
      bottomArea: AppButton(
        key: const ValueKey('mobile_things_to_know_continue'),
        expand: true,
        onPressed: () => context.push('/onboarding/secret-passphrase'),
        trailing: const AppIcon(AppIcons.chevronForward),
        child: const Text('Continue'),
      ),
      child: _SurfaceInfoCard(
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
            iconName: AppIcons.shieldKeyhole,
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
      width: double.infinity,
      decoration: BoxDecoration(
        color: colors.background.homeCard,
        borderRadius: BorderRadius.circular(AppRadii.large),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Figma `Card Pattern` (4394:81168): concentric shield
          // outlines at ~4% alpha behind the card content.
          Positioned.fill(
            child: Image.asset(
              'assets/illustrations/onboarding_card_pattern.png',
              fit: BoxFit.cover,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Column(
              children: [
                const SizedBox(height: AppSpacing.md),
                AppIcon(iconName, size: 28, color: colors.text.homeCard),
                const SizedBox(height: AppSpacing.md),
                Text(
                  text,
                  textAlign: TextAlign.center,
                  style: AppTypography.bodyMedium.copyWith(
                    color: colors.text.homeCard,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
              ],
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

class _SurfaceInfoCard extends StatelessWidget {
  const _SurfaceInfoCard({required this.sections});

  final List<_InfoSection> sections;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // Figma `Main` card (4394:81701): 20 px side / 44 px vertical
    // padding, 16 between a section title and its body, and 36 on each
    // side of the divider.
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 44),
      decoration: BoxDecoration(
        color: colors.background.ground,
        borderRadius: BorderRadius.circular(AppRadii.large),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < sections.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 36),
                child: Container(height: 1, color: colors.border.subtle),
              ),
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
                    ),
                  ),
                ),
                if (sections[i].trailing != null) sections[i].trailing!,
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text.rich(
              sections[i].bodySpan(
                AppTypography.bodyMedium.copyWith(color: colors.text.primary),
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
        ? colors.background.homeCard
        : colors.background.raised;
    // The prefix sits on its own little badge — crimson for the shielded
    // chip, dark for the transparent chip — with white prefix text, per
    // the Figma address-type chips.
    final badgeBg = emphasized
        ? colors.background.brandCrimsonStrong
        : colors.background.homeCard;
    final textColor = emphasized ? colors.text.homeCard : colors.text.primary;
    // Figma `Card Top` chip: 37 px pill, Code M address, 8 px inset.
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
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
                color: colors.text.homeCard,
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

class _TextLinkButton extends StatelessWidget {
  const _TextLinkButton({
    required this.label,
    required this.onTap,
    this.trailingIconName,
    super.key,
  });

  final String label;
  final VoidCallback onTap;
  final String? trailingIconName;

  @override
  Widget build(BuildContext context) {
    final color = context.colors.text.primary;
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          height: 44,
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: AppTypography.labelLarge.copyWith(color: color),
                ),
                if (trailingIconName != null) ...[
                  const SizedBox(width: AppSpacing.xs),
                  AppIcon(trailingIconName!, size: 18, color: color),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
