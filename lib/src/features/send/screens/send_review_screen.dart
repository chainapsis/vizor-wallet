import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../main.dart' show log;
import '../../../core/formatting/zec_amount.dart';
import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_pane_scroll_scaffold.dart';
import '../../../core/layout/app_layout.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/storage/wallet_paths.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_back_link.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_pane_modal_overlay.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/zec_price_change_provider.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../core/navigation/payment_uri_busy_surface_hold.dart';
import '../../../core/navigation/payment_uri_busy_surface_provider.dart';
import '../../../core/navigation/app_back_resolver.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../providers/sync_provider.dart';
import '../../../rust/api/keystone.dart' as rust_keystone;
import '../../../rust/api/sync.dart' as rust_sync;
import '../../address_book/models/address_book_contact.dart';
import '../../address_book/providers/address_book_provider.dart';
import '../../keystone/widgets/keystone_signing_modal.dart';
import '../../keystone/services/keystone_batch_signing.dart';
import '../../donation/widgets/donation_views.dart';
import '../services/sapling_params.dart';
import '../services/send_flow.dart';
import 'keystone_send_scan_screen.dart';
import '../widgets/sapling_params_prompt.dart';
import '../widgets/send_recipient_resolver.dart';
import '../widgets/send_review_content_view.dart';
import '../widgets/send_verify_address_overlay.dart';

export '../services/send_flow.dart' show KeystoneBroadcastArgs, SendReviewArgs;

class SendReviewScreen extends ConsumerStatefulWidget {
  const SendReviewScreen({super.key, required this.args});

  final SendReviewArgs args;

  @override
  ConsumerState<SendReviewScreen> createState() => _SendReviewScreenState();
}

class _SendReviewScreenState extends ConsumerState<SendReviewScreen> {
  late final PaymentUriBusySurfaceNotifier _paymentUriBusySurface;
  bool _holdsPaymentUriBusySurface = false;
  late final SyncNotifier _syncNotifier;
  Future<bool>? _discardFuture;
  bool _cancelling = false;
  bool _proposalAbandoned = false;
  late SendReviewArgs _reviewArgs;
  int _signingGeneration = 0;
  Future<Object?>? _proposalConsumption;
  bool _reviewRecoveryFailed = false;
  bool _handoffToKeystone = false;
  bool _showSaplingParamsPrompt = false;
  bool _messageExpanded = false;
  bool _showVerifyAddress = false;
  Completer<bool>? _saplingParamsPromptCompleter;
  KeystoneSigningModalPhase? _keystonePhase;
  String? _keystoneError;
  List<String> _keystoneUrParts = const [];
  List<List<String>> _keystoneUrPartsByRound = const [];
  List<KeystoneBatchSigningRequest?> _keystoneBatchRequestsByRound = const [];
  List<List<int>> _keystonePcztsWithProofs = const [];
  final List<List<int>> _keystoneSignatures = [];
  int _keystoneRound = 0;
  SaplingParamsStatus? _keystoneSaplingParams;

