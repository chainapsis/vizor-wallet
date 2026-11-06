import '../../../../core/l10n/l10n.dart';
import '../../../../core/navigation/mobile_sidebar_exit.dart';
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../providers/sync_provider.dart';

import '../../../../core/feedback/app_haptics.dart';
import '../../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../../core/zcash/network_upgrade_hold.dart';
import '../../../../core/widgets/mobile/mobile_transaction_progress_screen.dart';
import '../../services/send_flow.dart';
import '../../../donation/widgets/donation_views.dart';
import 'mobile_send_screen.dart' show MobileSaplingParamsSheet;

enum _MobileSendStatusPhase { sending, pendingBroadcast, succeeded, failed }

const _statusSubtitleWidth = 223.0;

typedef MobileSendBroadcastRunner =
    Future<SendBroadcastOutcome> Function({
      required WidgetRef ref,
      required AppLocalizations l10n,
      required SendReviewArgs args,
      KeystoneBroadcastArgs? keystone,
      LedgerBroadcastArgs? ledger,
      required Future<bool> Function() confirmSaplingParamsDownload,
      Future<bool> Function()? shouldAbort,
    });

class MobileSendStatusScreen extends ConsumerStatefulWidget {
  const MobileSendStatusScreen({
    required this.args,
    this.keystone,
    this.ledger,
    this.broadcastRunner,
    super.key,
  });

  final SendReviewArgs args;
  final KeystoneBroadcastArgs? keystone;
  final LedgerBroadcastArgs? ledger;

  @visibleForTesting
  final MobileSendBroadcastRunner? broadcastRunner;

  @override
  ConsumerState<MobileSendStatusScreen> createState() =>
      _MobileSendStatusScreenState();
}

