import 'dart:async';

import 'package:flutter/material.dart' show CircularProgressIndicator, Scaffold;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../main.dart' show log;
import '../../../../core/formatting/address_display.dart';
import '../../../../core/formatting/zec_amount.dart';
import '../../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/mobile/mobile_review_row.dart';
import '../../../../core/widgets/mobile/mobile_surface_card.dart';
import '../../../../providers/account_provider.dart';
import '../../../../providers/multisig_account_material_provider.dart';
import '../../../../providers/multisig_operation_error.dart';
import '../../../../providers/multisig_realtime_provider.dart';
import '../../../../providers/multisig_signing_request_provider.dart';
import '../../../send/screens/mobile/mobile_send_screen.dart'
    show MobileSaplingParamsSheet;
import '../../../send/services/sapling_params.dart';

class MobileMultisigSigningDetailScreen extends ConsumerStatefulWidget {
  const MobileMultisigSigningDetailScreen({
    required this.signingRequestId,
    super.key,
  });

  final String signingRequestId;

  @override
  ConsumerState<MobileMultisigSigningDetailScreen> createState() =>
      _MobileMultisigSigningDetailScreenState();
}

class _MobileMultisigSigningDetailScreenState
    extends ConsumerState<MobileMultisigSigningDetailScreen> {
  String? _busyAction;
  String? _error;
  bool _refreshing = false;
  MultisigRealtimeLease? _realtimeLease;
  String? _realtimeKey;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_refresh());
    });
  }

  @override
  void dispose() {
    _releaseRealtimeLease();
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
      log('MobileMultisigSigningDetail.refresh: ERROR: $e\n$st');
      if (!mounted) return;
      setState(() => _error = friendlyMultisigError(e));
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }

    if (!mounted) return;
    try {
      await ref
          .read(multisigSigningRequestsProvider.notifier)
          .refreshRequestProgress(
            accountUuid: accountUuid,
            signingRequestId: widget.signingRequestId,
          );
    } catch (e, st) {
      log('MobileMultisigSigningDetail.refreshProgress: ERROR: $e\n$st');
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
      log('MobileMultisigSigningDetail.$action: ERROR: $e\n$st');
      if (!mounted) return;
      setState(() => _error = friendlyMultisigError(e));
    } finally {
      if (mounted) setState(() => _busyAction = null);
    }
  }

  Future<void> _submitPreparedRequest(
    MultisigSigningRequestRecord request,
  ) async {
    await _run('request', () async {
      final submitted = await ref
          .read(multisigSigningRequestsProvider.notifier)
          .submitPreparedRequest(request);
      if (!mounted || submitted.signingRequestId == widget.signingRequestId) {
        return;
      }
      context.go(
        '/multisig/sign/${Uri.encodeComponent(submitted.signingRequestId)}',
      );
    });
  }

  Future<void> _submitRound1(MultisigSigningRequestRecord request) {
    return _run('round1', () async {
      await ref
          .read(multisigSigningRequestsProvider.notifier)
          .submitRound1(request);
    });
  }

  Future<void> _submitRound2(MultisigSigningRequestRecord request) {
    return _run('round2', () async {
      await ref
          .read(multisigSigningRequestsProvider.notifier)
          .submitRound2(request);
    });
  }

  Future<void> _broadcast(MultisigSigningRequestRecord request) {
    return _run('broadcast', () async {
      var saplingParams = await loadSaplingParamsStatus();
      if (request.needsSaplingParams && !saplingParams.complete) {
        final confirmed = await _confirmSaplingParamsDownload();
        if (!confirmed) return;
        await downloadMissingSaplingParams(
          saplingParams,
          log: (message) => log('MobileMultisigSigningDetail: $message'),
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

  Future<bool> _confirmSaplingParamsDownload() async {
    if (!mounted) return false;
    final confirmed = await showAppMobileSheet<bool>(
      context: context,
      isDismissible: false,
      builder: (_) => const MobileSaplingParamsSheet(),
    );
    return confirmed == true;
  }

  void _syncRealtimeLease(MultisigAccountMaterial? material) {
    if (material == null) {
      _releaseRealtimeLease();
      return;
    }
    final target = MultisigRealtimeTarget.fromAccountMaterial(material);
    final key = target.connectionKey;
    final notifier = ref.read(multisigRealtimeProvider.notifier);
    if (_realtimeKey == key && notifier.updateTarget(target)) return;
    _releaseRealtimeLease();
    _realtimeKey = key;
    _realtimeLease = notifier.acquire(target, reason: 'mobile-signing-detail');
  }

  void _releaseRealtimeLease() {
    _realtimeLease?.dispose();
    _realtimeLease = null;
    _realtimeKey = null;
  }

  void _handleBack() {
    if (_busyAction != null) return;
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go('/home');
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
    final request = _requestById(requests, accountUuid);
    final loading =
        ref.watch(multisigSigningRequestsProvider).isLoading && request == null;

    return PopScope<void>(
      canPop: _busyAction == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        backgroundColor: context.colors.background.window,
        body: SafeArea(
          child: Column(
            children: [
              MobileTopNav.back(
                title: 'Multisig',
                onBack: _busyAction == null ? _handleBack : null,
              ),
              Expanded(
                child: loading
                    ? const Center(child: CircularProgressIndicator())
                    : request == null
                    ? _MissingRequest(onBack: _handleBack)
                    : _DetailBody(
                        request: request,
                        busyAction: _busyAction,
                        refreshing: _refreshing,
                        error: _error,
                        onRefresh: () => unawaited(_refresh()),
                        onSubmitRequest: () =>
                            unawaited(_submitPreparedRequest(request)),
                        onRound1: () => unawaited(_submitRound1(request)),
                        onRound2: () => unawaited(_submitRound2(request)),
                        onBroadcast: () => unawaited(_broadcast(request)),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  MultisigSigningRequestRecord? _requestById(
    List<MultisigSigningRequestRecord> requests,
    String? accountUuid,
  ) {
    for (final request in requests) {
      if (request.signingRequestId == widget.signingRequestId &&
          request.accountUuid == accountUuid) {
        return request;
      }
    }
    return null;
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

class _DetailBody extends StatelessWidget {
  const _DetailBody({
    required this.request,
    required this.onRefresh,
    required this.onSubmitRequest,
    required this.onRound1,
    required this.onRound2,
    required this.onBroadcast,
    this.busyAction,
    this.refreshing = false,
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
    final action = _actionForRequest(
      request: request,
      busyAction: busyAction,
      refreshing: refreshing,
      onRefresh: onRefresh,
      onSubmitRequest: onSubmitRequest,
      onRound1: onRound1,
      onRound2: onRound2,
      onBroadcast: onBroadcast,
    );
    final busy = busyAction != null || refreshing;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.sm,
              AppSpacing.s,
              AppSpacing.sm,
              AppSpacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Header(request: request, refreshing: refreshing),
                const SizedBox(height: AppSpacing.base),
                _TransactionSummary(request: request),
                const SizedBox(height: AppSpacing.base),
                _NextActionCard(action: action, request: request),
                if (error != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  _InlineError(message: error!),
                ],
              ],
            ),
          ),
        ),
        ColoredBox(
          color: context.colors.background.window,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.sm,
              AppSpacing.xs,
              AppSpacing.sm,
              AppSpacing.sm,
            ),
            child: AppButton(
              expand: true,
              onPressed: action.onPressed,
              variant: action.variant,
              leading: busy ? null : AppIcon(action.iconName),
              child: Text(action.buttonLabel),
            ),
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.request, required this.refreshing});

  final MultisigSigningRequestRecord request;
  final bool refreshing;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        const MobileReviewIconBadge(
          child: AppIcon(AppIcons.users, size: AppIconSize.large),
        ),
        const SizedBox(width: AppSpacing.s),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Signature request',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.headlineLarge.copyWith(
                  color: colors.text.accent,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                refreshing ? 'Refreshing' : _statusLabelForRequest(request),
                style: AppTypography.labelMedium.copyWith(
                  color: colors.text.secondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TransactionSummary extends StatelessWidget {
  const _TransactionSummary({required this.request});

  final MultisigSigningRequestRecord request;

  @override
  Widget build(BuildContext context) {
    final amount = ZecAmount.fromZatoshi(
      BigInt.tryParse(request.amountZatoshi) ?? BigInt.zero,
    ).activityDetail.toString();
    final fee = ZecAmount.fromZatoshi(
      BigInt.tryParse(request.feeZatoshi) ?? BigInt.zero,
    ).fee.toString();
    final recipientPool = _isShielded(request.addressType)
        ? 'Shielded'
        : 'Transparent';

    return MobileSurfaceCard(
      child: Column(
        children: [
          MobileReviewInfoRow(
            label: 'Amount',
            value: amount,
            leading: const MobileReviewZecBadge(),
            bottom: Text(
              'Network fee $fee',
              style: AppTypography.labelMedium.copyWith(
                color: context.colors.text.secondary,
              ),
            ),
          ),
          const MobileReviewFlowArrow(),
          MobileReviewInfoRow(
            label: 'To',
            value: truncatedAddress(request.recipientAddress),
            leading: const MobileReviewIconBadge(
              child: AppIcon(AppIcons.shieldKeyhole, size: AppIconSize.large),
            ),
            bottom: Text(
              '$recipientPool · ${truncatedAddress(request.recipientAddress)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.labelMedium.copyWith(
                color: context.colors.text.secondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

bool _isShielded(String addressType) {
  return addressType == 'unified' || addressType == 'sapling';
}

class _NextActionCard extends StatelessWidget {
  const _NextActionCard({required this.action, required this.request});

  final _MobileDetailAction action;
  final MultisigSigningRequestRecord request;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return MobileSurfaceCard(
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
          Text(
            action.title,
            style: AppTypography.bodyLarge.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            action.body,
            style: AppTypography.labelMedium.copyWith(
              color: colors.text.secondary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _ProgressSummary(request: request),
        ],
      ),
    );
  }
}

class _ProgressSummary extends StatelessWidget {
  const _ProgressSummary({required this.request});

  final MultisigSigningRequestRecord request;

  @override
  Widget build(BuildContext context) {
    final signerCount = request.selectedParticipantIds.length;
    return Row(
      children: [
        Expanded(
          child: _ProgressMetric(
            label: 'Selected',
            value: signerCount.toString(),
          ),
        ),
        const SizedBox(width: AppSpacing.xxs),
        Expanded(
          child: _ProgressMetric(
            label: 'Ready',
            value: '${request.round1SelectedParticipantCount}/$signerCount',
          ),
        ),
        const SizedBox(width: AppSpacing.xxs),
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
          horizontal: AppSpacing.xs,
          vertical: AppSpacing.xs,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.labelSmall.copyWith(
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

class _MobileDetailAction {
  const _MobileDetailAction({
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

_MobileDetailAction _actionForRequest({
  required MultisigSigningRequestRecord request,
  required String? busyAction,
  required bool refreshing,
  required VoidCallback onRefresh,
  required VoidCallback onSubmitRequest,
  required VoidCallback onRound1,
  required VoidCallback onRound2,
  required VoidCallback onBroadcast,
}) {
  final busy = busyAction != null || refreshing;
  final refreshAction = busy ? null : onRefresh;
  const primary = AppButtonVariant.primary;
  const secondary = AppButtonVariant.secondary;

  if (request.isBroadcasted) {
    return _MobileDetailAction(
      title: 'Sent',
      body: 'This send is on the network. You can review it in Activity.',
      buttonLabel: refreshing ? 'Refreshing' : 'Refresh',
      iconName: AppIcons.renew,
      variant: secondary,
      onPressed: refreshAction,
    );
  }
  if (request.hasBroadcastTxid) {
    return _MobileDetailAction(
      title: 'Share send result',
      body:
          'The transaction was sent. Share the result so the group can stop tracking this request.',
      buttonLabel: busyAction == 'broadcast' ? 'Sharing...' : 'Share result',
      iconName: AppIcons.plane,
      variant: primary,
      onPressed: busy ? null : onBroadcast,
    );
  }
  if (request.isReviewOnly || !request.localParticipantSelected) {
    return _MobileDetailAction(
      title: 'Review only',
      body:
          'You can review this send, but you were not selected to approve it.',
      buttonLabel: refreshing ? 'Refreshing' : 'Refresh',
      iconName: AppIcons.renew,
      variant: secondary,
      onPressed: refreshAction,
    );
  }
  if (!request.coordinatorSubmitted) {
    return _MobileDetailAction(
      title: 'Finish request setup',
      body: 'Save this request so selected approvers can continue.',
      buttonLabel: busyAction == 'request' ? 'Submitting...' : 'Submit request',
      iconName: AppIcons.sync,
      variant: primary,
      onPressed: busy ? null : onSubmitRequest,
    );
  }
  if (!request.localRound1Submitted) {
    return _MobileDetailAction(
      title: 'Approve this send',
      body:
          'Start your approval. The request continues once the selected approvers are ready.',
      buttonLabel: busyAction == 'round1' ? 'Approving...' : 'Approve',
      iconName: AppIcons.sync,
      variant: primary,
      onPressed: busy ? null : onRound1,
    );
  }
  if (!request.round1Complete) {
    return _MobileDetailAction(
      title: 'Waiting for other approvers',
      body:
          'Your first approval step is complete. This request continues when the others are ready.',
      buttonLabel: refreshing ? 'Refreshing' : 'Refresh',
      iconName: AppIcons.renew,
      variant: secondary,
      onPressed: refreshAction,
    );
  }
  if (!request.localRound2Submitted && !request.round2Complete) {
    return _MobileDetailAction(
      title: 'Finish your approval',
      body:
          'The selected approvers are ready. Finish your approval so the transaction can be sent.',
      buttonLabel: busyAction == 'round2' ? 'Approving...' : 'Finish approval',
      iconName: AppIcons.sync,
      variant: primary,
      onPressed: busy ? null : onRound2,
    );
  }
  if (!request.round2Complete) {
    return _MobileDetailAction(
      title: 'Waiting for final approvals',
      body:
          'Your approval is complete. This can be sent after the other approvers finish.',
      buttonLabel: refreshing ? 'Refreshing' : 'Refresh',
      iconName: AppIcons.renew,
      variant: secondary,
      onPressed: refreshAction,
    );
  }

  return _MobileDetailAction(
    title: 'Ready to send',
    body: 'All required approvals are collected. Send this to the network.',
    buttonLabel: busyAction == 'broadcast' ? 'Sending...' : 'Send now',
    iconName: AppIcons.plane,
    variant: primary,
    onPressed: busy ? null : onBroadcast,
  );
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

class _MissingRequest extends StatelessWidget {
  const _MissingRequest({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const MobileReviewIconBadge(
              child: AppIcon(AppIcons.warning, size: AppIconSize.large),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text('Request not found', style: AppTypography.headlineLarge),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Refresh the multisig list or switch back to the account that received this request.',
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(
                color: colors.text.secondary,
              ),
            ),
            const SizedBox(height: AppSpacing.base),
            AppButton(onPressed: onBack, child: const Text('Back')),
          ],
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
