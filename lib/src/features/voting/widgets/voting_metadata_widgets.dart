import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../voting_choice_style.dart';
import '../voting_flow_models.dart';
import '../../../../l10n/app_localizations.dart';

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
    this.label,
    this.size = AppButtonSize.small,
    super.key,
  });

  final Uri uri;
  final String? label;
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
      child: Text(label ?? AppLocalizations.of(context).votingForumDiscussion),
    );
  }
}

class VotingProposalMetadataRow extends StatelessWidget {
  const VotingProposalMetadataRow({
    required this.zipBadges,
    required this.forumUri,
    this.forumLabel,
    this.trailing,
    super.key,
  });

  final List<String> zipBadges;
  final Uri? forumUri;
  final String? forumLabel;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final trailing = this.trailing;
    if (zipBadges.isEmpty && forumUri == null && trailing == null) {
      return const SizedBox.shrink();
    }
    if (trailing != null) {
      final metadata = [
        for (final badge in zipBadges) VotingMetadataBadge(badge),
        if (forumUri != null)
          VotingForumLinkButton(uri: forumUri!, label: forumLabel),
      ];
      if (metadata.isEmpty) {
        return Align(alignment: Alignment.centerRight, child: trailing);
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xxs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: metadata,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          trailing,
        ],
      );
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

class VotingProposalCard extends StatelessWidget {
  const VotingProposalCard({
    required this.proposal,
    this.selectedChoice,
    this.fallbackForumUri,
    this.enabled = true,
    this.readOnly = false,
    this.statusLabel,
    this.titleCollapsedMaxLines,
    this.onDisabledOptionTap,
    this.onChoice,
    super.key,
  });

  final VotingProposalView proposal;
  final int? selectedChoice;
  final Uri? fallbackForumUri;
  final bool enabled;
  final bool readOnly;
  final String? statusLabel;
  final int? titleCollapsedMaxLines;
  final VoidCallback? onDisabledOptionTap;
  final ValueChanged<int?>? onChoice;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final zipBadges = proposal.zipBadges;
    final forumUri = proposal.forumUri ?? fallbackForumUri;
    final statusLabel = this.statusLabel;
    final selectedChoice = this.selectedChoice;
    final missingSelectedOption =
        readOnly &&
            selectedChoice != null &&
            !proposal.options.any((option) => option.index == selectedChoice)
        ? VotingOptionView(
            index: selectedChoice,
            label: AppLocalizations.of(context).votingChoiceLabel(
              '$selectedChoice',
            ),
          )
        : null;
    final titleStyle = AppTypography.headlineSmall.copyWith(
      color: colors.text.accent,
      fontWeight: FontWeight.w600,
      height: 24 / 16,
      letterSpacing: 0,
    );
    final titleCollapsedMaxLines = this.titleCollapsedMaxLines;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: colors.background.ground,
        borderRadius: BorderRadius.circular(AppRadii.medium),
        border: Border.all(color: colors.border.subtle),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A231F20),
            offset: Offset(0, 1),
            blurRadius: 1,
            spreadRadius: -0.5,
          ),
          BoxShadow(
            color: Color(0x0A231F20),
            offset: Offset(0, 3),
            blurRadius: 3,
            spreadRadius: -1.5,
          ),
          BoxShadow(
            color: Color(0x0A231F20),
            offset: Offset(0, 24),
            blurRadius: 24,
            spreadRadius: -12,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (zipBadges.isNotEmpty ||
              forumUri != null ||
              statusLabel != null) ...[
            VotingProposalMetadataRow(
              zipBadges: zipBadges,
              forumUri: forumUri,
              trailing: statusLabel == null
                  ? null
                  : VotingMetadataBadge(statusLabel),
            ),
            const SizedBox(height: AppSpacing.s),
          ],
          if (titleCollapsedMaxLines == null)
            Text(proposal.title, style: titleStyle)
          else
            VotingExpandableText(
              text: proposal.title,
              style: titleStyle,
              collapsedMaxLines: titleCollapsedMaxLines,
            ),
          if (proposal.description.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              proposal.description.trim(),
              style: AppTypography.bodySmall.copyWith(
                color: colors.text.secondary,
                height: 16 / 12,
                letterSpacing: 0,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.s),
          for (final option in proposal.options) ...[
            _VotingProposalOptionRow(
              option: option,
              selected: selectedChoice == option.index,
              enabled: enabled,
              readOnly: readOnly,
              onDisabledTap: onDisabledOptionTap,
              onTap: () {
                final onChoice = this.onChoice;
                if (onChoice == null) return;
                onChoice(selectedChoice == option.index ? null : option.index);
              },
            ),
            if (option != proposal.options.last)
              const SizedBox(height: AppSpacing.xs),
          ],
          if (missingSelectedOption != null) ...[
            if (proposal.options.isNotEmpty)
              const SizedBox(height: AppSpacing.xs),
            _VotingProposalOptionRow(
              option: missingSelectedOption,
              selected: true,
              enabled: true,
              readOnly: true,
              onDisabledTap: null,
              onTap: () {},
            ),
          ],
        ],
      ),
    );
  }
}

