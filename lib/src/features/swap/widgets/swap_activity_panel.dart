import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart' show Material, MaterialType;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_pane_modal_overlay.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../providers/account_provider.dart';
import '../domain/near_intents_explorer.dart';
import '../models/swap_prototype_models.dart';
import '../providers/swap_prototype_provider.dart';
import 'redacted_receipt_drawer.dart';
import 'swap_amount_text.dart';
import 'swap_asset_icon.dart';
import 'swap_copy_feedback.dart';
import 'swap_deposit_qr_panel.dart';
import 'swap_keystone_signing_overlay.dart';
import 'swap_queue_panel.dart';

class SwapActivityDetailSurface extends ConsumerStatefulWidget {
  const SwapActivityDetailSurface({
    required this.intentId,
    this.autoSignZecDeposit = false,
    super.key,
  });

  final String intentId;
  final bool autoSignZecDeposit;

  @override
  ConsumerState<SwapActivityDetailSurface> createState() =>
      _SwapActivityDetailSurfaceState();
}

class _SwapKeystoneSigningRequest {
  const _SwapKeystoneSigningRequest({
    required this.intentId,
    required this.accountUuid,
    this.removeUnsentIntentOnCancel = false,
  });

  final String intentId;
  final String accountUuid;
  final bool removeUnsentIntentOnCancel;
}

class _SwapActivityDetailSurfaceState
    extends ConsumerState<SwapActivityDetailSurface> {
  final _toastOverlayContextKey = GlobalKey(
    debugLabel: 'swap_activity_toast_overlay_context',
  );
  String? _removeIntentId;
  _SwapKeystoneSigningRequest? _keystoneSigningRequest;
  var _initialIntentApplied = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _applyInitialIntent();
    });
  }

  @override
  void didUpdateWidget(covariant SwapActivityDetailSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.intentId != widget.intentId ||
        oldWidget.autoSignZecDeposit != widget.autoSignZecDeposit) {
      _initialIntentApplied = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _applyInitialIntent();
      });
    }
  }

  void _applyInitialIntent() {
    if (_initialIntentApplied) return;
    final intentId = widget.intentId.trim();
    if (intentId.isEmpty) {
      _initialIntentApplied = true;
      return;
    }
    final intent = _intentById(
      ref.read(swapPrototypeProvider).intents,
      intentId,
    );
    if (intent == null) return;
    ref.read(swapPrototypeProvider.notifier).selectIntent(intentId);
    final needsAutoSign =
        widget.autoSignZecDeposit &&
        _isHardwareIntent(intent) &&
        intent.direction == SwapDirection.zecToExternal &&
        !(intent.depositTxHash?.trim().isNotEmpty ?? false);
    setState(() {
      _initialIntentApplied = true;
      if (needsAutoSign) {
        _keystoneSigningRequest = _SwapKeystoneSigningRequest(
          intentId: intent.id,
          accountUuid: intent.accountUuid ?? _activeAccountUuid ?? '',
          removeUnsentIntentOnCancel: true,
        );
      }
    });
  }

  String? get _activeAccountUuid =>
      ref.read(accountProvider).value?.activeAccountUuid;

  BuildContext _toastContext(BuildContext fallback) =>
      _toastOverlayContextKey.currentContext ?? fallback;

  bool _isHardwareIntent(SwapPrototypeIntent intent) {
    final accountUuid = intent.accountUuid;
    if (accountUuid == null || accountUuid.trim().isEmpty) return false;
    final accountState = ref.read(accountProvider).value;
    final accountHardwareByUuid = {
      for (final account in accountState?.accounts ?? const <AccountInfo>[])
        account.uuid: account.isHardware,
    };
    return accountHardwareByUuid[accountUuid] ?? false;
  }

  void _closeRemoveIntentDialog() {
    setState(() => _removeIntentId = null);
  }

  void _refreshStatus() {
    final selected = ref.read(swapPrototypeProvider).selectedIntentOrNull;
    if (selected == null || !canRefreshSwapIntentStatus(selected.status)) {
      return;
    }
    unawaited(
      ref.read(swapPrototypeProvider.notifier).refreshSelectedIntentStatus(),
    );
  }

  void _submitDepositTransaction() {
    unawaited(
      ref
          .read(swapPrototypeProvider.notifier)
          .submitSelectedDepositTransaction(),
    );
  }

  void _reviewFreshQuote() {
    ref.read(swapPrototypeProvider.notifier).prepareRetryFromSelectedIntent();
    context.go('/swap');
  }

  void _copyNearIntentsExplorerLink(
    BuildContext context,
    SwapPrototypeIntent intent,
  ) {
    final uri = nearIntentsExplorerUri(
      nearIntentHash: intent.nearIntentHash,
      depositTxHash: intent.depositTxHash,
      depositAddress: intent.depositAddress ?? intent.id,
    );
    if (uri == null) return;
    copySwapText(
      _toastContext(context),
      text: uri.toString(),
      toastMessage: 'Explorer Link Copied',
    );
  }

  void _requestRemoveIntent() {
    final intent = ref.read(swapPrototypeProvider).selectedIntentOrNull;
    if (intent == null) return;
    setState(() => _removeIntentId = intent.id);
  }

  void _confirmRemoveIntent() {
    final intentId = _removeIntentId;
    if (intentId == null) return;
    _closeRemoveIntentDialog();
    unawaited(ref.read(swapPrototypeProvider.notifier).removeIntent(intentId));
    context.go('/activity');
  }

  void _signZecDeposit(SwapPrototypeIntent intent) {
    setState(() {
      _keystoneSigningRequest = _SwapKeystoneSigningRequest(
        intentId: intent.id,
        accountUuid: intent.accountUuid ?? _activeAccountUuid ?? '',
      );
    });
  }

  void _closeKeystoneSigning({bool cleanupCancelledRequest = false}) {
    final request = _keystoneSigningRequest;
    setState(() => _keystoneSigningRequest = null);
    if (cleanupCancelledRequest &&
        request != null &&
        request.removeUnsentIntentOnCancel) {
      unawaited(
        ref
            .read(swapPrototypeProvider.notifier)
            .removeUnsentHardwareDepositIntent(request.intentId),
      );
    }
  }

  void _handleKeystoneDepositBroadcast(
    BuildContext context,
    SwapKeystoneBroadcastResult result,
  ) {
    final request = _keystoneSigningRequest;
    if (request == null) return;
    _closeKeystoneSigning();
    unawaited(
      ref
          .read(swapPrototypeProvider.notifier)
          .submitDepositTransactionForIntent(
            intentId: request.intentId,
            accountUuid: request.accountUuid,
            txHash: result.txHash,
            broadcastStatus: result.status,
            broadcastMessage: result.message,
          ),
    );
    showAppToast(
      _toastContext(context),
      result.isCertain ? 'ZEC Deposit Sent' : 'ZEC Deposit Checking',
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(
      accountProvider.select((value) => value.value?.activeAccountUuid),
      (previous, next) {
        if (previous == next || !mounted) return;
        setState(() {
          _removeIntentId = null;
          _keystoneSigningRequest = null;
        });
        context.go('/activity');
      },
    );

    final state = ref.watch(swapPrototypeProvider);
    final liveFundsEnabled = ref.watch(swapLiveFundsEnabledProvider);
    final initialIntentId = widget.intentId.trim();
    if (!_initialIntentApplied && initialIntentId.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _applyInitialIntent();
      });
    }
    final activityDetailIntent = _intentById(state.intents, initialIntentId);
    final removeIntent = _intentById(state.intents, _removeIntentId);
    final keystoneSigningRequest = _keystoneSigningRequest;
    final keystoneSigningIntent = _intentById(
      state.intents,
      keystoneSigningRequest?.intentId,
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (activityDetailIntent == null)
          const _SwapActivityMissingPanel()
        else
          SwapActivityDetailPagePanel(
            state: state,
            intent: activityDetailIntent,
            liveFundsEnabled: liveFundsEnabled,
            onCopyText:
                ({required String text, required String toastMessage}) =>
                    copySwapText(
                      _toastContext(context),
                      text: text,
                      toastMessage: toastMessage,
                    ),
            onRefreshStatus: _refreshStatus,
            onDepositTxHashChanged: ref
                .read(swapPrototypeProvider.notifier)
                .updateDepositTxHash,
            onSubmitDepositTransaction: _submitDepositTransaction,
            onReviewFreshQuote: _reviewFreshQuote,
            onSignZecDeposit: _signZecDeposit,
            onCopyExplorerLink: (intent) =>
                _copyNearIntentsExplorerLink(context, intent),
            onRemoveIntent: _requestRemoveIntent,
            intentIsHardware: _isHardwareIntent(activityDetailIntent),
          ),
        if (keystoneSigningRequest != null && keystoneSigningIntent != null)
          Positioned.fill(
            child: SwapKeystoneSigningOverlay(
              intent: keystoneSigningIntent,
              onCancel: () =>
                  _closeKeystoneSigning(cleanupCancelledRequest: true),
              onDepositBroadcast: (result) =>
                  _handleKeystoneDepositBroadcast(context, result),
            ),
          ),
        if (removeIntent != null)
          AppPaneModalOverlay(
            onDismiss: _closeRemoveIntentDialog,
            child: Material(
              type: MaterialType.transparency,
              child: RemoveSwapActivityModal(
                intent: removeIntent,
                onCancel: _closeRemoveIntentDialog,
                onConfirm: _confirmRemoveIntent,
              ),
            ),
          ),
        Positioned.fill(
          child: IgnorePointer(
            child: AppToastHost(
              key: const ValueKey('swap_toast_overlay_host'),
              child: SizedBox.expand(key: _toastOverlayContextKey),
            ),
          ),
        ),
      ],
    );
  }
}

SwapPrototypeIntent? _intentById(
  List<SwapPrototypeIntent> intents,
  String? intentId,
) {
  if (intentId == null) return null;
  for (final intent in intents) {
    if (intent.id == intentId) return intent;
  }
  return null;
}

class SwapActivityPanel extends StatelessWidget {
  const SwapActivityPanel({
    required this.state,
    required this.onRefreshStatus,
    required this.onIntentSelected,
    super.key,
  });

