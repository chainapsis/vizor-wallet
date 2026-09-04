import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/zcash_explorer.dart';
import '../../../core/formatting/address_display.dart';
import '../../../core/formatting/date_format.dart';
import '../../../core/formatting/zec_amount.dart';
import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_pane_scroll_scaffold.dart';
import '../../../core/layout/app_layout.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_copy_feedback.dart';
import '../../../core/widgets/app_back_link.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/zec_price_change_provider.dart';
import '../../../providers/rpc_endpoint_failover_provider.dart';
import '../../../providers/zcash_explorer_provider.dart';
import '../../address_book/models/address_book_contact.dart';
import '../../address_book/providers/address_book_provider.dart';
import '../../keystone/widgets/keystone_transaction_progress_panel.dart';
import '../../donation/widgets/donation_views.dart';
import '../services/send_flow.dart';
import '../widgets/sapling_params_prompt.dart';
import '../widgets/send_recipient_resolver.dart';
import '../widgets/send_status_content_view.dart';
import '../widgets/send_verify_address_overlay.dart';

enum _SendStatusPhase { sending, pendingBroadcast, succeeded, failed }

typedef SendStatusBroadcastRunner =
    Future<SendBroadcastOutcome> Function({
      required WidgetRef ref,
      required SendReviewArgs args,
      KeystoneBroadcastArgs? keystone,
      required Future<bool> Function() confirmSaplingParamsDownload,
      Future<bool> Function()? shouldAbort,
    });

class SendStatusScreen extends ConsumerStatefulWidget {
  const SendStatusScreen({
    super.key,
    required this.args,
    this.keystone,
    this.broadcastRunner,
  });

  final SendReviewArgs args;
  final KeystoneBroadcastArgs? keystone;

  /// The software send's missing-mnemonic branch is `!Platform.isMacOS`, so a
  /// macOS test host cannot reach it through the real runner.
  @visibleForTesting
  final SendStatusBroadcastRunner? broadcastRunner;

  @override
  ConsumerState<SendStatusScreen> createState() => _SendStatusScreenState();
}

class _SendStatusScreenState extends ConsumerState<SendStatusScreen> {
  _SendStatusPhase _phase = _SendStatusPhase.sending;
  bool _proposalConsumed = false;

  /// The one release of this receipt's proposal, once something has claimed
  /// it — the failed outcome or `dispose`. Handed to the terminal flag on the
  /// way out so a departure mid-release does not publish "safe to leave"
  /// before the inputs are actually free.
  Future<bool>? _proposalRelease;
  String? _error;
  String? _statusMessage;
  String? _txid;
  late final DateTime _startedAt = DateTime.now();
  DateTime? _completedAt;
  bool _showSaplingParamsPrompt = false;
  bool _messageExpanded = false;
  bool _showVerifyAddress = false;
  Completer<bool>? _saplingParamsPromptCompleter;

  /// Captured in [initState] so [dispose] can release the flag without reading
  /// from `ref` after the element is gone.
  late final SendStatusTerminalNotifier _sendStatusTerminal;
  bool get _suppressSidebarSelection =>
      widget.args.flowKind == SendFlowKind.donation;

