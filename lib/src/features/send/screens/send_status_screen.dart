import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/zcash_explorer.dart';
import '../../../core/formatting/zec_amount.dart';
import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_layout.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_back_link.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../providers/rpc_endpoint_failover_provider.dart';
import '../../address_book/models/address_book_contact.dart';
import '../../address_book/models/address_book_label_lookup.dart';
import '../../address_book/providers/address_book_provider.dart';
import '../../keystone/widgets/keystone_transaction_progress_panel.dart';
import '../services/send_flow.dart';
import '../widgets/sapling_params_prompt.dart';
import '../widgets/transaction_receipt_view.dart';

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

  String _formatReceiptAmount(BigInt zatoshi) {
    return ZecAmount.fromZatoshi(zatoshi).receipt.toString();
  }

  String _formatFee(BigInt zatoshi) {
    return ZecAmount.fromZatoshi(zatoshi).fee.toString();
  }

  String _formatDate(DateTime value) {
    const months = <String>[
      '',
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    final hh = value.hour.toString().padLeft(2, '0');
    final mm = value.minute.toString().padLeft(2, '0');
    return '${months[value.month]} ${value.day}, ${value.year} $hh:$mm';
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

  Future<void> _copyTransactionHash() async {
    final txid = _txid;
    if (txid == null) return;
    await Clipboard.setData(ClipboardData(text: txid));
    if (!mounted) return;
    showAppToast(context, 'Transaction Hash Copied');
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
    await _copyTransactionHash();
  }

  Future<void> _copyRecipientAddress() async {
    await Clipboard.setData(ClipboardData(text: widget.args.address.trim()));
    if (!mounted) return;
    showAppToast(context, 'Address copied');
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
        SendBroadcastPhase.pendingBroadcast => _SendStatusPhase.pendingBroadcast,
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
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: AppRouteBackLink(),
            ),
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

  TransactionReceiptBlockData _primaryBlockFor(
    BuildContext context, {
    required bool useFailedReceiptLayout,
    required String? addressBookLabel,
  }) {
    final trimmedAddress = widget.args.address.trim();
    final trimmedLabel = addressBookLabel?.trim();
    if (trimmedLabel != null && trimmedLabel.isNotEmpty) {
      return TransactionReceiptBlockData(
        title: 'To',
        child: TransactionReceiptSavedRecipientAddress(
          address: trimmedAddress,
          label: trimmedLabel,
          onCopy: () => unawaited(_copyRecipientAddress()),
        ),
      );
    }

    return TransactionReceiptBlockData(
      title: 'To',
      child: TransactionReceiptAddressText(
        address: trimmedAddress,
        highlightEdges: widget.args.isShielded,
        compact: !useFailedReceiptLayout && widget.args.isShielded,
        highlightColor: useFailedReceiptLayout
            ? null
            : context.colors.text.brandCrimson,
      ),
      onCopy: useFailedReceiptLayout
          ? () => unawaited(_copyRecipientAddress())
          : null,
    );
  }

  String? _recipientAddressBookLabel(
    Iterable<AddressBookContact> addressBookContacts,
  ) {
    return addressBookLabelFor(
      contacts: addressBookContacts,
      network: AddressBookNetwork.zcash,
      address: widget.args.address,
    );
  }

  @override
  Widget build(BuildContext context) {
    final receiptPhase = switch (_phase) {
      _SendStatusPhase.sending => TransactionReceiptPhase.sending,
      _SendStatusPhase.pendingBroadcast => TransactionReceiptPhase.pending,
      _SendStatusPhase.succeeded => TransactionReceiptPhase.succeeded,
      _SendStatusPhase.failed => TransactionReceiptPhase.failed,
    };
    final useFailedReceiptLayout = _phase == _SendStatusPhase.failed;
    final statusMessage = _statusMessage;
    final isKeystoneSubmitting =
        widget.keystone != null && _phase == _SendStatusPhase.sending;
    final addressBookContacts =
        ref.watch(addressBookProvider).value?.contacts ??
        const <AddressBookContact>[];
    final addressBookLabel = _recipientAddressBookLabel(addressBookContacts);

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
                  children: [
                    Positioned.fill(
                      child: IgnorePointer(
                        child: TransactionReceiptIllustration(
                          failed: useFailedReceiptLayout,
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.md,
                          AppSpacing.md,
                          0,
                          AppSpacing.md,
                        ),
                        child: Column(
                          children: [
                            const Align(
                              alignment: Alignment.centerLeft,
                              child: AppRouteBackLink(),
                            ),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(right: 255),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: TransactionReceiptView(
                                    key: ValueKey(
                                      'send_status_${receiptPhase.name}',
                                    ),
                                    phase: receiptPhase,
                                    amountText: _formatReceiptAmount(
                                      widget.args.amountZatoshi,
                                    ),
                                    primaryBlock: _primaryBlockFor(
                                      context,
                                      useFailedReceiptLayout:
                                          useFailedReceiptLayout,
                                      addressBookLabel: addressBookLabel,
                                    ),
                                    feeText: _formatFee(widget.args.feeZatoshi),
                                    extraBlocks: [
                                      if (statusMessage != null)
                                        TransactionReceiptBlockData(
                                          title: 'Status',
                                          child: Text(
                                            statusMessage,
                                            style: AppTypography.bodyMedium
                                                .copyWith(
                                                  color: context
                                                      .colors
                                                      .text
                                                      .accent,
                                                ),
                                          ),
                                        ),
                                    ],
                                    dateText: _formatDate(
                                      _completedAt ?? _startedAt,
                                    ),
                                    error: _error,
                                    failureFallbackText: 'Send failed',
                                    useFailedReceiptLayout:
                                        useFailedReceiptLayout,
                                    onTransactionHashPressed:
                                        (_phase == _SendStatusPhase.succeeded ||
                                                _phase ==
                                                    _SendStatusPhase
                                                        .pendingBroadcast) &&
                                            _txid != null
                                        ? _openTransactionExplorer
                                        : null,
                                    onBackToWallet:
                                        _phase == _SendStatusPhase.failed
                                        ? _goHome
                                        : null,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
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