  final SwapPrototypeState state;
  final VoidCallback onRefreshStatus;
  final ValueChanged<String> onIntentSelected;

  @override
  Widget build(BuildContext context) {
    final selectedIntent = state.selectedIntentOrNull;
    final hasRefreshableIntents = state.intents.any(
      (intent) => canRefreshSwapIntentStatus(intent.status),
    );
    final queueRefreshAction = hasRefreshableIntents ? onRefreshStatus : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwapQueuePanel(
          intents: state.intents,
          selectedIntentId: selectedIntent?.id,
          onIntentSelected: onIntentSelected,
          statusRefreshing: state.statusRefreshing,
          onRefresh: queueRefreshAction,
        ),
        if (selectedIntent == null) ...[
          const SizedBox(height: AppSpacing.xs),
          const SwapActivityEmptyState(),
        ],
      ],
    );
  }
}

class SwapActivityDetailEntrance extends StatelessWidget {
  const SwapActivityDetailEntrance({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: const ValueKey('swap_activity_detail_entrance'),
      tween: Tween<double>(begin: 28, end: 0),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      child: child,
      builder: (context, dx, child) {
        final opacity = 1 - (dx.abs() / 28);
        return Opacity(
          opacity: opacity.clamp(0.0, 1.0).toDouble(),
          child: Transform.translate(offset: Offset(dx, 0), child: child),
        );
      },
    );
  }
}

class RemoveSwapActivityModal extends StatelessWidget {
  const RemoveSwapActivityModal({
    required this.intent,
    required this.onCancel,
    required this.onConfirm,
    super.key,
  });

