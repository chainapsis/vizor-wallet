import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_pane_scroll_scaffold.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_back_link.dart';
import '../../../core/widgets/app_copy_feedback.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_pane_modal_overlay.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../../rust/api/sync.dart' as rust_sync;
import '../../address_book/models/address_book_contact.dart';
import '../../address_book/providers/address_book_provider.dart';
import '../../address_book/widgets/contact_name_inline.dart';
import '../../send/widgets/verify_address_modal.dart';
import '../models/swap_activity_navigation.dart';
import '../models/swap_activity_status_mapper.dart';
import '../models/swap_address_book_helpers.dart';
import '../models/swap_keystone_broadcast_result.dart';
import '../models/swap_models.dart';
import '../providers/pay_deposit_transaction_provider.dart';
import '../providers/swap_state_provider.dart';
import '../screens/mobile/mobile_swap_keystone_sign_screen.dart';
import 'swap_deposit_tokens_page_content.dart';
import 'swap_keystone_signing_overlay.dart';
import 'mobile/mobile_swap_review_header.dart';
import 'mobile/mobile_swap_status_content.dart';
import 'mobile/mobile_swap_timeout_content.dart';
import 'pay_activity_status_content.dart';
import 'swap_status_page_content.dart';

/// Which rendering the detail surface uses. The orchestration (intent
/// selection, status refresh, deposit submission, Keystone signing)
/// is identical; only the widgets differ — desktop keeps the 400pt
/// pane content, mobile renders the Figma mobile swap frames.
enum SwapActivityDetailLayout { desktop, mobile }

class SwapActivityDetailSurface extends ConsumerStatefulWidget {
  const SwapActivityDetailSurface({
    required this.intentId,
    this.returnTarget,
    this.autoSignZecDeposit = false,
    this.layout = SwapActivityDetailLayout.desktop,
    super.key,
  });

  final String intentId;
  final SwapActivityReturnTarget? returnTarget;
  final bool autoSignZecDeposit;
  final SwapActivityDetailLayout layout;

  @override
  ConsumerState<SwapActivityDetailSurface> createState() =>
      _SwapActivityDetailSurfaceState();
}

class _SwapKeystoneSigningRequest {
  const _SwapKeystoneSigningRequest({
    required this.intent,
    required this.intentId,
    required this.accountUuid,
    this.removeUnsentIntentOnCancel = false,
    this.clearPendingIntentOnCancel = false,
  });

  final SwapIntent intent;
  final String intentId;
  final String accountUuid;
  final bool removeUnsentIntentOnCancel;
  final bool clearPendingIntentOnCancel;
}

class _PayRecipientOverlayRequest {
  const _PayRecipientOverlayRequest({required this.address, this.contact});

  final String address;
  final AddressBookContact? contact;
}

