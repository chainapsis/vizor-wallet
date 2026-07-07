import 'dart:async';

import 'package:flutter/material.dart' show CircularProgressIndicator, Scaffold;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/formatting/address_display.dart';
import '../../../../core/formatting/zec_amount.dart';
import '../../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/app_icon_hover_button.dart';
import '../../../../core/widgets/mobile/mobile_review_row.dart';
import '../../../../core/widgets/mobile/mobile_surface_card.dart';
import '../../../../providers/account_provider.dart';
import '../../../../providers/multisig_account_material_provider.dart';
import '../../../../providers/multisig_operation_error.dart';
import '../../../../providers/multisig_realtime_provider.dart';
import '../../../../providers/multisig_signing_request_provider.dart';
import '../../multisig_signing_request_summary.dart';

class MobileMultisigInboxScreen extends ConsumerStatefulWidget {
  const MobileMultisigInboxScreen({super.key});

  @override
  ConsumerState<MobileMultisigInboxScreen> createState() =>
      _MobileMultisigInboxScreenState();
}

class _MobileMultisigInboxScreenState
    extends ConsumerState<MobileMultisigInboxScreen> {
  bool _refreshing = false;
  String? _refreshError;
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
      setState(() => _refreshError = friendlyMultisigError(e));
    } finally {
      if (mounted) setState(() => _refreshing = false);
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
    if (_realtimeKey == key && notifier.updateTarget(target)) return;
    _releaseRealtimeLease();
    _realtimeKey = key;
    _realtimeLease = notifier.acquire(target, reason: 'mobile-signing-inbox');
  }

  void _releaseRealtimeLease() {
    _realtimeLease?.dispose();
    _realtimeLease = null;
    _realtimeKey = null;
  }

  void _handleBack() {
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final accountState = ref.watch(accountProvider).value;
    final accountUuid = accountState?.activeAccountUuid;
    final isMultisig =
        accountUuid != null &&
        ref.read(accountProvider.notifier).isMultisigAccount(accountUuid);
    final materials = ref.watch(multisigAccountMaterialsProvider).value;
    final activeMaterial = _materialForAccount(materials, accountUuid);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncRealtimeLease(isMultisig ? activeMaterial : null);
    });

    final requestsAsync = ref.watch(multisigSigningRequestsProvider);
    final activeRequests = activeMultisigSigningRequestsForAccount(
      requestsAsync.value ?? const <MultisigSigningRequestRecord>[],
      accountUuid,
    );
    final groups = groupMultisigSigningRequests(activeRequests);
    final loading = requestsAsync.isLoading && activeRequests.isEmpty;

    return Scaffold(
      backgroundColor: context.colors.background.window,
      body: SafeArea(
        child: Column(
          children: [
            MobileTopNav.back(
              title: 'Multisig',
              onBack: _handleBack,
              trailing: _RefreshButton(
                refreshing: _refreshing,
                onRefresh: isMultisig ? () => unawaited(_refresh()) : null,
              ),
            ),
            Expanded(
              child: !isMultisig
                  ? const _EmptyState(
                      title: 'No multisig account',
                      body:
                          'Switch to a multisig account to view active sends.',
                    )
                  : loading
                  ? const Center(child: CircularProgressIndicator())
                  : _InboxBody(
                      groups: groups,
                      refreshError: _refreshError,
                      material: activeMaterial,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RefreshButton extends StatelessWidget {
  const _RefreshButton({required this.refreshing, required this.onRefresh});

  final bool refreshing;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    return AppIconHoverButton(
      icon: AppIcons.renew,
      semanticLabel: refreshing ? 'Refreshing' : 'Refresh',
      tooltip: refreshing ? 'Refreshing' : 'Refresh',
      onTap: onRefresh ?? () {},
      iconColor: onRefresh == null
          ? context.colors.icon.disabled
          : context.colors.icon.accent,
    );
  }
}

class _InboxBody extends StatelessWidget {
  const _InboxBody({
    required this.groups,
    required this.refreshError,
    required this.material,
  });

  final MultisigSigningRequestGroups groups;
  final String? refreshError;
  final MultisigAccountMaterial? material;

  @override
  Widget build(BuildContext context) {
    if (groups.isEmpty && refreshError == null) {
      return const _EmptyState(
        title: 'No active multisig sends',
        body: 'New requests will appear here when they need your attention.',
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.s,
        AppSpacing.sm,
        AppSpacing.lg,
      ),
      children: [
        _SummaryCard(groups: groups, material: material),
        if (refreshError != null) ...[
          const SizedBox(height: AppSpacing.s),
          _InlineWarning(message: refreshError!),
        ],
        const SizedBox(height: AppSpacing.base),
        if (groups.needsAction.isNotEmpty)
          _RequestSection(
            title: 'Needs your action',
            requests: groups.needsAction,
          ),
        if (groups.readyToSend.isNotEmpty)
          _RequestSection(title: 'Ready to send', requests: groups.readyToSend),
        if (groups.waiting.isNotEmpty)
          _RequestSection(
            title: 'Waiting for others',
            requests: groups.waiting,
          ),
        if (groups.reviewOnly.isNotEmpty)
          _RequestSection(title: 'Review only', requests: groups.reviewOnly),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.groups, required this.material});

  final MultisigSigningRequestGroups groups;
  final MultisigAccountMaterial? material;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final groupLabel = material == null
        ? null
        : '${material!.threshold} of ${material!.participantCount}';
    final subtitle = groups.actionableCount > 0
        ? 'Choose a send below to continue.'
        : groups.waiting.isNotEmpty
        ? 'Waiting for the group to continue.'
        : groups.reviewOnly.isNotEmpty
        ? 'Requests available for review.'
        : 'No active sends right now.';

    return MobileSurfaceCard(
      child: Row(
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
                  multisigSigningHomeTitle(groups),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodyLarge.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colors.text.accent,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  groupLabel == null ? subtitle : '$groupLabel · $subtitle',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.labelMedium.copyWith(
                    color: colors.text.secondary,
                  ),
                ),
              ],
            ),
          ),
        ],
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
      padding: const EdgeInsets.only(bottom: AppSpacing.base),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            child: Text(
              title,
              style: AppTypography.labelLarge.copyWith(
                fontWeight: FontWeight.w600,
                color: context.colors.text.accent,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          for (final request in requests) ...[
            _RequestCard(request: request),
            const SizedBox(height: AppSpacing.xs),
          ],
        ],
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({required this.request});

  final MultisigSigningRequestRecord request;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final amount = ZecAmount.fromZatoshi(
      BigInt.tryParse(request.amountZatoshi) ?? BigInt.zero,
    ).activityDetail.toString();
    final signerCount = request.selectedParticipantIds.length;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.push(
        '/multisig/sign/${Uri.encodeComponent(request.signingRequestId)}',
      ),
      child: MobileSurfaceCard(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          amount,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.bodyLarge.copyWith(
                            fontWeight: FontWeight.w600,
                            color: colors.text.accent,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      _StatusPill(
                        label: multisigSigningRequestStatusLabel(request),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    multisigSigningRequestStatusBody(request),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.labelMedium.copyWith(
                      color: colors.text.secondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    truncatedAddress(request.recipientAddress),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.labelMedium.copyWith(
                      color: colors.text.secondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    children: [
                      _ProgressChip(
                        label:
                            'Ready ${request.round1SelectedParticipantCount}/$signerCount',
                      ),
                      const SizedBox(width: AppSpacing.xxs),
                      _ProgressChip(
                        label:
                            'Approved ${request.round2SelectedParticipantCount}/$signerCount',
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            AppIcon(
              AppIcons.chevronForward,
              color: colors.icon.muted,
              size: AppIconSize.medium,
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.background.overlay,
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
          style: AppTypography.labelSmall.copyWith(
            color: colors.text.secondary,
          ),
        ),
      ),
    );
  }
}

class _ProgressChip extends StatelessWidget {
  const _ProgressChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppTypography.labelSmall.copyWith(
        color: context.colors.text.secondary,
      ),
    );
  }
}

class _InlineWarning extends StatelessWidget {
  const _InlineWarning({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppIcon(AppIcons.warning, color: context.colors.text.warning),
        const SizedBox(width: AppSpacing.xxs),
        Expanded(
          child: Text(
            message,
            style: AppTypography.labelMedium.copyWith(
              color: context.colors.text.warning,
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.title, required this.body});

  final String title;
  final String body;

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
              child: AppIcon(AppIcons.users, size: AppIconSize.large),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTypography.headlineLarge.copyWith(
                color: colors.text.accent,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              body,
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(
                color: colors.text.secondary,
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
