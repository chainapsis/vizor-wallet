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
import '../../../providers/account_provider.dart';
import '../../../providers/multisig_account_material_provider.dart';
import '../../../providers/multisig_operation_error.dart';
import '../../../providers/multisig_realtime_provider.dart';
import '../../../providers/multisig_signing_request_provider.dart';
import '../../send/services/sapling_params.dart';
import '../../send/widgets/sapling_params_prompt.dart';

class MultisigSigningDetailScreen extends ConsumerStatefulWidget {
  const MultisigSigningDetailScreen({
    required this.signingRequestId,
    super.key,
  });

  final String signingRequestId;

  @override
  ConsumerState<MultisigSigningDetailScreen> createState() =>
      _MultisigSigningDetailScreenState();
}

class _MultisigSigningDetailScreenState
    extends ConsumerState<MultisigSigningDetailScreen> {
  String? _busyAction;
  String? _error;
  bool _showSaplingParamsPrompt = false;
  Completer<bool>? _saplingParamsPrompt;
  MultisigRealtimeLease? _realtimeLease;
  String? _realtimeKey;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(appLayoutProvider.notifier).setMode(AppLayoutMode.large);
      unawaited(_refresh());
    });
  }

  @override
  void dispose() {
    _releaseRealtimeLease();
    final completer = _saplingParamsPrompt;
    if (completer != null && !completer.isCompleted) {
      completer.complete(false);
    }
    super.dispose();
  }

  Future<void> _refresh() async {
    final accountUuid = ref.read(accountProvider).value?.activeAccountUuid;
    if (accountUuid == null) return;
    try {
      await ref
          .read(multisigSigningRequestsProvider.notifier)
          .refreshForAccount(accountUuid);
      if (!mounted) return;
      setState(() {
        _error = null;
      });
    } catch (e, st) {
      log('MultisigSigningDetail.refresh: ERROR: $e\n$st');
      if (!mounted) return;
      setState(() {
        _error = friendlyMultisigError(e);
      });
    }
  }

  Future<void> _run(String action, Future<void> Function() operation) async {
    if (_busyAction != null) return;
    setState(() {
      _busyAction = action;
      _error = null;
    });
    try {
      await operation();
    } catch (e, st) {
      log('MultisigSigningDetail.$action: ERROR: $e\n$st');
      if (!mounted) return;
      setState(() {
        _error = friendlyMultisigError(e);
      });
    } finally {
      if (mounted) {
        setState(() {
          _busyAction = null;
        });
      }
    }
  }

  Future<void> _submitPreparedRequest(
    MultisigSigningRequestRecord request,
  ) async {
    await _run('request', () async {
      final submitted = await ref
          .read(multisigSigningRequestsProvider.notifier)
          .submitPreparedRequest(request);
      // Preparing a local record swaps its id for the coordinator-issued
      // one; follow it so this screen doesn't dead-end on "Request not
      // found".
      if (!mounted || submitted.signingRequestId == widget.signingRequestId) {
        return;
      }
      context.go(
        '/multisig/sign/${Uri.encodeComponent(submitted.signingRequestId)}',
      );
    });
  }

  Future<void> _submitRound1(MultisigSigningRequestRecord request) async {
    await _run('round1', () async {
      await ref
          .read(multisigSigningRequestsProvider.notifier)
          .submitRound1(request);
    });
  }

  Future<void> _submitRound2(MultisigSigningRequestRecord request) async {
    await _run('round2', () async {
      await ref
          .read(multisigSigningRequestsProvider.notifier)
          .submitRound2(request);
    });
  }

  Future<void> _broadcast(MultisigSigningRequestRecord request) async {
    await _run('broadcast', () async {
      var saplingParams = await loadSaplingParamsStatus();
      if (request.needsSaplingParams && !saplingParams.complete) {
        final confirmed = await _showSaplingParamsDialog();
        if (!confirmed) return;
        await downloadMissingSaplingParams(
          saplingParams,
          log: (message) => log('MultisigSigningDetail: $message'),
        );
        saplingParams = await loadSaplingParamsStatus();
      }

      await ref
          .read(multisigSigningRequestsProvider.notifier)
          .broadcast(
            request,
            spendParamsPath: request.needsSaplingParams
                ? saplingParams.spendPath
                : null,
            outputParamsPath: request.needsSaplingParams
                ? saplingParams.outputPath
                : null,
          );
    });
  }

  Future<bool> _showSaplingParamsDialog() {
    final completer = Completer<bool>();
    setState(() {
      _saplingParamsPrompt = completer;
      _showSaplingParamsPrompt = true;
    });
    return completer.future;
  }

  void _resolveSaplingParamsDialog(bool confirmed) {
    final completer = _saplingParamsPrompt;
    if (completer != null && !completer.isCompleted) {
      completer.complete(confirmed);
    }
    setState(() {
      _saplingParamsPrompt = null;
      _showSaplingParamsPrompt = false;
    });
  }

  void _syncRealtimeLease(MultisigAccountMaterial? material) {
    if (material == null) {
      _releaseRealtimeLease();
      return;
    }

    final target = MultisigRealtimeTarget.fromAccountMaterial(material);
    final key = target.connectionKey;
    final notifier = ref.read(multisigRealtimeProvider.notifier);
    if (_realtimeKey == key && notifier.updateTarget(target)) {
      return;
    }

    _releaseRealtimeLease();
    _realtimeKey = key;
    _realtimeLease = notifier.acquire(target, reason: 'signing-detail');
  }

  void _releaseRealtimeLease() {
    _realtimeLease?.dispose();
    _realtimeLease = null;
    _realtimeKey = null;
  }

  @override
  Widget build(BuildContext context) {
    final accountUuid = ref.watch(accountProvider).value?.activeAccountUuid;
    final materials = ref.watch(multisigAccountMaterialsProvider).value;
    final activeMaterial = _materialForAccount(materials, accountUuid);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncRealtimeLease(activeMaterial);
    });
    final requests =
        ref.watch(multisigSigningRequestsProvider).value ??
        const <MultisigSigningRequestRecord>[];
    MultisigSigningRequestRecord? request;
    for (final entry in requests) {
      if (entry.signingRequestId == widget.signingRequestId &&
          entry.accountUuid == accountUuid) {
        request = entry;
        break;
      }
    }

    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        padding: EdgeInsets.zero,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: request == null
                  ? _MissingRequest(onBack: () => context.go('/multisig'))
                  : Builder(
                      builder: (_) {
                        final current = request!;
                        return _SigningDetailContent(
                          request: current,
                          busyAction: _busyAction,
                          error: _error,
                          onRefresh: () => unawaited(_refresh()),
                          onSubmitRequest: () =>
                              unawaited(_submitPreparedRequest(current)),
                          onRound1: () => unawaited(_submitRound1(current)),
                          onRound2: () => unawaited(_submitRound2(current)),
                          onBroadcast: () => unawaited(_broadcast(current)),
                        );
                      },
                    ),
            ),
            if (_showSaplingParamsPrompt)
              SaplingParamsPrompt(
                onDownload: () => _resolveSaplingParamsDialog(true),
                onCancel: () => _resolveSaplingParamsDialog(false),
              ),
          ],
        ),
      ),
    );
  }
}

