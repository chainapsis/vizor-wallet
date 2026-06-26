import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../main.dart' show log;
import '../../../core/formatting/zec_amount.dart';
import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_layout.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_back_link.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../providers/multisig_operation_error.dart';
import '../../../providers/multisig_signing_request_provider.dart';
import '../../../rust/api/sync.dart' as rust_sync;
import '../../send/screens/send_review_screen.dart';

class MultisigSigningRequestScreen extends ConsumerStatefulWidget {
  const MultisigSigningRequestScreen({required this.args, super.key});

  final SendReviewArgs args;

  @override
  ConsumerState<MultisigSigningRequestScreen> createState() =>
      _MultisigSigningRequestScreenState();
}

class _MultisigSigningRequestScreenState
    extends ConsumerState<MultisigSigningRequestScreen> {
  MultisigSigningDraft? _draft;
  final Set<String> _selected = <String>{};
  bool _loading = true;
  bool _submitting = false;
  bool _proposalReleased = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(appLayoutProvider.notifier).setMode(AppLayoutMode.large);
    });
    unawaited(_loadDraft());
  }

  @override
  void dispose() {
    if (!_proposalReleased) {
      _proposalReleased = true;
      unawaited(
        rust_sync.discardProposal(
          proposalId: widget.args.proposalId,
          sendFlowId: widget.args.sendFlowId,
        ),
      );
    }
    super.dispose();
  }

  Future<void> _loadDraft() async {
    try {
      final draft = await ref
          .read(multisigSigningRequestsProvider.notifier)
          .loadDraft(widget.args.proposalAccountUuid);
      if (!mounted) return;
      setState(() {
        _draft = draft;
        _loading = false;
        _error = null;
      });
      _selectDefaultSigners(draft);
    } catch (e, st) {
      log('MultisigSigningRequestScreen.loadDraft: ERROR: $e\n$st');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = friendlyMultisigError(e);
      });
    }
  }

  void _selectDefaultSigners(MultisigSigningDraft draft) {
    if (_selected.isNotEmpty) return;
    final localParticipantId = draft.material.participantId;
    final next = <String>{localParticipantId};
    for (final participant in draft.participants) {
      if (next.length >= draft.threshold) break;
      next.add(participant.participantId);
    }
    setState(() {
      _selected
        ..clear()
        ..addAll(next);
    });
  }

  void _toggleSigner(String participantId, bool selected) {
    final draft = _draft;
    if (draft == null || _submitting) return;
    if (participantId == draft.material.participantId) return;

    setState(() {
      _error = null;
      if (selected) {
        if (_selected.length >= draft.threshold) {
          _error = 'Select exactly ${draft.threshold} signers.';
          return;
        }
        _selected.add(participantId);
      } else {
        _selected.remove(participantId);
      }
    });
  }

  Future<void> _submit() async {
    final draft = _draft;
    if (draft == null || _submitting) return;
    if (!_selected.contains(draft.material.participantId)) {
      setState(() {
        _error = 'Requester must be included.';
      });
      return;
    }
    if (_selected.length != draft.threshold) {
      setState(() {
        _error = 'Select exactly ${draft.threshold} signers.';
      });
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    _proposalReleased = true;
    try {
      await ref
          .read(multisigSigningRequestsProvider.notifier)
          .createRequest(
            accountUuid: widget.args.proposalAccountUuid,
            proposalId: widget.args.proposalId,
            sendFlowId: widget.args.sendFlowId,
            recipientAddress: widget.args.address,
            addressType: widget.args.addressType,
            amountZatoshi: widget.args.amountZatoshi,
            feeZatoshi: widget.args.feeZatoshi,
            selectedParticipantIds: _selected.toList()..sort(),
            needsSaplingParams: widget.args.needsSaplingParams,
            memo: widget.args.memo,
          );
      if (!mounted) return;
      context.go('/multisig');
    } catch (e, st) {
      log('MultisigSigningRequestScreen.submit: ERROR: $e\n$st');
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = friendlyMultisigError(e);
      });
    }
  }

  Future<void> _releaseProposalBeforeNavigate() async {
    if (_proposalReleased) return;
    _proposalReleased = true;
    await rust_sync.discardProposal(
      proposalId: widget.args.proposalId,
      sendFlowId: widget.args.sendFlowId,
    );
  }

  Future<void> _cancel() async {
    await _releaseProposalBeforeNavigate();
    if (!mounted) return;
    context.go('/send');
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final draft = _draft;

    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        padding: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppRouteBackLink(
                onBeforeNavigate: _releaseProposalBeforeNavigate,
              ),
              const Spacer(),
              Center(
                child: SizedBox(
                  width: 720,
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null && draft == null
                      ? _ErrorCard(error: _error!, onRetry: _loadDraft)
                      : _RequestCard(
                          args: widget.args,
                          draft: draft!,
                          selected: _selected,
                          error: _error,
                          submitting: _submitting,
                          onToggleSigner: _toggleSigner,
                          onSubmit: _selected.length == draft.threshold
                              ? _submit
                              : null,
                          onCancel: () => unawaited(_cancel()),
                        ),
                ),
              ),
              const Spacer(),
              Text(
                'The requester is always included. Every participant can review the transaction; only selected signers can sign.',
                style: AppTypography.labelMedium.copyWith(
                  color: colors.text.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({
    required this.args,
    required this.draft,
    required this.selected,
    required this.submitting,
    required this.onToggleSigner,
    required this.onSubmit,
    required this.onCancel,
    this.error,
  });

  final SendReviewArgs args;
  final MultisigSigningDraft draft;
  final Set<String> selected;
  final bool submitting;
  final String? error;
  final void Function(String participantId, bool selected) onToggleSigner;
  final VoidCallback? onSubmit;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final amount = ZecAmount.fromZatoshi(args.amountZatoshi).receipt;
    final fee = ZecAmount.fromZatoshi(args.feeZatoshi).fee;
    final localParticipantId = draft.material.participantId;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface.card,
        border: Border.all(color: colors.border.subtle),
        borderRadius: BorderRadius.circular(AppRadii.medium),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const AppIcon(AppIcons.users, size: AppIconSize.large),
                const SizedBox(width: AppSpacing.xs),
                Text('Request signatures', style: AppTypography.headlineMedium),
                const Spacer(),
                Text(
                  '${selected.length} of ${draft.threshold}',
                  style: AppTypography.labelLarge.copyWith(
                    color: selected.length == draft.threshold
                        ? colors.text.primary
                        : colors.text.warning,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: _SummaryTile(
                    label: 'Amount',
                    value: amount.toString(),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: _SummaryTile(label: 'Fee', value: fee.toString()),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            _SummaryTile(label: 'Recipient', value: args.address),
            const SizedBox(height: AppSpacing.lg),
            Text('Signers', style: AppTypography.labelLarge),
            const SizedBox(height: AppSpacing.xs),
            for (final participant in draft.participants)
              _SignerRow(
                participant: participant,
                checked: selected.contains(participant.participantId),
                locked: participant.participantId == localParticipantId,
                onChanged: (value) =>
                    onToggleSigner(participant.participantId, value ?? false),
              ),
            if (error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                error!,
                style: AppTypography.labelMedium.copyWith(
                  color: colors.text.warning,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                AppButton(
                  onPressed: submitting ? null : onCancel,
                  variant: AppButtonVariant.secondary,
                  child: const Text('Cancel'),
                ),
                const Spacer(),
                AppButton(
                  onPressed: submitting ? null : onSubmit,
                  leading: submitting
                      ? null
                      : AppIcon(
                          AppIcons.sync,
                          color: colors.button.primary.label,
                        ),
                  child: Text(
                    submitting ? 'Creating request...' : 'Request signatures',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface.input,
        border: Border.all(color: colors.border.subtle),
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: AppTypography.labelMedium.copyWith(
                color: colors.text.secondary,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.labelLarge,
            ),
          ],
        ),
      ),
    );
  }
}

class _SignerRow extends StatelessWidget {
  const _SignerRow({
    required this.participant,
    required this.checked,
    required this.locked,
    required this.onChanged,
  });

  final MultisigSigningParticipant participant;
  final bool checked;
  final bool locked;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: checked ? colors.surface.input : colors.surface.card,
          border: Border.all(color: colors.border.subtle),
          borderRadius: BorderRadius.circular(AppRadii.xSmall),
        ),
        child: CheckboxListTile(
          value: checked,
          onChanged: locked ? null : onChanged,
          controlAffinity: ListTileControlAffinity.leading,
          dense: true,
          title: Text(participant.displayName, style: AppTypography.labelLarge),
          subtitle: Text(
            locked ? 'You, requester' : participant.shortParticipantId,
            style: AppTypography.labelMedium.copyWith(
              color: colors.text.secondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface.card,
        border: Border.all(color: colors.border.subtle),
        borderRadius: BorderRadius.circular(AppRadii.medium),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Cannot prepare request', style: AppTypography.headlineMedium),
            const SizedBox(height: AppSpacing.sm),
            Text(
              error,
              style: AppTypography.labelMedium.copyWith(
                color: colors.text.secondary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            AppButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