  final SwapPrototypeIntent intent;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: Container(
        key: const ValueKey('swap_remove_intent_modal'),
        margin: const EdgeInsets.all(AppSpacing.sm),
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: colors.background.base,
          border: Border.all(color: colors.border.regular),
          borderRadius: BorderRadius.circular(AppRadii.small),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: colors.background.raised,
                    border: Border.all(color: colors.border.subtle),
                    borderRadius: BorderRadius.circular(AppRadii.xSmall),
                  ),
                  child: AppIcon(
                    AppIcons.warning,
                    size: AppIconSize.medium,
                    color: colors.icon.warning,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Remove from activity?',
                        style: AppTypography.headlineMedium.copyWith(
                          color: colors.text.accent,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        intent.pair,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.labelLarge.copyWith(
                          color: colors.text.secondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'This removes the saved swap from this wallet and stops polling it. '
              'If this wallet has not seen funds for its reserved ZEC address, the address is released for reuse.',
              style: AppTypography.bodyMedium.copyWith(
                color: colors.text.primary,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: colors.background.raised,
                border: Border.all(color: colors.border.subtle),
                borderRadius: BorderRadius.circular(AppRadii.xSmall),
              ),
              child: Text(
                'This does not cancel the provider quote or recover sent funds. Remove it only if you did not send funds, or if you saved the deposit details elsewhere for support.',
                style: AppTypography.bodySmall.copyWith(
                  color: colors.text.warning,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    key: const ValueKey('swap_remove_intent_cancel_button'),
                    onPressed: onCancel,
                    variant: AppButtonVariant.secondary,
                    size: AppButtonSize.medium,
                    child: const Text('Keep'),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: AppButton(
                    key: const ValueKey('swap_remove_intent_confirm_button'),
                    onPressed: onConfirm,
                    variant: AppButtonVariant.destructive,
                    size: AppButtonSize.medium,
                    child: const Text('Remove'),
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

class SwapActivityEmptyState extends StatelessWidget {
  const SwapActivityEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      key: const ValueKey('swap_activity_empty_state'),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: colors.background.base,
        border: Border.all(color: colors.border.regular),
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppIcon(AppIcons.history, size: 20, color: colors.icon.brandCrimson),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'No swap activity yet',
                  style: AppTypography.labelLarge.copyWith(
                    color: colors.text.accent,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  'Review a live quote to create an activity record with deposit, delivery, and recovery details.',
                  style: AppTypography.bodySmall.copyWith(
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

class _SwapActivityStack extends StatelessWidget {
  const _SwapActivityStack({
    required this.state,
    required this.selectedIntent,
    required this.onCopyText,
    required this.onRefreshStatus,
    required this.onDepositTxHashChanged,
    required this.onSubmitDepositTransaction,
    required this.onReviewFreshQuote,
    required this.onSignZecDeposit,
    required this.onCopyExplorerLink,
    required this.onRemoveIntent,
    required this.liveFundsEnabled,
    required this.intentIsHardware,
  });

  final SwapPrototypeState state;
  final SwapPrototypeIntent selectedIntent;
  final SwapSupportCopyText onCopyText;
  final VoidCallback onRefreshStatus;
  final ValueChanged<String> onDepositTxHashChanged;
  final VoidCallback onSubmitDepositTransaction;
  final VoidCallback onReviewFreshQuote;
  final ValueChanged<SwapPrototypeIntent> onSignZecDeposit;
  final ValueChanged<SwapPrototypeIntent> onCopyExplorerLink;
  final VoidCallback onRemoveIntent;
  final bool liveFundsEnabled;
  final bool intentIsHardware;

  @override
  Widget build(BuildContext context) {
    final depositInstruction = _ActivityDepositInstruction.fromIntent(
      selectedIntent,
    );
    final statusPlan = _ActivityStatusPlan.fromIntent(selectedIntent);
    final resolution = _ActivityResolution.fromIntent(selectedIntent);
    final showDepositControls = _showDepositControls(selectedIntent.status);
    final showSupportDetails = _showActivityReceipt(selectedIntent.status);
    final statusError = selectedIntent.statusError ?? state.statusError;
    final hasDepositTx =
        selectedIntent.depositTxHash?.trim().isNotEmpty ?? false;
    final showHardwareDepositAction =
        intentIsHardware &&
        selectedIntent.direction == SwapDirection.zecToExternal &&
        selectedIntent.status == SwapIntentStatus.awaitingDeposit &&
        !hasDepositTx;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ActiveSwapSummaryPanel(
          intent: selectedIntent,
          plan: statusPlan,
          statusRefreshing: state.statusRefreshing,
          canRefreshStatus: canRefreshSwapIntentStatus(selectedIntent.status),
          onRefreshStatus: onRefreshStatus,
          onCopyExplorerLink: onCopyExplorerLink,
          onRemoveIntent: onRemoveIntent,
        ),
        if (statusError != null) ...[
          const SizedBox(height: AppSpacing.xs),
          _ActivityStatusErrorPanel(message: statusError),
        ],
        const SizedBox(height: AppSpacing.xs),
        if (showHardwareDepositAction) ...[
          _ActivityHardwareActionPanel(
            key: const ValueKey('swap_hardware_deposit_action_panel'),
            iconName: AppIcons.qr,
            title: 'Sign ZEC deposit',
            message:
                'Use Keystone to approve one ZEC transaction to the swap deposit address.',
            buttonKey: const ValueKey('swap_hardware_deposit_button'),
            buttonLabel: 'Sign with Keystone',
            onPressed: () => onSignZecDeposit(selectedIntent),
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
        if (resolution != null) ...[
          _ActivityResolutionPanel(
            resolution: resolution,
            intent: selectedIntent,
            onReviewFreshQuote: onReviewFreshQuote,
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
        if (showDepositControls &&
            depositInstruction != null &&
            !showHardwareDepositAction) ...[
          _ActivityDepositActionPanel(
            state: state,
            instruction: depositInstruction,
            onDepositTxHashChanged: onDepositTxHashChanged,
            onSubmitDepositTransaction: onSubmitDepositTransaction,
            liveFundsEnabled: liveFundsEnabled,
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
        if (showSupportDetails) ...[
          _ActivitySupportDetailsSection(
            intent: selectedIntent,
            onCopyText: onCopyText,
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
      ],
    );
  }
}

class SwapActivityDetailPagePanel extends StatelessWidget {
  const SwapActivityDetailPagePanel({
    required this.state,
    required this.intent,
    required this.liveFundsEnabled,
    required this.onCopyText,
    required this.onRefreshStatus,
    required this.onDepositTxHashChanged,
    required this.onSubmitDepositTransaction,
    required this.onReviewFreshQuote,
    required this.onSignZecDeposit,
    required this.onCopyExplorerLink,
    required this.onRemoveIntent,
    required this.intentIsHardware,
    super.key,
  });

  final SwapPrototypeState state;
  final SwapPrototypeIntent intent;
  final bool liveFundsEnabled;
  final SwapSupportCopyText onCopyText;
  final VoidCallback onRefreshStatus;
  final ValueChanged<String> onDepositTxHashChanged;
  final VoidCallback onSubmitDepositTransaction;
  final VoidCallback onReviewFreshQuote;
  final ValueChanged<SwapPrototypeIntent> onSignZecDeposit;
  final ValueChanged<SwapPrototypeIntent> onCopyExplorerLink;
  final VoidCallback onRemoveIntent;
  final bool intentIsHardware;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      key: const ValueKey('swap_activity_detail_page'),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xs,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ActivityAssetPair(intent: intent),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Swap progress',
                      key: const ValueKey('swap_activity_detail_title'),
                      style: AppTypography.headlineSmall.copyWith(
                        color: colors.text.accent,
                        fontSize: 24,
                        height: 30 / 24,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      intent.pair,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.labelLarge.copyWith(
                        color: colors.text.secondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: _ActivityDetailScrollArea(
              child: _SwapActivityStack(
                state: state,
                selectedIntent: intent,
                onCopyText: onCopyText,
                onRefreshStatus: onRefreshStatus,
                onDepositTxHashChanged: onDepositTxHashChanged,
                onSubmitDepositTransaction: onSubmitDepositTransaction,
                onReviewFreshQuote: onReviewFreshQuote,
                onSignZecDeposit: onSignZecDeposit,
                onCopyExplorerLink: onCopyExplorerLink,
                onRemoveIntent: onRemoveIntent,
                liveFundsEnabled: liveFundsEnabled,
                intentIsHardware: intentIsHardware,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SwapActivityMissingPanel extends StatelessWidget {
  const _SwapActivityMissingPanel();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      key: const ValueKey('swap_activity_detail_missing'),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Swap activity could not be loaded.',
            style: AppTypography.headlineSmall.copyWith(
              color: colors.text.accent,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Return to Activity and select a saved swap.',
            style: AppTypography.bodyMedium.copyWith(
              color: colors.text.secondary,
            ),
          ),
        ],
      ),
    );
  }
}

class SwapActivityDetailModal extends StatelessWidget {
  const SwapActivityDetailModal({
    required this.state,
    required this.intent,
    required this.liveFundsEnabled,
    required this.onCopyText,
    required this.onClose,
    required this.onRefreshStatus,
    required this.onDepositTxHashChanged,
    required this.onSubmitDepositTransaction,
    required this.onReviewFreshQuote,
    required this.onSignZecDeposit,
    required this.onCopyExplorerLink,
    required this.onRemoveIntent,
    required this.intentIsHardware,
    super.key,
  });

  final SwapPrototypeState state;
  final SwapPrototypeIntent intent;
  final bool liveFundsEnabled;
  final SwapSupportCopyText onCopyText;
  final VoidCallback onClose;
  final VoidCallback onRefreshStatus;
  final ValueChanged<String> onDepositTxHashChanged;
  final VoidCallback onSubmitDepositTransaction;
  final VoidCallback onReviewFreshQuote;
  final ValueChanged<SwapPrototypeIntent> onSignZecDeposit;
  final ValueChanged<SwapPrototypeIntent> onCopyExplorerLink;
  final VoidCallback onRemoveIntent;
  final bool intentIsHardware;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : MediaQuery.sizeOf(context).height;
        return ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: SizedBox(
            height: height,
            child: Container(
              key: const ValueKey('swap_activity_detail_modal'),
              margin: const EdgeInsets.all(AppSpacing.xs),
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: colors.background.base,
                border: Border.all(color: colors.border.regular),
                borderRadius: BorderRadius.circular(AppRadii.small),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _ActivityAssetPair(intent: intent),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Swap progress',
                              key: const ValueKey('swap_activity_detail_title'),
                              style: AppTypography.headlineSmall.copyWith(
                                color: colors.text.accent,
                                fontSize: 24,
                                height: 30 / 24,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              intent.pair,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.labelLarge.copyWith(
                                color: colors.text.secondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      AppButton(
                        key: const ValueKey(
                          'swap_activity_detail_close_button',
                        ),
                        onPressed: onClose,
                        variant: AppButtonVariant.secondary,
                        size: AppButtonSize.large,
                        minWidth: 132,
                        leading: const AppIcon(AppIcons.cross, size: 20),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Expanded(
                    child: _ActivityDetailScrollArea(
                      child: _SwapActivityStack(
                        state: state,
                        selectedIntent: intent,
                        onCopyText: onCopyText,
                        onRefreshStatus: onRefreshStatus,
                        onDepositTxHashChanged: onDepositTxHashChanged,
                        onSubmitDepositTransaction: onSubmitDepositTransaction,
                        onReviewFreshQuote: onReviewFreshQuote,
                        onSignZecDeposit: onSignZecDeposit,
                        onCopyExplorerLink: onCopyExplorerLink,
                        onRemoveIntent: onRemoveIntent,
                        liveFundsEnabled: liveFundsEnabled,
                        intentIsHardware: intentIsHardware,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ActivityDetailScrollArea extends StatefulWidget {
  const _ActivityDetailScrollArea({required this.child});

  final Widget child;

  @override
  State<_ActivityDetailScrollArea> createState() =>
      _ActivityDetailScrollAreaState();
}

class _ActivityDetailScrollAreaState extends State<_ActivityDetailScrollArea> {
  late final ScrollController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: RawScrollbar(
        key: const ValueKey('swap_activity_detail_scrollbar'),
        controller: _controller,
        thumbVisibility: true,
        thickness: 4,
        radius: const Radius.circular(AppRadii.full),
        thumbColor: colors.border.regular.withValues(alpha: 0.72),
        mainAxisMargin: AppSpacing.xxs,
        crossAxisMargin: AppSpacing.xxs,
        child: SingleChildScrollView(
          key: const ValueKey('swap_activity_detail_scroll_view'),
          controller: _controller,
          child: Padding(
            key: const ValueKey('swap_activity_detail_scroll_gutter'),
            padding: const EdgeInsets.only(right: AppSpacing.s),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

class _ActivityAssetPair extends StatelessWidget {
  const _ActivityAssetPair({required this.intent});

  final SwapPrototypeIntent intent;

  @override
  Widget build(BuildContext context) {
    final sellAsset = _activitySellAsset(intent);
    final receiveAsset = _activityReceiveAsset(intent);
    if (sellAsset == null || receiveAsset == null) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      key: const ValueKey('swap_activity_detail_asset_pair'),
      width: 80,
      height: 48,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            top: 4,
            child: SwapAssetIcon(asset: sellAsset, selected: true, size: 38),
          ),
          Positioned(
            left: 36,
            top: 4,
            child: Container(
              padding: const EdgeInsets.all(1),
              decoration: BoxDecoration(
                color: context.colors.background.base,
                border: Border.all(color: context.colors.border.regular),
                borderRadius: BorderRadius.circular(AppRadii.full),
              ),
              child: SwapAssetIcon(
                asset: receiveAsset,
                selected: true,
                size: 38,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityStatusErrorPanel extends StatelessWidget {
  const _ActivityStatusErrorPanel({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: colors.text.destructive.withValues(alpha: 0.08),
        border: Border.all(
          color: colors.text.destructive.withValues(alpha: 0.26),
        ),
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppIcon(AppIcons.warning, size: 16, color: colors.icon.destructive),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              message,
              style: AppTypography.bodySmall.copyWith(
                color: colors.text.destructive,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityStatusPlan {
  const _ActivityStatusPlan({
    required this.title,
    required this.detail,
    required this.iconName,
    required this.tone,
  });

  static _ActivityStatusPlan fromIntent(SwapPrototypeIntent intent) {
    final sourceSymbol = _pairSymbol(intent.pair, 0);
    final receiveSymbol = _pairSymbol(intent.pair, 1);
    final hasDepositTx = intent.depositTxHash?.trim().isNotEmpty ?? false;

    return switch (intent.status) {
      SwapIntentStatus.awaitingDeposit => _ActivityStatusPlan(
        title: hasDepositTx ? '$sourceSymbol sent' : 'Send $sourceSymbol',
        detail: hasDepositTx
            ? 'Waiting for the deposit to confirm.'
            : 'Send once to the deposit address below.',
        iconName: hasDepositTx ? AppIcons.eye : AppIcons.link,
        tone: _ActivityStatusPlanTone.action,
      ),
      SwapIntentStatus.awaitingExternalDeposit => _ActivityStatusPlan(
        title: hasDepositTx ? '$sourceSymbol sent' : 'Send $sourceSymbol',
        detail: hasDepositTx
            ? 'Waiting for the source-chain deposit to confirm.'
            : 'Send once to the source-chain deposit address below.',
        iconName: hasDepositTx ? AppIcons.eye : AppIcons.link,
        tone: _ActivityStatusPlanTone.action,
      ),
      SwapIntentStatus.depositObserved => _ActivityStatusPlan(
        title: '$sourceSymbol deposit confirmed',
        detail: 'Preparing the $receiveSymbol delivery.',
        iconName: AppIcons.eye,
        tone: _ActivityStatusPlanTone.action,
      ),
      SwapIntentStatus.processing => _ActivityStatusPlan(
        title: '$receiveSymbol delivery in progress',
        detail: 'No new approval is needed.',
        iconName: AppIcons.renew,
        tone: _ActivityStatusPlanTone.action,
      ),
      SwapIntentStatus.providerStatusUnknown => _ActivityStatusPlan(
        title: 'Checking provider status',
        detail: intent.providerStatusRaw == null
            ? 'Refresh once. Keep the swap record open if it does not update.'
            : 'Provider returned ${intent.providerStatusRaw}. Keep this record open.',
        iconName: AppIcons.warning,
        tone: _ActivityStatusPlanTone.warning,
      ),
      SwapIntentStatus.incompleteDeposit => const _ActivityStatusPlan(
        title: 'Deposit needs attention',
        detail: 'Top up the missing amount or wait for refund.',
        iconName: AppIcons.warning,
        tone: _ActivityStatusPlanTone.warning,
      ),
      SwapIntentStatus.complete => _ActivityStatusPlan(
        title: receiveSymbol == 'ZEC'
            ? 'ZEC ready'
            : '$receiveSymbol delivered',
        detail: 'The swap is complete.',
        iconName: AppIcons.checkCircle,
        tone: _ActivityStatusPlanTone.success,
      ),
      SwapIntentStatus.refunded => const _ActivityStatusPlan(
        title: 'Funds refunded',
        detail: 'Check the refund transaction before retrying.',
        iconName: AppIcons.checkCircle,
        tone: _ActivityStatusPlanTone.success,
      ),
      SwapIntentStatus.expired => const _ActivityStatusPlan(
        title: 'Deposit window closed',
        detail: 'No funds moved if no deposit was sent.',
        iconName: AppIcons.block,
        tone: _ActivityStatusPlanTone.destructive,
      ),
      SwapIntentStatus.failed => const _ActivityStatusPlan(
        title: 'Swap failed',
        detail: 'Start a fresh quote when ready.',
        iconName: AppIcons.block,
        tone: _ActivityStatusPlanTone.destructive,
      ),
    };
  }

  static String _pairSymbol(String pair, int index) {
    final parts = pair.split(' -> ');
    if (parts.length > index && parts[index].trim().isNotEmpty) {
      return parts[index].trim();
    }
    return index == 0 ? 'deposit asset' : 'receive asset';
  }

  final String title;
  final String detail;
  final String iconName;
  final _ActivityStatusPlanTone tone;
}

enum _ActivityStatusPlanTone { action, warning, success, destructive }

class _ActivityStatusPlanPanel extends StatelessWidget {
  const _ActivityStatusPlanPanel({
    required this.intent,
    required this.plan,
    required this.statusRefreshing,
  });

  final SwapPrototypeIntent intent;
  final _ActivityStatusPlan plan;
  final bool statusRefreshing;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = switch (plan.tone) {
      _ActivityStatusPlanTone.action => colors.text.accent,
      _ActivityStatusPlanTone.warning => colors.text.warning,
      _ActivityStatusPlanTone.success => colors.text.success,
      _ActivityStatusPlanTone.destructive => colors.text.destructive,
    };
    final iconColor = switch (plan.tone) {
      _ActivityStatusPlanTone.action => colors.icon.accent,
      _ActivityStatusPlanTone.warning => colors.icon.warning,
      _ActivityStatusPlanTone.success => colors.icon.success,
      _ActivityStatusPlanTone.destructive => colors.icon.destructive,
    };
    final live = _shouldAutoRefreshActivityStatus(intent.status);
    return Column(
      key: const ValueKey('swap_activity_status_plan'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 48,
              height: 48,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.08),
                      border: Border.all(color: color.withValues(alpha: 0.22)),
                      borderRadius: BorderRadius.circular(AppRadii.small),
                    ),
                    child: AppIcon(plan.iconName, size: 20, color: iconColor),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.s),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          plan.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.headlineSmall.copyWith(
                            color: color,
                            fontSize: 18,
                            height: 23 / 18,
                          ),
                        ),
                      ),
                      if (live) ...[
                        const SizedBox(width: AppSpacing.xs),
                        _ActivityLiveBadge(
                          checking: statusRefreshing,
                          color: color,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    plan.detail,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodyExtraSmall.copyWith(
                      color: colors.text.secondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s),
        _ActivityRouteTracker(intent: intent, tone: plan.tone),
      ],
    );
  }
}

class _ActivityRouteTracker extends StatefulWidget {
  const _ActivityRouteTracker({required this.intent, required this.tone});

  final SwapPrototypeIntent intent;
  final _ActivityStatusPlanTone tone;

  @override
  State<_ActivityRouteTracker> createState() => _ActivityRouteTrackerState();
}

class _ActivityRouteTrackerState extends State<_ActivityRouteTracker> {
  Timer? _timer;
  Timer? _advanceTimer;
  var _pulse = 0;
  late int _displayProgressIndex;
  late String _displayIntentId;

  @override
  void initState() {
    super.initState();
    final plan = _ActivityRoutePlan.fromIntent(widget.intent);
    _displayProgressIndex = plan.progressIndex;
    _displayIntentId = widget.intent.id;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncPulseTimer();
    _syncDisplayProgress();
  }

  @override
  void didUpdateWidget(covariant _ActivityRouteTracker oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changedIntent = _displayIntentId != widget.intent.id;
    if (changedIntent) {
      final plan = _ActivityRoutePlan.fromIntent(widget.intent);
      _displayProgressIndex = plan.progressIndex;
      _displayIntentId = widget.intent.id;
    }
    _syncPulseTimer();
    if (!changedIntent) {
      _syncDisplayProgress();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _advanceTimer?.cancel();
    super.dispose();
  }

  void _syncPulseTimer() {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final plan = _ActivityRoutePlan.fromIntent(widget.intent);
    final shouldPulse = !reduceMotion && plan.hasActiveStep;
    if (shouldPulse && _timer == null) {
      _timer = Timer.periodic(_activityStepBlinkTempo, (_) => _triggerPulse());
      return;
    }
    if (!shouldPulse && _timer != null) {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _triggerPulse() {
    if (!mounted) return;
    setState(() => _pulse += 1);
  }

  void _syncDisplayProgress() {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final targetPlan = _ActivityRoutePlan.fromIntent(widget.intent);
    final targetIndex = targetPlan.progressIndex;
    if (reduceMotion ||
        !targetPlan.canAnimateProgress ||
        targetIndex <= _displayProgressIndex) {
      _advanceTimer?.cancel();
      _advanceTimer = null;
      if (_displayProgressIndex != targetIndex) {
        setState(() => _displayProgressIndex = targetIndex);
      }
      return;
    }

    if (targetIndex == _displayProgressIndex + 1) {
      _advanceTimer?.cancel();
      _advanceTimer = null;
      setState(() => _displayProgressIndex = targetIndex);
      return;
    }

    _advanceDisplayProgress();
    _advanceTimer ??= Timer.periodic(
      _activityRouteAdvanceTempo,
      (_) => _advanceDisplayProgress(),
    );
  }

  void _advanceDisplayProgress() {
    if (!mounted) return;
    final targetPlan = _ActivityRoutePlan.fromIntent(widget.intent);
    final targetIndex = targetPlan.progressIndex;
    if (!targetPlan.canAnimateProgress ||
        targetIndex <= _displayProgressIndex) {
      _advanceTimer?.cancel();
      _advanceTimer = null;
      if (_displayProgressIndex != targetIndex) {
        setState(() => _displayProgressIndex = targetIndex);
      }
      return;
    }

    final nextIndex = _displayProgressIndex + 1;
    setState(() => _displayProgressIndex = nextIndex);
    if (nextIndex >= targetIndex) {
      _advanceTimer?.cancel();
      _advanceTimer = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final plan = _ActivityRoutePlan.fromIntent(widget.intent);
    final displayPlan = plan.displayedAtProgress(_displayProgressIndex);
    return Semantics(
      label: 'Swap progress: ${displayPlan.semanticLabel}',
      child: Container(
        key: const ValueKey('swap_activity_route_tracker'),
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: colors.background.raised,
          border: Border.all(color: colors.border.subtle),
          borderRadius: BorderRadius.circular(AppRadii.xSmall),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ActivityRouteSegmentStrip(
              plan: displayPlan,
              tone: widget.tone,
              pulse: _pulse,
            ),
            const SizedBox(height: AppSpacing.s),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var index = 0; index < plan.steps.length; index++)
                  Expanded(
                    child: _ActivityRouteStepView(
                      key: ValueKey(
                        'swap_activity_route_step_${index}_${displayPlan.steps[index].state.name}',
                      ),
                      step: displayPlan.steps[index],
                      tone: widget.tone,
                      pulse: _pulse,
                    ),
                  ),
              ],
            ),
            if (!plan.isComplete) ...[
              const SizedBox(height: AppSpacing.s),
              _ActivityRouteFocusCard(plan: plan, tone: widget.tone),
            ],
          ],
        ),
      ),
    );
  }
}

class _ActivityRouteSegmentStrip extends StatelessWidget {
  const _ActivityRouteSegmentStrip({
    required this.plan,
    required this.tone,
    required this.pulse,
  });

  final _ActivityRoutePlan plan;
  final _ActivityStatusPlanTone tone;
  final int pulse;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var index = 0; index < plan.steps.length; index++) ...[
          Expanded(
            child: _ActivityRouteSegment(
              index: index,
              state: plan.steps[index].state,
              tone: tone,
              pulse: pulse,
            ),
          ),
          if (index != plan.steps.length - 1)
            const SizedBox(width: AppSpacing.xxs),
        ],
      ],
    );
  }
}

class _ActivityRouteSegment extends StatelessWidget {
  const _ActivityRouteSegment({
    required this.index,
    required this.state,
    required this.tone,
    required this.pulse,
  });

  final int index;
  final _ActivityRouteStepState state;
  final _ActivityStatusPlanTone tone;
  final int pulse;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final segment = AnimatedContainer(
      key: ValueKey('swap_activity_route_segment_${index}_${state.name}'),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      height: state == _ActivityRouteStepState.active ? 7 : 5,
      decoration: BoxDecoration(
        color: _activityRouteSegmentColor(context, state, tone),
        borderRadius: BorderRadius.circular(AppRadii.full),
        border: Border.all(
          color: state == _ActivityRouteStepState.pending
              ? colors.border.subtle
              : _activityRouteColor(
                  context,
                  state,
                  tone,
                ).withValues(alpha: 0.28),
        ),
      ),
    );
    if (state != _ActivityRouteStepState.active) return segment;
    return _ActivityStepBlinkOpacity(
      key: ValueKey('swap_activity_route_segment_blink_$index'),
      pulse: pulse,
      minOpacity: 0.62,
      maxOpacity: 1,
      child: segment,
    );
  }
}

class _ActivityStepBlinkOpacity extends StatelessWidget {
  const _ActivityStepBlinkOpacity({
    required this.child,
    required this.pulse,
    this.minOpacity = 0.08,
    this.maxOpacity = 0.32,
    super.key,
  });

  final Widget child;
  final int pulse;
  final double minOpacity;
  final double maxOpacity;

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) return child;
    return TweenAnimationBuilder<double>(
      key: ValueKey(pulse),
      tween: Tween<double>(begin: 0, end: 1),
      duration: _activityStepBlinkDuration,
      curve: Curves.easeInOutCubic,
      builder: (context, value, child) {
        final pulse = math.sin(value * math.pi);
        final opacity = minOpacity + ((maxOpacity - minOpacity) * pulse);
        return Opacity(opacity: opacity, child: child);
      },
      child: child,
    );
  }
}

class _ActivityRouteFocusCard extends StatelessWidget {
  const _ActivityRouteFocusCard({required this.plan, required this.tone});

  final _ActivityRoutePlan plan;
  final _ActivityStatusPlanTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final step = plan.activeStep;
    final color = _activityRouteColor(context, step.state, tone);
    final iconName = switch (step.state) {
      _ActivityRouteStepState.done => AppIcons.checkCircle,
      _ActivityRouteStepState.warning => AppIcons.warning,
      _ActivityRouteStepState.failed => AppIcons.block,
      _ => step.iconName,
    };
    return Container(
      key: const ValueKey('swap_activity_current_step_card'),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        border: Border.all(color: color.withValues(alpha: 0.2)),
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 32,
            height: 32,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    border: Border.all(color: color.withValues(alpha: 0.32)),
                    borderRadius: BorderRadius.circular(AppRadii.full),
                  ),
                  child: AppIcon(iconName, size: 14, color: color),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  plan.focusLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.labelSmall.copyWith(
                    color: colors.text.secondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  plan.focusTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.labelLarge.copyWith(color: color),
                ),
                const SizedBox(height: 2),
                Text(
                  plan.focusDetail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodyExtraSmall.copyWith(
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

class _ActivityRouteStepView extends StatelessWidget {
  const _ActivityRouteStepView({
    required this.step,
    required this.tone,
    required this.pulse,
    super.key,
  });

  final _ActivityRouteStep step;
  final _ActivityStatusPlanTone tone;
  final int pulse;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = _activityRouteColor(context, step.state, tone);
    final pending = step.state == _ActivityRouteStepState.pending;
    final active = step.state == _ActivityRouteStepState.active;
    final iconName = switch (step.state) {
      _ActivityRouteStepState.done => AppIcons.check,
      _ActivityRouteStepState.warning => AppIcons.warning,
      _ActivityRouteStepState.failed => AppIcons.block,
      _ => step.iconName,
    };
    return Column(
      children: [
        SizedBox(
          width: 32,
          height: 32,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (active) _ActivityActiveStepHalo(color: color, pulse: pulse),
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: pending
                      ? colors.background.base
                      : color.withValues(alpha: 0.1),
                  border: Border.all(
                    color: pending
                        ? colors.border.subtle
                        : color.withValues(alpha: 0.34),
                  ),
                  borderRadius: BorderRadius.circular(AppRadii.full),
                ),
                child: AppIcon(
                  iconName,
                  size: 14,
                  color: pending ? colors.icon.muted : color,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          step.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: AppTypography.labelSmall.copyWith(
            color: pending ? colors.text.secondary : color,
          ),
        ),
      ],
    );
  }
}

class _ActivityLiveBadge extends StatelessWidget {
  const _ActivityLiveBadge({required this.checking, required this.color});

  final bool checking;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      key: const ValueKey('swap_activity_live_badge'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.22)),
        borderRadius: BorderRadius.circular(AppRadii.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _LiveDot(color: color),
          const SizedBox(width: AppSpacing.xxs),
          Text(
            checking ? 'Checking' : 'Live',
            style: AppTypography.labelSmall.copyWith(
              color: checking ? color : colors.text.secondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveDot extends StatelessWidget {
  const _LiveDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      return Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(AppRadii.full),
        ),
      );
    }
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.48, end: 1),
      duration: const Duration(milliseconds: 620),
      curve: Curves.easeOutCubic,
      builder: (context, opacity, child) {
        return Opacity(opacity: opacity, child: child);
      },
      child: Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(AppRadii.full),
        ),
      ),
    );
  }
}

const _activityStepBlinkTempo = Duration(milliseconds: 2200);
const _activityStepBlinkDuration = Duration(milliseconds: 1000);
const _activityRouteAdvanceTempo = Duration(milliseconds: 420);

class _ActivityActiveStepHalo extends StatelessWidget {
  const _ActivityActiveStepHalo({required this.color, required this.pulse});

  final Color color;
  final int pulse;

  @override
  Widget build(BuildContext context) {
    const size = 32.0;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppRadii.full),
        ),
      );
    }
    return KeyedSubtree(
      key: const ValueKey('swap_activity_active_step_halo'),
      child: TweenAnimationBuilder<double>(
        key: ValueKey(pulse),
        tween: Tween<double>(begin: 0, end: 1),
        duration: _activityStepBlinkDuration,
        curve: Curves.easeInOutCubic,
        builder: (context, value, child) {
          final pulse = math.sin(value * math.pi);
          return Transform.scale(
            key: const ValueKey('swap_activity_active_step_blink_scale'),
            scale: 0.96 + (pulse * 0.1),
            child: Opacity(
              key: const ValueKey('swap_activity_active_step_blink_opacity'),
              opacity: 0.08 + (pulse * 0.24),
              child: child,
            ),
          );
        },
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(AppRadii.full),
          ),
        ),
      ),
    );
  }
}

bool _shouldAutoRefreshActivityStatus(SwapIntentStatus status) {
  return switch (status) {
    SwapIntentStatus.awaitingDeposit ||
    SwapIntentStatus.awaitingExternalDeposit ||
    SwapIntentStatus.depositObserved ||
    SwapIntentStatus.processing ||
    SwapIntentStatus.providerStatusUnknown => true,
    _ => false,
  };
}

Color _activityRouteSegmentColor(
  BuildContext context,
  _ActivityRouteStepState state,
  _ActivityStatusPlanTone tone,
) {
  final colors = context.colors;
  return switch (state) {
    _ActivityRouteStepState.done => colors.text.success,
    _ActivityRouteStepState.active ||
    _ActivityRouteStepState.warning ||
    _ActivityRouteStepState.failed => _activityRouteColor(
      context,
      state,
      tone,
    ).withValues(alpha: 0.72),
    _ActivityRouteStepState.pending => colors.background.base,
  };
}

class _ActivityRoutePlan {
  const _ActivityRoutePlan({required this.steps});

  factory _ActivityRoutePlan.fromIntent(SwapPrototypeIntent intent) {
    final sourceSymbol = _ActivityStatusPlan._pairSymbol(intent.pair, 0);
    final receiveSymbol = _ActivityStatusPlan._pairSymbol(intent.pair, 1);
    final receivesZec = receiveSymbol == 'ZEC';
    final deliverLabel = receivesZec ? 'Receive ZEC' : 'Deliver';
    final deliverDetail = receivesZec
        ? 'Provider is sending ZEC directly to this wallet shielded address.'
        : 'Provider is sending funds to your destination address.';
    final hasDepositTx = intent.depositTxHash?.trim().isNotEmpty ?? false;

    final labels = ['Send $sourceSymbol', 'Confirm', 'Swap', deliverLabel];
    final details = [
      'Send the quoted amount to the one-time deposit address.',
      'Waiting for the source chain and provider to recognize the deposit.',
      'Provider is converting funds and preparing delivery.',
      deliverDetail,
    ];
    final icons = [
      AppIcons.link,
      AppIcons.eye,
      AppIcons.renew,
      receivesZec ? AppIcons.shieldKeyhole : AppIcons.checkCircle,
    ];
    final states = switch (intent.status) {
      SwapIntentStatus.awaitingDeposit ||
      SwapIntentStatus.awaitingExternalDeposit =>
        hasDepositTx
            ? const [
                _ActivityRouteStepState.done,
                _ActivityRouteStepState.active,
                _ActivityRouteStepState.pending,
                _ActivityRouteStepState.pending,
              ]
            : const [
                _ActivityRouteStepState.active,
                _ActivityRouteStepState.pending,
                _ActivityRouteStepState.pending,
                _ActivityRouteStepState.pending,
              ],
      SwapIntentStatus.depositObserved || SwapIntentStatus.processing => const [
        _ActivityRouteStepState.done,
        _ActivityRouteStepState.done,
        _ActivityRouteStepState.active,
        _ActivityRouteStepState.pending,
      ],
      SwapIntentStatus.providerStatusUnknown => const [
        _ActivityRouteStepState.done,
        _ActivityRouteStepState.warning,
        _ActivityRouteStepState.active,
        _ActivityRouteStepState.pending,
      ],
      SwapIntentStatus.incompleteDeposit =>
        hasDepositTx
            ? const [
                _ActivityRouteStepState.done,
                _ActivityRouteStepState.warning,
                _ActivityRouteStepState.pending,
                _ActivityRouteStepState.pending,
              ]
            : const [
                _ActivityRouteStepState.warning,
                _ActivityRouteStepState.pending,
                _ActivityRouteStepState.pending,
                _ActivityRouteStepState.pending,
              ],
      SwapIntentStatus.complete => const [
        _ActivityRouteStepState.done,
        _ActivityRouteStepState.done,
        _ActivityRouteStepState.done,
        _ActivityRouteStepState.done,
      ],
      SwapIntentStatus.refunded => const [
        _ActivityRouteStepState.done,
        _ActivityRouteStepState.warning,
        _ActivityRouteStepState.pending,
        _ActivityRouteStepState.pending,
      ],
      SwapIntentStatus.expired => const [
        _ActivityRouteStepState.failed,
        _ActivityRouteStepState.pending,
        _ActivityRouteStepState.pending,
        _ActivityRouteStepState.pending,
      ],
      SwapIntentStatus.failed =>
        hasDepositTx
            ? const [
                _ActivityRouteStepState.done,
                _ActivityRouteStepState.done,
                _ActivityRouteStepState.failed,
                _ActivityRouteStepState.pending,
              ]
            : const [
                _ActivityRouteStepState.failed,
                _ActivityRouteStepState.pending,
                _ActivityRouteStepState.pending,
                _ActivityRouteStepState.pending,
              ],
    };
    return _ActivityRoutePlan(
      steps: [
        for (var index = 0; index < labels.length; index++)
          _ActivityRouteStep(
            label: labels[index],
            detail: details[index],
            state: states[index],
            iconName: icons[index],
          ),
      ],
    );
  }

  int get activeStepIndex {
    final failedOrWarningIndex = steps.indexWhere(
      (step) =>
          step.state == _ActivityRouteStepState.failed ||
          step.state == _ActivityRouteStepState.warning,
    );
    if (failedOrWarningIndex != -1) return failedOrWarningIndex;
    final activeIndex = steps.indexWhere(
      (step) => step.state == _ActivityRouteStepState.active,
    );
    if (activeIndex != -1) return activeIndex;
    final lastDoneIndex = steps.lastIndexWhere(
      (step) => step.state == _ActivityRouteStepState.done,
    );
    return lastDoneIndex == -1 ? 0 : lastDoneIndex;
  }

  _ActivityRouteStep get activeStep => steps[activeStepIndex];

  bool get hasActiveStep =>
      steps.any((step) => step.state == _ActivityRouteStepState.active);

  bool get hasAlertStep => steps.any(
    (step) =>
        step.state == _ActivityRouteStepState.failed ||
        step.state == _ActivityRouteStepState.warning,
  );

  bool get canAnimateProgress => !hasAlertStep && (hasActiveStep || isComplete);

  int get progressIndex {
    if (isComplete) return steps.length;
    final activeIndex = steps.indexWhere(
      (step) => step.state == _ActivityRouteStepState.active,
    );
    if (activeIndex != -1) return activeIndex;
    return activeStepIndex;
  }

  _ActivityRoutePlan displayedAtProgress(int progressIndex) {
    if (!canAnimateProgress || progressIndex >= this.progressIndex) {
      return this;
    }
    final clampedIndex = progressIndex.clamp(0, steps.length).toInt();
    if (clampedIndex >= steps.length) return this;
    return _ActivityRoutePlan(
      steps: [
        for (var index = 0; index < steps.length; index++)
          steps[index].copyWith(
            state: index < clampedIndex
                ? _ActivityRouteStepState.done
                : index == clampedIndex
                ? _ActivityRouteStepState.active
                : _ActivityRouteStepState.pending,
          ),
      ],
    );
  }

  int get completedStepCount =>
      steps.where((step) => step.state == _ActivityRouteStepState.done).length;

  String get focusLabel => switch (activeStep.state) {
    _ActivityRouteStepState.warning => 'Needs review',
    _ActivityRouteStepState.failed => 'Stopped',
    _ => 'Now',
  };

  String get focusTitle => activeStep.label;

  String get focusDetail => isComplete
      ? 'All funds have reached the final destination.'
      : activeStep.detail;

  String get phaseLabel {
    if (isComplete) return 'Funds delivered';
    final step = activeStep;
    return step.state == _ActivityRouteStepState.active
        ? 'Now: ${step.label}'
        : step.state.label;
  }

  String get semanticLabel =>
      '$phaseLabel, $completedStepCount of ${steps.length} steps done';

  bool get isComplete =>
      steps.every((step) => step.state == _ActivityRouteStepState.done);

  final List<_ActivityRouteStep> steps;
}

class _ActivityRouteStep {
  const _ActivityRouteStep({
    required this.label,
    required this.detail,
    required this.state,
    required this.iconName,
  });

  final String label;
  final String detail;
  final _ActivityRouteStepState state;
  final String iconName;

  _ActivityRouteStep copyWith({_ActivityRouteStepState? state}) {
    return _ActivityRouteStep(
      label: label,
      detail: detail,
      state: state ?? this.state,
      iconName: iconName,
    );
  }
}

enum _ActivityRouteStepState { pending, active, done, warning, failed }

extension _ActivityRouteStepStateLabel on _ActivityRouteStepState {
  String get label => switch (this) {
    _ActivityRouteStepState.pending => 'Waiting',
    _ActivityRouteStepState.active => 'Now',
    _ActivityRouteStepState.done => 'Done',
    _ActivityRouteStepState.warning => 'Check',
    _ActivityRouteStepState.failed => 'Stopped',
  };
}

Color _activityRouteColor(
  BuildContext context,
  _ActivityRouteStepState state,
  _ActivityStatusPlanTone tone,
) {
  final colors = context.colors;
  return switch (state) {
    _ActivityRouteStepState.done => colors.text.success,
    _ActivityRouteStepState.warning => colors.text.warning,
    _ActivityRouteStepState.failed => colors.text.destructive,
    _ActivityRouteStepState.active => switch (tone) {
      _ActivityStatusPlanTone.warning => colors.text.warning,
      _ActivityStatusPlanTone.destructive => colors.text.destructive,
      _ => colors.text.accent,
    },
    _ActivityRouteStepState.pending => colors.text.secondary,
  };
}

class _ActivityResolution {
  const _ActivityResolution({
    required this.title,
    required this.message,
    required this.detail,
    required this.iconName,
    required this.tone,
    this.primaryAction,
  });

  static _ActivityResolution? fromIntent(SwapPrototypeIntent intent) {
    return switch (intent.status) {
      SwapIntentStatus.incompleteDeposit => _ActivityResolution(
        title: 'Resolve incomplete deposit',
        message: 'The deposit is below the quoted amount.',
        detail:
            'Send only the missing amount with the same one-time deposit details, or wait for the refund path.',
        iconName: AppIcons.warning,
        tone: _ActivityResolutionTone.warning,
        primaryAction: _ActivityResolutionAction.copyTopUpDetails,
      ),
      SwapIntentStatus.providerStatusUnknown => _ActivityResolution(
        title: 'Status needs review',
        message: intent.providerStatusRaw == null
            ? 'The provider status could not be interpreted.'
            : 'The provider returned ${intent.providerStatusRaw}.',
        detail:
            'Do not resend funds. Refresh once and keep this activity item for support if the status does not move forward.',
        iconName: AppIcons.warning,
        tone: _ActivityResolutionTone.warning,
      ),
      SwapIntentStatus.refunded => _ActivityResolution(
        title: 'Refund complete',
        message: 'The swap is closed and the refund has been submitted.',
        detail:
            'Check the origin-chain refund transaction before starting a fresh quote.',
        iconName: AppIcons.checkCircle,
        tone: _ActivityResolutionTone.success,
        primaryAction: _ActivityResolutionAction.reviewFreshQuote,
      ),
      SwapIntentStatus.failed => _ActivityResolution(
        title: 'Route failed',
        message: 'The swap could not complete this route.',
        detail:
            'No funds moved according to status. Review the receipt, then start a new quote.',
        iconName: AppIcons.block,
        tone: _ActivityResolutionTone.destructive,
        primaryAction: _ActivityResolutionAction.reviewFreshQuote,
      ),
      SwapIntentStatus.expired => _ActivityResolution(
        title: 'Deposit window closed',
        message: 'The deposit window for this quote has closed.',
        detail:
            'If you did not send funds, no action is needed. If you sent funds near expiry, refresh once and keep this deposit address for support.',
        iconName: AppIcons.block,
        tone: _ActivityResolutionTone.destructive,
        primaryAction: _ActivityResolutionAction.reviewFreshQuote,
      ),
      _ => null,
    };
  }

  final String title;
  final String message;
  final String detail;
  final String iconName;
  final _ActivityResolutionTone tone;
  final _ActivityResolutionAction? primaryAction;
}

enum _ActivityResolutionTone { warning, success, destructive }

enum _ActivityResolutionAction { copyTopUpDetails, reviewFreshQuote }

class _ActivityResolutionPanel extends StatelessWidget {
  const _ActivityResolutionPanel({
    required this.resolution,
    required this.intent,
    required this.onReviewFreshQuote,
  });

  final _ActivityResolution resolution;
  final SwapPrototypeIntent intent;
  final VoidCallback onReviewFreshQuote;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = switch (resolution.tone) {
      _ActivityResolutionTone.warning => colors.text.warning,
      _ActivityResolutionTone.success => colors.text.success,
      _ActivityResolutionTone.destructive => colors.text.destructive,
    };
    final iconColor = switch (resolution.tone) {
      _ActivityResolutionTone.warning => colors.icon.warning,
      _ActivityResolutionTone.success => colors.icon.success,
      _ActivityResolutionTone.destructive => colors.icon.destructive,
    };
    final action = resolution.primaryAction;
    final actionLabel = switch (action) {
      _ActivityResolutionAction.copyTopUpDetails => 'Copy top-up details',
      _ActivityResolutionAction.reviewFreshQuote => 'Review fresh quote',
      null => null,
    };
    final actionIcon = switch (action) {
      _ActivityResolutionAction.copyTopUpDetails => AppIcons.copy,
      _ActivityResolutionAction.reviewFreshQuote => AppIcons.renew,
      null => null,
    };
    final actionKey = switch (action) {
      _ActivityResolutionAction.copyTopUpDetails => const ValueKey(
        'swap_resolution_copy_deposit_button',
      ),
      _ActivityResolutionAction.reviewFreshQuote => const ValueKey(
        'swap_resolution_review_again_button',
      ),
      null => null,
    };
    final depositAddress = intent.depositAddress;
    final actionEnabled =
        action == _ActivityResolutionAction.reviewFreshQuote ||
        (action == _ActivityResolutionAction.copyTopUpDetails &&
            depositAddress != null &&
            depositAddress.isNotEmpty);
    return Container(
      key: const ValueKey('swap_resolution_panel'),
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.28)),
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppIcon(resolution.iconName, size: 18, color: iconColor),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  resolution.title,
                  style: AppTypography.labelLarge.copyWith(color: color),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  resolution.message,
                  style: AppTypography.bodySmall.copyWith(
                    color: colors.text.primary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  resolution.detail,
                  style: AppTypography.bodyExtraSmall.copyWith(
                    color: colors.text.secondary,
                  ),
                ),
                if (actionLabel != null && actionIcon != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: AppButton(
                      key: actionKey,
                      onPressed: actionEnabled
                          ? () {
                              if (action ==
                                      _ActivityResolutionAction
                                          .copyTopUpDetails &&
                                  depositAddress != null) {
                                copySwapText(
                                  context,
                                  text: _topUpDetailsText(intent),
                                  toastMessage: 'Top-up Details Copied',
                                );
                                return;
                              }
                              if (action ==
                                  _ActivityResolutionAction.reviewFreshQuote) {
                                onReviewFreshQuote();
                              }
                            }
                          : null,
                      variant: AppButtonVariant.secondary,
                      size: AppButtonSize.medium,
                      leading: AppIcon(actionIcon),
                      child: Text(actionLabel),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _topUpDetailsText(SwapPrototypeIntent intent) {
    final lines = [
      if (intent.depositAddress != null)
        'Deposit address: ${intent.depositAddress}',
      if (intent.depositMemo != null) 'Deposit memo: ${intent.depositMemo}',
    ];
    return lines.join('\n');
  }
}

bool _showDepositControls(SwapIntentStatus status) {
  return switch (status) {
    SwapIntentStatus.complete ||
    SwapIntentStatus.refunded ||
    SwapIntentStatus.expired ||
    SwapIntentStatus.providerStatusUnknown ||
    SwapIntentStatus.failed => false,
    _ => true,
  };
}

bool _showActivityReceipt(SwapIntentStatus status) {
  return switch (status) {
    SwapIntentStatus.complete ||
    SwapIntentStatus.refunded ||
    SwapIntentStatus.expired ||
    SwapIntentStatus.failed ||
    SwapIntentStatus.depositObserved ||
    SwapIntentStatus.processing ||
    SwapIntentStatus.incompleteDeposit ||
    SwapIntentStatus.providerStatusUnknown => true,
    _ => false,
  };
}

bool canRefreshSwapIntentStatus(SwapIntentStatus status) {
  return status != SwapIntentStatus.complete;
}

class _ActiveSwapSummaryPanel extends StatelessWidget {
  const _ActiveSwapSummaryPanel({
    required this.intent,
    required this.plan,
    required this.statusRefreshing,
    required this.canRefreshStatus,
    required this.onRefreshStatus,
    required this.onCopyExplorerLink,
    required this.onRemoveIntent,
  });

  final SwapPrototypeIntent intent;
  final _ActivityStatusPlan plan;
  final bool statusRefreshing;
  final bool canRefreshStatus;
  final VoidCallback onRefreshStatus;
  final ValueChanged<SwapPrototypeIntent> onCopyExplorerLink;
  final VoidCallback onRemoveIntent;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 560;
        final checkedLabel = statusRefreshing
            ? 'Checking now'
            : _lastStatusCheckedLabel(intent.lastStatusCheckedAt) ??
                  'Not checked yet';
        final checkedStatus = _ActiveSwapCheckedStatus(
          label: checkedLabel,
          active: statusRefreshing,
        );
        final explorerUri = nearIntentsExplorerUri(
          nearIntentHash: intent.nearIntentHash,
          depositTxHash: intent.depositTxHash,
          depositAddress: intent.depositAddress ?? intent.id,
        );
        final statusActions = Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            AppButton(
              key: const ValueKey(
                'swap_activity_copy_near_intents_explorer_button',
              ),
              onPressed: explorerUri == null
                  ? null
                  : () => onCopyExplorerLink(intent),
              variant: AppButtonVariant.secondary,
              size: AppButtonSize.medium,
              minWidth: 116,
              leading: const AppIcon(AppIcons.link),
              child: const Text('Copy link'),
            ),
            if (canRefreshStatus)
              AppButton(
                key: const ValueKey('swap_status_refresh_button'),
                onPressed: statusRefreshing ? null : onRefreshStatus,
                variant: AppButtonVariant.secondary,
                size: AppButtonSize.medium,
                minWidth: 124,
                leading: const AppIcon(AppIcons.renew),
                child: Text(statusRefreshing ? 'Refreshing' : 'Refresh'),
              ),
            AppButton(
              key: const ValueKey('swap_activity_remove_button'),
              onPressed: onRemoveIntent,
              variant: AppButtonVariant.ghost,
              size: AppButtonSize.medium,
              minWidth: 112,
              leading: const AppIcon(AppIcons.cross),
              child: const Text('Remove'),
            ),
          ],
        );

        return Container(
          key: const ValueKey('swap_active_summary_panel'),
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: colors.background.base,
            border: Border.all(color: colors.border.regular),
            borderRadius: BorderRadius.circular(AppRadii.xSmall),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (compact) ...[
                checkedStatus,
                const SizedBox(height: AppSpacing.xs),
                Align(alignment: Alignment.centerRight, child: statusActions),
              ] else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: checkedStatus),
                    const SizedBox(width: AppSpacing.s),
                    statusActions,
                  ],
                ),
              const SizedBox(height: AppSpacing.md),
              _ActivityStatusPlanPanel(
                intent: intent,
                plan: plan,
                statusRefreshing: statusRefreshing,
              ),
              const SizedBox(height: AppSpacing.md),
              _ActiveSwapTradeLine(intent: intent),
            ],
          ),
        );
      },
    );
  }
}

class _ActiveSwapCheckedStatus extends StatelessWidget {
  const _ActiveSwapCheckedStatus({required this.label, required this.active});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = active ? colors.text.accent : colors.text.muted;
    return Row(
      key: const ValueKey('swap_activity_checked_label'),
      mainAxisSize: MainAxisSize.min,
      children: [
        AppIcon(
          active ? AppIcons.renew : AppIcons.time,
          size: 14,
          color: active ? colors.icon.accent : colors.icon.muted,
        ),
        const SizedBox(width: AppSpacing.xxs),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.labelSmall.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

String? _lastStatusCheckedLabel(DateTime? checkedAt) {
  if (checkedAt == null) return null;
  final local = checkedAt.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return 'Checked $hour:$minute';
}

SwapAsset? _activitySellAsset(SwapPrototypeIntent intent) {
  final direction = intent.direction;
  final externalAsset = intent.externalAsset;
  if (direction == null || externalAsset == null) {
    return _activityAssetFromPair(intent.pair, 0);
  }
  return direction.fromAsset(externalAsset);
}

SwapAsset? _activityReceiveAsset(SwapPrototypeIntent intent) {
  final direction = intent.direction;
  final externalAsset = intent.externalAsset;
  if (direction == null || externalAsset == null) {
    return _activityAssetFromPair(intent.pair, 1);
  }
  return direction.toAsset(externalAsset);
}

SwapAsset? _activityAssetFromPair(String pair, int index) {
  final parts = pair.split('->');
  if (index < 0 || index >= parts.length) return null;
  final tokens = parts[index].trim().split(RegExp(r'\s+'));
  final symbol = tokens.isEmpty ? '' : tokens.first;
  if (symbol.isEmpty) return null;
  return SwapAsset.byName(symbol.toLowerCase());
}

class _ActiveSwapTradeLine extends StatelessWidget {
  const _ActiveSwapTradeLine({required this.intent});

  final SwapPrototypeIntent intent;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final recipient = _externalRecipientSummary(intent);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: colors.background.raised,
        border: Border.all(color: colors.border.subtle),
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _ActiveTradeAmount(
                  label: 'You send',
                  value: intent.sellAmount,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                child: AppIcon(
                  AppIcons.arrowForwardIos,
                  size: 14,
                  color: colors.icon.muted,
                ),
              ),
              Expanded(
                child: _ActiveTradeAmount(
                  label: 'You receive',
                  value: intent.receiveEstimate,
                  alignEnd: true,
                ),
              ),
            ],
          ),
          if (recipient != null) ...[
            const SizedBox(height: AppSpacing.xs),
            _ExternalRecipientLine(recipient: recipient),
          ],
        ],
      ),
    );
  }
}

class _ExternalRecipientSummary {
  const _ExternalRecipientSummary({required this.label, required this.value});

  final String label;
  final String value;
}

_ExternalRecipientSummary? _externalRecipientSummary(
  SwapPrototypeIntent intent,
) {
  if (intent.direction != SwapDirection.zecToExternal) return null;
  final recipient = intent.oneClickRecipient?.trim();
  if (recipient == null || recipient.isEmpty) return null;
  final symbol =
      intent.externalAsset?.symbol ??
      _ActivityStatusPlan._pairSymbol(intent.pair, 1);
  return _ExternalRecipientSummary(
    label: '$symbol recipient',
    value: recipient,
  );
}

class _ExternalRecipientLine extends StatelessWidget {
  const _ExternalRecipientLine({required this.recipient});

  final _ExternalRecipientSummary recipient;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      key: const ValueKey('swap_activity_external_recipient_line'),
      children: [
        AppIcon(AppIcons.user, size: 14, color: colors.icon.muted),
        const SizedBox(width: AppSpacing.xxs),
        Text(
          recipient.label,
          style: AppTypography.labelMedium.copyWith(
            color: colors.text.secondary,
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            recipient.value,
            key: const ValueKey('swap_activity_external_recipient_value'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
            style: AppTypography.codeSmall.copyWith(color: colors.text.primary),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        _CopyValueButton(label: recipient.label, value: recipient.value),
      ],
    );
  }
}

class _ActiveTradeAmount extends StatelessWidget {
  const _ActiveTradeAmount({
    required this.label,
    required this.value,
    this.alignEnd = false,
  });

  final String label;
  final String value;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.labelMedium.copyWith(
            color: colors.text.secondary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          compactSwapAmountText(value),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: alignEnd ? TextAlign.end : TextAlign.start,
          style: AppTypography.labelLarge.copyWith(color: colors.text.accent),
        ),
      ],
    );
  }
}

class _ActivityDepositInstruction {
  const _ActivityDepositInstruction({
    required this.sendLabel,
    required this.depositSymbol,
    required this.depositAddressLabel,
    required this.address,
    required this.railLabel,
    required this.reuseWarning,
    required this.deliveryLabel,
    required this.deliveryValue,
    required this.txHashLabel,
    required this.txHashHint,
    required this.submitLabel,
    required this.showQr,
    this.memo,
  });

  static _ActivityDepositInstruction? fromIntent(SwapPrototypeIntent intent) {
    final direction = intent.direction;
    final externalAsset = intent.externalAsset;
    final depositAddress = intent.depositAddress;
    if (direction == null || externalAsset == null || depositAddress == null) {
      return null;
    }

    final depositSymbol = direction.fromSymbol(externalAsset);
    final receiveSymbol = direction.toSymbol(externalAsset);
    final deliveryLabel = direction.sendsZec
        ? '$receiveSymbol destination'
        : 'Receive address';
    final deliveryValue = direction.sendsZec
        ? intent.oneClickRecipient ?? 'external destination'
        : intent.oneClickRecipient ?? 'shielded wallet address';
    final depositAddressLabel = direction.sendsZec
        ? '$depositSymbol deposit'
        : '$depositSymbol source deposit';

    return _ActivityDepositInstruction(
      sendLabel: direction.sendsZec
          ? 'Send $depositSymbol'
          : 'Send $depositSymbol from source chain',
      depositSymbol: depositSymbol,
      depositAddressLabel: depositAddressLabel,
      address: depositAddress,
      railLabel: externalAsset.railLabel,
      reuseWarning: 'Do not reuse this address',
      memo: intent.depositMemo,
      deliveryLabel: deliveryLabel,
      deliveryValue: deliveryValue,
      txHashLabel: '$depositSymbol deposit tx hash',
      txHashHint: '$depositSymbol source-chain transaction hash',
      submitLabel: 'Submit $depositSymbol deposit',
      showQr: !direction.sendsZec,
    );
  }

  final String sendLabel;
  final String depositSymbol;
  final String depositAddressLabel;
  final String address;
  final String railLabel;
  final String reuseWarning;
  final String? memo;
  final String deliveryLabel;
  final String deliveryValue;
  final String txHashLabel;
  final String txHashHint;
  final String submitLabel;
  final bool showQr;
}

class _ActivityHardwareActionPanel extends StatelessWidget {
  const _ActivityHardwareActionPanel({
    required this.iconName,
    required this.title,
    required this.message,
    required this.buttonKey,
    required this.buttonLabel,
    required this.onPressed,
    super.key,
  });

  final String iconName;
  final String title;
  final String message;
  final Key buttonKey;
  final String buttonLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: colors.background.raised,
        border: Border.all(color: colors.border.regular),
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.background.base,
              border: Border.all(color: colors.border.subtle),
              borderRadius: BorderRadius.circular(AppRadii.xSmall),
            ),
            child: AppIcon(iconName, size: 20, color: colors.icon.regular),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTypography.labelLarge.copyWith(
                    color: colors.text.accent,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  message,
                  style: AppTypography.bodySmall.copyWith(
                    color: colors.text.secondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          AppButton(
            key: buttonKey,
            onPressed: onPressed,
            variant: AppButtonVariant.primary,
            size: AppButtonSize.medium,
            leading: AppIcon(iconName),
            child: Text(buttonLabel),
          ),
        ],
      ),
    );
  }
}

