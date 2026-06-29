import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/formatting/zec_amount.dart';
import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_layout.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/multisig_account_material_provider.dart';
import '../../../providers/multisig_realtime_provider.dart';
import '../../../providers/multisig_signing_request_provider.dart';

class MultisigSigningHomeScreen extends ConsumerStatefulWidget {
  const MultisigSigningHomeScreen({super.key});

  @override
  ConsumerState<MultisigSigningHomeScreen> createState() =>
      _MultisigSigningHomeScreenState();
}

class _MultisigSigningHomeScreenState
    extends ConsumerState<MultisigSigningHomeScreen> {
  bool _refreshing = false;
  String? _refreshError;
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
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    final accountState = ref.read(accountProvider).value;
    final accountUuid = accountState?.activeAccountUuid;
    if (accountUuid == null) return;
    if (!ref.read(accountProvider.notifier).isMultisigAccount(accountUuid)) {
      return;
    }

    setState(() {
      _refreshing = true;
      _refreshError = null;
    });
    try {
      await ref
          .read(multisigSigningRequestsProvider.notifier)
          .refreshForAccount(accountUuid);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _refreshError = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _refreshing = false;
        });
      }
    }
  }

  void _syncRealtimeLease(MultisigAccountMaterial? material) {
    if (material == null) {
      _releaseRealtimeLease();
      return;
    }

    final target = MultisigRealtimeTarget.fromAccountMaterial(material);
    final key = target.connectionKey;
    final notifier = ref.read(multisigRealtimeProvider.notifier);
    if (_realtimeKey == key) {
      notifier.updateTarget(target);
      return;
    }

    _releaseRealtimeLease();
    _realtimeKey = key;
    _realtimeLease = notifier.acquire(target, reason: 'signing-home');
  }

  void _releaseRealtimeLease() {
    _realtimeLease?.dispose();
    _realtimeLease = null;
    _realtimeKey = null;
  }

  @override
  Widget build(BuildContext context) {
    final accountState = ref.watch(accountProvider).value;
    final accountUuid = accountState?.activeAccountUuid;
    final isMultisig =
        accountUuid != null &&
        ref.read(accountProvider.notifier).isMultisigAccount(accountUuid);
    final requestsAsync = ref.watch(multisigSigningRequestsProvider);
    final materialsAsync = ref.watch(multisigAccountMaterialsProvider);
    final activeMaterial = _materialForAccount(
      materialsAsync.value,
      accountUuid,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncRealtimeLease(isMultisig ? activeMaterial : null);
    });
    final requests = [
      for (final request
          in requestsAsync.value ?? const <MultisigSigningRequestRecord>[])
        if (accountUuid != null && request.accountUuid == accountUuid) request,
    ];
    final localParticipantId = _localParticipantId(requests);
    final needsAction = requests
        .where((request) => _needsLocalAction(request, localParticipantId))
        .toList();
    final ready = requests
        .where((request) => request.readyToBroadcast)
        .toList();
    final waitingOnOthers = requests
        .where(
          (request) =>
              _waitingOnOtherSigners(request, localParticipantId) &&
              !needsAction.contains(request) &&
              !ready.contains(request),
        )
        .toList();
    final requestedByMe = requests
        .where(
          (request) =>
              request.requesterParticipantId == localParticipantId &&
              !needsAction.contains(request) &&
              !ready.contains(request) &&
              !waitingOnOthers.contains(request) &&
              !request.isBroadcasted,
        )
        .toList();
    final reviewOnly = requests
        .where(
          (request) =>
              request.isReviewOnly &&
              !needsAction.contains(request) &&
              !ready.contains(request) &&
              !request.isBroadcasted,
        )
        .toList();
    final completed = requests
        .where((request) => request.isBroadcasted)
        .toList();

    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        padding: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const AppIcon(AppIcons.users, size: AppIconSize.large),
                  const SizedBox(width: AppSpacing.xs),
                  Text('Multisig', style: AppTypography.displaySmall),
                  if (isMultisig) ...[
                    const SizedBox(width: AppSpacing.sm),
                    Flexible(
                      fit: FlexFit.loose,
                      child: _SessionIdBadge(
                        sessionId: activeMaterial?.sessionId,
                        isLoading: materialsAsync.isLoading,
                      ),
                    ),
                  ],
                  const Spacer(),
                  AppButton(
                    onPressed: () => context.go('/multisig/connect'),
                    variant: AppButtonVariant.secondary,
                    leading: const AppIcon(AppIcons.cog),
                    child: const Text('Setup'),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  AppButton(
                    onPressed: _refreshing || !isMultisig
                        ? null
                        : () => unawaited(_refresh()),
                    variant: AppButtonVariant.secondary,
                    leading: const AppIcon(AppIcons.renew),
                    child: Text(_refreshing ? 'Refreshing' : 'Refresh'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              if (!isMultisig)
                const _EmptyPanel(
                  title: 'No multisig account selected',
                  body:
                      'Switch to a multisig account to view signing requests.',
                )
              else if (requestsAsync.isLoading && requests.isEmpty)
                const Expanded(
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                Expanded(
                  child: ListView(
                    children: [
                      if (_refreshError != null)
                        _WarningPanel(message: _refreshError!),
                      _RequestSection(
                        title: 'Needs your action',
                        requests: needsAction,
                        empty: 'No signing requests need your action.',
                      ),
                      _RequestSection(
                        title: 'Ready to broadcast',
                        requests: ready,
                        empty:
                            'No completed signatures are ready to broadcast.',
                      ),
                      _RequestSection(
                        title: 'Waiting on others',
                        requests: waitingOnOthers,
                        empty: 'No signing requests are waiting on others.',
                      ),
                      _RequestSection(
                        title: 'Requested by me',
                        requests: requestedByMe,
                        empty: 'No open requests created by you.',
                      ),
                      _RequestSection(
                        title: 'Review only',
                        requests: reviewOnly,
                        empty: 'No review-only signing requests.',
                      ),
                      _RequestSection(
                        title: 'Completed',
                        requests: completed,
                        empty: 'No completed multisig sends yet.',
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
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

  String _localParticipantId(List<MultisigSigningRequestRecord> requests) {
    if (requests.isEmpty) return '';
    return requests.first.localParticipantId;
  }

  bool _needsLocalAction(
    MultisigSigningRequestRecord request,
    String localParticipantId,
  ) {
    if (!request.coordinatorSubmitted) return false;
    if (!request.selectedParticipantIds.contains(localParticipantId) ||
        request.isBroadcasted) {
      return false;
    }
    if (!request.round1ParticipantIds.contains(localParticipantId)) {
      return true;
    }
    final round1Complete =
        request.round1ParticipantIds.length >=
        request.selectedParticipantIds.length;
    return round1Complete &&
        !request.round2ParticipantIds.contains(localParticipantId);
  }

  bool _waitingOnOtherSigners(
    MultisigSigningRequestRecord request,
    String localParticipantId,
  ) {
    if (!request.coordinatorSubmitted || request.isBroadcasted) return false;
    if (request.requesterParticipantId == localParticipantId) return false;
    if (!request.selectedParticipantIds.contains(localParticipantId)) {
      return false;
    }
    return request.round1ParticipantIds.contains(localParticipantId) ||
        request.round2ParticipantIds.contains(localParticipantId);
  }
}

class _SessionIdBadge extends StatelessWidget {
  const _SessionIdBadge({required this.sessionId, required this.isLoading});

  final String? sessionId;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final value = sessionId?.trim();
    final displayValue = value == null || value.isEmpty
        ? isLoading
              ? 'Loading'
              : 'Unavailable'
        : value;

    return Tooltip(
      message: value == null || value.isEmpty ? displayValue : value,
      child: DecoratedBox(
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
            'Session ID: $displayValue',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.labelMedium.copyWith(
              color: colors.text.primary,
            ),
          ),
        ),
      ),
    );
  }
}

class _RequestSection extends StatelessWidget {
  const _RequestSection({
    required this.title,
    required this.requests,
    required this.empty,
  });

  final String title;
  final List<MultisigSigningRequestRecord> requests;
  final String empty;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTypography.headlineSmall),
          const SizedBox(height: AppSpacing.xs),
          if (requests.isEmpty)
            _EmptySectionLabel(empty)
          else
            for (final request in requests) _RequestRow(request: request),
        ],
      ),
    );
  }
}

