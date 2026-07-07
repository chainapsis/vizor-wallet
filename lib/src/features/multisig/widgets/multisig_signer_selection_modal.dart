import 'package:flutter/material.dart';

import '../../../core/layout/app_pane_scroll_scaffold.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../providers/multisig_signing_request_provider.dart';

class MultisigSignerSelectionModal extends StatelessWidget {
  const MultisigSignerSelectionModal({
    required this.loading,
    required this.draft,
    required this.selected,
    required this.submitting,
    required this.onRetry,
    required this.onToggleSigner,
    required this.onSubmit,
    required this.onCancel,
    this.error,
    super.key,
  });

  final bool loading;
  final MultisigSigningDraft? draft;
  final Set<String> selected;
  final bool submitting;
  final String? error;
  final VoidCallback onRetry;
  final void Function(String participantId, bool selected) onToggleSigner;
  final VoidCallback? onSubmit;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final draft = this.draft;
    final modalMaxHeight = (MediaQuery.sizeOf(context).height - 96)
        .clamp(420.0, 600.0)
        .toDouble();
    final selectedCount = selected.length;
    final threshold = draft?.threshold ?? 0;
    final isComplete = draft != null && selectedCount == threshold;
    final participants = draft == null
        ? const <MultisigSigningParticipant>[]
        : _orderedParticipants(draft);

    return Container(
      width: 440,
      constraints: BoxConstraints(maxHeight: modalMaxHeight),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.background.base,
        borderRadius: BorderRadius.circular(AppRadii.large),
        boxShadow: appSurfaceShadow(colors),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Choose signers',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodyLarge.copyWith(
                      color: colors.text.accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (draft != null) ...[
                  const SizedBox(width: AppSpacing.xs),
                  _SignerCountBadge(
                    label: '$selectedCount of $threshold',
                    complete: isComplete,
                  ),
                ],
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'You are always included. Every participant can review the transaction; only selected signers can approve it.',
              style: AppTypography.bodySmall.copyWith(
                color: colors.text.secondary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            if (loading && draft == null)
              const SizedBox(
                height: 160,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (draft == null)
              _MultisigModalError(
                error: error ?? 'Multisig signers could not be loaded.',
                onRetry: onRetry,
                onCancel: onCancel,
              )
            else
              Flexible(
                child: AppPaneScrollbar(
                  builder: (context, controller) => ListView.separated(
                    controller: controller,
                    primary: false,
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: participants.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppSpacing.xxs),
                    itemBuilder: (context, index) {
                      final participant = participants[index];
                      return _SignerChoiceRow(
                        participant: participant,
                        checked: selected.contains(participant.participantId),
                        locked:
                            participant.participantId ==
                            draft.material.participantId,
                        disabled: submitting,
                        onChanged: (value) =>
                            onToggleSigner(participant.participantId, value),
                      );
                    },
                  ),
                ),
              ),
            if (error != null && draft != null) ...[
              const SizedBox(height: AppSpacing.sm),
              _InlineError(message: error!),
            ],
            if (draft != null) ...[
              const SizedBox(height: AppSpacing.md),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  AppButton(
                    onPressed: submitting ? null : onCancel,
                    variant: AppButtonVariant.ghost,
                    size: AppButtonSize.medium,
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  AppButton(
                    key: const ValueKey('multisig_modal_send_request_button'),
                    onPressed: submitting ? null : onSubmit,
                    size: AppButtonSize.medium,
                    leading: submitting ? null : const AppIcon(AppIcons.users),
                    child: Text(submitting ? 'Creating...' : 'Send request'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<MultisigSigningParticipant> _orderedParticipants(
    MultisigSigningDraft draft,
  ) {
    final localParticipantId = draft.material.participantId;
    return [...draft.participants]..sort((a, b) {
      final rankA = _participantRank(a, localParticipantId);
      final rankB = _participantRank(b, localParticipantId);
      if (rankA != rankB) return rankA.compareTo(rankB);

      final nameOrder = a.displayName.toLowerCase().compareTo(
        b.displayName.toLowerCase(),
      );
      if (nameOrder != 0) return nameOrder;

      return a.participantId.compareTo(b.participantId);
    });
  }

  int _participantRank(
    MultisigSigningParticipant participant,
    String localParticipantId,
  ) {
    if (participant.participantId == localParticipantId) return 0;
    if (selected.contains(participant.participantId)) return 1;
    return 2;
  }
}

class _MultisigModalError extends StatelessWidget {
  const _MultisigModalError({
    required this.error,
    required this.onRetry,
    required this.onCancel,
  });

  final String error;
  final VoidCallback onRetry;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _InlineError(message: error),
        const SizedBox(height: AppSpacing.md),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            AppButton(
              onPressed: onCancel,
              variant: AppButtonVariant.ghost,
              size: AppButtonSize.medium,
              child: const Text('Cancel'),
            ),
            const SizedBox(width: AppSpacing.xs),
            AppButton(
              onPressed: onRetry,
              size: AppButtonSize.medium,
              child: const Text('Retry'),
            ),
          ],
        ),
      ],
    );
  }
}

class _SignerCountBadge extends StatelessWidget {
  const _SignerCountBadge({required this.label, required this.complete});

