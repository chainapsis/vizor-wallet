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
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_pane_modal_overlay.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/zec_price_change_provider.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../rust/api/keystone.dart' as rust_keystone;
import '../../../rust/api/sync.dart' as rust_sync;
import '../../address_book/models/address_book_contact.dart';
import '../../address_book/providers/address_book_provider.dart';
import '../../keystone/widgets/keystone_signing_modal.dart';
import '../services/sapling_params.dart';
import '../services/send_flow.dart';
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
  bool _discardScheduled = false;
  bool _handoffToKeystone = false;
  bool _keystoneProposalConsumed = false;
  bool _showSaplingParamsPrompt = false;
  bool _messageExpanded = false;
  bool _showVerifyAddress = false;
  Completer<bool>? _saplingParamsPromptCompleter;
  KeystoneSigningModalPhase? _keystonePhase;
  String? _keystoneError;
  List<String> _keystoneUrParts = const [];
  List<int>? _keystonePcztWithProofs;
  SaplingParamsStatus? _keystoneSaplingParams;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
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
    if (!_handoffToKeystone) {
      _scheduleDiscard();
    }
    super.dispose();
  }

  void _scheduleDiscard() {
    if (_keystoneProposalConsumed || _discardScheduled) return;
    _discardScheduled = true;
    unawaited(
      discardSendProposal(
        proposalId: widget.args.proposalId,
        sendFlowId: widget.args.sendFlowId,
        logContext: 'SendReview',
      ),
    );
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
    final isHardware = ref
        .read(accountProvider.notifier)
        .isHardwareAccount(widget.args.proposalAccountUuid);
    if (isHardware) {
      _showKeystoneSigningModal();
      return;
    }

    await context.push('/send/status', extra: widget.args);
  }

  void _handleCancel() {
    _scheduleDiscard();
    if (!mounted) return;
    context.go('/send');
  }

  void _showKeystoneSigningModal() {
    if (_keystonePhase != null) return;
    setState(() {
      _keystonePhase = KeystoneSigningModalPhase.preparing;
      _keystoneError = null;
      _keystoneUrParts = const [];
      _keystonePcztWithProofs = null;
      _keystoneSaplingParams = null;
    });
    unawaited(_prepareKeystonePczt());
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

  Future<void> _prepareKeystonePczt() async {
    try {
      final dbPath = await getWalletDbPath();
      final endpoint = ref.read(rpcEndpointProvider);
      final saplingParams = await loadSaplingParamsStatus();

      if (widget.args.needsSaplingParams && !saplingParams.complete) {
        final confirmed = await _showDownloadPrompt();
        if (!confirmed) {
          _scheduleDiscard();
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

      if (!mounted) return;
      final currentSaplingParams = await loadSaplingParamsStatus();
      _keystoneSaplingParams = currentSaplingParams;

      final pcztBytes = await rust_sync.createPcztFromProposal(
        dbPath: dbPath,
        network: endpoint.walletNetworkName,
        proposalId: widget.args.proposalId,
        sendFlowId: widget.args.sendFlowId,
      );
      _keystoneProposalConsumed = true;

      final redactedPczt = await rust_sync.redactPcztForSigner(
        pcztBytes: pcztBytes,
      );
      final urParts = await rust_keystone.encodePcztUrParts(
        pcztBytes: redactedPczt,
        maxFragmentLen: BigInt.from(140),
      );

      if (!mounted) return;
      setState(() {
        _keystonePhase = KeystoneSigningModalPhase.ready;
        _keystoneUrParts = urParts;
      });

      final pcztWithProofs = await rust_sync.addProofsToPczt(
        pcztBytes: pcztBytes,
        spendParamsPath: widget.args.needsSaplingParams
            ? currentSaplingParams.spendPath
            : null,
        outputParamsPath: widget.args.needsSaplingParams
            ? currentSaplingParams.outputPath
            : null,
      );

      if (!mounted) return;
      setState(() {
        _keystonePcztWithProofs = pcztWithProofs;
      });
    } catch (e, st) {
      log('SendReview._prepareKeystonePczt: ERROR: $e\n$st');
      if (!_keystoneProposalConsumed) {
        _scheduleDiscard();
      }
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
    if (lower.contains('sapling') || lower.contains('download')) {
      return 'Required proving parameters could not be prepared.';
    }
    return 'Keystone signing could not be prepared. Return to Send and try again.';
  }

  Future<void> _cancelKeystoneSigning() async {
    _scheduleDiscard();
    if (!mounted) return;
    context.go('/send');
  }

  Future<void> _getKeystoneSignature() async {
    final pcztWithProofs = _keystonePcztWithProofs;
    final saplingParams = _keystoneSaplingParams;
    if (_keystonePhase != KeystoneSigningModalPhase.ready ||
        pcztWithProofs == null ||
        saplingParams == null) {
      return;
    }

    final signatures = await context.push<List<int>>('/send/keystone/scan');
    if (signatures == null || !mounted) return;

    _handoffToKeystone = true;
    context.go(
      '/send/status',
      extra: KeystoneBroadcastArgs(
        reviewArgs: widget.args,
        pcztWithProofsBytes: pcztWithProofs,
        pcztWithSignaturesBytes: signatures,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isHardware = ref
        .read(accountProvider.notifier)
        .isHardwareAccount(widget.args.proposalAccountUuid);
    final keystonePhase = _keystonePhase;
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

    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        padding: EdgeInsets.zero,
        child: Stack(
          fit: StackFit.expand,
          children: [
            AppPaneScrollScaffold(
              toolbar: AppPaneToolbar(
                onBeforeNavigate: _scheduleDiscard,
                backLinkMinWidth: 60,
              ),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: SendReviewContentView(
                amountText: _formatAmount(widget.args.amountZatoshi),
                fiatText: fiatTextForZatoshi(
                  widget.args.amountZatoshi,
                  zecUsdUnitPrice: zecUsdUnitPrice,
                ),
                recipient: recipient,
                feeText: _formatFee(widget.args.feeZatoshi),
                isShieldedRecipient: widget.args.isShielded,
                recipientAddressType: widget.args.addressType,
                memoText: hasMemo ? memo : null,
                memoExpanded: _messageExpanded,
                confirmLabel: isHardware
                    ? 'Confirm with Keystone'
                    : 'Confirm & send',
                confirmLeadingIconName: isHardware
                    ? AppIcons.qr
                    : AppIcons.plane,
                onConfirm: () => unawaited(_handleSend()),
                onCancel: _handleCancel,
                onShowFullAddress: () =>
                    setState(() => _showVerifyAddress = true),
                onExpandMemo: _toggleMessageExpanded,
              ),
            ),
            if (_showVerifyAddress && keystonePhase == null)
              SendVerifyAddressOverlay(
                accountUuid: widget.args.proposalAccountUuid,
                address: widget.args.address.trim(),
                isShieldedAddress: widget.args.isShielded,
                onClose: () => setState(() => _showVerifyAddress = false),
              ),
            if (keystonePhase != null)
              AppPaneModalOverlay(
                onDismiss: () => unawaited(_cancelKeystoneSigning()),
                child: KeystoneSigningModal(
                  phase: keystonePhase,
                  urParts: _keystoneUrParts,
                  error: _keystoneError,
                  title: 'Confirm with Keystone',
                  subtitle: 'Scan with your Keystone',
                  instruction: _keystonePcztWithProofs == null
                      ? 'Scan now. Signature import unlocks after proofs are ready.'
                      : 'After you scanned, click Get signature.',
                  primaryLabel: _keystonePcztWithProofs == null
                      ? 'Preparing'
                      : 'Get signature',
                  onPrimary:
                      keystonePhase == KeystoneSigningModalPhase.ready &&
                          _keystonePcztWithProofs != null
                      ? () => unawaited(_getKeystoneSignature())
                      : null,
                  secondaryLabel: 'Cancel',
                  onSecondary: () => unawaited(_cancelKeystoneSigning()),
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
    );
  }
}