class _RequestRow extends StatelessWidget {
  const _RequestRow({required this.request});

  final MultisigSigningRequestRecord request;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final amount = ZecAmount.fromZatoshi(
      BigInt.tryParse(request.amountZatoshi) ?? BigInt.zero,
    ).receipt;
    final reviewOnly = request.isReviewOnly;
    final stateLabel = request.isBroadcasted
        ? 'Broadcasted'
        : !request.coordinatorSubmitted
        ? 'Pending'
        : reviewOnly
        ? 'Review'
        : request.readyToBroadcast
        ? 'Ready'
        : request.localParticipantSelected &&
              (request.round1ParticipantIds.contains(
                    request.localParticipantId,
                  ) ||
                  request.round2ParticipantIds.contains(
                    request.localParticipantId,
                  ))
        ? 'Waiting'
        : 'Requested';

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => context.go(
          '/multisig/sign/${Uri.encodeComponent(request.signingRequestId)}',
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surface.card,
            border: Border.all(color: colors.border.subtle),
            borderRadius: BorderRadius.circular(AppRadii.medium),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Row(
              children: [
                const AppIcon(AppIcons.shieldKeyholeOutline),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(amount.toString(), style: AppTypography.labelLarge),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        request.recipientAddress,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.labelMedium.copyWith(
                          color: colors.text.secondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                if (reviewOnly)
                  const _ProgressPill(label: 'Review only')
                else ...[
                  _ProgressPill(
                    label:
                        'R1 ${request.round1ParticipantIds.length}/${request.selectedParticipantIds.length}',
                  ),
                  const SizedBox(width: AppSpacing.xxs),
                  _ProgressPill(
                    label:
                        'R2 ${request.round2ParticipantIds.length}/${request.selectedParticipantIds.length}',
                  ),
                ],
                const SizedBox(width: AppSpacing.sm),
                SizedBox(
                  width: 96,
                  child: Text(
                    stateLabel,
                    textAlign: TextAlign.right,
                    style: AppTypography.labelMedium.copyWith(
                      color: colors.text.secondary,
                    ),
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

class _ProgressPill extends StatelessWidget {
  const _ProgressPill({required this.label});

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
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Text(
        message,
        style: AppTypography.labelMedium.copyWith(color: colors.text.warning),
      ),
    );
  }
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Expanded(
      child: Center(
        child: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AppIcon(AppIcons.users, size: AppIconSize.large),
              const SizedBox(height: AppSpacing.sm),
              Text(title, style: AppTypography.headlineMedium),
              const SizedBox(height: AppSpacing.xs),
              Text(
                body,
                textAlign: TextAlign.center,
                style: AppTypography.labelMedium.copyWith(
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

class _EmptySectionLabel extends StatelessWidget {
  const _EmptySectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Text(
        text,
        style: AppTypography.labelMedium.copyWith(color: colors.text.secondary),
      ),
    );
  }
}