  final String label;
  final bool complete;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: complete
            ? colors.surface.input
            : colors.text.warning.withValues(alpha: 0.12),
        border: Border.all(
          color: complete
              ? colors.border.subtle
              : colors.text.warning.withValues(alpha: 0.36),
        ),
        borderRadius: BorderRadius.circular(AppRadii.full),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: AppSpacing.xxs,
        ),
        child: Text(
          label,
          style: AppTypography.labelMedium.copyWith(
            color: complete ? colors.text.primary : colors.text.warning,
          ),
        ),
      ),
    );
  }
}

class _SignerChoiceRow extends StatelessWidget {
  const _SignerChoiceRow({
    required this.participant,
    required this.checked,
    required this.locked,
    required this.disabled,
    required this.onChanged,
  });

  final MultisigSigningParticipant participant;
  final bool checked;
  final bool locked;
  final bool disabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final active = checked || locked;
    final canChange = !locked && !disabled;

    return Semantics(
      button: canChange,
      checked: checked,
      enabled: canChange,
      label: participant.displayName,
      child: MouseRegion(
        cursor: canChange ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: canChange ? () => onChanged(!checked) : null,
          child: Container(
            constraints: const BoxConstraints(minHeight: 52),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xs,
              vertical: AppSpacing.xxs,
            ),
            decoration: BoxDecoration(
              color: active
                  ? colors.surface.input
                  : colors.background.ground.withValues(alpha: 0),
              borderRadius: BorderRadius.circular(AppRadii.small),
            ),
            child: Row(
              children: [
                _SignerCheckMark(checked: checked, locked: locked),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        participant.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodyMediumStrong.copyWith(
                          color: disabled && !locked
                              ? colors.text.muted
                              : colors.text.accent,
                        ),
                      ),
                      Text(
                        locked
                            ? 'You, requester'
                            : participant.shortParticipantId,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodySmall.copyWith(
                          color: colors.text.secondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (locked)
                  const _RequiredBadge()
                else if (checked)
                  Text(
                    'Selected',
                    style: AppTypography.labelSmall.copyWith(
                      color: colors.text.secondary,
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

class _SignerCheckMark extends StatelessWidget {
  const _SignerCheckMark({required this.checked, required this.locked});

  final bool checked;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: checked ? colors.text.accent : colors.surface.input,
        border: Border.all(
          color: checked ? colors.text.accent : colors.border.regular,
        ),
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      child: checked
          ? Center(
              child: AppIcon(
                locked ? AppIcons.lock : AppIcons.check,
                size: 14,
                color: colors.background.ground,
              ),
            )
          : null,
    );
  }
}

class _RequiredBadge extends StatelessWidget {
  const _RequiredBadge();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface.input,
        border: Border.all(color: colors.border.subtle),
        borderRadius: BorderRadius.circular(AppRadii.full),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: AppSpacing.xxs,
        ),
        child: Text(
          'Required',
          style: AppTypography.labelSmall.copyWith(
            color: colors.text.secondary,
          ),
        ),
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppIcon(
          AppIcons.warning,
          size: AppIconSize.medium,
          color: colors.text.warning,
        ),
        const SizedBox(width: AppSpacing.xxs),
        Expanded(
          child: Text(
            message,
            style: AppTypography.bodySmall.copyWith(color: colors.text.warning),
          ),
        ),
      ],
    );
  }
}