class _ActivityDepositActionPanel extends StatelessWidget {
  const _ActivityDepositActionPanel({
    required this.state,
    required this.instruction,
    required this.onDepositTxHashChanged,
    required this.onSubmitDepositTransaction,
    required this.liveFundsEnabled,
  });

  final SwapPrototypeState state;
  final _ActivityDepositInstruction instruction;
  final ValueChanged<String> onDepositTxHashChanged;
  final VoidCallback onSubmitDepositTransaction;
  final bool liveFundsEnabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (instruction.showQr) ...[
          SwapDepositQrPanel(
            key: const ValueKey('swap_activity_deposit_qr_panel'),
            title: 'Send ${instruction.depositSymbol} to this deposit address',
            qrData: instruction.address,
            addressLabel: instruction.depositAddressLabel,
            address: instruction.address,
            railLabel: instruction.railLabel,
            reuseWarning: instruction.reuseWarning,
            memo: instruction.memo,
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
        _ActivityDepositInstructionPanel(instruction: instruction),
        const SizedBox(height: AppSpacing.xs),
        _DepositTxHashDisclosure(
          state: state,
          instruction: instruction,
          onDepositTxHashChanged: onDepositTxHashChanged,
          onSubmitDepositTransaction: onSubmitDepositTransaction,
          liveFundsEnabled: liveFundsEnabled,
        ),
      ],
    );
  }
}