class _VotingProposalOptionRow extends StatelessWidget {
  const _VotingProposalOptionRow({
    required this.option,
    required this.selected,
    required this.enabled,
    required this.readOnly,
    required this.onDisabledTap,
    required this.onTap,
  });

  final VotingOptionView option;
  final bool selected;
  final bool enabled;
  final bool readOnly;
  final VoidCallback? onDisabledTap;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final description = option.description.trim();
    final palette = votingChoicePalette(context, option.label);
    final interactive = enabled && !readOnly;
    final primaryTextColor = enabled || readOnly
        ? selected
              ? palette.text
              : colors.text.accent
        : colors.text.secondary.withValues(alpha: 0.56);
    final secondaryTextColor = enabled || readOnly
        ? selected
              ? palette.text.withValues(alpha: 0.82)
              : colors.text.secondary
        : colors.text.secondary.withValues(alpha: 0.48);
    final trailingLabel = selected
        ? AppLocalizations.of(context).votingSelected
        : readOnly
        ? null
        : AppLocalizations.of(context).votingChoose;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadii.small),
      onTap: interactive
          ? onTap
          : readOnly
          ? null
          : onDisabledTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: (enabled || readOnly) && selected
              ? palette.background
              : colors.background.neutralSubtleOpacity,
          borderRadius: BorderRadius.circular(AppRadii.small),
          border: Border.all(
            color: (enabled || readOnly) && selected
                ? palette.border
                : colors.border.subtle,
          ),
        ),
        child: Row(
          crossAxisAlignment: description.isEmpty
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    option.label,
                    style: AppTypography.labelLarge.copyWith(
                      color: primaryTextColor,
                    ),
                  ),
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      description,
                      style: AppTypography.bodySmall.copyWith(
                        color: secondaryTextColor,
                        height: 16 / 12,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailingLabel != null) ...[
              const SizedBox(width: AppSpacing.sm),
              Text(
                trailingLabel,
                style: AppTypography.bodySmall.copyWith(
                  color: (enabled || readOnly) && selected
                      ? palette.text
                      : secondaryTextColor,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class VotingExpandableText extends StatefulWidget {
  const VotingExpandableText({
    required this.text,
    required this.style,
    this.collapsedMaxLines = 2,
    super.key,
  });

  final String text;
  final TextStyle style;
  final int collapsedMaxLines;

  @override
  State<VotingExpandableText> createState() => _VotingExpandableTextState();
}

class _VotingExpandableTextState extends State<VotingExpandableText> {
  bool _expanded = false;

  @override
  void didUpdateWidget(covariant VotingExpandableText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        oldWidget.collapsedMaxLines != widget.collapsedMaxLines) {
      _expanded = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.text.trim();
    if (text.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final canExpand = _textExceedsMaxLines(
          context: context,
          text: text,
          style: widget.style,
          maxWidth: constraints.maxWidth,
          maxLines: widget.collapsedMaxLines,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              text,
              maxLines: _expanded || !canExpand
                  ? null
                  : widget.collapsedMaxLines,
              overflow: _expanded || !canExpand
                  ? TextOverflow.visible
                  : TextOverflow.ellipsis,
              style: widget.style,
            ),
            if (canExpand)
              Align(
                alignment: Alignment.centerRight,
                child: _VotingViewMoreButton(
                  expanded: _expanded,
                  onPressed: () {
                    setState(() {
                      _expanded = !_expanded;
                    });
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}

bool _textExceedsMaxLines({
  required BuildContext context,
  required String text,
  required TextStyle style,
  required double maxWidth,
  required int maxLines,
}) {
  if (!maxWidth.isFinite || maxWidth <= 0) return false;
  final textPainter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: maxLines,
  )..layout(maxWidth: maxWidth);
  return textPainter.didExceedMaxLines;
}

class _VotingViewMoreButton extends StatelessWidget {
  const _VotingViewMoreButton({
    required this.expanded,
    required this.onPressed,
  });

  final bool expanded;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onPressed,
      child: Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xxs),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              expanded ? AppLocalizations.of(context).votingViewLess : AppLocalizations.of(context).votingViewMore,
              style: AppTypography.bodyMediumStrong.copyWith(
                color: colors.text.accent,
                height: 20 / 14,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(width: AppSpacing.xxs),
            Transform.rotate(
              angle: expanded ? -1.5708 : 1.5708,
              child: AppIcon(
                AppIcons.chevronForward,
                size: 16,
                color: colors.icon.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
