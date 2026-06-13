import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';
import 'mobile_onboarding_scaffold.dart';

/// Second onboarding step — Figma `Method Selection` (4752:26334): the
/// "Welcome to Vizor" title over three illustrated cards (create /
/// import / Keystone), reached from the Welcome screen's "Get started"
/// button. Keeps the `mobile_welcome_*` keys so the onboarding flow
/// helpers route through here unchanged.
class MobileMethodSelectionScreen extends StatelessWidget {
  const MobileMethodSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MobileOnboardingStepScaffold(
      // First step, just before the create flow's step 1
      // (mobileCreateProgress(1) ≈ 0.167) so the track never moves back.
      progress: 0.15,
      onBack: () => context.pop(),
      title: 'Welcome to Vizor',
      subtitle: 'Select the method you want.',
      bottomArea: const _MethodLegalFooter(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _MethodCard(
            buttonKey: const ValueKey('mobile_welcome_create'),
            iconName: AppIcons.addNew,
            label: 'Create wallet',
            illustration: 'assets/illustrations/method_create_dark.png',
            // The create knight is taller than the card and bleeds above
            // its top edge in Figma (4752:26357).
            bleed: true,
            onTap: () => context.push('/onboarding/intro'),
          ),
          const SizedBox(height: AppSpacing.sm),
          _MethodCard(
            buttonKey: const ValueKey('mobile_welcome_import'),
            iconName: AppIcons.importWallet,
            label: 'Import wallet',
            illustration: 'assets/illustrations/method_import_dark.png',
            onTap: () => context.push('/import'),
          ),
          const SizedBox(height: AppSpacing.sm),
          _MethodCard(
            buttonKey: const ValueKey('mobile_welcome_keystone'),
            iconName: AppIcons.qr,
            label: 'Connect Keystone',
            illustration: 'assets/illustrations/method_keystone_dark.png',
            onTap: () => context.push('/onboarding/keystone'),
          ),
        ],
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
  });

  final Key buttonKey;
  final String iconName;
  final String label;
  final String illustration;
  final VoidCallback onTap;

  /// The create knight is rendered at 186×151 and bleeds 31px above the
  /// card; the masked import/Keystone art is 180×120 and stays inside the
  /// rounded card. Both assets are exact 3× of their target box so a
  /// BoxFit.fill is pixel-accurate.
  final bool bleed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // Figma `New Wallet Bg` 186×151 @ top -32.5; `Import/keystone card bg`
    // 180×120 @ top 0, both right-aligned.
    final art = Positioned(
      top: bleed ? -31 : 0,
      right: 0,
      width: bleed ? 186 : 180,
      height: bleed ? 151 : 120,
      child: Image.asset(illustration, fit: BoxFit.fill),
    );
    final content = Padding(
      // Figma insets the icon/label 14.5 from the card edge (~sm).
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppIcon(iconName, size: 20, color: colors.icon.accent),
          const Spacer(),
          Text(
            label,
            style: AppTypography.headlineMedium.copyWith(
              color: colors.text.accent,
            ),
          ),
        ],
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
          height: 120,
          // clipBehavior none lets the create knight bleed above the card;
          // expand keeps the rounded card filling the full 120 box.
          child: Stack(
            fit: StackFit.expand,
            clipBehavior: Clip.none,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadii.large),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: ColoredBox(color: colors.background.raised),
                    ),
                    if (!bleed) art,
                    content,
                  ],
                ),
              ),
              if (bleed) art,
            ],
          ),
        ),
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
    // The legal documents aren't ready yet, so Terms/Privacy render as
    // plain emphasised text — no links (product decision, 2026-06).
    final emphasis = AppTypography.bodySmall.copyWith(
      color: colors.text.secondary,
    );
    return Center(
      child: SizedBox(
        width: 200,
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
