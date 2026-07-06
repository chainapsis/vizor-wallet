import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/formatting/zec_amount.dart';
import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_layout.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/layout/app_pane_scroll_scaffold.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/multisig_account_material_provider.dart';
import '../../../providers/multisig_operation_error.dart';
import '../../../providers/multisig_realtime_provider.dart';
import '../../../providers/multisig_signing_request_provider.dart';

const _multisigSigningContentMaxWidth = 560.0;
const _multisigHeaderTitleHeight = 33.0;

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
        _refreshError = friendlyMultisigError(e);
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
    if (_realtimeKey == key && notifier.updateTarget(target)) {
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
    final activeRequests = requests
        .where((request) => !request.hasBroadcastTxid)
        .toList();
    final localParticipantId = _localParticipantId(requests);
    final actionNeeded = activeRequests
        .where(
          (request) =>
              request.readyToBroadcast ||
              _needsLocalAction(request, localParticipantId),
        )
        .toList();
    final waitingForSignatures = activeRequests
        .where((request) => !actionNeeded.contains(request))
        .toList();

    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AppPaneToolbar(backLinkMinWidth: 60),
            _MultisigHeader(
              material: activeMaterial,
              isMaterialLoading: materialsAsync.isLoading,
              isMultisig: isMultisig,
              isRefreshing: _refreshing,
              onSetup: () => context.go('/multisig/connect'),
              onRefresh: isMultisig && !_refreshing
                  ? () => unawaited(_refresh())
                  : null,
            ),
            if (!isMultisig)
              const _EmptyPanel(
                title: 'No multisig account selected',
                body: 'Switch to a multisig account to view active sends.',
              )
            else if (requestsAsync.isLoading && requests.isEmpty)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (activeRequests.isEmpty)
              Expanded(
                child: Column(
                  children: [
                    if (_refreshError != null)
                      _WarningPanel(message: _refreshError!),
                    const Expanded(
                      child: _EmptyPanelContent(
                        title: 'No active multisig sends',
                        body:
                            'New multisig sends will appear here when they need your attention.',
                      ),
                    ),
                  ],
                ),
              )
            else
              Expanded(
                child: _RequestListView(
                  refreshError: _refreshError,
                  actionNeeded: actionNeeded,
                  waitingForSignatures: waitingForSignatures,
                ),
              ),
          ],
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
        request.hasBroadcastTxid) {
      return false;
    }
    if (request.readyToBroadcast) return false;
    if (!request.localRound1Submitted) {
      return true;
    }
    return request.round1Complete && !request.localRound2Submitted;
  }
}

class _MultisigHeader extends StatelessWidget {
  const _MultisigHeader({
    required this.material,
    required this.isMaterialLoading,
    required this.isMultisig,
    required this.isRefreshing,
    required this.onSetup,
    required this.onRefresh,
  });

  final MultisigAccountMaterial? material;
  final bool isMaterialLoading;
  final bool isMultisig;
  final bool isRefreshing;
  final VoidCallback onSetup;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final showBadge = isMultisig && (material != null || isMaterialLoading);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: _multisigSigningContentMaxWidth,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.xs,
            AppSpacing.md,
            AppSpacing.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: _multisigHeaderTitleHeight,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Text(
                      'Multisig',
                      style: AppTypography.headlineLarge.copyWith(
                        color: context.colors.text.accent,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (showBadge)
                      Align(
                        alignment: Alignment.centerRight,
                        child: _GroupBadge(
                          material: material,
                          isLoading: isMaterialLoading,
                        ),
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
                      onPressed: onSetup,
                      variant: AppButtonVariant.secondary,
                      size: AppButtonSize.small,
                      leading: const AppIcon(AppIcons.cog),
                      child: const Text('Setup'),
                    ),
                    const SizedBox(width: AppSpacing.xxs),
                    AppButton(
                      onPressed: onRefresh,
                      variant: AppButtonVariant.secondary,
                      size: AppButtonSize.small,
                      leading: const AppIcon(AppIcons.renew),
                      child: Text(isRefreshing ? 'Refreshing' : 'Refresh'),
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
}

class _GroupBadge extends StatelessWidget {
  const _GroupBadge({required this.material, required this.isLoading});

  final MultisigAccountMaterial? material;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final sessionId = material?.sessionId.trim();
    final displayValue = material == null
        ? 'Loading'
        : '${material!.threshold} of ${material!.participantCount}';
    final tooltip = sessionId == null || sessionId.isEmpty
        ? displayValue
        : 'Setup ID: $sessionId';

    return Tooltip(
      message: tooltip,
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
            displayValue,
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

class _RequestListView extends StatelessWidget {
  const _RequestListView({
    required this.refreshError,
    required this.actionNeeded,
    required this.waitingForSignatures,
  });

  final String? refreshError;
  final List<MultisigSigningRequestRecord> actionNeeded;
  final List<MultisigSigningRequestRecord> waitingForSignatures;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      if (refreshError != null) _WarningPanel(message: refreshError!),
      if (actionNeeded.isNotEmpty)
        _RequestSection(title: 'Action needed', requests: actionNeeded),
      if (waitingForSignatures.isNotEmpty)
        _RequestSection(
          title: 'Waiting for signatures',
          requests: waitingForSignatures,
        ),
    ];

    return AppPaneScrollbar(
      builder: (context, controller) => ListView(
        controller: controller,
        primary: false,
        padding: const EdgeInsets.only(top: AppSpacing.sm, bottom: 40),
        children: [
          for (final child in children)
            _CenteredTrack(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: child,
            ),
        ],
      ),
    );
  }
}

class _CenteredTrack extends StatelessWidget {
  const _CenteredTrack({required this.padding, required this.child});

  final EdgeInsets padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: _multisigSigningContentMaxWidth,
        ),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class _RequestSection extends StatelessWidget {
  const _RequestSection({required this.title, required this.requests});

  final String title;
  final List<MultisigSigningRequestRecord> requests;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTypography.headlineSmall),
          const SizedBox(height: AppSpacing.xs),
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
    final signerCount = request.selectedParticipantIds.length;
    final stateLabel = !request.coordinatorSubmitted
        ? 'Preparing'
        : reviewOnly
        ? 'Review only'
        : request.readyToBroadcast
        ? 'Ready to send'
        : _needsSignature(request)
        ? 'Sign needed'
        : request.requesterParticipantId == request.localParticipantId
        ? 'Created by you'
        : 'Waiting';
    final progressLabel = signerCount == 0
        ? 'No signers'
        : 'Signed ${request.round2SelectedParticipantCount}/$signerCount';

    final ownershipLabel =
        request.requesterParticipantId == request.localParticipantId &&
            !reviewOnly &&
            stateLabel != 'Created by you'
        ? 'Created by you'
        : null;

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
                _ProgressPill(label: progressLabel),
                if (ownershipLabel != null) ...[
                  const SizedBox(width: AppSpacing.xxs),
                  _ProgressPill(label: ownershipLabel),
                ],
                const SizedBox(width: AppSpacing.sm),
                SizedBox(
                  width: 112,
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

  bool _needsSignature(MultisigSigningRequestRecord request) {
    if (!request.localParticipantSelected || request.readyToBroadcast) {
      return false;
    }
    if (!request.localRound1Submitted) {
      return true;
    }
    return request.round1Complete && !request.localRound2Submitted;
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
    return Expanded(
      child: _EmptyPanelContent(title: title, body: body),
    );
  }
}

class _EmptyPanelContent extends StatelessWidget {
  const _EmptyPanelContent({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Center(
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
    );
  }
}
