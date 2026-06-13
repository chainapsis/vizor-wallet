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
      // Earliest step in the flow, so the track is barely filled.
      progress: 0.12,
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
            label: 'Create a wallet',
            illustration: 'assets/illustrations/method_create_dark.png',
            onTap: () => context.push('/onboarding/intro'),
          ),
          const SizedBox(height: AppSpacing.base),
          _MethodCard(
            buttonKey: const ValueKey('mobile_welcome_import'),
            iconName: AppIcons.importWallet,
            label: 'Import a wallet',
            illustration: 'assets/illustrations/method_import_dark.png',
            onTap: () => context.push('/import'),
          ),
          const SizedBox(height: AppSpacing.base),
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
  });

  final Key buttonKey;
  final String iconName;
  final String label;
  final String illustration;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
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
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.large),
            child: Stack(
              children: [
                Positioned.fill(
                  child: ColoredBox(color: colors.background.ground),
                ),
                // Right-aligned card art (Figma bleeds it toward the
                // right edge); the masked import/Keystone PNGs already
                // carry their own dark backdrop, the create knight is
                // transparent over the card colour.
                Positioned(
                  top: 0,
                  bottom: 0,
                  right: 0,
                  child: Image.asset(
                    illustration,
                    fit: BoxFit.fitHeight,
                    alignment: Alignment.centerRight,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.base),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppIcon(iconName, size: 20, color: colors.icon.accent),
                      const Spacer(),
                      Text(
                        label,
                        style: AppTypography.headlineSmall.copyWith(
                          color: colors.text.accent,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
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
