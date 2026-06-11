import 'dart:async';

import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/config/app_version_config.dart';
import '../../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/mobile/mobile_surface_card.dart';
import '../../../onboarding/shared/onboarding_welcome_art.dart'
    show VizorWordmark;
import '../../about_content.dart';

/// Mobile About — Figma `About` (4654:55218): wordmark, version line,
/// the shared paragraphs on a surface card, and the Github / Website
/// links. Copy comes from `about_content.dart` (shared with desktop).
class MobileAboutScreen extends StatelessWidget {
  const MobileAboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.background.window,
      body: SafeArea(
        child: Column(
          children: [
            MobileTopNav.back(
              title: 'About Vizor Wallet',
              onBack: () => context.pop(),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.sm,
                  AppSpacing.s,
                  AppSpacing.sm,
                  AppSpacing.lg,
                ),
                children: [
                  Center(
                    child: VizorWordmark(
                      width: 74,
                      height: 28,
                      color: colors.text.muted,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    kVizorAboutVersionLabel,
                    textAlign: TextAlign.center,
                    style: AppTypography.bodyMedium.copyWith(
                      color: colors.text.secondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const _ParagraphCard(paragraphs: kAboutParagraphs),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _LinkButton(
                        label: 'Github',
                        iconName: AppIcons.link,
                        url: kVizorGithubUrl,
                      ),
                      const SizedBox(width: AppSpacing.md),
                      _LinkButton(
                        label: 'Website',
                        iconName: AppIcons.endpoint,
                        url: kVizorWebsiteUrl,
                      ),
                    ],
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

/// Mobile Terms / Privacy — Figma `Terms / Privacy` (4654:55485):
/// version subtitle and the shared legal placeholder paragraphs.
class MobileLegalScreen extends StatelessWidget {
  const MobileLegalScreen({required this.title, super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.background.window,
      body: SafeArea(
        child: Column(
          children: [
            MobileTopNav.back(title: title, onBack: () => context.pop()),
            const SizedBox(height: AppSpacing.xs),
            Text(
              kVizorAboutVersionLabel,
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(
                color: colors.text.secondary,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.sm,
                  0,
                  AppSpacing.sm,
                  AppSpacing.lg,
                ),
                children: const [_ParagraphCard(paragraphs: kLegalParagraphs)],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ParagraphCard extends StatelessWidget {
  const _ParagraphCard({required this.paragraphs});

  final List<AboutParagraph> paragraphs;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return MobileSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < paragraphs.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.md),
            Text(
              paragraphs[i].heading,
              style: AppTypography.bodyMediumStrong.copyWith(
                color: colors.text.accent,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              paragraphs[i].body,
              style: AppTypography.bodyMedium.copyWith(
                color: colors.text.secondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LinkButton extends StatelessWidget {
  const _LinkButton({
    required this.label,
    required this.iconName,
    required this.url,
  });

  final String label;
  final String iconName;
  final String url;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      link: true,
      label: '$label link',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => unawaited(launchAboutUrl(url)),
        child: SizedBox(
          height: 44,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(iconName, size: AppIconSize.medium,
                  color: colors.icon.accent),
              const SizedBox(width: AppSpacing.xxs),
              Text(
                label,
                style: AppTypography.labelLarge.copyWith(
                  color: colors.text.accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
