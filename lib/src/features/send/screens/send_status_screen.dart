import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../main.dart' show log;
import '../../../core/config/zcash_explorer.dart';
import '../../../core/formatting/zec_amount.dart';
import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_layout.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/storage/wallet_paths.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_back_link.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/rpc_endpoint_failover_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../../rust/api/sync.dart' as rust_sync;
import '../../keystone/widgets/keystone_transaction_progress_panel.dart';
import '../services/sapling_params.dart';
import '../widgets/sapling_params_prompt.dart';
import '../widgets/transaction_receipt_view.dart';
import 'send_review_screen.dart';

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
      rust_sync
          .discardProposal(
            proposalId: widget.args.proposalId,
            sendFlowId: widget.args.sendFlowId,
          )
          .then((_) {
            log(
              'SendStatus: released proposal ${widget.args.proposalId} on dispose',
            );
          })
          .catchError((Object e) {
            log(
              'SendStatus: discardProposal cleanup failed (non-critical): $e',
            );
          }),
    );
  }

  String _friendlyError(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('insufficientfunds') || lower.contains('insufficient')) {
      return 'Insufficient shielded balance to cover amount and fee.';
    }
    if (lower.contains('grpc connect failed') ||
        lower.contains('connection refused') ||
        lower.contains('dns error') ||
        lower.contains('tls error')) {
      return 'Network error. Check your connection and try again.';
    }
    if (lower.contains('broadcast failed after') &&
        lower.contains('txs sent')) {
      return 'Some parts of this transaction were sent. Open Activity to see '
          'what went through before you try again.';
    }
    if (lower.contains('broadcast rejected')) {
      return 'The network rejected this transaction. Try again later.';
    }
    if (lower.contains('proposal not found') ||
        lower.contains('send flow mismatch')) {
      return 'Transaction expired before it could be sent.';
    }
    return "Transaction couldn't be sent. Go back to your wallet and check "
        'the latest status.';
  }

  String? _firstTxid(String txids) {
    for (final part in txids.split(',')) {
      final trimmed = part.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
    return null;
  }

  String _broadcastStatusMessage(rust_sync.ExecuteProposalResult result) {
    if (result.status == 'partial_broadcast') {
      return 'Some transactions were broadcast and the rest will retry automatically. Check activity before sending again.';
    }
    final rawMessage = result.message?.toLowerCase() ?? '';
    if (rawMessage.contains('broadcast rejected')) {
      return "Transaction was created locally but didn't reach the network. "
          'The wallet will keep retrying until it expires. '
          "Don't send again unless this one expires.";
    }
    return 'Transaction was created locally but could not be broadcast. It will retry automatically when the network is available. Do not send again unless this transaction expires.';
  }

  String _pcztBroadcastStatusMessage(
    rust_sync.ExtractAndBroadcastPcztResult result,
  ) {
    if (result.status == 'broadcast_unknown') {
      return result.message ??
          'The transaction may have reached the network, but confirmation timed out. Check activity before sending again.';
    }
    if (result.status == 'broadcasted_storage_failed') {
      return result.message ??
          'The transaction reached the network, but Vizor could not store it locally. Do not send again until sync or an explorer confirms the latest status.';
    }
    final rawMessage = result.message?.toLowerCase() ?? '';
    if (rawMessage.contains('broadcast rejected')) {
      return 'Transaction was rejected by the network. Please try again later.';
    }
    return 'Transaction was created locally but could not be broadcast. It will retry automatically when the network is available. Do not send again unless this transaction expires.';
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

  List<TextSpan> _addressSpans(BuildContext context, String line) {
    final colors = context.colors;
    if (!widget.args.isShielded || line.length < 8) {
      return [
        TextSpan(
          text: line,
          style: AppTypography.bodyMedium.copyWith(color: colors.text.accent),
        ),
      ];
    }
    final prefix = line.substring(0, 7);
    final suffix = line.length > 8 ? line.substring(line.length - 8) : '';
    final middle = line.substring(prefix.length, line.length - suffix.length);
    return [
      TextSpan(
        text: prefix,
        style: AppTypography.bodyMedium.copyWith(
          color: colors.text.brandCrimson,
        ),
      ),
      TextSpan(
        text: middle,
        style: AppTypography.bodyMedium.copyWith(color: colors.text.accent),
      ),
      if (suffix.isNotEmpty)
        TextSpan(
          text: suffix,
          style: AppTypography.bodyMedium.copyWith(
            color: colors.text.brandCrimson,
          ),
        ),
    ];
  }

  List<String> _splitAddress() {
    final address = widget.args.address.trim();
    if (address.length <= 16) return [address];
    final midpoint = (address.length / 2).ceil();
    return [address.substring(0, midpoint), address.substring(midpoint)];
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
    showAppToast(context, 'Address Copied');
  }

  Future<bool> _abortIfUnmounted() async {
    if (mounted) return false;
    if (!_proposalConsumed && !_discardScheduled) {
      _discardScheduled = true;
      try {
        await rust_sync.discardProposal(
          proposalId: widget.args.proposalId,
          sendFlowId: widget.args.sendFlowId,
        );
      } catch (e) {
        log(
          'SendStatus: discardProposal cleanup failed after unmount (non-critical): $e',
        );
      }
    }
    return true;
  }

  Future<void> _startBroadcast() async {
    try {
      final dbPath = await getWalletDbPath();
      final endpoint = ref.read(rpcEndpointFailoverProvider).current;
      var saplingParams = await loadSaplingParamsStatus();

      if (widget.args.needsSaplingParams) {
        if (!saplingParams.complete) {
          if (await _abortIfUnmounted()) return;
          final downloadConfirmed = await _showSaplingParamsDialog();
          if (!downloadConfirmed) {
            if (await _abortIfUnmounted()) return;
            setState(() {
              _phase = _SendStatusPhase.failed;
              _error =
                  'Sending was cancelled before proving parameters were downloaded.';
            });
            return;
          }

          await downloadMissingSaplingParams(
            saplingParams,
            log: (message) => log('SendStatus: $message'),
          );
          saplingParams = await loadSaplingParamsStatus();
          if (await _abortIfUnmounted()) return;
        }
      }

      final accountNotifier = ref.read(accountProvider.notifier);
      final isHardware = accountNotifier.isHardwareAccount(
        widget.args.proposalAccountUuid,
      );

      late final String txids;
      late final bool broadcastComplete;
      late final String? pendingStatusMessage;
      String? broadcastMessageForFallback;

      if (isHardware) {
        final keystone = widget.keystone;
        if (keystone == null) {
          throw Exception('Missing Keystone transaction signature.');
        }
        _proposalConsumed = true;
        final result = await rust_sync.extractAndBroadcastPczt(
          dbPath: dbPath,
          lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
          network: endpoint.networkName,
          pcztWithProofsBytes: keystone.pcztWithProofsBytes,
          pcztWithSignaturesBytes: keystone.pcztWithSignaturesBytes,
          spendParamsPath: widget.args.needsSaplingParams
              ? saplingParams.spendPath
              : null,
          outputParamsPath: widget.args.needsSaplingParams
              ? saplingParams.outputPath
              : null,
        );
        txids = result.txid;
        broadcastComplete = result.status == 'broadcasted';
        pendingStatusMessage = broadcastComplete
            ? null
            : _pcztBroadcastStatusMessage(result);
        broadcastMessageForFallback = result.message;
      } else {
        final mnemonicBytes = await accountNotifier.getMnemonicBytesForAccount(
          widget.args.proposalAccountUuid,
        );
        if (mnemonicBytes == null || mnemonicBytes.isEmpty) {
          if (await _abortIfUnmounted()) return;
          setState(() {
            _phase = _SendStatusPhase.failed;
            _error = 'Mnemonic not found for the proposal account.';
          });
          return;
        }

        late final rust_sync.ExecuteProposalResult result;
        try {
          result = await rust_sync.executeProposal(
            dbPath: dbPath,
            lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
            proposalId: widget.args.proposalId,
            sendFlowId: widget.args.sendFlowId,
            mnemonicBytes: mnemonicBytes,
            spendParamsPath: widget.args.needsSaplingParams
                ? saplingParams.spendPath
                : null,
            outputParamsPath: widget.args.needsSaplingParams
                ? saplingParams.outputPath
                : null,
          );
        } finally {
          mnemonicBytes.fillRange(0, mnemonicBytes.length, 0);
        }
        _proposalConsumed = true;
        txids = result.txids;
        broadcastComplete = result.status == 'broadcasted';
        pendingStatusMessage = broadcastComplete
            ? null
            : _broadcastStatusMessage(result);
        broadcastMessageForFallback = result.message;
      }

      if (!broadcastComplete && broadcastMessageForFallback != null) {
        final switched = await ref
            .read(rpcEndpointFailoverProvider.notifier)
            .switchToFallbackFor(
              broadcastMessageForFallback,
              endpoint: endpoint,
              operation: isHardware
                  ? 'keystone send broadcast'
                  : 'send broadcast',
            );
        if (switched) {
          unawaited(ref.read(syncProvider.notifier).restartSync());
        }
      }

      try {
        await ref.read(syncProvider.notifier).refreshAfterSend();
      } catch (e) {
        log('SendStatus: refreshAfterSend failed (non-critical): $e');
      }

      if (Platform.isIOS) {
        try {
          const channel = MethodChannel('com.zcash.wallet/background_sync');
          final available =
              await channel.invokeMethod<bool>('isAvailable') ?? false;
          if (available) {
            await channel.invokeMethod('startTxTracking', {
              'lightwalletdUrl': endpoint.normalizedLightwalletdUrl,
              'network': endpoint.networkName,
              'presetId': endpoint.effectivePresetId,
            });
          }
        } catch (e) {
          log('SendStatus: iOS TX tracking failed (non-critical): $e');
        }
      }

      if (await _abortIfUnmounted()) return;
      setState(() {
        _phase = broadcastComplete
            ? _SendStatusPhase.succeeded
            : _SendStatusPhase.pendingBroadcast;
        _txid = _firstTxid(txids);
        _statusMessage = pendingStatusMessage;
        _completedAt = DateTime.now();
      });
    } catch (e) {
      log('SendStatus: ERROR: $e');
      final message = _friendlyError(e.toString());
      if (!mounted) {
        if (!_proposalConsumed) {
          try {
            await rust_sync.discardProposal(
              proposalId: widget.args.proposalId,
              sendFlowId: widget.args.sendFlowId,
            );
          } catch (_) {}
        }
        return;
      }
      setState(() {
        _phase = _SendStatusPhase.failed;
        _error = message;
        _statusMessage = null;
      });
    }
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

  @override
  Widget build(BuildContext context) {
    final addressLines = _splitAddress();
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
                                    primaryBlock: TransactionReceiptBlockData(
                                      title: 'To',
                                      child: useFailedReceiptLayout
                                          ? TransactionReceiptAddressText(
                                              address: widget.args.address,
                                              highlightEdges:
                                                  widget.args.isShielded,
                                            )
                                          : Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                for (final line in addressLines)
                                                  RichText(
                                                    text: TextSpan(
                                                      children: _addressSpans(
                                                        context,
                                                        line,
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                      onCopy: useFailedReceiptLayout
                                          ? () => unawaited(
                                              _copyRecipientAddress(),
                                            )
                                          : null,
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
