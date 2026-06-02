import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_back_link.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../providers/account_provider.dart';
import '../../address_book/providers/address_book_provider.dart';
import '../domain/near_intents_explorer.dart';
import '../models/swap_activity_navigation.dart';
import '../models/swap_activity_status_mapper.dart';
import '../models/swap_keystone_broadcast_result.dart';
import '../models/swap_models.dart';
import '../providers/swap_state_provider.dart';
import 'swap_deposit_tokens_page_content.dart';
import 'swap_keystone_signing_overlay.dart';
import 'swap_near_intents_attribution.dart';
import 'swap_status_page_content.dart';

class SwapActivityDetailSurface extends ConsumerStatefulWidget {
  const SwapActivityDetailSurface({
    required this.intentId,
    this.returnTarget,
    this.autoSignZecDeposit = false,
    super.key,
  });

  final String intentId;
  final SwapActivityReturnTarget? returnTarget;
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
  _SwapKeystoneSigningRequest? _keystoneSigningRequest;
  String? _depositCheckingIntentId;
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
    final intent = _intentById(ref.read(swapStateProvider).intents, intentId);
    if (intent == null) return;
    ref.read(swapStateProvider.notifier).selectIntent(intentId);
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

  bool _isHardwareIntent(SwapIntent intent) {
    final accountUuid = intent.accountUuid;
    if (accountUuid == null || accountUuid.trim().isEmpty) return false;
    final accountState = ref.read(accountProvider).value;
    final accountHardwareByUuid = {
      for (final account in accountState?.accounts ?? const <AccountInfo>[])
        account.uuid: account.isHardware,
    };
    return accountHardwareByUuid[accountUuid] ?? false;
  }

  void _refreshStatus() {
    unawaited(_refreshStatusForSelectedIntent());
  }

  void _markDepositClaimed() {
    unawaited(
      ref.read(swapStateProvider.notifier).markSelectedDepositClaimed(),
    );
  }

  Future<void> _refreshStatusForSelectedIntent() async {
    final selected = ref.read(swapStateProvider).selectedIntentOrNull;
    if (selected == null || !canRefreshSwapIntentStatus(selected.status)) {
      return;
    }
    if (mounted) {
      setState(() {
        _depositCheckingIntentId = selected.id;
      });
    }
    await ref.read(swapStateProvider.notifier).refreshSelectedIntentStatus();
    if (!mounted) return;

    setState(() {
      _depositCheckingIntentId = null;
    });
  }

  void _submitDepositTransaction() {
    unawaited(
      ref.read(swapStateProvider.notifier).submitSelectedDepositTransaction(),
    );
  }

  void _reviewFreshQuote() {
    ref.read(swapStateProvider.notifier).prepareRetryFromSelectedIntent();
    context.go('/swap');
  }

  void _openNearIntentsExplorerLink(SwapIntent intent) {
    unawaited(
      launchNearIntentsExplorer(
        nearIntentHash: intent.nearIntentHash,
        depositTxHash: intent.depositTxHash,
        depositAddress: intent.depositAddress ?? intent.id,
      ),
    );
  }

