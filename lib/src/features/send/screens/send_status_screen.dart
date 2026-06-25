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
import '../../address_book/models/address_book_contact.dart';
import '../../address_book/providers/address_book_provider.dart';
import '../../keystone/widgets/keystone_transaction_progress_panel.dart';
import '../services/send_flow.dart';
import '../widgets/sapling_params_prompt.dart';
import '../widgets/send_recipient_resolver.dart';
import '../widgets/send_status_content_view.dart';
import '../widgets/send_verify_address_overlay.dart';

enum _SendStatusPhase { sending, pendingBroadcast, succeeded, failed }

class SendStatusScreen extends ConsumerStatefulWidget {
  const SendStatusScreen({super.key, required this.args, this.keystone});

  final SendReviewArgs args;
  final KeystoneBroadcastArgs? keystone;

  @override
  ConsumerState<SendStatusScreen> createState() => _SendStatusScreenState();
}

class _SendStatusScreenState extends ConsumerState<SendStatusScreen> {
  _SendStatusPhase _phase = _SendStatusPhase.sending;
  bool _proposalConsumed = false;
  bool _discardScheduled = false;
  String? _error;
  String? _statusMessage;
  String? _txid;
  late final DateTime _startedAt = DateTime.now();
  DateTime? _completedAt;
  bool _showSaplingParamsPrompt = false;
  bool _messageExpanded = false;
  bool _showVerifyAddress = false;
  Completer<bool>? _saplingParamsPromptCompleter;

  @override
  void initState() {
    super.initState();
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
      _scheduleDiscardIfNeeded();
    }
    super.dispose();
  }

  void _scheduleDiscardIfNeeded() {
    if (_proposalConsumed || _discardScheduled) return;
    _discardScheduled = true;
    unawaited(
      discardSendProposal(
        proposalId: widget.args.proposalId,
        sendFlowId: widget.args.sendFlowId,
        logContext: 'SendStatus(dispose)',
      ),
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
    );
    if (launched || !mounted) return;
    _copyTransactionHash();
  }

  Future<void> _startBroadcast() async {
    final outcome = await runSendBroadcast(
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
  }

  Widget _buildKeystoneSubmittingScreen(BuildContext context) {
    final colors = context.colors;
    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
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
    final hasMemo = memo != null && memo.trim().isNotEmpty;
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
          : AppDesktopShell(
              sidebar: const AppMainSidebar(),
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
                        memoText: hasMemo ? memo : null,
                        memoExpanded: _messageExpanded,
                        noticeText: _phase == _SendStatusPhase.failed
                            ? (_error ?? 'Send failed')
                            : _statusMessage,
                        onShowFullAddress: () =>
                            setState(() => _showVerifyAddress = true),
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
