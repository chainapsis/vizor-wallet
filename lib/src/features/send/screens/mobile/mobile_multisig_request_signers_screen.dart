import 'dart:async';

import 'package:flutter/material.dart' show CircularProgressIndicator, Scaffold;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../main.dart' show log;
import '../../../../core/formatting/address_display.dart';
import '../../../../core/formatting/zec_amount.dart';
import '../../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../../core/storage/wallet_paths.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/app_profile_picture.dart';
import '../../../../core/widgets/mobile/mobile_review_row.dart';
import '../../../../core/widgets/mobile/mobile_surface_card.dart';
import '../../../../providers/multisig_operation_error.dart';
import '../../../../providers/multisig_signing_request_provider.dart';
import '../../../../providers/zec_price_change_provider.dart';
import '../../services/send_flow.dart';

class MobileMultisigRequestSignersArgs {
  const MobileMultisigRequestSignersArgs({
    required this.accountUuid,
    required this.sendFlowId,
    required this.recipient,
    required this.addressType,
    required this.amountText,
    this.feeZatoshi,
    this.memo,
    this.contactLabel,
    this.contactPictureId,
  });

  final String accountUuid;
  final String sendFlowId;
  final String recipient;
  final String addressType;
  final String amountText;
  final BigInt? feeZatoshi;
  final String? memo;
  final String? contactLabel;
  final String? contactPictureId;

  bool get isShielded => addressType == 'unified' || addressType == 'sapling';
}

class MobileMultisigRequestSignersScreen extends ConsumerStatefulWidget {
  const MobileMultisigRequestSignersScreen({
    required this.args,
    this.loadWalletDbPath = getWalletDbPath,
    super.key,
  });

  final MobileMultisigRequestSignersArgs args;
  final Future<String> Function() loadWalletDbPath;

  @override
  ConsumerState<MobileMultisigRequestSignersScreen> createState() =>
      _MobileMultisigRequestSignersScreenState();
}

