import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
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
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../../rust/api/sync.dart' as rust_sync;
import '../../../rust/api/wallet.dart' as rust_wallet;
import '../widgets/sapling_params_prompt.dart';
import '../widgets/transaction_receipt_view.dart';
import 'send_review_screen.dart';

const _saplingSpendHash = 'a15ab54c2888880e53c823a3063820c728444126';
const _saplingOutputHash = '0ebc5a1ef3653948e1c46cf7a16071eac4b7e352';
const _saplingParamBaseUrl = 'https://download.z.cash/downloads/';

enum _SendStatusPhase { sending, pendingBroadcast, succeeded, failed }

class SendStatusScreen extends ConsumerStatefulWidget {
  const SendStatusScreen({super.key, required this.args});

  final SendReviewArgs args;

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
      return 'Network error. Please check your connection and try again.';
    }
    if (lower.contains('broadcast failed after') &&
        lower.contains('txs sent')) {
      return 'Some transactions were broadcast but not all. Please check history before retrying.';
    }
    if (lower.contains('broadcast rejected')) {
      return 'Transaction was rejected by the network. Please try again later.';
    }
    if (lower.contains('proposal not found') ||
        lower.contains('send flow mismatch')) {
      return 'Transaction expired before it could be sent.';
    }
    return 'Transaction could not be sent. Please return to your wallet and verify the latest status.';
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
      return 'Transaction was created locally, but the network did not accept the first broadcast. It may retry automatically until it expires. Do not send again unless this transaction expires.';
    }
    return 'Transaction was created locally but could not be broadcast. It will retry automatically when the network is available. Do not send again unless this transaction expires.';
  }

  String _formatReceiptAmount(BigInt zatoshi) {
    return ZecAmount.fromZatoshi(zatoshi).receipt.toString();
  }

  String _formatFee(BigInt zatoshi) {
    return ZecAmount.fromZatoshi(zatoshi).pretty().amountText;
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

  Future<void> _downloadAndVerify(
    String url,
    String destPath,
    String expectedSha1,
  ) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode != 200) {
        throw Exception(
          'Download failed: HTTP ${response.statusCode} for $url',
        );
      }
      final tempPath = '${destPath}_tmp';
      final file = File(tempPath);
      final sink = file.openWrite();
      await response.pipe(sink);

      final bytes = await File(tempPath).readAsBytes();
      final digest = sha1.convert(bytes);
      if (digest.toString() != expectedSha1) {
        await File(tempPath).delete();
        throw Exception('SHA-1 mismatch: expected $expectedSha1, got $digest');
      }

      await File(tempPath).rename(destPath);
      log('SendStatus: downloaded and verified $destPath');
    } finally {
      client.close();
    }
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
    final endpoint = ref.read(rpcEndpointProvider);
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
      final supportDir = await getWalletSupportDirectory();
      final dbPath = await getWalletDbPath();
      final endpoint = ref.read(rpcEndpointProvider);
      final paramsDir =
          '${supportDir.path}${Platform.pathSeparator}sapling_params';
      final spendPath =
          '$paramsDir${Platform.pathSeparator}sapling-spend.params';
      final outputPath =
          '$paramsDir${Platform.pathSeparator}sapling-output.params';

      if (widget.args.needsSaplingParams) {
        final spendExists = File(spendPath).existsSync();
        final outputExists = File(outputPath).existsSync();

        if (!spendExists || !outputExists) {
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

          await Directory(paramsDir).create(recursive: true);
          if (!spendExists) {
            await _downloadAndVerify(
              '${_saplingParamBaseUrl}sapling-spend.params',
              spendPath,
              _saplingSpendHash,
            );
          }
          if (!outputExists) {
            await _downloadAndVerify(
              '${_saplingParamBaseUrl}sapling-output.params',
              outputPath,
              _saplingOutputHash,
            );
          }
          if (await _abortIfUnmounted()) return;
        }
      }

      final accountNotifier = ref.read(accountProvider.notifier);
      final mnemonic = await accountNotifier.getMnemonicForAccount(
        widget.args.proposalAccountUuid,
      );
      if (mnemonic == null) {
        if (await _abortIfUnmounted()) return;
        setState(() {
          _phase = _SendStatusPhase.failed;
          _error = 'Mnemonic not found for the proposal account.';
        });
        return;
      }

      final seedBytes = await rust_wallet.deriveSeed(mnemonic: mnemonic);
      final result = await rust_sync.executeProposal(
        dbPath: dbPath,
        lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
        proposalId: widget.args.proposalId,
        sendFlowId: widget.args.sendFlowId,
        seed: seedBytes,
        spendParamsPath: widget.args.needsSaplingParams ? spendPath : null,
        outputParamsPath: widget.args.needsSaplingParams ? outputPath : null,
      );
      _proposalConsumed = true;
      final broadcastComplete = result.status == 'broadcasted';

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
        _txid = _firstTxid(result.txids);
        _statusMessage = broadcastComplete
            ? null
            : _broadcastStatusMessage(result);
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

    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          unawaited(_goHome());
        }
      },
      child: AppDesktopShell(
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
                              key: ValueKey('send_status_${receiptPhase.name}'),
                              phase: receiptPhase,
                              amountText: _formatReceiptAmount(
                                widget.args.amountZatoshi,
                              ),
                              primaryBlock: TransactionReceiptBlockData(
                                title: 'To',
                                child: useFailedReceiptLayout
                                    ? TransactionReceiptAddressText(
                                        address: widget.args.address,
                                        highlightEdges: widget.args.isShielded,
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
                                    ? () => unawaited(_copyRecipientAddress())
                                    : null,
                              ),
                              feeText:
                                  '${_formatFee(widget.args.feeZatoshi)} ZEC',
                              extraBlocks: [
                                if (statusMessage != null)
                                  TransactionReceiptBlockData(
                                    title: 'Status',
                                    child: Text(
                                      statusMessage,
                                      style: AppTypography.bodyMedium.copyWith(
                                        color: context.colors.text.accent,
                                      ),
                                    ),
                                  ),
                              ],
                              dateText: _formatDate(_completedAt ?? _startedAt),
                              error: _error,
                              failureFallbackText: 'Send failed',
                              useFailedReceiptLayout: useFailedReceiptLayout,
                              onTransactionHashPressed:
                                  (_phase == _SendStatusPhase.succeeded ||
                                          _phase ==
                                              _SendStatusPhase
                                                  .pendingBroadcast) &&
                                      _txid != null
                                  ? _openTransactionExplorer
                                  : null,
                              onBackToWallet: _phase == _SendStatusPhase.failed
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
