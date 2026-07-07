import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../main.dart' show log;
import '../../../core/formatting/address_display.dart';
import '../../../core/formatting/zec_amount.dart';
import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_layout.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/layout/app_pane_scroll_scaffold.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_back_link.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/review_list_row.dart';
import '../../../core/widgets/review_wrap_card.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/multisig_account_material_provider.dart';
import '../../../providers/multisig_operation_error.dart';
import '../../../providers/multisig_realtime_provider.dart';
import '../../../providers/multisig_signing_request_provider.dart';
import '../../send/services/sapling_params.dart';
import '../../send/widgets/sapling_params_prompt.dart';

const _multisigSigningDetailContentMaxWidth = 560.0;

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
  bool _refreshing = false;
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
    if (_refreshing) return;
    final accountUuid = ref.read(accountProvider).value?.activeAccountUuid;
    if (accountUuid == null) return;
    setState(() {
      _refreshing = true;
      _error = null;
    });
    try {
      await ref
          .read(multisigSigningRequestsProvider.notifier)
          .refreshForAccount(accountUuid);
    } catch (e, st) {
      log('MultisigSigningDetail.refresh: ERROR: $e\n$st');
      if (!mounted) return;
      setState(() {
        _error = friendlyMultisigError(e);
      });
    } finally {
      if (mounted) {
        setState(() {
          _refreshing = false;
        });
      }
    }
    if (!mounted) return;
    // Coordinator-side round progress is advisory on top of the inbox
    // markers, so a failure here must not replace the refresh result.
    try {
      await ref
          .read(multisigSigningRequestsProvider.notifier)
          .refreshRequestProgress(
            accountUuid: accountUuid,
            signingRequestId: widget.signingRequestId,
          );
    } catch (e, st) {
      log('MultisigSigningDetail.refreshProgress: ERROR: $e\n$st');
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
            AppPaneScrollScaffold(
              toolbar: AppPaneToolbar(
                leading: AppBackLink(
                  label: 'Multisig',
                  minWidth: 60,
                  onTap: () => context.go('/multisig'),
                ),
              ),
              padding: const EdgeInsets.only(bottom: 40),
              child: request == null
                  ? _MissingRequest(onBack: () => context.go('/multisig'))
                  : Builder(
                      builder: (_) {
                        final current = request!;
                        return _CenteredDetailTrack(
                          child: _SigningDetailContent(
                            request: current,
                            busyAction: _busyAction,
                            refreshing: _refreshing,
                            error: _error,
                            onRefresh: () => unawaited(_refresh()),
                            onSubmitRequest: () =>
                                unawaited(_submitPreparedRequest(current)),
                            onRound1: () => unawaited(_submitRound1(current)),
                            onRound2: () => unawaited(_submitRound2(current)),
                            onBroadcast: () => unawaited(_broadcast(current)),
                          ),
                        );
                      },
                    ),
            ),
            if (_showSaplingParamsPrompt)
              Positioned.fill(
                child: SaplingParamsPrompt(
                  onDownload: () => _resolveSaplingParamsDialog(true),
                  onCancel: () => _resolveSaplingParamsDialog(false),
                ),
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
    this.refreshing = false,
    this.busyAction,
    this.error,
  });

  final MultisigSigningRequestRecord request;
  final String? busyAction;
  final bool refreshing;
  final String? error;
  final VoidCallback onRefresh;
  final VoidCallback onSubmitRequest;
  final VoidCallback onRound1;
  final VoidCallback onRound2;
  final VoidCallback onBroadcast;

  @override
  Widget build(BuildContext context) {
    final busy = busyAction != null || refreshing;
    final amount = ZecAmount.fromZatoshi(
      BigInt.tryParse(request.amountZatoshi) ?? BigInt.zero,
    ).receipt;
    final fee = ZecAmount.fromZatoshi(
      BigInt.tryParse(request.feeZatoshi) ?? BigInt.zero,
    ).fee;
    final action = _detailActionForRequest(
      request: request,
      busyAction: busyAction,
      onRefresh: onRefresh,
      onSubmitRequest: onSubmitRequest,
      onRound1: onRound1,
      onRound2: onRound2,
      onBroadcast: onBroadcast,
      refreshing: refreshing,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DetailHeader(
          request: request,
          refreshing: refreshing,
          onRefresh: busy ? null : onRefresh,
        ),
        const SizedBox(height: AppSpacing.md),
        _RequestSummaryCard(
          amount: amount.toString(),
          fee: fee.toString(),
          recipient: request.recipientAddress,
          txid: request.broadcastTxid,
        ),
        const SizedBox(height: AppSpacing.md),
        _NextActionPanel(action: action, request: request, busy: busy),
        if (error != null) ...[
          const SizedBox(height: AppSpacing.md),
          _WarningPanel(message: error!),
        ],
      ],
    );
  }
}