class _SwapActivityDetailSurfaceState
    extends ConsumerState<SwapActivityDetailSurface> {
  final _toastOverlayContextKey = GlobalKey(
    debugLabel: 'swap_activity_toast_overlay_context',
  );
  _SwapKeystoneSigningRequest? _keystoneSigningRequest;
  _PayRecipientOverlayRequest? _payRecipientOverlayRequest;
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
      _payRecipientOverlayRequest = null;
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
    final swapState = ref.read(swapStateProvider);
    final persistedIntent = _intentById(swapState.intents, intentId);
    final pendingIntent = widget.autoSignZecDeposit
        ? _pendingKeystoneSigningIntentById(swapState, intentId)
        : null;
    final intent = persistedIntent ?? pendingIntent;
    if (intent == null) return;
    if (persistedIntent != null) {
      ref.read(swapStateProvider.notifier).selectIntent(intentId);
    }
    final needsAutoSign =
        widget.autoSignZecDeposit &&
        _isHardwareIntent(intent) &&
        intent.direction == SwapDirection.zecToExternal &&
        !(intent.depositTxHash?.trim().isNotEmpty ?? false);
    final request = needsAutoSign
        ? _SwapKeystoneSigningRequest(
            intent: intent,
            intentId: intent.id,
            accountUuid: intent.accountUuid ?? _activeAccountUuid ?? '',
            removeUnsentIntentOnCancel: persistedIntent != null,
            clearPendingIntentOnCancel: pendingIntent != null,
          )
        : null;
    if (request != null && widget.layout == SwapActivityDetailLayout.mobile) {
      setState(() => _initialIntentApplied = true);
      unawaited(_openMobileKeystoneSigning(intent, request));
      return;
    }

    setState(() {
      _initialIntentApplied = true;
      if (request != null) {
        _keystoneSigningRequest = request;
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
    final selectedIntent = ref.read(swapStateProvider).selectedIntentOrNull;
    ref.read(swapStateProvider.notifier).prepareRetryFromSelectedIntent();
    if (selectedIntent?.payMode ?? false) {
      context.go(
        '/pay',
        extra: const PayComposerNavigationArgs(preservePreparedComposer: true),
      );
      return;
    }
    context.go('/swap');
  }

  void _signZecDeposit(SwapIntent intent) {
    final request = _SwapKeystoneSigningRequest(
      intent: intent,
      intentId: intent.id,
      accountUuid: intent.accountUuid ?? _activeAccountUuid ?? '',
    );
    if (widget.layout == SwapActivityDetailLayout.mobile) {
      unawaited(_openMobileKeystoneSigning(intent, request));
      return;
    }

    setState(() {
      _keystoneSigningRequest = request;
    });
  }

  void _closeKeystoneSigning({bool cleanupCancelledRequest = false}) {
    final request = _keystoneSigningRequest;
    setState(() => _keystoneSigningRequest = null);
    if (!cleanupCancelledRequest || request == null) return;
    _cleanupCancelledKeystoneSigningRequest(request);
  }

  void _showPayRecipientAddress(String address, AddressBookContact? contact) {
    setState(() {
      _payRecipientOverlayRequest = _PayRecipientOverlayRequest(
        address: address,
        contact: contact,
      );
    });
  }

  void _closePayRecipientAddress() {
    if (_payRecipientOverlayRequest == null) return;
    setState(() => _payRecipientOverlayRequest = null);
  }

  void _cleanupCancelledKeystoneSigningRequest(
    _SwapKeystoneSigningRequest request,
  ) {
    if (request.clearPendingIntentOnCancel) {
      ref
          .read(swapStateProvider.notifier)
          .clearPendingKeystoneSigningIntent(request.intentId);
      if (mounted) {
        context.go((widget.returnTarget ?? SwapActivityReturnTarget.swap).path);
      }
      return;
    }
    if (request.removeUnsentIntentOnCancel) {
      unawaited(
        ref
            .read(swapStateProvider.notifier)
            .removeUnsentHardwareDepositIntent(request.intentId),
      );
    }
  }

  Future<void> _handleKeystoneDepositBroadcast(
    BuildContext context,
    SwapKeystoneBroadcastResult result,
  ) async {
    final request = _keystoneSigningRequest;
    if (request == null) return;
    await _submitKeystoneDepositBroadcast(context, request, result);
    if (!mounted) return;
    _closeKeystoneSigning();
  }

  Future<void> _openMobileKeystoneSigning(
    SwapIntent intent,
    _SwapKeystoneSigningRequest request,
  ) async {
    final result = await context.push<MobileSwapKeystoneSignResult>(
      '/swap/keystone-sign',
      extra: MobileSwapKeystoneSignArgs(intent: intent),
    );
    if (!mounted) return;
    if (result == null) {
      _cleanupCancelledKeystoneSigningRequest(request);
      return;
    }
    switch (result) {
      case MobileSwapKeystoneSignSuccess(:final broadcast):
        await _submitKeystoneDepositBroadcast(context, request, broadcast);
      case MobileSwapKeystoneSignFailure(:final message):
        showAppToast(
          _toastContext(context),
          message,
          iconName: AppIcons.warning,
        );
        _cleanupCancelledKeystoneSigningRequest(request);
    }
  }

  Future<void> _submitKeystoneDepositBroadcast(
    BuildContext context,
    _SwapKeystoneSigningRequest request,
    SwapKeystoneBroadcastResult result,
  ) async {
    final toastContext = _toastContext(context);
    if (request.clearPendingIntentOnCancel) {
      await ref
          .read(swapStateProvider.notifier)
          .recordKeystoneDepositBroadcast(
            intent: request.intent,
            broadcast: result,
          );
    } else {
      await ref
          .read(swapStateProvider.notifier)
          .submitDepositTransactionForIntent(
            intentId: request.intentId,
            accountUuid: request.accountUuid,
            txHash: result.txHash,
            broadcastStatus: result.status,
            broadcastMessage: result.message,
          );
    }
    if (!toastContext.mounted) return;
    showAppToast(
      toastContext,
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
          _payRecipientOverlayRequest = null;
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
    final activityDetailIntent =
        _intentById(state.intents, initialIntentId) ??
        (widget.autoSignZecDeposit
            ? _pendingKeystoneSigningIntentById(state, initialIntentId)
            : null);
    final keystoneSigningRequest = _keystoneSigningRequest;
    final keystoneSigningIntent =
        _intentById(state.intents, keystoneSigningRequest?.intentId) ??
        _pendingKeystoneSigningIntentById(
          state,
          keystoneSigningRequest?.intentId,
        ) ??
        keystoneSigningRequest?.intent;
    final holdInitialAutoSignContent =
        !_initialIntentApplied &&
        widget.autoSignZecDeposit &&
        activityDetailIntent != null &&
        _isHardwareIntent(activityDetailIntent) &&
        activityDetailIntent.direction == SwapDirection.zecToExternal &&
        !(activityDetailIntent.depositTxHash?.trim().isNotEmpty ?? false);
    final hideTransientSigningContent =
        keystoneSigningRequest?.clearPendingIntentOnCancel == true &&
        activityDetailIntent?.id == keystoneSigningRequest?.intentId;

    final Widget pageContent = activityDetailIntent == null
        ? const _SwapActivityMissingPanel()
        : holdInitialAutoSignContent || hideTransientSigningContent
        ? const SizedBox.shrink()
        : SwapActivityDetailPagePanel(
            state: state,
            intent: activityDetailIntent,
            layout: widget.layout,
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
            intentIsHardware: _isHardwareIntent(activityDetailIntent),
            onShowPayRecipientAddress: _showPayRecipientAddress,
          );

    return Stack(
      key: const ValueKey('swap_activity_detail_surface'),
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: _SwapActivityDetailPaneContent(
            returnTarget: widget.returnTarget,
            layout: widget.layout,
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
        if (_payRecipientOverlayRequest case final request?)
          AppPaneModalOverlay(
            onDismiss: _closePayRecipientAddress,
            child: VerifyAddressModal(
              address: request.address,
              variant: request.contact == null
                  ? VerifyAddressModalVariant.unknown
                  : VerifyAddressModalVariant.knownContact,
              unknownAddressKind: VerifyAddressModalAddressKind.external,
              contactName: request.contact?.label,
              contactProfilePictureId: request.contact?.profilePictureId,
              onClose: _closePayRecipientAddress,
            ),
          ),
        if (widget.layout != SwapActivityDetailLayout.mobile)
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
    this.layout = SwapActivityDetailLayout.desktop,
  });

  final Widget child;
  final SwapActivityReturnTarget? returnTarget;
  final SwapActivityDetailLayout layout;

  @override
  Widget build(BuildContext context) {
    // The mobile host draws its own top nav and side padding.
    if (layout == SwapActivityDetailLayout.mobile) {
      return child;
    }
    final returnTarget = this.returnTarget;
    return AppPaneScrollScaffold(
      toolbar: AppPaneToolbar(
        // The surface is also embedded without a navigation origin (no back
        // affordance); the toolbar band stays for the shared scroll layout.
        leading: returnTarget == null
            ? const SizedBox.shrink()
            : AppBackLink(
                label: returnTarget.label,
                minWidth: 60,
                onTap: () => context.go(returnTarget.path),
              ),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: child,
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

SwapIntent? _pendingKeystoneSigningIntentById(
  SwapState state,
  String? intentId,
) {
  if (intentId == null) return null;
  final pending = state.pendingKeystoneSigningIntent;
  if (pending == null || pending.id != intentId) return null;
  return pending;
}

class SwapActivityDetailPagePanel extends StatelessWidget {
  const SwapActivityDetailPagePanel({
    required this.state,
    required this.intent,
    this.layout = SwapActivityDetailLayout.desktop,
    required this.depositChecking,
    required this.depositCheckWarning,
    required this.onRefreshStatus,
    required this.onMarkDeposited,
    required this.onDepositTxHashChanged,
    required this.onSubmitDepositTransaction,
    required this.onReviewFreshQuote,
    required this.onSignZecDeposit,
    required this.intentIsHardware,
    this.onShowPayRecipientAddress,
    super.key,
  });

  final SwapState state;
  final SwapIntent intent;
  final SwapActivityDetailLayout layout;
  final bool depositChecking;
  final String? depositCheckWarning;
  final VoidCallback onRefreshStatus;
  final VoidCallback onMarkDeposited;
  final ValueChanged<String> onDepositTxHashChanged;
  final VoidCallback onSubmitDepositTransaction;
  final VoidCallback onReviewFreshQuote;
  final ValueChanged<SwapIntent> onSignZecDeposit;
  final bool intentIsHardware;
  final void Function(String address, AddressBookContact? contact)?
  onShowPayRecipientAddress;

  @override
  Widget build(BuildContext context) {
    final flowContent = _SwapActivityFlowContent(
      state: state,
      intent: intent,
      layout: layout,
      depositChecking: depositChecking,
      depositCheckWarning: depositCheckWarning,
      onRefreshStatus: onRefreshStatus,
      onMarkDeposited: onMarkDeposited,
      onDepositTxHashChanged: onDepositTxHashChanged,
      onSubmitDepositTransaction: onSubmitDepositTransaction,
      onReviewFreshQuote: onReviewFreshQuote,
      onSignZecDeposit: onSignZecDeposit,
      intentIsHardware: intentIsHardware,
      onShowPayRecipientAddress: onShowPayRecipientAddress,
    );
    final isDepositPage = swapActivityShowsDepositPage(
      intent,
      intentIsHardware: intentIsHardware,
    );

    if (layout == SwapActivityDetailLayout.mobile) {
      return Container(
        key: const ValueKey('swap_activity_detail_page'),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
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

    return KeyedSubtree(
      key: const ValueKey('swap_activity_detail_page'),
      child: Align(
        alignment: isDepositPage ? Alignment.center : Alignment.topCenter,
        child: flowContent,
      ),
    );
  }
}

class _SwapActivityFlowContent extends StatelessWidget {
  const _SwapActivityFlowContent({
    required this.state,
    required this.intent,
    this.layout = SwapActivityDetailLayout.desktop,
    required this.depositChecking,
    required this.depositCheckWarning,
    required this.onRefreshStatus,
    required this.onMarkDeposited,
    required this.onDepositTxHashChanged,
    required this.onSubmitDepositTransaction,
    required this.onReviewFreshQuote,
    required this.onSignZecDeposit,
    required this.intentIsHardware,
    this.onShowPayRecipientAddress,
  });

  final SwapState state;
  final SwapIntent intent;
  final SwapActivityDetailLayout layout;
  final bool depositChecking;
  final String? depositCheckWarning;
  final VoidCallback onRefreshStatus;
  final VoidCallback onMarkDeposited;
  final ValueChanged<String> onDepositTxHashChanged;
  final VoidCallback onSubmitDepositTransaction;
  final VoidCallback onReviewFreshQuote;
  final ValueChanged<SwapIntent> onSignZecDeposit;
  final bool intentIsHardware;
  final void Function(String address, AddressBookContact? contact)?
  onShowPayRecipientAddress;

  @override
  Widget build(BuildContext context) {
    final depositInstruction = SwapActivityDepositInstruction.fromIntent(
      intent,
    );
    final statusError = intent.statusError ?? state.statusError;
    // The expired/failed layouts already tell the failure story; a stale
    // refresh error persisted by an earlier poll (e.g. "service temporarily
    // unavailable") only muddies it, so the warning panel stays hidden there.
    final showStatusError =
        statusError != null &&
        intent.status != SwapIntentStatus.expired &&
        intent.status != SwapIntentStatus.failed;
    final showExternalDepositPage = swapActivityShowsExternalDepositPage(
      intent,
    );
    final showHardwareDepositPage = swapActivityShowsHardwareZecDepositPage(
      intent,
      intentIsHardware: intentIsHardware,
    );
    final primaryContent = switch (intent.status) {
      SwapIntentStatus.expired =>
        layout == SwapActivityDetailLayout.mobile
            ? MobileSwapTimeoutContent(onRestart: onReviewFreshQuote)
            : SwapDepositTimeoutPageContent(onRestart: onReviewFreshQuote),
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
          mobile: layout == SwapActivityDetailLayout.mobile,
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
          mobile: layout == SwapActivityDetailLayout.mobile,
        ),
      _ => _SwapStatusForIntent(
        intent: intent,
        layout: layout,
        onShowPayRecipientAddress: onShowPayRecipientAddress,
      ),
    };

    final mobile = layout == SwapActivityDetailLayout.mobile;
    // All mobile branches now render native full-width content (deposit,
    // status, timeout), so no desktop-content down-scaling is needed.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: mobile
          ? CrossAxisAlignment.stretch
          : CrossAxisAlignment.center,
      children: [
        primaryContent,
        if (showStatusError) ...[
          const SizedBox(height: AppSpacing.md),
          if (mobile)
            _ActivityStatusErrorPanel(message: statusError)
          else
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
    this.layout = SwapActivityDetailLayout.desktop,
    this.onShowPayRecipientAddress,
  });

  final SwapIntent intent;
  final SwapActivityDetailLayout layout;
  final void Function(String address, AddressBookContact? contact)?
  onShowPayRecipientAddress;

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
    final depositTxid = intent.depositTxHash?.trim();
    final accountUuid = intent.accountUuid?.trim();
    final shouldLoadPayDeposit =
        widget.layout == SwapActivityDetailLayout.desktop &&
        intent.payMode &&
        intent.direction == SwapDirection.zecToExternal &&
        depositTxid != null &&
        depositTxid.isNotEmpty &&
        accountUuid != null &&
        accountUuid.isNotEmpty;
    rust_sync.TransactionInfo? depositTransaction;
    if (shouldLoadPayDeposit) {
      depositTransaction = ref.watch(
        syncProvider.select(
          (sync) => _recentPayDepositTransaction(sync.value, intent),
        ),
      );
      depositTransaction ??= ref
          .watch(
            payDepositTransactionProvider((
              accountUuid: accountUuid,
              depositTxid: depositTxid,
            )),
          )
          .value;
    }
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
      confirmedDepositFeeZatoshi: _confirmedPayDepositFeeZatoshi(
        depositTransaction,
      ),
    );
    if (widget.layout == SwapActivityDetailLayout.mobile) {
      final terminal = !presentation.showTabs;
      final paymentMode = presentation.paymentMode;
      final recipient = intent.oneClickRecipient?.trim();
      final hasRecipient = recipient != null && recipient.isNotEmpty;
      final recipientFullAddress = mobileSwapStatusRecipientFullAddress(intent);
      return MobileSwapStatusContent(
        presentation: presentation,
        payHeaderRow: MobileSwapReviewHeaderRow(
          label: !paymentMode && terminal ? 'You paid' : presentation.payLabel,
          amountText: trimSwapAmountText(presentation.payAmountText),
          asset: presentation.payAsset,
          bottomText: presentation.payDetailText,
        ),
        receiveHeaderRow: MobileSwapReviewHeaderRow(
          label: !paymentMode && terminal
              ? 'You received'
              : presentation.receiveLabel,
          amountText: trimSwapAmountText(presentation.receiveAmountText),
          asset: presentation.receiveAsset,
          bottomText: hasRecipient
              ? 'To: ${_headerRecipientText(recipient, presentation: presentation, contacts: addressBookContacts)}'
              : presentation.receiveFiatText,
          fullAddress: recipientFullAddress,
        ),
        activeTab: _activeTab,
        detailsExpanded: _detailsExpanded,
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
      );
    }

    final payStatus = presentation.payStatus;
    final recipientAddress = intent.oneClickRecipient?.trim();
    if (payStatus != null &&
        recipientAddress != null &&
        recipientAddress.isNotEmpty) {
      final recipientContact = addressBookContactForSwapAsset(
        contacts: addressBookContacts,
        asset: presentation.receiveAsset,
        address: recipientAddress,
      );
      final txIdUri = payStatus.txIdUri;
      return PayActivityStatusContent(
        status: payStatus,
        amountAsset: presentation.receiveAsset,
        amountText: presentation.receiveAmountText,
        amountFiatText: presentation.receiveFiatText,
        recipientAddress: recipientAddress,
        recipientContact: recipientContact,
        onShowFullAddress: () => widget.onShowPayRecipientAddress?.call(
          recipientAddress,
          recipientContact,
        ),
        onOpenExplorer: txIdUri == null
            ? null
            : () => unawaited(
                launchUrl(txIdUri, mode: LaunchMode.externalApplication),
              ),
      );
    }

    return SwapStatusPageContent(
      title: presentation.title,
      payAsset: presentation.payAsset,
      receiveAsset: presentation.receiveAsset,
      payAmountText: presentation.payAmountText,
      receiveAmountText: presentation.receiveAmountText,
      payLabel: presentation.payLabel,
      receiveLabel: presentation.receiveLabel,
      payDetailText: presentation.payDetailText,
      payDetailCopyText: presentation.payDetailCopyText,
      receiveDetailText: presentation.receiveDetailText,
      receiveDetailCopyText: presentation.receiveDetailCopyText,
      statusLabel: presentation.statusLabel,
      badgeKind: presentation.badgeKind,
      progressIndex: presentation.progressIndex,
      activeTab: _activeTab,
      steps: presentation.steps,
      details: presentation.details,
      progressTabLabel: presentation.progressTabLabel,
      paymentMode: presentation.paymentMode,
      showTabs: presentation.showTabs,
      onTabChanged: (tab) {
        setState(() {
          _activeTab = tab;
        });
      },
      onCopy: (text) =>
          copyTextWithToast(context, text: text, toastMessage: 'Copied'),
    );
  }
}

BigInt? _confirmedPayDepositFeeZatoshi(rust_sync.TransactionInfo? transaction) {
  if (transaction == null ||
      transaction.expiredUnmined ||
      transaction.minedHeight <= BigInt.zero) {
    return null;
  }
  return transaction.fee > BigInt.zero ? transaction.fee : null;
}

rust_sync.TransactionInfo? _recentPayDepositTransaction(
  SyncState? syncState,
  SwapIntent intent,
) {
  if (syncState == null || syncState.accountUuid != intent.accountUuid) {
    return null;
  }
  final walletTxid = swapChainTxidToWalletTxidHex(intent.depositTxHash);
  if (walletTxid == null) return null;
  for (final transaction in syncState.recentTransactions) {
    if (transaction.txidHex.toLowerCase() == walletTxid) return transaction;
  }
  return null;
}

/// Figma-style 6 ... 5 truncation for the header's "To:" line.
String _truncateHeaderAddress(String address) {
  if (address.length <= 14) return address;
  return '${address.substring(0, 6)} ... '
      '${address.substring(address.length - 5)}';
}

/// Header "To:" text — `"Rowan (0x0cd7 ... 27181)"` when the recipient
/// matches a saved contact on the receive asset's chain, plain truncated
/// address otherwise.
String _headerRecipientText(
  String recipient, {
  required SwapActivityStatusPresentation presentation,
  required Iterable<AddressBookContact> contacts,
}) {
  final label = addressBookContactForSwapAsset(
    contacts: contacts,
    asset: presentation.receiveAsset,
    address: recipient,
  )?.label.trim();
  final compact = _truncateHeaderAddress(recipient);
  if (label == null || label.isEmpty) return compact;
  return contactAddressDisplayText(label: label, compactAddress: compact);
}

String? mobileSwapStatusRecipientFullAddress(SwapIntent intent) {
  final recipient = intent.oneClickRecipient?.trim();
  if (recipient == null || recipient.isEmpty) return null;
  if (intent.direction == SwapDirection.externalToZec) return null;
  return recipient;
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
        if (mounted) {
          setState(() => _hasScrollableExtent = hasScrollableExtent);
        }
      });
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: _handleScrollMetrics,
      child: PrimaryScrollController(
        controller: _controller,
        child: SingleChildScrollView(
          physics: _hasScrollableExtent
              ? const AlwaysScrollableScrollPhysics()
              : const ClampingScrollPhysics(),
          child: widget.child,
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