  @override
  void initState() {
    super.initState();
    _sendStatusTerminal = ref.read(sendStatusTerminalProvider.notifier);
    _proposalConsumed = widget.keystone != null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(appLayoutProvider.notifier).setMode(AppLayoutMode.large);
      unawaited(_startBroadcast());
    });
  }

  @override
  void dispose() {
    final promptCompleter = _saplingParamsPromptCompleter;
    _saplingParamsPromptCompleter = null;
    if (promptCompleter != null && !promptCompleter.isCompleted) {
      promptCompleter.complete(false);
    }
    if (_phase != _SendStatusPhase.sending) {
      unawaited(_discardProposalIfNeeded('SendStatus(dispose)'));
    }
    _sendStatusTerminal.resetAfterNavigation(afterRelease: _proposalRelease);
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
      proposalId: widget.args.proposalId,
      sendFlowId: widget.args.sendFlowId,
      logContext: logContext,
    );
  }

  String _formatAmount(BigInt zatoshi) {
    return ZecAmount.fromZatoshi(zatoshi).activityDetail.toString();
  }

  String _formatFee(BigInt zatoshi) {
    return ZecAmount.fromZatoshi(zatoshi).fee.toString();
  }

  Future<bool> _showSaplingParamsDialog() {
    if (!mounted) return Future.value(false);

    final existingCompleter = _saplingParamsPromptCompleter;
    if (existingCompleter != null && !existingCompleter.isCompleted) {
      return existingCompleter.future;
    }

    final completer = Completer<bool>();
    setState(() {
      _saplingParamsPromptCompleter = completer;
      _showSaplingParamsPrompt = true;
    });
    return completer.future;
  }

  void _resolveSaplingParamsDialog(bool confirmed) {
    final completer = _saplingParamsPromptCompleter;
    if (completer == null || completer.isCompleted) return;

    setState(() {
      _showSaplingParamsPrompt = false;
      _saplingParamsPromptCompleter = null;
    });
    completer.complete(confirmed);
  }

  Future<void> _goHome() async {
    if (!mounted) return;
    ref.read(sendStatusRoutePayloadProvider.notifier).clear();
    context.go('/home');
  }

  void _copyTransactionHash() {
    final txid = _txid;
    if (txid == null) return;
    copyTextWithToast(
      context,
      text: txid,
      toastMessage: 'Transaction hash copied',
    );
  }

  Future<void> _openTransactionExplorer() async {
    final txid = _txid;
    if (txid == null) return;
    final endpoint = ref.read(rpcEndpointFailoverProvider).current;
    final launched = await launchZcashExplorerTransaction(
      networkName: endpoint.networkName,
      txidHex: txid,
      txidOrder: ZcashExplorerTxidOrder.display,
      customTemplate: ref.read(zcashExplorerProvider),
    );
    if (launched || !mounted) return;
    _copyTransactionHash();
  }

  Future<void> _startBroadcast() async {
    // A broadcast is starting: nothing is safe to leave yet.
    _sendStatusTerminal.reset();
    final runner = widget.broadcastRunner ?? runSendBroadcast;
    final outcome = await runner(
      ref: ref,
      args: widget.args,
      keystone: widget.keystone,
      confirmSaplingParamsDownload: _showSaplingParamsDialog,
      shouldAbort: () async => !mounted,
    );
    _proposalConsumed = outcome.proposalConsumed;
    if (outcome.phase == SendBroadcastPhase.aborted || !mounted) return;
    setState(() {
      _phase = switch (outcome.phase) {
        SendBroadcastPhase.succeeded => _SendStatusPhase.succeeded,
        SendBroadcastPhase.pendingBroadcast =>
          _SendStatusPhase.pendingBroadcast,
        SendBroadcastPhase.failed => _SendStatusPhase.failed,
        SendBroadcastPhase.aborted => _SendStatusPhase.failed,
      };
      _txid = outcome.txid;
      _statusMessage = outcome.statusMessage;
      _error = outcome.error;
      if (outcome.phase != SendBroadcastPhase.failed) {
        _completedAt = DateTime.now();
      }
    });
    if (_phase == _SendStatusPhase.succeeded ||
        _phase == _SendStatusPhase.failed) {
      if (_phase == _SendStatusPhase.failed) {
        // A failed outcome does not always hand the proposal back: the
        // software send's missing-mnemonic branch returns
        // `proposalConsumed: false` without touching Rust's PROPOSAL_STORE,
        // and until now the release waited for `dispose`. Marking the send
        // terminal first lets `_IncomingLinkHost` drain a parked `zcash:`
        // request against inputs this dead send still locks, which the
        // request pre-check reads as insufficient funds. So: release, then
        // publish "safe to leave".
        final released = await _discardProposalIfNeeded('SendStatus(failed)');
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

  Widget _buildKeystoneSubmittingScreen(BuildContext context) {
    final colors = context.colors;
    return AppDesktopShell(
      sidebar: AppMainSidebar(
        suppressActiveSelection: _suppressSidebarSelection,
      ),
      pane: AppDesktopPane(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AppPaneToolbar(leading: AppRouteBackLink(minWidth: 60)),
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Scan your Keystone QR Code',
                      style: AppTypography.headlineLarge.copyWith(
                        color: colors.button.ghost.label,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    const KeystoneTransactionProgressPanel(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // The legacy receipt's pending phase rendered the loader + "In progress"
    // status with the explorer link; pendingBroadcast keeps that mapping
    // (in-progress visuals + Tx ID row + the broadcast guidance notice).
    final statusPhase = switch (_phase) {
      _SendStatusPhase.sending ||
      _SendStatusPhase.pendingBroadcast => SendStatusPhase.inProgress,
      _SendStatusPhase.succeeded => SendStatusPhase.completed,
      _SendStatusPhase.failed => SendStatusPhase.failed,
    };
    final isDonation = widget.args.flowKind == SendFlowKind.donation;
    final isKeystoneSubmitting =
        widget.keystone != null && _phase == _SendStatusPhase.sending;
    final addressBookContacts =
        ref.watch(addressBookProvider).value?.contacts ??
        const <AddressBookContact>[];
    final ownAccounts =
        ref.watch(ownAccountAddressesProvider).value ??
        const <String, AccountInfo>{};
    final recipient = sendReviewRecipientFor(
      contacts: addressBookContacts,
      address: widget.args.address,
      ownAccounts: ownAccounts,
    );
    final zecUsdUnitPrice = ref.watch(zecHomeUsdUnitPriceProvider);
    final memo = widget.args.memo;
    // Present means non-empty, not non-blank: an edited request whose memo is
    // only whitespace still sends that memo, so the row has to say so rather
    // than omit a memo the transaction carries.
    final hasMemo = memo != null && memo.isNotEmpty;
    final canOpenExplorer =
        (_phase == _SendStatusPhase.succeeded ||
            _phase == _SendStatusPhase.pendingBroadcast) &&
        _txid != null;

    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          unawaited(_goHome());
        }
      },
      child: isKeystoneSubmitting
          ? _buildKeystoneSubmittingScreen(context)
          : widget.args.flowKind == SendFlowKind.donation &&
                _phase == _SendStatusPhase.succeeded
          ? AppDesktopShell(
              background: const DonationSuccessBackground(),
              sidebar: AppMainSidebar(
                suppressActiveSelection: _suppressSidebarSelection,
              ),
              pane: AppDesktopPane(
                padding: EdgeInsets.zero,
                child: DonationSuccessView(onDone: () => unawaited(_goHome())),
              ),
            )
          : AppDesktopShell(
              sidebar: AppMainSidebar(
                suppressActiveSelection: _suppressSidebarSelection,
              ),
              pane: AppDesktopPane(
                padding: EdgeInsets.zero,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    AppPaneScrollScaffold(
                      toolbar: const AppPaneToolbar(backLinkMinWidth: 60),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                      ),
                      child: SendStatusContentView(
                        key: ValueKey('send_status_${statusPhase.name}'),
                        phase: statusPhase,
                        titleOverride: isDonation
                            ? switch (_phase) {
                                _SendStatusPhase.failed => 'Donation failed',
                                _ => 'Donation in progress...',
                              }
                            : null,
                        amountText: _formatAmount(widget.args.amountZatoshi),
                        fiatText: fiatTextForZatoshi(
                          widget.args.amountZatoshi,
                          zecUsdUnitPrice: zecUsdUnitPrice,
                        ),
                        recipient: recipient,
                        timestampText: formatDayMonthTime(
                          _completedAt ?? _startedAt,
                        ),
                        txIdText: _txid == null ? null : truncatedTxid(_txid!),
                        feeText: _formatFee(widget.args.feeZatoshi),
                        isShieldedRecipient: widget.args.isShielded,
                        recipientAddressType: widget.args.addressType,
                        recipientRow: isDonation
                            ? DonationRecipientInfoRow(
                                struckThrough:
                                    _phase == _SendStatusPhase.failed,
                              )
                            : null,
                        memoText: hasMemo ? memo : null,
                        memoExpanded: _messageExpanded,
                        noticeText: _phase == _SendStatusPhase.failed
                            ? (_error ?? 'Send failed')
                            : _statusMessage,
                        onShowFullAddress: isDonation
                            ? null
                            : () => setState(() => _showVerifyAddress = true),
                        onExpandMemo: () => setState(
                          () => _messageExpanded = !_messageExpanded,
                        ),
                        onOpenExplorer: canOpenExplorer
                            ? _openTransactionExplorer
                            : null,
                      ),
                    ),
                    if (_showVerifyAddress)
                      SendVerifyAddressOverlay(
                        accountUuid: widget.args.proposalAccountUuid,
                        address: widget.args.address.trim(),
                        isShieldedAddress: widget.args.isShielded,
                        onClose: () =>
                            setState(() => _showVerifyAddress = false),
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
            ),
    );
  }
}