class _MobileSendStatusScreenState
    extends ConsumerState<MobileSendStatusScreen> {
  bool get _isDonation => widget.args.flowKind == SendFlowKind.donation;
  var _phase = _MobileSendStatusPhase.sending;
  var _proposalConsumed = false;

  /// The one release of this receipt's proposal, once something has claimed
  /// it — the failed outcome or `dispose`. Handed to the terminal flag on the
  /// way out so a departure mid-release does not publish "safe to leave"
  /// before the inputs are actually free.
  Future<bool>? _proposalRelease;

  /// The running broadcast; a receipt left while still `sending` hands its
  /// completion to the terminal flag instead of a release of its own.
  Future<SendBroadcastOutcome>? _broadcast;
  bool _canRetryBroadcast = false;
  KeystoneBroadcastArgs? _keystoneRecovery;
  String? _statusMessage;
  String? _error;
  NetworkUpgradeHold? _errorHold;

  /// Captured in [initState] so [dispose] can release the flag without reading
  /// from `ref` after the element is gone.
  late final SendStatusTerminalNotifier _sendStatusTerminal;
  late final SyncNotifier _syncNotifier;

  @override
  void initState() {
    super.initState();
    _sendStatusTerminal = ref.read(sendStatusTerminalProvider.notifier);
    _syncNotifier = ref.read(syncProvider.notifier);
    _proposalConsumed = widget.keystone != null || widget.ledger != null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_startBroadcast());
    });
  }

  @override
  void dispose() {
    // Unmounted before the post-frame broadcast ever started: nothing else
    // owns the proposal, so release it here.
    final broadcastOwnsProposal =
        _phase == _MobileSendStatusPhase.sending && _broadcast != null;
    if (!broadcastOwnsProposal) {
      unawaited(_discardProposalIfNeeded('MobileSendStatus(dispose)'));
    }
    _sendStatusTerminal.resetAfterNavigation(
      // Left mid-broadcast: the runner's abort cleanup owns the proposal, so
      // the edge waits for it.
      afterRelease: broadcastOwnsProposal
          ? _broadcast!.then((outcome) => outcome.proposalConsumed)
          : _proposalRelease,
      // Idempotent in Rust, so no gate on the (optimistic) consumed flag.
      retryRelease: () => discardSendProposal(
        syncNotifier: _syncNotifier,
        accountUuid: widget.args.proposalAccountUuid,
        proposalId: widget.args.proposalId,
        sendFlowId: widget.args.sendFlowId,
        logContext: 'MobileSendStatus(retry)',
      ),
    );
    super.dispose();
  }

  /// Releases the proposal unless the broadcast already consumed it.
  ///
  /// Idempotent by claim rather than by retry: the first caller — the failed
  /// outcome below or [dispose] — takes the discard and every later call is a
  /// no-op, so a failure that releases the proposal on screen does not get a
  /// second release when the receipt is finally left.
  Future<bool> _discardProposalIfNeeded(String logContext) {
    if (_proposalConsumed) return Future<bool>.value(true);
    return _proposalRelease ??= discardSendProposal(
      syncNotifier: _syncNotifier,
      accountUuid: widget.args.proposalAccountUuid,
      proposalId: widget.args.proposalId,
      sendFlowId: widget.args.sendFlowId,
      logContext: logContext,
    );
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

  Future<void> _startBroadcast() async {
    if (!mounted ||
        (_phase == _MobileSendStatusPhase.sending && _broadcast != null)) {
      return;
    }
    if (_canRetryBroadcast) {
      _keystoneRecovery = widget.keystone!.forRecoveryRetry();
    }
    setState(() {
      _phase = _MobileSendStatusPhase.sending;
      _canRetryBroadcast = false;
      _statusMessage = null;
    });
    // A broadcast is starting: nothing is safe to leave yet.
    _sendStatusTerminal.reset();
    final runner = widget.broadcastRunner ?? runSendBroadcast;
    final broadcast = runner(
      ref: ref,
      l10n: context.l10n,
      args: widget.args,
      keystone: _keystoneRecovery ?? widget.keystone,
      ledger: widget.ledger,
      confirmSaplingParamsDownload: _confirmSaplingParamsDownload,
      shouldAbort: () async => !mounted,
    );
    _broadcast = broadcast;
    final outcome = await broadcast;
    _proposalConsumed = outcome.proposalConsumed;
    if (outcome.phase == SendBroadcastPhase.aborted || !mounted) return;

    setState(() {
      _canRetryBroadcast = outcome.canRetryBroadcast;
      _phase = switch (outcome.phase) {
        SendBroadcastPhase.succeeded => _MobileSendStatusPhase.succeeded,
        SendBroadcastPhase.pendingBroadcast =>
          _MobileSendStatusPhase.pendingBroadcast,
        SendBroadcastPhase.failed => _MobileSendStatusPhase.failed,
        SendBroadcastPhase.aborted => _MobileSendStatusPhase.failed,
      };
      _statusMessage = outcome.statusMessage;
      _error = outcome.error;
      _errorHold = outcome.errorHold;
    });
    // Success and failure use custom native haptic patterns without system
    // notification sounds.
    switch (_phase) {
      case _MobileSendStatusPhase.succeeded:
        unawaited(AppHaptics.sendSuccess());
      case _MobileSendStatusPhase.failed:
        unawaited(AppHaptics.sendFailure());
      case _MobileSendStatusPhase.sending:
      case _MobileSendStatusPhase.pendingBroadcast:
        break;
    }
    // A retained signed batch still owns recovery; keep incoming payment
    // links parked until it completes or the user explicitly leaves.
    if (_canRetryBroadcast) return;
    if (_phase == _MobileSendStatusPhase.succeeded ||
        _phase == _MobileSendStatusPhase.failed) {
      if (_phase == _MobileSendStatusPhase.failed) {
        // A failed outcome does not always hand the proposal back: the
        // software send's missing-mnemonic branch returns
        // `proposalConsumed: false` without touching Rust's PROPOSAL_STORE,
        // and until now the release waited for `dispose`. Marking the send
        // terminal first lets `_IncomingLinkHost` drain a parked `zcash:`
        // request against inputs this dead send still locks, which the
        // request pre-check reads as insufficient funds. So: release, then
        // publish "safe to leave".
        final released = await _discardProposalIfNeeded(
          'MobileSendStatus(failed)',
        );
        // Leaving during the release means `dispose` already reset the flag;
        // re-raising it here would strand it for the next screen.
        if (!mounted) return;
        // A release Rust never confirmed leaves the inputs held until expiry;
        // the drain must keep waiting rather than pre-check against them.
        if (!released) return;
      }
      _sendStatusTerminal.markTerminal();
    }
  }

  void _handleBack() {
    if (_phase == _MobileSendStatusPhase.sending) return;
    if (_isDonation) {
      context.go('/settings');
      return;
    }
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go('/home');
  }

  bool get _routePopAllowed => _phase != _MobileSendStatusPhase.sending;

  MobileTransactionProgressPhase get _presentationPhase {
    return switch (_phase) {
      _MobileSendStatusPhase.sending =>
        MobileTransactionProgressPhase.inProgress,
      _MobileSendStatusPhase.pendingBroadcast =>
        MobileTransactionProgressPhase.pending,
      _MobileSendStatusPhase.succeeded =>
        MobileTransactionProgressPhase.succeeded,
      _MobileSendStatusPhase.failed => MobileTransactionProgressPhase.failed,
    };
  }

  String get _title {
    if (_isDonation) {
      return switch (_phase) {
        _MobileSendStatusPhase.sending =>
          context.l10n.sendStatusMobileSendingDonation,
        _MobileSendStatusPhase.pendingBroadcast =>
          context.l10n.sendStatusMobileDonationQueued,
        _MobileSendStatusPhase.succeeded =>
          context.l10n.sendStatusMobileDonationThanks,
        _MobileSendStatusPhase.failed => context.l10n.sendStatusDonationFailed,
      };
    }
    return switch (_phase) {
      _MobileSendStatusPhase.sending => context.l10n.commonSending,
      _MobileSendStatusPhase.pendingBroadcast =>
        context.l10n.sendStatusMobileQueued,
      _MobileSendStatusPhase.succeeded => context.l10n.sendStatusMobileSent,
      _MobileSendStatusPhase.failed => context.l10n.commonSendFailed,
    };
  }

  String get _subtitle {
    if (_isDonation && _phase == _MobileSendStatusPhase.succeeded) {
      return context.l10n.sendStatusMobileDonationSupport;
    }
    final statusMessage = _statusMessage?.trim();
    return switch (_phase) {
      _MobileSendStatusPhase.sending => context.l10n.sendStatusMobileSubmitting,
      _MobileSendStatusPhase.pendingBroadcast =>
        statusMessage == null || statusMessage.isEmpty
            ? context.l10n.sendStatusMobilePendingDefault
            : statusMessage,
      _MobileSendStatusPhase.succeeded =>
        context.l10n.sendStatusMobileConfirmSoon,
      _MobileSendStatusPhase.failed =>
        _canRetryBroadcast
            ? (_error ?? context.l10n.sendStatusRetryAfterSync)
            : _errorHold == NetworkUpgradeHold.hold
            ? networkUpgradeHoldText(context.l10n)
            : context.l10n.sendStatusMobileNothingSent,
    };
  }

  String? get _buttonLabel {
    return switch (_phase) {
      _MobileSendStatusPhase.sending => null,
      _MobileSendStatusPhase.pendingBroadcast ||
      _MobileSendStatusPhase.succeeded => context.l10n.commonDone,
      _MobileSendStatusPhase.failed =>
        _canRetryBroadcast
            ? context.l10n.commonRetry
            : _isDonation
            ? context.l10n.sendStatusMobileReturnToSettings
            : context.l10n.commonReturnHome,
    };
  }

  @override
  Widget build(BuildContext context) {
    return MobileSidebarExitScope(
      canNavigate: _routePopAllowed,
      canSwitchAccount: _routePopAllowed,
      onExit: () => _discardProposalIfNeeded('MobileSendStatus(sidebar)'),
      child: MobileTransactionProgressScreen(
        phase: _presentationPhase,
        title: _title,
        body: _subtitle,
        bodyMaxWidth: _phase == _MobileSendStatusPhase.pendingBroadcast
            ? null
            : _isDonation && _phase == _MobileSendStatusPhase.succeeded
            ? 260
            : _statusSubtitleWidth,
        canPop: _routePopAllowed && !_isDonation,
        onPopBlocked: _handleBack,
        titleKey: ValueKey('mobile_send_status_${_phase.name}'),
        progressIconKey: const ValueKey('mobile_send_status_icon_loader'),
        successIconKey: const ValueKey('mobile_send_status_icon_success'),
        failureIconKey: const ValueKey('mobile_send_status_icon_failed'),
        successRippleKey: const ValueKey('mobile_send_status_success_ripple'),
        successBadge: _isDonation ? const DonationHeartBadge(size: 112) : null,
        primaryActionKey: const ValueKey('mobile_send_status_button'),
        primaryActionLabel: _buttonLabel,
        onPrimaryAction: _buttonLabel == null
            ? null
            : _canRetryBroadcast
            ? () => unawaited(_startBroadcast())
            : _handleBack,
        secondaryActionLabel: _canRetryBroadcast
            ? (_isDonation
                  ? context.l10n.sendStatusMobileReturnToSettings
                  : context.l10n.commonReturnHome)
            : null,
        onSecondaryAction: _canRetryBroadcast ? _handleBack : null,
      ),
    );
  }
}
