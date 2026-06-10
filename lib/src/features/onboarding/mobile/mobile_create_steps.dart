import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import 'mobile_onboarding_scaffold.dart';

/// Create-flow step ordering for the steps-nav progress track:
/// intro → address types → things to know → secret passphrase →
/// passcode.
const kMobileCreateStepCount = 5;

double mobileCreateProgress(int step) => step / kMobileCreateStepCount;

/// Step 1 — Figma `Onboarding 1 Intro` (4394:78213).
class MobileOnboardingIntroScreen extends StatelessWidget {
  const MobileOnboardingIntroScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return MobileOnboardingStepScaffold(
      progress: mobileCreateProgress(1),
      onBack: () => Navigator.of(context).maybePop(),
      title: 'The Shielded World',
      subtitle: 'Zcash (ZEC) built around financial privacy & self-custody.',
      bottomArea: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppButton(
            key: const ValueKey('mobile_intro_continue'),
            onPressed: () => context.push('/onboarding/address-types'),
            child: const Text('Tell me how Zcash works'),
          ),
          const SizedBox(height: AppSpacing.s),
          _TextLinkButton(
            key: const ValueKey('mobile_intro_skip'),
            label: 'I know how to use Zcash',
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
          const SizedBox(height: AppSpacing.md),
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

/// Step 2 — Figma `Onboarding 2 Address Type` (4394:81701).
class MobileAddressTypesScreen extends StatelessWidget {
  const MobileAddressTypesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return MobileOnboardingStepScaffold(
      progress: mobileCreateProgress(2),
      onBack: () => Navigator.of(context).maybePop(),
      title: 'Zcash Address Types',
      subtitle:
          'Zcash has two addresses types. One for Privacy, one for '
          'Transparency.',
      bottomArea: AppButton(
        key: const ValueKey('mobile_address_types_continue'),
        onPressed: () => context.push('/onboarding/things-to-know'),
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
            body:
                'Address starts with u1 (or zs for legacy). Only you can '
                'see your account balance and transaction history.',
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

/// Step 3 — Figma `Onboarding 3 Things to know` (4394:81851).
class MobileThingsToKnowScreen extends StatelessWidget {
  const MobileThingsToKnowScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return MobileOnboardingStepScaffold(
      progress: mobileCreateProgress(3),
      onBack: () => Navigator.of(context).maybePop(),
      title: 'Things to know',
      subtitle: 'Before you dive in.',
      bottomArea: AppButton(
        key: const ValueKey('mobile_things_to_know_continue'),
        onPressed: () => context.push('/onboarding/secret-passphrase'),
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
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: colors.background.homeCard,
        borderRadius: BorderRadius.circular(AppRadii.large),
      ),
      child: Column(
        children: [
          const SizedBox(height: AppSpacing.md),
          AppIcon(iconName, size: 28, color: colors.icon.brandCrimson),
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
  });

  final String iconName;
  final Color iconColor;
  final String title;
  final String body;
  final Widget? trailing;
}

class _SurfaceInfoCard extends StatelessWidget {
  const _SurfaceInfoCard({required this.sections});

  final List<_InfoSection> sections;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
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
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Container(height: 1, color: colors.border.subtle),
              ),
            Row(
              children: [
                AppIcon(
                  sections[i].iconName,
                  size: 22,
                  color: sections[i].iconColor,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    sections[i].title,
                    style: AppTypography.headlineSmall.copyWith(
                      color: colors.text.accent,
                    ),
                  ),
                ),
                if (sections[i].trailing != null) sections[i].trailing!,
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              sections[i].body,
              style: AppTypography.bodyMedium.copyWith(
                color: colors.text.primary,
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
    final prefixColor = emphasized
        ? colors.text.brandCrimson
        : colors.text.homeCard;
    final textColor = emphasized ? colors.text.homeCard : colors.text.primary;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      child: Text.rich(
        TextSpan(
          style: AppTypography.codeSmall,
          children: [
            TextSpan(
              text: prefix,
              style: TextStyle(
                color: prefixColor,
                backgroundColor: emphasized
                    ? colors.background.brandCrimsonStrong
                    : null,
              ),
            ),
            TextSpan(
              text: ' $sample',
              style: TextStyle(color: textColor),
            ),
          ],
        ),
      ),
    );
  }
}

class _TextLinkButton extends StatelessWidget {
  const _TextLinkButton({required this.label, required this.onTap, super.key});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          height: 44,
          child: Center(
            child: Text(
              label,
              style: AppTypography.labelLarge.copyWith(
                color: context.colors.text.primary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