class _MobileMultisigRequestSignersScreenState
    extends ConsumerState<MobileMultisigRequestSignersScreen> {
  MultisigSigningDraft? _draft;
  final Set<String> _selected = <String>{};
  var _loading = true;
  var _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_loadDraft());
    });
  }

  bool get _canPop => !_submitting;

  Future<void> _loadDraft() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final draft = await ref
          .read(multisigSigningRequestsProvider.notifier)
          .loadDraft(widget.args.accountUuid);
      if (!mounted) return;
      setState(() {
        _draft = draft;
        _selected
          ..clear()
          ..addAll(_defaultSigners(draft));
        _loading = false;
      });
    } catch (e, st) {
      log('MobileMultisigRequestSigners.loadDraft: ERROR: $e\n$st');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = friendlyMultisigError(e);
      });
    }
  }

  Set<String> _defaultSigners(MultisigSigningDraft draft) {
    final selected = <String>{draft.material.participantId};
    for (final participant in _orderedParticipants(draft)) {
      if (selected.length >= draft.threshold) break;
      selected.add(participant.participantId);
    }
    return selected;
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
    if (_selected.contains(participant.participantId)) return 1;
    return 2;
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
      setState(() => _error = 'Requester must be included.');
      return;
    }
    if (_selected.length != draft.threshold) {
      setState(() => _error = 'Select exactly ${draft.threshold} signers.');
      return;
    }

    final amountZatoshi = parseZecAmount(widget.args.amountText.trim());
    if (amountZatoshi == null || amountZatoshi <= BigInt.zero) {
      setState(() => _error = 'Enter a valid amount.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    SendReviewArgs? proposalArgs;
    try {
      proposalArgs = await proposeSendTransfer(
        ref: ref,
        loadDbPath: widget.loadWalletDbPath,
        accountUuid: widget.args.accountUuid,
        sendFlowId: widget.args.sendFlowId,
        address: widget.args.recipient,
        addressType: widget.args.addressType,
        amountZatoshi: amountZatoshi,
        memo: widget.args.memo,
      );
      if (!mounted) {
        unawaited(
          discardSendProposal(
            proposalId: proposalArgs.proposalId,
            sendFlowId: proposalArgs.sendFlowId,
            logContext: 'MobileMultisigRequestSigners(unmounted)',
          ),
        );
        return;
      }

      final record = await ref
          .read(multisigSigningRequestsProvider.notifier)
          .createRequest(
            accountUuid: widget.args.accountUuid,
            proposalId: proposalArgs.proposalId,
            sendFlowId: proposalArgs.sendFlowId,
            recipientAddress: proposalArgs.address,
            addressType: proposalArgs.addressType,
            amountZatoshi: proposalArgs.amountZatoshi,
            feeZatoshi: proposalArgs.feeZatoshi,
            selectedParticipantIds: _selected.toList()..sort(),
            needsSaplingParams: proposalArgs.needsSaplingParams,
            memo: proposalArgs.memo,
          );
      if (!mounted) return;
      context.go(
        '/multisig/sign/${Uri.encodeComponent(record.signingRequestId)}',
      );
    } catch (e, st) {
      log('MobileMultisigRequestSigners.submit: ERROR: $e\n$st');
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = friendlyMultisigError(e);
      });
    }
  }

  void _handleBack() {
    if (!_canPop) return;
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go('/send');
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final draft = _draft;
    final selectedCount = _selected.length;
    final threshold = draft?.threshold ?? 0;
    final amountZatoshi = parseZecAmount(widget.args.amountText.trim());
    final amountText = amountZatoshi == null
        ? '${widget.args.amountText} ZEC'
        : ZecAmount.fromZatoshi(amountZatoshi).activityDetail.toString();
    final amountFiatText = amountZatoshi == null
        ? null
        : fiatTextForZatoshi(
            amountZatoshi,
            zecUsdUnitPrice: ref.watch(zecHomeUsdUnitPriceProvider),
          );
    final feeText = widget.args.feeZatoshi == null
        ? 'Calculated at request'
        : ZecAmount.fromZatoshi(widget.args.feeZatoshi!).fee.toString();
    final participants = draft == null
        ? const <MultisigSigningParticipant>[]
        : _orderedParticipants(draft);
    final submitEnabled =
        draft != null && selectedCount == threshold && !_submitting;

    return PopScope<void>(
      canPop: _canPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        backgroundColor: colors.background.window,
        body: SafeArea(
          child: Column(
            children: [
              MobileTopNav.back(
                title: 'Request signatures',
                onBack: _handleBack,
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.sm,
                    AppSpacing.s,
                    AppSpacing.sm,
                    AppSpacing.xl2,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Choose who will approve this send. You are always included.',
                        style: AppTypography.bodyMedium.copyWith(
                          color: colors.text.secondary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      MobileSurfaceCard(
                        child: Column(
                          children: [
                            MobileReviewInfoRow(
                              label: 'Amount',
                              value: amountText,
                              leading: const MobileReviewZecBadge(),
                              bottom: amountFiatText == null
                                  ? null
                                  : Text(
                                      amountFiatText,
                                      style: AppTypography.labelMedium.copyWith(
                                        color: colors.text.secondary,
                                      ),
                                    ),
                            ),
                            const MobileReviewFlowArrow(),
                            MobileReviewInfoRow(
                              label: 'To',
                              value:
                                  widget.args.contactLabel ??
                                  truncatedAddress(widget.args.recipient),
                              leading: _RecipientLeading(
                                profilePictureId: widget.args.contactPictureId,
                              ),
                              bottom: Text(
                                _recipientBottomLabel(widget.args),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.labelMedium.copyWith(
                                  color: colors.text.secondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.base),
                      _SignersSection(
                        loading: _loading,
                        error: _error,
                        draft: draft,
                        participants: participants,
                        selected: _selected,
                        selectedCount: selectedCount,
                        threshold: threshold,
                        submitting: _submitting,
                        onRetry: () => unawaited(_loadDraft()),
                        onToggle: _toggleSigner,
                      ),
                      const SizedBox(height: AppSpacing.base),
                      _FeeNote(feeText: feeText),
                    ],
                  ),
                ),
              ),
              ColoredBox(
                color: colors.background.window,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.sm,
                    AppSpacing.xs,
                    AppSpacing.sm,
                    AppSpacing.sm,
                  ),
                  child: AppButton(
                    key: const ValueKey(
                      'mobile_multisig_create_request_button',
                    ),
                    expand: true,
                    onPressed: submitEnabled
                        ? () => unawaited(_submit())
                        : null,
                    leading: _submitting ? null : const AppIcon(AppIcons.users),
                    child: Text(
                      _submitting ? 'Creating request...' : 'Create request',
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _recipientBottomLabel(MobileMultisigRequestSignersArgs args) {
  final label = args.isShielded ? 'Shielded' : 'Transparent';
  return '$label · ${truncatedAddress(args.recipient)}';
}

class _RecipientLeading extends StatelessWidget {
  const _RecipientLeading({this.profilePictureId});

  final String? profilePictureId;

  @override
  Widget build(BuildContext context) {
    return AppProfilePicture(
      profilePictureId: profilePictureId ?? '',
      size: AppProfilePictureSize.navLarge,
    );
  }
}

class _SignersSection extends StatelessWidget {
  const _SignersSection({
    required this.loading,
    required this.error,
    required this.draft,
    required this.participants,
    required this.selected,
    required this.selectedCount,
    required this.threshold,
    required this.submitting,
    required this.onRetry,
    required this.onToggle,
  });

  final bool loading;
  final String? error;
  final MultisigSigningDraft? draft;
  final List<MultisigSigningParticipant> participants;
  final Set<String> selected;
  final int selectedCount;
  final int threshold;
  final bool submitting;
  final VoidCallback onRetry;
  final void Function(String participantId, bool selected) onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final complete = draft != null && selectedCount == threshold;
    return MobileSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Approvers',
                  style: AppTypography.bodyLarge.copyWith(
                    color: colors.text.accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (draft != null)
                _SignerCountBadge(
                  label: '$selectedCount of $threshold',
                  complete: complete,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Only selected approvers can approve this send.',
            style: AppTypography.labelMedium.copyWith(
              color: colors.text.secondary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (loading && draft == null)
            const SizedBox(
              height: 160,
              child: Center(child: CircularProgressIndicator()),
            )
          else if (draft == null)
            _InlineErrorWithRetry(
              message: error ?? 'Signers could not be loaded.',
              onRetry: onRetry,
            )
          else ...[
            for (final participant in participants) ...[
              _SignerChoiceRow(
                participant: participant,
                checked: selected.contains(participant.participantId),
                locked:
                    participant.participantId == draft!.material.participantId,
                disabled:
                    submitting ||
                    (!selected.contains(participant.participantId) &&
                        selectedCount >= threshold),
                onChanged: (value) =>
                    onToggle(participant.participantId, value),
              ),
              if (participant != participants.last)
                const SizedBox(height: AppSpacing.xxs),
            ],
            if (error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              _InlineError(message: error!),
            ],
          ],
        ],
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
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: canChange ? () => onChanged(!checked) : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          constraints: const BoxConstraints(minHeight: 56),
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
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
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

class _FeeNote extends StatelessWidget {
  const _FeeNote({required this.feeText});

  final String feeText;

  @override
  Widget build(BuildContext context) {
    return Text(
      'Network fee: $feeText',
      textAlign: TextAlign.center,
      style: AppTypography.labelMedium.copyWith(
        color: context.colors.text.secondary,
      ),
    );
  }
}

class _InlineErrorWithRetry extends StatelessWidget {
  const _InlineErrorWithRetry({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _InlineError(message: message),
        const SizedBox(height: AppSpacing.sm),
        AppButton(
          onPressed: onRetry,
          variant: AppButtonVariant.secondary,
          child: const Text('Retry'),
        ),
      ],
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
        AppIcon(AppIcons.warning, color: colors.text.warning),
        const SizedBox(width: AppSpacing.xxs),
        Expanded(
          child: Text(
            message,
            style: AppTypography.labelMedium.copyWith(
              color: colors.text.warning,
            ),
          ),
        ),
      ],
    );
  }
}