  @override
  void initState() {
    super.initState();
    _reviewArgs = widget.args;
    _paymentUriBusySurface = ref.read(paymentUriBusySurfaceProvider.notifier);
    _syncNotifier = ref.read(syncProvider.notifier);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_holdsPaymentUriBusySurface) {
        _paymentUriBusySurface.acquire();
        _holdsPaymentUriBusySurface = true;
      }
      ref.read(appLayoutProvider.notifier).setMode(AppLayoutMode.large);
    });
  }

  @override
  void dispose() {
    final promptCompleter = _saplingParamsPromptCompleter;
    _saplingParamsPromptCompleter = null;
    if (promptCompleter != null && !promptCompleter.isCompleted) {
      promptCompleter.complete(false);
    }
    final discard = _handoffToKeystone ? null : _scheduleDiscard();
    _releasePaymentUriBusySurface(after: discard);
    super.dispose();
  }

  Future<bool> _scheduleDiscard() {
    _proposalAbandoned = true;
    final args = _reviewArgs;
    return _discardFuture ??=
        () async {
          try {
            await _proposalConsumption;
          } catch (_) {
            // A failed creator still needs idempotent proposal cleanup.
          }
          return discardSendProposal(
            proposalId: args.proposalId,
            sendFlowId: args.sendFlowId,
            logContext: 'SendReview',
            syncNotifier: _syncNotifier,
            accountUuid: args.proposalAccountUuid,
          );
        }().then((released) {
          if (!released) _discardFuture = null;
          return released;
        });
  }

  void _releasePaymentUriBusySurface({Future<void>? after}) {
    if (!_holdsPaymentUriBusySurface) return;
    _holdsPaymentUriBusySurface = false;
    if (after == null) {
      _paymentUriBusySurface.releaseAfterNavigation();
      return;
    }
    // The route is already gone, but Rust may still hold the selected inputs.
    // Do not re-drain the parked request until that release has completed.
    unawaited(after.whenComplete(_paymentUriBusySurface.release));
  }

  String _formatAmount(BigInt zatoshi) {
    return ZecAmount.fromZatoshi(zatoshi).activityDetail.toString();
  }

  String _formatFee(BigInt zatoshi) {
    return ZecAmount.fromZatoshi(zatoshi).fee.toString();
  }

  void _toggleMessageExpanded() {
    setState(() {
      _messageExpanded = !_messageExpanded;
    });
  }

  Future<void> _handleSend() async {
    if (_reviewRecoveryFailed) {
      await _cancelKeystoneSigning();
      return;
    }
    if (_cancelling || _proposalAbandoned) return;
    final isHardware = ref
        .read(accountProvider.notifier)
        .isHardwareAccount(_reviewArgs.proposalAccountUuid);
    if (isHardware) {
      _showKeystoneSigningModal();
      return;
    }

    ref.read(sendStatusRoutePayloadProvider.notifier).retain(_reviewArgs);
    _releasePaymentUriBusySurface();
    await context.push(
      sendStatusRouteLocation(_reviewArgs.sendFlowId),
      extra: _reviewArgs,
    );
  }

  Future<void> _leaveReview(VoidCallback navigate) async {
    if (_cancelling) return;
    setState(() => _cancelling = true);
    final released = await _scheduleDiscard();
    if (!mounted) return;
    if (released) {
      navigate();
      return;
    }
    const error = 'Could not finish cancelling. Please try again.';
    setState(() {
      _cancelling = false;
      if (_keystonePhase != null) {
        _keystonePhase = KeystoneSigningModalPhase.failed;
        _keystoneError = error;
      }
    });
    showAppToast(
      context,
      error,
      iconName: AppIcons.warningCircle,
      tone: AppToastTone.destructive,
    );
  }

  void _handleCancel() => unawaited(
    _leaveReview(
      () => context.go(
        _reviewArgs.flowKind == SendFlowKind.donation ? '/donation' : '/send',
      ),
    ),
  );

  Future<void> _handleDonationBack() => _keystonePhase != null
      ? _cancelKeystoneSigning()
      : _leaveReview(() {
          if (context.canPop()) {
            context.pop();
          } else {
            context.go('/donation');
          }
        });

  void _showKeystoneSigningModal() {
    if (_keystonePhase != null || _proposalAbandoned) return;
    setState(() {
      _keystonePhase = KeystoneSigningModalPhase.preparing;
      _keystoneError = null;
      _keystoneUrParts = const [];
      _keystoneUrPartsByRound = const [];
      _keystoneBatchRequestsByRound = const [];
      _keystonePcztsWithProofs = const [];
      _keystoneSignatures.clear();
      _keystoneRound = 0;
      _keystoneSaplingParams = null;
    });
    unawaited(_prepareKeystonePczt(++_signingGeneration));
  }

  Future<bool> _showDownloadPrompt() {
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

  Future<void> _prepareKeystonePczt(int generation) async {
    bool isCurrent() =>
        mounted && !_proposalAbandoned && generation == _signingGeneration;
    final args = _reviewArgs;
    try {
      final dbPath = await getWalletDbPath();
      if (!isCurrent()) return;
      final endpoint = ref.read(rpcEndpointProvider);
      final saplingParams = await loadSaplingParamsStatus();
      if (!isCurrent()) return;

      if (args.needsSaplingParams && !saplingParams.complete) {
        final confirmed = await _showDownloadPrompt();
        if (!confirmed) {
          unawaited(_scheduleDiscard());
          if (!mounted) return;
          setState(() {
            _keystonePhase = KeystoneSigningModalPhase.failed;
            _keystoneError =
                'Signing was cancelled before proving parameters were downloaded.';
          });
          return;
        }

        await downloadMissingSaplingParams(
          saplingParams,
          log: (message) => log('SendReview Keystone: $message'),
        );
      }

      if (!isCurrent()) return;
      final currentSaplingParams = await loadSaplingParamsStatus();
      if (!isCurrent()) return;
      _keystoneSaplingParams = currentSaplingParams;

      final texFuture = args.addressType == 'tex'
          ? rust_sync.createTexPcztsFromProposal(
              dbPath: dbPath,
              lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
              network: endpoint.networkName,
              proposalId: args.proposalId,
              sendFlowId: args.sendFlowId,
            )
          : null;
      _proposalConsumption = texFuture;
      final texPczts = await texFuture;
      if (!isCurrent()) return;
      final pcztFuture = texPczts == null
          ? rust_sync.createPcztFromProposal(
              dbPath: dbPath,
              lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
              network: endpoint.networkName,
              proposalId: args.proposalId,
              sendFlowId: args.sendFlowId,
            )
          : null;
      if (pcztFuture != null) _proposalConsumption = pcztFuture;
      final pczts = texPczts?.pczts ?? [await pcztFuture!];
      if (!isCurrent()) return;
      final urPartsByRound = <List<String>>[];
      final batchRequestsByRound = <KeystoneBatchSigningRequest?>[];
      final signerPczts = texPczts?.signerPczts;
      for (var index = 0; index < pczts.length; index++) {
        if (args.addressType == 'tex') {
          final redacted = signerPczts![index];
          urPartsByRound.add(
            await rust_keystone.encodePcztUrParts(
              pcztBytes: redacted,
              maxFragmentLen: BigInt.from(140),
            ),
          );
          batchRequestsByRound.add(null);
        } else {
          final request = await buildKeystoneBatchSigningRequest(
            requestId: 'vizor-send-${args.sendFlowId}-transaction-${index + 1}',
            pczts: [
              KeystoneBatchPcztSource(
                id: 'send-transaction-${index + 1}',
                pcztBytes: pczts[index],
              ),
            ],
          );
          urPartsByRound.add(request.urParts);
          batchRequestsByRound.add(request);
        }
      }

      if (!isCurrent()) return;
      setState(() {
        _keystonePhase = KeystoneSigningModalPhase.ready;
        _keystoneUrPartsByRound = urPartsByRound;
        _keystoneBatchRequestsByRound = batchRequestsByRound;
        _keystoneUrParts = urPartsByRound.first;
      });

      final proofs = <List<int>>[];
      for (final pczt in pczts) {
        proofs.add(
          await rust_sync.addProofsToPczt(
            pcztBytes: pczt,
            spendParamsPath: args.needsSaplingParams
                ? currentSaplingParams.spendPath
                : null,
            outputParamsPath: args.needsSaplingParams
                ? currentSaplingParams.outputPath
                : null,
          ),
        );
      }

      if (!isCurrent()) return;
      setState(() {
        _keystonePcztsWithProofs = proofs;
      });
    } catch (e, st) {
      log('SendReview._prepareKeystonePczt: ERROR: $e\n$st');
      if (!isCurrent()) return;
      unawaited(_scheduleDiscard());
      if (!mounted) return;
      setState(() {
        _keystonePhase = KeystoneSigningModalPhase.failed;
        _keystoneError = _friendlyKeystoneError(e.toString());
      });
    }
  }

  String _friendlyKeystoneError(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('proposal not found') ||
        lower.contains('send flow mismatch')) {
      return 'Transaction expired before it could be signed.';
    }
    final batchError = keystoneBatchSigningFriendlyError(raw);
    if (batchError != null) return batchError;
    if (lower.contains('sapling') || lower.contains('download')) {
      return 'Required proving parameters could not be prepared.';
    }
    return 'Keystone signing could not be prepared. Return to Send and try again.';
  }

  Future<void> _cancelKeystoneSigning() async {
    if (_cancelling) return;
    setState(() {
      _cancelling = true;
      _proposalAbandoned = true;
      _reviewRecoveryFailed = false;
      _signingGeneration++;
    });
    final released = await _scheduleDiscard();
    if (!mounted) return;
    if (!released) {
      setState(() {
        _cancelling = false;
        _keystonePhase = KeystoneSigningModalPhase.failed;
        _keystoneError = 'Could not finish cancelling. Please try again.';
      });
      return;
    }
    setState(() => _keystonePhase = null);
    final previous = _reviewArgs;
    try {
      final refreshed = await proposeSendTransfer(
        ref: ref,
        accountUuid: previous.proposalAccountUuid,
        sendFlowId: previous.sendFlowId,
        address: previous.address,
        addressType: previous.addressType,
        amountZatoshi: previous.amountZatoshi,
        memo: previous.memo,
        isPaymentRequest: previous.isPaymentRequest,
        requestedBy: previous.requestedBy,
        requestedAmountZatoshi: previous.requestedAmountZatoshi,
        flowKind: previous.flowKind,
      );
      if (!mounted) {
        await discardSendProposal(
          proposalId: refreshed.proposalId,
          sendFlowId: refreshed.sendFlowId,
          accountUuid: refreshed.proposalAccountUuid,
          syncNotifier: _syncNotifier,
          logContext: 'SendReview(cancelled recovery)',
        );
        return;
      }
      setState(() {
        _reviewArgs = refreshed;
        _discardFuture = null;
        _proposalConsumption = null;
        _proposalAbandoned = false;
        _cancelling = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _cancelling = false;
        _reviewRecoveryFailed = true;
      });
      showAppToast(
        context,
        friendlyProposeSendError(error.toString()),
        iconName: AppIcons.warningCircle,
        tone: AppToastTone.destructive,
      );
    }
  }

  Future<void> _getKeystoneSignature() async {
    final generation = _signingGeneration;
    final saplingParams = _keystoneSaplingParams;
    if (_proposalAbandoned ||
        _keystonePhase != KeystoneSigningModalPhase.ready ||
        _keystonePcztsWithProofs.isEmpty ||
        saplingParams == null) {
      return;
    }

    final response = await context.push<List<int>>(
      '/send/keystone/scan',
      extra: _keystoneBatchRequestsByRound[_keystoneRound] == null
          ? KeystoneSendScanArgs(
              suppressSidebarSelection:
                  _reviewArgs.flowKind == SendFlowKind.donation,
            )
          : KeystoneSendScanArgs.batch(
              suppressSidebarSelection:
                  _reviewArgs.flowKind == SendFlowKind.donation,
            ),
    );
    if (response == null ||
        !mounted ||
        _proposalAbandoned ||
        generation != _signingGeneration) {
      return;
    }
    try {
      final batchRequest = _keystoneBatchRequestsByRound[_keystoneRound];
      if (batchRequest == null) {
        _keystoneSignatures.add(response);
      } else {
        _keystoneSignatures.addAll(await batchRequest.decodeResponse(response));
      }
      if (!mounted || _proposalAbandoned || generation != _signingGeneration) {
        return;
      }
      setState(() => _keystoneError = null);
    } catch (e, st) {
      log('SendReview._getKeystoneSignature: ERROR: $e\n$st');
      if (!mounted || generation != _signingGeneration) return;
      setState(() {
        _keystoneError =
            'This QR code does not match the current Keystone signing request.';
      });
      return;
    }
    if (_keystoneRound + 1 < _keystonePcztsWithProofs.length) {
      setState(() {
        _keystoneRound++;
        _keystoneUrParts = _keystoneUrPartsByRound[_keystoneRound];
      });
      return;
    }
    if (!mounted) return;

    _handoffToKeystone = true;
    _releasePaymentUriBusySurface();
    final statusArgs = KeystoneBroadcastArgs(
      reviewArgs: _reviewArgs,
      pcztWithProofs: _keystonePcztsWithProofs,
      pcztWithSignatures: List<List<int>>.of(_keystoneSignatures),
    );
    ref.read(sendStatusRoutePayloadProvider.notifier).retain(statusArgs);
    context.go(
      sendStatusRouteLocation(_reviewArgs.sendFlowId),
      extra: statusArgs,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isHardware = ref
        .read(accountProvider.notifier)
        .isHardwareAccount(_reviewArgs.proposalAccountUuid);
    final keystonePhase = _keystonePhase;
    final addressBookContacts =
        ref.watch(addressBookProvider).value?.contacts ??
        const <AddressBookContact>[];
    final ownAccounts =
        ref.watch(ownAccountAddressesProvider).value ??
        const <String, AccountInfo>{};
    final recipient = sendReviewRecipientFor(
      contacts: addressBookContacts,
      address: _reviewArgs.address,
      ownAccounts: ownAccounts,
    );
    final zecUsdUnitPrice = ref.watch(zecHomeUsdUnitPriceProvider);
    final memo = _reviewArgs.memo;
    // Present means non-empty, not non-blank: an edited request whose memo is
    // only whitespace still sends that memo, so the row has to say so rather
    // than omit a memo the transaction carries.
    final hasMemo = memo != null && memo.isNotEmpty;
    final requestedAmountZatoshi = _reviewArgs.differingRequestedAmountZatoshi;
    final backTarget = AppBackResolver.resolve(context);

    return PopScope<Object?>(
      canPop: keystonePhase == null && !_cancelling,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && keystonePhase != null) {
          unawaited(_cancelKeystoneSigning());
        }
      },
      child: AppDesktopShell(
        sidebar: AppMainSidebar(
          suppressActiveSelection:
              _reviewArgs.flowKind == SendFlowKind.donation,
        ),
        pane: AppDesktopPane(
          padding: EdgeInsets.zero,
          child: Stack(
            fit: StackFit.expand,
            children: [
              AppPaneScrollScaffold(
                toolbar: AppPaneToolbar(
                  leading: _reviewArgs.flowKind == SendFlowKind.donation
                      ? AppBackLink(
                          label: 'Support Vizor',
                          minWidth: 60,
                          onTap: _handleDonationBack,
                        )
                      : AppBackLink(
                          label: backTarget.label,
                          minWidth: 60,
                          onTap: () => keystonePhase != null
                              ? _cancelKeystoneSigning()
                              : _leaveReview(
                                  () => backTarget.navigate(context),
                                ),
                        ),
                  backLinkMinWidth: 60,
                ),
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: _reviewArgs.flowKind == SendFlowKind.donation
                    ? DonationReviewContentView(
                        amountText: _formatAmount(_reviewArgs.amountZatoshi),
                        fiatText: fiatTextForZatoshi(
                          _reviewArgs.amountZatoshi,
                          zecUsdUnitPrice: zecUsdUnitPrice,
                        ),
                        feeText: _formatFee(_reviewArgs.feeZatoshi),
                        confirmLabel: _reviewRecoveryFailed
                            ? 'Retry'
                            : _cancelling
                            ? 'Cancelling…'
                            : isHardware
                            ? 'Confirm with Keystone'
                            : 'Confirm donation',
                        confirmIcon: isHardware
                            ? AppIcons.qr
                            : AppIcons.donation,
                        onConfirm:
                            _cancelling ||
                                (_proposalAbandoned && !_reviewRecoveryFailed)
                            ? null
                            : () => unawaited(_handleSend()),
                      )
                    : SendReviewContentView(
                        isPaymentRequest: _reviewArgs.isPaymentRequest,
                        requestedAmountText: requestedAmountZatoshi == null
                            ? null
                            : _formatAmount(requestedAmountZatoshi),
                        amountText: _formatAmount(_reviewArgs.amountZatoshi),
                        fiatText: fiatTextForZatoshi(
                          _reviewArgs.amountZatoshi,
                          zecUsdUnitPrice: zecUsdUnitPrice,
                        ),
                        recipient: recipient,
                        feeText: _formatFee(_reviewArgs.feeZatoshi),
                        isShieldedRecipient: _reviewArgs.isShielded,
                        recipientAddressType: _reviewArgs.addressType,
                        memoText: hasMemo ? memo : null,
                        memoExpanded: _messageExpanded,
                        confirmLabel: _reviewRecoveryFailed
                            ? 'Retry'
                            : _cancelling
                            ? 'Cancelling…'
                            : isHardware
                            ? 'Confirm with Keystone'
                            : 'Confirm & send',
                        confirmLeadingIconName: isHardware
                            ? AppIcons.qr
                            : AppIcons.plane,
                        onConfirm:
                            _cancelling ||
                                (_proposalAbandoned && !_reviewRecoveryFailed)
                            ? null
                            : () => unawaited(_handleSend()),
                        onCancel: _cancelling ? null : _handleCancel,
                        onShowFullAddress: () =>
                            setState(() => _showVerifyAddress = true),
                        onExpandMemo: _toggleMessageExpanded,
                      ),
              ),
              if (_showVerifyAddress && keystonePhase == null)
                SendVerifyAddressOverlay(
                  accountUuid: _reviewArgs.proposalAccountUuid,
                  address: _reviewArgs.address.trim(),
                  isShieldedAddress: _reviewArgs.isShielded,
                  onClose: () => setState(() => _showVerifyAddress = false),
                ),
              // The review's outer hold protects its proposal inputs. This
              // nested hold protects the live QR as well, so the latch cannot
              // briefly open while signing subtrees change.
              if (keystonePhase != null)
                PaymentUriBusySurfaceHold(
                  child: AppPaneModalOverlay(
                    onDismiss: () => unawaited(_cancelKeystoneSigning()),
                    child: KeystoneSigningModal(
                      phase: keystonePhase,
                      urParts: _keystoneUrParts,
                      error: _keystoneError,
                      title: 'Confirm with Keystone',
                      subtitle: _keystoneUrPartsByRound.length == 2
                          ? 'Transaction ${_keystoneRound + 1} of 2'
                          : 'Scan with your Keystone',
                      instruction:
                          _keystoneError ??
                          (_keystonePcztsWithProofs.isEmpty
                              ? 'Scan now. Signature import unlocks after proofs are ready.'
                              : 'After you scanned, click Get signature.'),
                      primaryLabel: _keystonePcztsWithProofs.isEmpty
                          ? 'Preparing'
                          : 'Get signature',
                      onPrimary:
                          !_proposalAbandoned &&
                              keystonePhase ==
                                  KeystoneSigningModalPhase.ready &&
                              _keystonePcztsWithProofs.isNotEmpty
                          ? () => unawaited(_getKeystoneSignature())
                          : null,
                      secondaryLabel: _cancelling ? 'Cancelling…' : 'Cancel',
                      onSecondary: _cancelling
                          ? null
                          : () => unawaited(_cancelKeystoneSigning()),
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