  void _signZecDeposit(SwapIntent intent) {
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
            .read(swapStateProvider.notifier)
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
          .read(swapStateProvider.notifier)
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
      result.isCertain ? 'ZEC deposit sent' : 'Checking ZEC deposit',
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(
      accountProvider.select((value) => value.value?.activeAccountUuid),
      (previous, next) {
        if (previous == next || !mounted) return;
        setState(() {
          _keystoneSigningRequest = null;
        });
        context.go('/activity');
      },
    );

    final state = ref.watch(swapStateProvider);
    final initialIntentId = widget.intentId.trim();
    if (!_initialIntentApplied && initialIntentId.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _applyInitialIntent();
      });
    }
    final activityDetailIntent = _intentById(state.intents, initialIntentId);
    final keystoneSigningRequest = _keystoneSigningRequest;
    final keystoneSigningIntent = _intentById(
      state.intents,
      keystoneSigningRequest?.intentId,
    );

    final Widget pageContent = activityDetailIntent == null
        ? const _SwapActivityMissingPanel()
        : SwapActivityDetailPagePanel(
            state: state,
            intent: activityDetailIntent,
            depositChecking:
                _depositCheckingIntentId == activityDetailIntent.id,
            depositCheckWarning: null,
            onRefreshStatus: _refreshStatus,
            onMarkDeposited: _markDepositClaimed,
            onDepositTxHashChanged: ref
                .read(swapStateProvider.notifier)
                .updateDepositTxHash,
            onSubmitDepositTransaction: _submitDepositTransaction,
            onReviewFreshQuote: _reviewFreshQuote,
            onSignZecDeposit: _signZecDeposit,
            onCopyExplorerLink: _openNearIntentsExplorerLink,
            intentIsHardware: _isHardwareIntent(activityDetailIntent),
          );

    return Stack(
      key: const ValueKey('swap_activity_detail_surface'),
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: _SwapActivityDetailPaneContent(
            returnTarget: widget.returnTarget,
            child: pageContent,
          ),
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

class _SwapActivityDetailPaneContent extends StatelessWidget {
  const _SwapActivityDetailPaneContent({
    required this.child,
    required this.returnTarget,
  });

  final Widget child;
  final SwapActivityReturnTarget? returnTarget;

  @override
  Widget build(BuildContext context) {
    final returnTarget = this.returnTarget;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (returnTarget != null) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: AppBackLink(
                label: returnTarget.label,
                minWidth: 60,
                onTap: () => context.go(returnTarget.path),
              ),
            ),
            const SizedBox(height: AppSpacing.s),
          ],
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  children: [
                    Positioned.fill(child: child),
                    if (constraints.maxHeight >= 520)
                      const Positioned(
                        left: 0,
                        bottom: AppSpacing.md,
                        child: SwapNearIntentsAttribution(),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

SwapIntent? _intentById(List<SwapIntent> intents, String? intentId) {
  if (intentId == null) return null;
  for (final intent in intents) {
    if (intent.id == intentId) return intent;
  }
  return null;
}

class SwapActivityDetailPagePanel extends StatelessWidget {
  const SwapActivityDetailPagePanel({
    required this.state,
    required this.intent,
    required this.depositChecking,
    required this.depositCheckWarning,
    required this.onRefreshStatus,
    required this.onMarkDeposited,
    required this.onDepositTxHashChanged,
    required this.onSubmitDepositTransaction,
    required this.onReviewFreshQuote,
    required this.onSignZecDeposit,
    required this.onCopyExplorerLink,
    required this.intentIsHardware,
    super.key,
  });

  final SwapState state;
  final SwapIntent intent;
  final bool depositChecking;
  final String? depositCheckWarning;
  final VoidCallback onRefreshStatus;
  final VoidCallback onMarkDeposited;
  final ValueChanged<String> onDepositTxHashChanged;
  final VoidCallback onSubmitDepositTransaction;
  final VoidCallback onReviewFreshQuote;
  final ValueChanged<SwapIntent> onSignZecDeposit;
  final ValueChanged<SwapIntent> onCopyExplorerLink;
  final bool intentIsHardware;

  @override
  Widget build(BuildContext context) {
    final flowContent = _SwapActivityFlowContent(
      state: state,
      intent: intent,
      depositChecking: depositChecking,
      depositCheckWarning: depositCheckWarning,
      onRefreshStatus: onRefreshStatus,
      onMarkDeposited: onMarkDeposited,
      onDepositTxHashChanged: onDepositTxHashChanged,
      onSubmitDepositTransaction: onSubmitDepositTransaction,
      onReviewFreshQuote: onReviewFreshQuote,
      onSignZecDeposit: onSignZecDeposit,
      onCopyExplorerLink: onCopyExplorerLink,
      intentIsHardware: intentIsHardware,
    );
    final isDepositPage = swapActivityShowsDepositPage(
      intent,
      intentIsHardware: intentIsHardware,
    );

    return Container(
      key: const ValueKey('swap_activity_detail_page'),
      padding: EdgeInsets.zero,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return _ActivityDetailScrollArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Align(
                alignment: isDepositPage
                    ? Alignment.center
                    : Alignment.topCenter,
                child: flowContent,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SwapActivityFlowContent extends StatelessWidget {
  const _SwapActivityFlowContent({
    required this.state,
    required this.intent,
    required this.depositChecking,
    required this.depositCheckWarning,
    required this.onRefreshStatus,
    required this.onMarkDeposited,
    required this.onDepositTxHashChanged,
    required this.onSubmitDepositTransaction,
    required this.onReviewFreshQuote,
    required this.onSignZecDeposit,
    required this.onCopyExplorerLink,
    required this.intentIsHardware,
  });

  final SwapState state;
  final SwapIntent intent;
  final bool depositChecking;
  final String? depositCheckWarning;
  final VoidCallback onRefreshStatus;
  final VoidCallback onMarkDeposited;
  final ValueChanged<String> onDepositTxHashChanged;
  final VoidCallback onSubmitDepositTransaction;
  final VoidCallback onReviewFreshQuote;
  final ValueChanged<SwapIntent> onSignZecDeposit;
  final ValueChanged<SwapIntent> onCopyExplorerLink;
  final bool intentIsHardware;

  @override
  Widget build(BuildContext context) {
    final depositInstruction = SwapActivityDepositInstruction.fromIntent(
      intent,
    );
    final statusError = intent.statusError ?? state.statusError;
    final showExternalDepositPage = swapActivityShowsExternalDepositPage(
      intent,
    );
    final showHardwareDepositPage = swapActivityShowsHardwareZecDepositPage(
      intent,
      intentIsHardware: intentIsHardware,
    );
    final primaryContent = switch (intent.status) {
      SwapIntentStatus.expired => SwapDepositTimeoutPageContent(
        onRestart: onReviewFreshQuote,
      ),
      _ when showExternalDepositPage && depositInstruction != null =>
        SwapDepositTokensPageContent(
          asset: swapActivitySellAsset(intent) ?? SwapAsset.zec,
          amountText: intent.sellAmount,
          depositAddress: depositInstruction.address,
          expiresInLabel: swapDepositDeadlineLabel(intent) ?? '2hrs',
          expiresAt: intent.depositDeadline,
          memo: depositInstruction.memo,
          checking: depositChecking || state.statusRefreshing,
          checkWarning: depositCheckWarning,
          onDeposited: onMarkDeposited,
        ),
      _ when showHardwareDepositPage && depositInstruction != null =>
        SwapHardwareZecDepositPageContent(
          asset: swapActivitySellAsset(intent) ?? SwapAsset.zec,
          amountText: intent.sellAmount,
          depositAddress: depositInstruction.address,
          expiresInLabel: swapDepositDeadlineLabel(intent) ?? '2hrs',
          expiresAt: intent.depositDeadline,
          memo: depositInstruction.memo,
          onDepositZec: () => onSignZecDeposit(intent),
        ),
      _ => _SwapStatusForIntent(
        intent: intent,
        onOpenExplorer: () => onCopyExplorerLink(intent),
      ),
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        primaryContent,
        if (statusError != null) ...[
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: 400,
            child: _ActivityStatusErrorPanel(message: statusError),
          ),
        ],
      ],
    );
  }
}

class _SwapStatusForIntent extends ConsumerStatefulWidget {
  const _SwapStatusForIntent({
    required this.intent,
    required this.onOpenExplorer,
  });

  final SwapIntent intent;
  final VoidCallback onOpenExplorer;

  @override
  ConsumerState<_SwapStatusForIntent> createState() =>
      _SwapStatusForIntentState();
}

class _SwapStatusForIntentState extends ConsumerState<_SwapStatusForIntent> {
  SwapStatusTab _activeTab = SwapStatusTab.progress;
  bool _detailsExpanded = false;

  @override
  void didUpdateWidget(covariant _SwapStatusForIntent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.intent.id != widget.intent.id) {
      _activeTab = SwapStatusTab.progress;
      _detailsExpanded = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final intent = widget.intent;
    final state = ref.watch(swapStateProvider);
    final accountInfo = _accountInfoForIntent(
      ref.watch(accountProvider).value,
      intent,
    );
    final addressBookContacts =
        ref.watch(addressBookProvider).value?.contacts ?? const [];
    final presentation = swapActivityStatusPresentationForIntent(
      state,
      intent,
      accountDetail: accountInfo == null
          ? null
          : SwapActivityAccountDetail(
              name: accountInfo.name,
              profilePictureId: accountInfo.profilePictureId,
            ),
      addressBookContacts: addressBookContacts,
    );
    return SwapStatusPageContent(
      title: presentation.title,
      payAsset: presentation.payAsset,
      receiveAsset: presentation.receiveAsset,
      payFiatText: presentation.payFiatText,
      receiveFiatText: presentation.receiveFiatText,
      payAmountText: presentation.payAmountText,
      receiveAmountText: presentation.receiveAmountText,
      badgeKind: presentation.badgeKind,
      progressIndex: presentation.progressIndex,
      activeTab: _activeTab,
      steps: presentation.steps,
      details: presentation.details,
      detailsExpanded: _detailsExpanded,
      showTabs: presentation.showTabs,
      onTabChanged: (tab) {
        setState(() {
          _activeTab = tab;
        });
      },
      onToggleDetails: () {
        setState(() {
          _detailsExpanded = !_detailsExpanded;
        });
      },
      onOpenExplorer: widget.onOpenExplorer,
    );
  }
}

AccountInfo? _accountInfoForIntent(
  AccountState? accountState,
  SwapIntent intent,
) {
  if (accountState == null) return null;
  final accountUuid = intent.accountUuid?.trim();
  if (accountUuid != null && accountUuid.isNotEmpty) {
    for (final account in accountState.accounts) {
      if (account.uuid == accountUuid) return account;
    }
  }
  return accountState.activeAccount;
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
            "Couldn't load this swap. Try again or pull to refresh.",
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

class _ActivityDetailScrollArea extends StatefulWidget {
  const _ActivityDetailScrollArea({required this.child});

  final Widget child;

  @override
  State<_ActivityDetailScrollArea> createState() =>
      _ActivityDetailScrollAreaState();
}

class _ActivityDetailScrollAreaState extends State<_ActivityDetailScrollArea> {
  late final ScrollController _controller;
  bool _hasScrollableExtent = false;

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

  bool _handleScrollMetrics(ScrollMetricsNotification notification) {
    final hasScrollableExtent = notification.metrics.maxScrollExtent > 0.5;
    if (hasScrollableExtent != _hasScrollableExtent) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _hasScrollableExtent = hasScrollableExtent;
        });
      });
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: NotificationListener<ScrollMetricsNotification>(
        onNotification: _handleScrollMetrics,
        child: RawScrollbar(
          key: const ValueKey('swap_activity_detail_scrollbar'),
          controller: _controller,
          thumbVisibility: _hasScrollableExtent,
          interactive: _hasScrollableExtent,
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
              padding: EdgeInsets.only(
                right: _hasScrollableExtent ? AppSpacing.s : 0,
              ),
              child: widget.child,
            ),
          ),
        ),
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
