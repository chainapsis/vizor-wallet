import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';

class VotingMetadataBadge extends StatelessWidget {
  const VotingMetadataBadge(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: colors.background.neutralSubtleOpacity,
        borderRadius: BorderRadius.circular(AppRadii.full),
        border: Border.all(color: colors.border.regular),
      ),
      child: Text(
        label,
        style: AppTypography.labelMedium.copyWith(
          color: colors.text.secondary,
          height: 16 / 12,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class VotingForumLinkButton extends StatelessWidget {
  const VotingForumLinkButton({
    required this.uri,
    this.label = 'Forum discussion',
    this.size = AppButtonSize.small,
    super.key,
  });

  final Uri uri;
  final String label;
  final AppButtonSize size;

  @override
  Widget build(BuildContext context) {
    return AppButton(
      onPressed: () {
        unawaited(launchUrl(uri, mode: LaunchMode.externalApplication));
      },
      variant: AppButtonVariant.ghost,
      size: size,
      leading: const AppIcon(AppIcons.link),
      child: Text(label),
    );
  }
}

class VotingProposalMetadataRow extends StatelessWidget {
  const VotingProposalMetadataRow({
    required this.zipBadges,
    required this.forumUri,
    this.forumLabel = 'Forum discussion',
    super.key,
  });

  final List<String> zipBadges;
  final Uri? forumUri;
  final String forumLabel;

  @override
  Widget build(BuildContext context) {
    if (zipBadges.isEmpty && forumUri == null) {
      return const SizedBox.shrink();
    }
    if (forumUri == null) {
      return Wrap(
        spacing: AppSpacing.xs,
        runSpacing: AppSpacing.xxs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [for (final badge in zipBadges) VotingMetadataBadge(badge)],
      );
    }
    if (zipBadges.isEmpty) {
      return Align(
        alignment: Alignment.centerRight,
        child: VotingForumLinkButton(uri: forumUri!, label: forumLabel),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xxs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final badge in zipBadges) VotingMetadataBadge(badge),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        VotingForumLinkButton(uri: forumUri!, label: forumLabel),
      ],
    );
  }
}