class _ActivityDepositInstructionPanel extends StatelessWidget {
  const _ActivityDepositInstructionPanel({required this.instruction});

  final _ActivityDepositInstruction instruction;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: colors.background.base,
        border: Border.all(color: colors.border.subtle),
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            instruction.sendLabel,
            style: AppTypography.labelLarge.copyWith(color: colors.text.accent),
          ),
          const SizedBox(height: AppSpacing.xs),
          _ActivityInstructionRow(
            label: instruction.depositAddressLabel,
            value: instruction.address,
          ),
          if (instruction.memo != null)
            _ActivityInstructionRow(label: 'Memo', value: instruction.memo!),
          _ActivityInstructionRow(
            label: instruction.deliveryLabel,
            value: instruction.deliveryValue,
          ),
        ],
      ),
    );
  }
}

class _ActivityInstructionRow extends StatelessWidget {
  const _ActivityInstructionRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
      child: Row(
        children: [
          SizedBox(
            width: 124,
            child: Text(
              label,
              style: AppTypography.labelMedium.copyWith(
                color: colors.text.secondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.bodySmall.copyWith(
                color: colors.text.primary,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xxs),
          _CopyValueButton(label: label, value: value),
        ],
      ),
    );
  }
}

class _DepositTxHashDisclosure extends StatefulWidget {
  const _DepositTxHashDisclosure({
    required this.state,
    required this.instruction,
    required this.onDepositTxHashChanged,
    required this.onSubmitDepositTransaction,
    required this.liveFundsEnabled,
  });