class _CenteredDetailTrack extends StatelessWidget {
  const _CenteredDetailTrack({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: _multisigSigningDetailContentMaxWidth,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: child,
        ),
      ),
    );
  }
}

class _DetailHeader extends StatelessWidget {
  const _DetailHeader({
    required this.request,
    required this.refreshing,
    required this.onRefresh,
  });

  final MultisigSigningRequestRecord request;
  final bool refreshing;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 40,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Text(
                'Signature request',
                textAlign: TextAlign.center,
                style: AppTypography.displaySmall.copyWith(
                  color: context.colors.text.accent,
                  letterSpacing: 0,
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: _StatusPill(label: _statusLabelForRequest(request)),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          height: 24,
          child: Row(
            children: [
              const Spacer(),
              AppButton(
                onPressed: onRefresh,
                variant: AppButtonVariant.secondary,
                size: AppButtonSize.small,
                leading: const AppIcon(AppIcons.renew),
                child: Text(refreshing ? 'Refreshing' : 'Refresh'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

String _statusLabelForRequest(MultisigSigningRequestRecord request) {
  if (request.isBroadcasted) return 'Sent';
  if (request.hasBroadcastTxid) return 'Sharing result';
  if (request.readyToBroadcast) return 'Ready to send';
  if (request.isReviewOnly) return 'Review only';
  if (!request.coordinatorSubmitted) return 'Preparing';
  if (!request.localParticipantSelected) return 'Waiting';
  if (!request.localRound1Submitted) return 'Action needed';
  if (request.round1Complete && !request.localRound2Submitted) {
    return 'Action needed';
  }
  return 'Waiting';
}

class _RequestSummaryCard extends StatelessWidget {
  const _RequestSummaryCard({
    required this.amount,
    required this.fee,
    required this.recipient,
    this.txid,
  });

  final String amount;
  final String fee;
  final String recipient;
  final String? txid;

  @override
  Widget build(BuildContext context) {
    return ReviewWrapCard(
      children: [
        ReviewListRow(label: 'Amount', value: amount),
        const ReviewWrapDivider(),
        ReviewListRow(
          label: 'Recipient',
          value: truncatedAddress(recipient),
          copyText: recipient,
        ),
        const ReviewWrapDivider(),
        ReviewListRow(label: 'Tx fee', value: fee),
        if (txid != null && txid!.isNotEmpty) ...[
          const ReviewWrapDivider(),
          ReviewListRow(
            label: 'Tx ID',
            value: truncatedAddress(txid!),
            copyText: txid,
          ),
        ],
      ],
    );
  }
}

class _NextActionPanel extends StatelessWidget {
  const _NextActionPanel({
    required this.action,
    required this.request,
    required this.busy,
  });

  final _DetailAction action;
  final MultisigSigningRequestRecord request;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.background.ground,
        borderRadius: BorderRadius.circular(AppRadii.large),
        boxShadow: appSurfaceShadow(colors),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Next action',
              style: AppTypography.labelMedium.copyWith(
                color: colors.text.secondary,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(action.title, style: AppTypography.headlineSmall),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              action.body,
              style: AppTypography.labelMedium.copyWith(
                color: colors.text.secondary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            _ApprovalProgressSummary(request: request),
            const SizedBox(height: AppSpacing.md),
            Align(
              alignment: Alignment.centerRight,
              child: AppButton(
                onPressed: action.onPressed,
                variant: action.variant,
                minWidth: 184,
                leading: busy ? null : AppIcon(action.iconName),
                child: Text(action.buttonLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ApprovalProgressSummary extends StatelessWidget {
  const _ApprovalProgressSummary({required this.request});

  final MultisigSigningRequestRecord request;

  @override
  Widget build(BuildContext context) {
    final signerCount = request.selectedParticipantIds.length;

    return Row(
      children: [
        Expanded(
          child: _ProgressMetric(
            label: 'Selected signers',
            value: signerCount.toString(),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: _ProgressMetric(
            label: 'Ready',
            value: '${request.round1SelectedParticipantCount}/$signerCount',
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: _ProgressMetric(
            label: 'Approved',
            value: '${request.round2SelectedParticipantCount}/$signerCount',
          ),
        ),
      ],
    );
  }
}

class _ProgressMetric extends StatelessWidget {
  const _ProgressMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface.input,
        borderRadius: BorderRadius.circular(AppRadii.small),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.labelMedium.copyWith(
                color: colors.text.secondary,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(value, style: AppTypography.bodyMediumStrong),
          ],
        ),
      ),
    );
  }
}

class _DetailAction {
  const _DetailAction({
    required this.title,
    required this.body,
    required this.buttonLabel,
    required this.iconName,
    required this.variant,
    required this.onPressed,
  });

  final String title;
  final String body;
  final String buttonLabel;
  final String iconName;
  final AppButtonVariant variant;
  final VoidCallback? onPressed;
}

_DetailAction _detailActionForRequest({
  required MultisigSigningRequestRecord request,
  required String? busyAction,
  required VoidCallback onRefresh,
  required VoidCallback onSubmitRequest,
  required VoidCallback onRound1,
  required VoidCallback onRound2,
  required VoidCallback onBroadcast,
  required bool refreshing,
}) {
  final busy = busyAction != null || refreshing;
  final disabledRefresh = busy ? null : onRefresh;
  final primaryVariant = AppButtonVariant.primary;
  final secondaryVariant = AppButtonVariant.secondary;

  if (request.isBroadcasted) {
    return _DetailAction(
      title: 'Sent',
      body:
          'This send is already on the network. You can review it in Activity.',
      buttonLabel: refreshing ? 'Refreshing' : 'Refresh',
      iconName: AppIcons.renew,
      variant: secondaryVariant,
      onPressed: disabledRefresh,
    );
  }
  if (request.hasBroadcastTxid) {
    return _DetailAction(
      title: 'Share send result',
      body:
          'The transaction was sent. Share the result so the group can stop tracking this request.',
      buttonLabel: busyAction == 'broadcast' ? 'Sharing...' : 'Share result',
      iconName: AppIcons.plane,
      variant: primaryVariant,
      onPressed: busy ? null : onBroadcast,
    );
  }
  if (request.isReviewOnly || !request.localParticipantSelected) {
    return _DetailAction(
      title: 'Review only',
      body:
          'This send was shared with every participant, but you were not selected to approve it.',
      buttonLabel: refreshing ? 'Refreshing' : 'Refresh',
      iconName: AppIcons.renew,
      variant: secondaryVariant,
      onPressed: disabledRefresh,
    );
  }
  if (!request.coordinatorSubmitted) {
    return _DetailAction(
      title: 'Finish request setup',
      body:
          'Save this request with the coordinator so selected signers can approve it.',
      buttonLabel: busyAction == 'request' ? 'Submitting...' : 'Submit request',
      iconName: AppIcons.sync,
      variant: primaryVariant,
      onPressed: busy ? null : onSubmitRequest,
    );
  }
  if (!request.localRound1Submitted) {
    return _DetailAction(
      title: 'Approve this send',
      body:
          'Start your approval for this send. The request will continue once the selected signers are ready.',
      buttonLabel: busyAction == 'round1' ? 'Approving...' : 'Approve',
      iconName: AppIcons.sync,
      variant: primaryVariant,
      onPressed: busy ? null : onRound1,
    );
  }
  if (!request.round1Complete) {
    return _DetailAction(
      title: 'Waiting for other signers',
      body:
          'Your first approval step is complete. The request will continue after the other selected signers are ready.',
      buttonLabel: refreshing ? 'Refreshing' : 'Refresh',
      iconName: AppIcons.renew,
      variant: secondaryVariant,
      onPressed: disabledRefresh,
    );
  }
  if (!request.localRound2Submitted && !request.round2Complete) {
    return _DetailAction(
      title: 'Finish your approval',
      body:
          'The selected signers are ready. Finish your approval so the transaction can be sent.',
      buttonLabel: busyAction == 'round2' ? 'Approving...' : 'Finish approval',
      iconName: AppIcons.sync,
      variant: primaryVariant,
      onPressed: busy ? null : onRound2,
    );
  }
  if (!request.round2Complete) {
    return _DetailAction(
      title: 'Waiting for final approvals',
      body:
          'Your approval is complete. The transaction can be sent after the other selected signers finish.',
      buttonLabel: refreshing ? 'Refreshing' : 'Refresh',
      iconName: AppIcons.renew,
      variant: secondaryVariant,
      onPressed: disabledRefresh,
    );
  }

  return _DetailAction(
    title: 'Ready to send',
    body:
        'All required approvals are collected. Send this transaction to the network.',
    buttonLabel: busyAction == 'broadcast' ? 'Sending...' : 'Send now',
    iconName: AppIcons.plane,
    variant: primaryVariant,
    onPressed: busy ? null : onBroadcast,
  );
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label});

  final String label;

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
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.labelMedium.copyWith(
            color: colors.text.secondary,
          ),
        ),
      ),
    );
  }
}

class _WarningPanel extends StatelessWidget {
  const _WarningPanel({required this.message});

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
            style: AppTypography.labelMedium.copyWith(
              color: colors.text.warning,
            ),
          ),
        ),
      ],
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