MultisigAccountMaterial? _materialForAccount(
  List<MultisigAccountMaterial>? materials,
  String? accountUuid,
) {
  if (accountUuid == null || materials == null) return null;
  for (final material in materials) {
    if (material.accountUuid == accountUuid) return material;
  }
  return null;
}

class _SigningDetailContent extends StatelessWidget {
  const _SigningDetailContent({
    required this.request,
    required this.onRefresh,
    required this.onSubmitRequest,
    required this.onRound1,
    required this.onRound2,
    required this.onBroadcast,
    this.busyAction,
    this.error,
  });

  final MultisigSigningRequestRecord request;
  final String? busyAction;
  final String? error;
  final VoidCallback onRefresh;
  final VoidCallback onSubmitRequest;
  final VoidCallback onRound1;
  final VoidCallback onRound2;
  final VoidCallback onBroadcast;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final localSelected = request.localParticipantSelected;
    final reviewOnly = request.isReviewOnly;
    final round1Done = request.localRound1Submitted;
    final round2Done = request.localRound2Submitted;
    final round1Complete = request.round1Complete;
    final round2Complete = request.round2Complete;
    final coordinatorSubmitted = request.coordinatorSubmitted;
    final busy = busyAction != null;
    final amount = ZecAmount.fromZatoshi(
      BigInt.tryParse(request.amountZatoshi) ?? BigInt.zero,
    ).receipt;
    final fee = ZecAmount.fromZatoshi(
      BigInt.tryParse(request.feeZatoshi) ?? BigInt.zero,
    ).fee;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            AppBackLink(
              label: 'Multisig',
              onTap: () => context.go('/multisig'),
            ),
            const Spacer(),
            AppButton(
              onPressed: busy ? null : onRefresh,
              variant: AppButtonVariant.secondary,
              leading: const AppIcon(AppIcons.renew),
              child: const Text('Refresh'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        Row(
          children: [
            const AppIcon(AppIcons.users, size: AppIconSize.large),
            const SizedBox(width: AppSpacing.xs),
            Text('Signature request', style: AppTypography.displaySmall),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Expanded(
          child: ListView(
            children: [
              _SummaryPanel(
                amount: amount.toString(),
                fee: fee.toString(),
                recipient: request.recipientAddress,
                requestId: request.shortSigningRequestId,
                txid: request.broadcastTxid,
              ),
              const SizedBox(height: AppSpacing.md),
              if (reviewOnly) ...[
                _StepPanel(
                  title: 'Review',
                  count: 'Review only',
                  body:
                      'This transaction was shared with every participant. You were not selected to sign it.',
                  action: AppButton(
                    onPressed: busy ? null : onRefresh,
                    variant: AppButtonVariant.secondary,
                    leading: const AppIcon(AppIcons.renew),
                    child: const Text('Refresh'),
                  ),
                ),
              ] else ...[
                _StepPanel(
                  title: 'Round 1',
                  count:
                      '${request.round1SelectedParticipantCount}/${request.selectedParticipantIds.length}',
                  body: !coordinatorSubmitted
                      ? 'Submit the request to the coordinator before signing.'
                      : round1Done
                      ? 'Your Round 1 commitment was submitted.'
                      : 'Submit your nonce commitment for this transaction.',
                  action: AppButton(
                    onPressed: !busy && !request.isBroadcasted
                        ? (!coordinatorSubmitted
                              ? onSubmitRequest
                              : localSelected && !round1Done
                              ? onRound1
                              : null)
                        : null,
                    leading: busyAction == 'round1' || busyAction == 'request'
                        ? null
                        : const AppIcon(AppIcons.sync),
                    child: Text(
                      busyAction == 'round1' || busyAction == 'request'
                          ? 'Submitting...'
                          : !coordinatorSubmitted
                          ? 'Submit request'
                          : 'Submit Round 1',
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                _StepPanel(
                  title: 'Round 2',
                  count:
                      '${request.round2SelectedParticipantCount}/${request.selectedParticipantIds.length}',
                  body: !coordinatorSubmitted
                      ? 'Submit the request to the coordinator before signing.'
                      : !round1Done
                      ? 'Submit your Round 1 commitment before Round 2.'
                      : !round1Complete
                      ? 'Round 2 opens after every selected signer submits Round 1.'
                      : round2Complete
                      ? 'Every selected signer has submitted Round 2.'
                      : round2Done
                      ? 'Your signature share was submitted.'
                      : 'Submit your signature share for this transaction.',
                  action: AppButton(
                    onPressed:
                        !busy &&
                            coordinatorSubmitted &&
                            localSelected &&
                            round1Done &&
                            round1Complete &&
                            !round2Complete &&
                            !round2Done &&
                            !request.isBroadcasted
                        ? onRound2
                        : null,
                    leading: busyAction == 'round2'
                        ? null
                        : const AppIcon(AppIcons.sync),
                    child: Text(
                      busyAction == 'round2'
                          ? 'Submitting...'
                          : 'Submit Round 2',
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                _StepPanel(
                  title: 'Broadcast',
                  count: request.isBroadcasted
                      ? 'Done'
                      : request.hasBroadcastTxid
                      ? 'Notify'
                      : round2Complete
                      ? 'Ready'
                      : 'Waiting',
                  body: request.isBroadcasted
                      ? 'This transaction has been broadcast.'
                      : request.hasBroadcastTxid
                      ? 'Transaction was broadcast. Submit the result to the coordinator.'
                      : round2Complete
                      ? 'Any selected signer with all shares can combine and broadcast.'
                      : 'Broadcast becomes available after every selected signer submits Round 2.',
                  action: AppButton(
                    onPressed:
                        !busy &&
                            localSelected &&
                            round2Complete &&
                            !request.isBroadcasted
                        ? onBroadcast
                        : null,
                    leading: busyAction == 'broadcast'
                        ? null
                        : const AppIcon(AppIcons.plane),
                    child: Text(
                      busyAction == 'broadcast'
                          ? 'Broadcasting...'
                          : 'Broadcast',
                    ),
                  ),
                ),
              ],
              if (error != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  error!,
                  style: AppTypography.labelMedium.copyWith(
                    color: colors.text.warning,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SummaryPanel extends StatelessWidget {
  const _SummaryPanel({
    required this.amount,
    required this.fee,
    required this.recipient,
    required this.requestId,
    this.txid,
  });

  final String amount;
  final String fee;
  final String recipient;
  final String requestId;
  final String? txid;

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
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _SummaryItem(label: 'Amount', value: amount),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: _SummaryItem(label: 'Fee', value: fee),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: _SummaryItem(label: 'Request', value: requestId),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            _SummaryItem(label: 'Recipient', value: recipient),
            if (txid != null && txid!.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              _SummaryItem(label: 'Transaction ID', value: txid!),
            ],
          ],
        ),
      ),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  const _SummaryItem({required this.label, required this.value});

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

class _StepPanel extends StatelessWidget {
  const _StepPanel({
    required this.title,
    required this.count,
    required this.body,
    required this.action,
  });

  final String title;
  final String count;
  final String body;
  final Widget action;

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
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(title, style: AppTypography.headlineSmall),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        count,
                        style: AppTypography.labelLarge.copyWith(
                          color: colors.text.secondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    body,
                    style: AppTypography.labelMedium.copyWith(
                      color: colors.text.secondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            action,
          ],
        ),
      ),
    );
  }
}

class _MissingRequest extends StatelessWidget {
  const _MissingRequest({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Center(
      child: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AppIcon(AppIcons.warning, size: AppIconSize.large),
            const SizedBox(height: AppSpacing.sm),
            Text('Request not found', style: AppTypography.headlineMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Refresh the multisig list or switch back to the account that received this request.',
              textAlign: TextAlign.center,
              style: AppTypography.labelMedium.copyWith(
                color: colors.text.secondary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            AppButton(onPressed: onBack, child: const Text('Back')),
          ],
        ),
      ),
    );
  }
}