  final SwapPrototypeState state;
  final _ActivityDepositInstruction instruction;
  final ValueChanged<String> onDepositTxHashChanged;
  final VoidCallback onSubmitDepositTransaction;
  final bool liveFundsEnabled;

  @override
  State<_DepositTxHashDisclosure> createState() =>
      _DepositTxHashDisclosureState();
}

class _DepositTxHashDisclosureState extends State<_DepositTxHashDisclosure> {
  late bool _expanded = widget.state.depositTxHashText.trim().isNotEmpty;

  @override
  void didUpdateWidget(covariant _DepositTxHashDisclosure oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.state.depositTxHashText.trim().isNotEmpty && !_expanded) {
      _expanded = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final canSubmit =
        widget.state.canSubmitDepositTx && widget.liveFundsEnabled;
    final submitLabel = widget.state.depositSubmitting
        ? 'Submitting'
        : widget.instruction.submitLabel;
    return Container(
      key: const ValueKey('swap_deposit_tx_hash_disclosure'),
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: colors.background.base,
        border: Border.all(color: colors.border.subtle),
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.background.raised,
                  border: Border.all(color: colors.border.subtle),
                  borderRadius: BorderRadius.circular(AppRadii.xSmall),
                ),
                child: AppIcon(
                  AppIcons.link,
                  size: 16,
                  color: colors.icon.muted,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Already sent?',
                      style: AppTypography.labelLarge.copyWith(
                        color: colors.text.accent,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.liveFundsEnabled
                          ? 'Add the deposit transaction hash to speed up status checks.'
                          : 'Live submit disabled',
                      style: AppTypography.bodyExtraSmall.copyWith(
                        color: colors.text.secondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              AppButton(
                key: const ValueKey('swap_deposit_tx_hash_toggle'),
                onPressed: () => setState(() => _expanded = !_expanded),
                variant: AppButtonVariant.secondary,
                size: AppButtonSize.small,
                trailing: AppIcon(
                  _expanded ? AppIcons.arrowUpward : AppIcons.arrowDown,
                ),
                child: Text(_expanded ? 'Hide' : 'Add tx hash'),
              ),
            ],
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppTextField(
                    key: const ValueKey('swap_deposit_tx_hash_field'),
                    label: widget.instruction.txHashLabel,
                    initialValue: widget.state.depositTxHashText,
                    hintText: widget.instruction.txHashHint,
                    showClearButton: true,
                    onChanged: widget.onDepositTxHashChanged,
                    onClear: () => widget.onDepositTxHashChanged(''),
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) {
                      if (canSubmit) {
                        widget.onSubmitDepositTransaction();
                      }
                    },
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Align(
                    alignment: Alignment.centerRight,
                    child: AppButton(
                      key: const ValueKey('swap_deposit_submit_button'),
                      onPressed: canSubmit
                          ? widget.onSubmitDepositTransaction
                          : null,
                      variant: AppButtonVariant.secondary,
                      size: AppButtonSize.medium,
                      leading: const AppIcon(AppIcons.link),
                      child: Text(submitLabel),
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

class _ActivitySupportDetailsSection extends StatefulWidget {
  const _ActivitySupportDetailsSection({
    required this.intent,
    required this.onCopyText,
  });

  final SwapPrototypeIntent intent;
  final SwapSupportCopyText onCopyText;

  @override
  State<_ActivitySupportDetailsSection> createState() =>
      _ActivitySupportDetailsSectionState();
}

class _ActivitySupportDetailsSectionState
    extends State<_ActivitySupportDetailsSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      key: const ValueKey('swap_support_details_section'),
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: colors.background.base,
        border: Border.all(color: colors.border.subtle),
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Support details',
                  style: AppTypography.labelLarge.copyWith(
                    color: colors.text.accent,
                  ),
                ),
              ),
              AppButton(
                key: const ValueKey('swap_support_details_toggle'),
                onPressed: () => setState(() => _expanded = !_expanded),
                variant: AppButtonVariant.secondary,
                size: AppButtonSize.small,
                leading: const AppIcon(AppIcons.scroll),
                trailing: AppIcon(
                  _expanded ? AppIcons.arrowUpward : AppIcons.arrowDown,
                ),
                child: Text(_expanded ? 'Hide' : 'Show'),
              ),
            ],
          ),
          if (!_expanded)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xxs),
              child: Text(
                'Hidden by default. Copy this only when support asks for it.',
                style: AppTypography.bodyExtraSmall.copyWith(
                  color: colors.text.secondary,
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: RedactedReceiptDrawer(
                rows: widget.intent.receipt,
                intent: widget.intent,
                onCopyText: widget.onCopyText,
              ),
            ),
        ],
      ),
    );
  }
}

class _CopyValueButton extends StatelessWidget {
  const _CopyValueButton({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final keyLabel = label.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    return Semantics(
      button: true,
      label: 'Copy $label',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          key: ValueKey('swap_copy_$keyLabel'),
          behavior: HitTestBehavior.opaque,
          onTap: () {
            copySwapText(
              context,
              text: value,
              toastMessage: _copyValueToastMessage(label),
            );
          },
          child: Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.background.raised,
              border: Border.all(color: colors.border.subtle),
              borderRadius: BorderRadius.circular(AppRadii.xSmall),
            ),
            child: AppIcon(AppIcons.copy, size: 14, color: colors.icon.muted),
          ),
        ),
      ),
    );
  }
}

String _copyValueToastMessage(String label) {
  final normalized = label.trim();
  if (normalized.isEmpty) return 'Copied to Clipboard';
  final lower = normalized.toLowerCase();
  if (lower == 'memo') return 'Memo Copied';
  if (lower.contains('address') ||
      lower.contains('recipient') ||
      lower.contains('deposit')) {
    return 'Address Copied';
  }
  return 'Copied to Clipboard';
}
