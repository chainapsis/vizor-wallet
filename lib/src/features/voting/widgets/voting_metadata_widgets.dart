import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/layout/app_form_factor.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../voting_choice_style.dart';
import '../voting_flow_models.dart';

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
    this.trailing,
    super.key,
  });

  final List<String> zipBadges;
  final Uri? forumUri;
  final String forumLabel;
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
            label: 'Choice $selectedChoice',
          )
        : null;
    if (kAppFormFactor == AppFormFactor.mobile) {
      return _MobileVotingProposalCard(
        proposal: proposal,
        selectedChoice: selectedChoice,
        forumUri: forumUri,
        enabled: enabled,
        readOnly: readOnly,
        statusLabel: statusLabel,
        missingSelectedOption: missingSelectedOption,
        onDisabledOptionTap: onDisabledOptionTap,
        onChoice: onChoice,
      );
    }
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
              key: ValueKey(
                'voting_proposal_${proposal.id}_option_${option.index}',
              ),
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

class _MobileVotingProposalCard extends StatelessWidget {
  const _MobileVotingProposalCard({
    required this.proposal,
    required this.selectedChoice,
    required this.forumUri,
    required this.enabled,
    required this.readOnly,
    required this.statusLabel,
    required this.missingSelectedOption,
    required this.onDisabledOptionTap,
    required this.onChoice,
  });

  final VotingProposalView proposal;
  final int? selectedChoice;
  final Uri? forumUri;
  final bool enabled;
  final bool readOnly;
  final String? statusLabel;
  final VotingOptionView? missingSelectedOption;
  final VoidCallback? onDisabledOptionTap;
  final ValueChanged<int?>? onChoice;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final options = [...proposal.options, ?missingSelectedOption];
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: colors.background.ground,
        borderRadius: BorderRadius.circular(AppRadii.large),
        boxShadow: [
          BoxShadow(
            color: colors.shadows.subtle,
            offset: const Offset(0, 1),
            blurRadius: 2,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (proposal.zipBadges.isNotEmpty ||
              forumUri != null ||
              statusLabel != null) ...[
            _MobileProposalMetadata(
              zipBadges: proposal.zipBadges,
              forumUri: forumUri,
              statusLabel: statusLabel,
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
          Text(
            proposal.title,
            style: AppTypography.bodyMedium.copyWith(
              color: colors.text.accent,
              fontWeight: FontWeight.w600,
              height: 24 / 16,
              letterSpacing: -0.24,
            ),
          ),
          if (proposal.description.trim().isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              proposal.description.trim(),
              style: AppTypography.bodySmall.copyWith(
                color: colors.text.secondary,
                height: 21 / 14,
                letterSpacing: -0.21,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          for (var index = 0; index < options.length; index++) ...[
            _MobileVotingProposalOption(
              key: ValueKey(
                'voting_proposal_${proposal.id}_option_${options[index].index}',
              ),
              option: options[index],
              selected: selectedChoice == options[index].index,
              enabled: enabled,
              readOnly: readOnly,
              onDisabledTap: onDisabledOptionTap,
              onTap: () {
                final callback = onChoice;
                if (callback == null) return;
                callback(
                  selectedChoice == options[index].index
                      ? null
                      : options[index].index,
                );
              },
            ),
            if (index != options.length - 1)
              const SizedBox(height: AppSpacing.s),
          ],
        ],
      ),
    );
  }
}

class _MobileProposalMetadata extends StatelessWidget {
  const _MobileProposalMetadata({
    required this.zipBadges,
    required this.forumUri,
    required this.statusLabel,
  });

  final List<String> zipBadges;
  final Uri? forumUri;
  final String? statusLabel;

  @override
  Widget build(BuildContext context) {
    final metadataLabels = [...zipBadges, ?statusLabel];
    return SizedBox(
      height: forumUri == null ? 21 : 24,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  for (var index = 0; index < metadataLabels.length; index++)
                    TextSpan(
                      text:
                          '${index == 0 ? '' : '   '}${metadataLabels[index]}',
                      style: AppTypography.bodySmall.copyWith(
                        color: index < zipBadges.length
                            ? context.colors.text.primary
                            : context.colors.text.secondary,
                        height: 16 / 14,
                        letterSpacing: -0.06,
                      ),
                    ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (forumUri != null)
            VotingForumLinkButton(uri: forumUri!, size: AppButtonSize.small),
        ],
      ),
    );
  }
}

class _MobileVotingProposalOption extends StatelessWidget {
  const _MobileVotingProposalOption({
    super.key,
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
    final interactive = enabled && !readOnly;
    final description = option.description.trim();
    return Opacity(
      opacity: enabled || readOnly ? 1 : 0.56,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.medium),
        onTap: interactive
            ? onTap
            : readOnly
            ? null
            : onDisabledTap,
        child: Container(
          height: description.isEmpty ? 48 : 94,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: colors.background.base,
            borderRadius: BorderRadius.circular(AppRadii.medium),
            border: Border.all(
              color: selected ? colors.border.strong : Colors.transparent,
              width: 2,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      option.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodySmall.copyWith(
                        color: colors.text.accent,
                        fontWeight: FontWeight.w500,
                        height: 16 / 14,
                        letterSpacing: -0.06,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  SizedBox.square(
                    dimension: 20,
                    child: selected
                        ? AppIcon(
                            AppIcons.checkCircle,
                            key: const ValueKey(
                              'voting_selected_choice_indicator',
                            ),
                            size: 20,
                            color: colors.icon.accent,
                          )
                        : null,
                  ),
                ],
              ),
              if (description.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodySmall.copyWith(
                    color: colors.text.primary,
                    height: 21 / 14,
                    letterSpacing: -0.21,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _VotingProposalOptionRow extends StatelessWidget {
  const _VotingProposalOptionRow({
    super.key,
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
        ? 'Selected'
        : readOnly
        ? null
        : 'Choose';
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
                key: trailingLabel == 'Selected'
                    ? const ValueKey('voting_selected_choice_indicator')
                    : null,
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
    this.collapsedLabel = 'View more',
    this.expandedLabel = 'View less',
    this.buttonAlignment = Alignment.centerRight,
    this.showToggleWhenNotOverflowing = false,
    super.key,
  });

  final String text;
  final TextStyle style;
  final int collapsedMaxLines;
  final String collapsedLabel;
  final String expandedLabel;
  final AlignmentGeometry buttonAlignment;
  final bool showToggleWhenNotOverflowing;

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
        final showToggle = canExpand || widget.showToggleWhenNotOverflowing;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              text,
              maxLines: _expanded || !showToggle
                  ? null
                  : widget.collapsedMaxLines,
              overflow: _expanded || !showToggle
                  ? TextOverflow.visible
                  : TextOverflow.ellipsis,
              style: widget.style,
            ),
            if (showToggle)
              Align(
                alignment: widget.buttonAlignment,
                child: _VotingViewMoreButton(
                  expanded: _expanded,
                  collapsedLabel: widget.collapsedLabel,
                  expandedLabel: widget.expandedLabel,
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
    required this.collapsedLabel,
    required this.expandedLabel,
    required this.onPressed,
  });

  final bool expanded;
  final String collapsedLabel;
  final String expandedLabel;
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
              expanded ? expandedLabel : collapsedLabel,
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
