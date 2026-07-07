import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';

const double _methodCardHeight = 90;
const double _methodSelectionProgress = 60 / 196;

/// Second onboarding step — Figma `Method Selection` (4752:26334): the
/// "Welcome to Vizor" title over four illustrated cards (create /
/// import / desktop link / Keystone), reached from the Welcome screen's "Get started"
/// button. Keeps the `mobile_welcome_*` keys so the onboarding flow
/// helpers route through here unchanged.
///
/// Unlike the scrolling step scaffold, the Figma frame starts the content
/// 24px below the steps nav, then lays out the title block, a 32px gap, and
/// four method cards. The legal line in the Figma frame is intentionally not
/// rendered until the legal documents are ready.
class MobileMethodSelectionScreen extends StatelessWidget {
  const MobileMethodSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.background.window,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Welcome has no track, so method selection is the first visible
            // fill after one completed create-flow screen.
            MobileTopNav.steps(
              progress: _methodSelectionProgress,
              onBack: () => context.pop(),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.sm,
                  AppSpacing.md,
                  AppSpacing.sm,
                  AppSpacing.md,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
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
                    const SizedBox(height: AppSpacing.base),
                    _MethodCard(
                      buttonKey: const ValueKey('mobile_welcome_create'),
                      iconName: AppIcons.addNew,
                      label: 'Create Wallet',
                      illustration:
                          'assets/illustrations/method_create_card_bg.png',
                      onTap: () => context.push('/onboarding/intro'),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    _MethodCard(
                      buttonKey: const ValueKey('mobile_welcome_import'),
                      iconName: AppIcons.importWallet,
                      label: 'Import Wallet',
                      illustration:
                          'assets/illustrations/method_import_card_bg.png',
                      onTap: () => context.push('/import'),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    _MethodCard(
                      buttonKey: const ValueKey('mobile_welcome_link_desktop'),
                      iconName: AppIcons.monitor,
                      label: 'Link Vizor Desktop',
                      illustration:
                          'assets/illustrations/method_link_desktop_card_bg.png',
                      onTap: () => context.push('/onboarding/link-desktop'),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    _MethodCard(
                      buttonKey: const ValueKey('mobile_welcome_keystone'),
                      iconName: AppIcons.qr,
                      label: 'Connect Keystone',
                      illustration:
                          'assets/illustrations/method_keystone_card_bg.png',
                      onTap: () => context.push('/onboarding/keystone'),
                    ),
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
  });

  final Key buttonKey;
  final String iconName;
  final String label;
  final String illustration;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final cardRadius = BorderRadius.circular(AppRadii.large);
    final keySuffix = label.toLowerCase().replaceAll(' ', '_');
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
          child: Stack(
            fit: StackFit.expand,
            clipBehavior: Clip.hardEdge,
            children: [
              ClipRRect(
                borderRadius: cardRadius,
                child: DecoratedBox(
                  decoration: BoxDecoration(color: colors.background.homeCard),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.asset(
                        illustration,
                        key: ValueKey('mobile_method_${keySuffix}_art'),
                        fit: BoxFit.cover,
                        alignment: Alignment.centerRight,
                      ),
                    ],
                  ),
                ),
              ),
              _MethodCardContent(
                key: ValueKey('mobile_method_${keySuffix}_content'),
                iconName: iconName,
                label: label,
                color: colors.text.homeCard,
              ),
            ],
          ),
        ),
      ),
    );
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
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          AppIcon(iconName, size: 24, color: color),
          const SizedBox(width: 20),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.bodyMediumStrong.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
