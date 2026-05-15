import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../main.dart' show log;
import '../../../core/formatting/zec_amount.dart';
import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_layout.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/storage/wallet_paths.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_back_link.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_decorative_divider.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_pane_modal_overlay.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../rust/api/keystone.dart' as rust_keystone;
import '../../../rust/api/sync.dart' as rust_sync;
import '../../keystone/widgets/keystone_signing_modal.dart';
import '../services/sapling_params.dart';
import '../widgets/sapling_params_prompt.dart';

class SendReviewArgs {
  const SendReviewArgs({
    required this.proposalId,
    required this.sendFlowId,
    required this.proposalAccountUuid,
    required this.address,
    required this.addressType,
    required this.amountZatoshi,
    required this.feeZatoshi,
    required this.needsSaplingParams,
    this.memo,
  });

  final BigInt proposalId;
  final String sendFlowId;
  final String proposalAccountUuid;
  final String address;
  final String addressType;
  final BigInt amountZatoshi;
  final BigInt feeZatoshi;
  final bool needsSaplingParams;
  final String? memo;

  bool get isShielded => addressType == 'unified' || addressType == 'sapling';
}

class KeystoneBroadcastArgs {
  const KeystoneBroadcastArgs({
    required this.reviewArgs,
    required this.pcztWithProofsBytes,
    required this.pcztWithSignaturesBytes,
  });

  final SendReviewArgs reviewArgs;
  final List<int> pcztWithProofsBytes;
  final List<int> pcztWithSignaturesBytes;
}

class SendReviewScreen extends ConsumerStatefulWidget {
  const SendReviewScreen({super.key, required this.args});

  final SendReviewArgs args;

  @override
  ConsumerState<SendReviewScreen> createState() => _SendReviewScreenState();
}

class _SendReviewScreenState extends ConsumerState<SendReviewScreen> {
  static const _addressPrefixHighlightLength = 7;
  static const _addressLeadingPlainLength = 13;
  static const _addressTrailingPlainLength = 15;
  static const _addressSuffixHighlightLength = 8;

  bool _discardScheduled = false;
  bool _handoffToKeystone = false;
  bool _keystoneProposalConsumed = false;
  bool _showSaplingParamsPrompt = false;
  bool _messageExpanded = false;
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
      rust_sync
          .discardProposal(
            proposalId: widget.args.proposalId,
            sendFlowId: widget.args.sendFlowId,
          )
          .then((_) {
            log('SendReview: released proposal ${widget.args.proposalId}');
          })
          .catchError((Object e) {
            log(
              'SendReview: discardProposal cleanup failed (non-critical): $e',
            );
          }),
    );
  }

  String _formatReceiptAmount(BigInt zatoshi) {
    return ZecAmount.fromZatoshi(zatoshi).receipt.toString();
  }

  String _formatFee(BigInt zatoshi) {
    return ZecAmount.fromZatoshi(zatoshi).fee.toString();
  }

  List<TextSpan> _addressSpans(BuildContext context) {
    final colors = context.colors;
    final address = widget.args.address.trim();
    final accentStyle = AppTypography.labelLarge.copyWith(
      color: colors.text.accent,
    );
    final highlightStyle = AppTypography.labelLarge.copyWith(
      color: widget.args.isShielded
          ? colors.text.brandCrimson
          : colors.text.accent,
    );

    // Keep this as the sum of the four visible chunks used below so the
    // middle-ellipsis slices cannot overlap.
    final minShortenedLength =
        _addressPrefixHighlightLength +
        _addressLeadingPlainLength +
        _addressTrailingPlainLength +
        _addressSuffixHighlightLength;
    if (address.length <= minShortenedLength) {
      if (address.length < _addressPrefixHighlightLength) {
        return [TextSpan(text: address, style: accentStyle)];
      }
      final suffixLength =
          address.length >
              _addressPrefixHighlightLength + _addressSuffixHighlightLength
          ? _addressSuffixHighlightLength
          : 0;
      return [
        TextSpan(
          text: address.substring(0, _addressPrefixHighlightLength),
          style: highlightStyle,
        ),
        TextSpan(
          text: address.substring(
            _addressPrefixHighlightLength,
            address.length - suffixLength,
          ),
          style: accentStyle,
        ),
        if (suffixLength > 0)
          TextSpan(
            text: address.substring(address.length - suffixLength),
            style: highlightStyle,
          ),
      ];
    }

    final prefixEnd = _addressPrefixHighlightLength;
    final leadingEnd = prefixEnd + _addressLeadingPlainLength;
    final trailingStart =
        address.length -
        _addressSuffixHighlightLength -
        _addressTrailingPlainLength;
    final suffixStart = address.length - _addressSuffixHighlightLength;
    assert(leadingEnd <= trailingStart);
    return [
      TextSpan(text: address.substring(0, prefixEnd), style: highlightStyle),
      TextSpan(
        text: address.substring(prefixEnd, leadingEnd),
        style: accentStyle,
      ),
      TextSpan(text: '...\n', style: accentStyle),
      TextSpan(
        text: address.substring(trailingStart, suffixStart),
        style: accentStyle,
      ),
      TextSpan(text: address.substring(suffixStart), style: highlightStyle),
    ];
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
        network: endpoint.networkName,
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

  Future<void> _copyRecipientAddress() async {
    await Clipboard.setData(ClipboardData(text: widget.args.address.trim()));
    if (!mounted) return;
    showAppToast(context, 'Address Copied');
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isHardware = ref
        .read(accountProvider.notifier)
        .isHardwareAccount(widget.args.proposalAccountUuid);
    final keystonePhase = _keystonePhase;

    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        padding: EdgeInsets.zero,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: AppRouteBackLink(onBeforeNavigate: _scheduleDiscard),
                  ),
                  Expanded(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _SendReviewReceiptCard(
                            args: widget.args,
                            amountText: _formatReceiptAmount(
                              widget.args.amountZatoshi,
                            ),
                            feeText: _formatFee(widget.args.feeZatoshi),
                            addressSpans: _addressSpans(context),
                            messageExpanded: _messageExpanded,
                            onToggleMessageExpanded: _toggleMessageExpanded,
                            onCopyAddress: () =>
                                unawaited(_copyRecipientAddress()),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          SizedBox(
                            width: 256,
                            child: AppButton(
                              key: const ValueKey('send_confirm_button'),
                              onPressed: _handleSend,
                              variant: AppButtonVariant.primary,
                              minWidth: 256,
                              leading: AppIcon(
                                isHardware ? AppIcons.qr : AppIcons.plane,
                                color: colors.button.primary.label,
                              ),
                              child: Text(
                                isHardware ? 'Confirm with Keystone' : 'Send',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (keystonePhase != null)
              AppPaneModalOverlay(
                onDismiss: () => unawaited(_cancelKeystoneSigning()),
                child: KeystoneSigningModal(
                  phase: keystonePhase,
                  urParts: _keystoneUrParts,
                  error: _keystoneError,
                  title: 'Sign tx on your Keystone',
                  subtitle: 'Scan the QR code to sign',
                  instruction: _keystonePcztWithProofs == null
                      ? 'Scan now. Signature import unlocks after proofs are ready.'
                      : 'After you scanned, click Get Signature.',
                  primaryLabel: _keystonePcztWithProofs == null
                      ? 'Preparing'
                      : 'Get Signature',
                  onPrimary:
                      keystonePhase == KeystoneSigningModalPhase.ready &&
                          _keystonePcztWithProofs != null
                      ? () => unawaited(_getKeystoneSignature())
                      : null,
                  secondaryLabel: 'Reject',
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

class _SendReviewReceiptCard extends StatelessWidget {
  const _SendReviewReceiptCard({
    required this.args,
    required this.amountText,
    required this.feeText,
    required this.addressSpans,
    required this.messageExpanded,
    required this.onToggleMessageExpanded,
    required this.onCopyAddress,
  });

  final SendReviewArgs args;
  final String amountText;
  final String feeText;
  final List<TextSpan> addressSpans;
  final bool messageExpanded;
  final VoidCallback onToggleMessageExpanded;
  final VoidCallback onCopyAddress;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = context.appTheme == AppThemeData.dark;
    final receiptMaskAsset = isDark
        ? 'assets/illustrations/send_review_receipt_mask_dark.png'
        : 'assets/illustrations/send_review_receipt_mask.png';
    final hasMemo = args.memo != null && args.memo!.trim().isNotEmpty;
    final messageTextHeight = messageExpanded ? 156.0 : 62.0;
    final messageBlockHeight = 24.0 + messageTextHeight;
    final dividerTop = hasMemo ? 214.0 + messageBlockHeight + 16.0 : 214.0;
    final feeTop = dividerTop + 32.0;
    final receiptHeight = hasMemo && messageExpanded ? feeTop + 56.0 : 404.0;

    return SizedBox(
      width: 352,
      height: receiptHeight,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned(
            left: 0,
            top: 0,
            width: 352,
            height: receiptHeight + 80.0,
            child: Image.asset(receiptMaskAsset, fit: BoxFit.fill),
          ),
          Positioned(
            top: 23,
            right: 18,
            child: _SendReviewStatusBadge(isShielded: args.isShielded),
          ),
          Positioned(
            left: AppSpacing.sm,
            top: 35,
            width: 320,
            height: 87,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sending',
                  style: AppTypography.labelMedium.copyWith(
                    color: colors.text.secondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                SizedBox(
                  width: double.infinity,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      amountText,
                      maxLines: 1,
                      softWrap: false,
                      style: AppTypography.displayLarge.copyWith(
                        color: colors.text.accent,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: AppSpacing.sm,
            top: 138,
            width: 320,
            height: 60,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SendReviewFieldTitle(
                  label: 'To',
                  rightLabel: _SendReviewCopyAction(onTap: onCopyAddress),
                ),
                const SizedBox(height: AppSpacing.xs),
                RichText(
                  maxLines: 2,
                  overflow: TextOverflow.clip,
                  softWrap: false,
                  text: TextSpan(children: addressSpans),
                ),
              ],
            ),
          ),
          if (hasMemo)
            Positioned(
              left: AppSpacing.sm,
              top: 214,
              width: 320,
              height: messageBlockHeight,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SendReviewFieldTitle(
                    label: 'Message',
                    rightLabel: _SendReviewMessageToggle(
                      expanded: messageExpanded,
                      onTap: onToggleMessageExpanded,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  SizedBox(
                    height: messageTextHeight,
                    child: messageExpanded
                        ? SingleChildScrollView(
                            child: Text(
                              args.memo!,
                              maxLines: null,
                              overflow: TextOverflow.visible,
                              style: AppTypography.bodyMediumStrong.copyWith(
                                color: colors.text.accent,
                              ),
                            ),
                          )
                        : Text(
                            args.memo!,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.bodyMediumStrong.copyWith(
                              color: colors.text.accent,
                            ),
                          ),
                  ),
                ],
              ),
            ),
          Positioned(
            left: AppSpacing.sm,
            top: dividerTop,
            width: 320,
            height: 16,
            child: const AppDecorativeDivider(width: 320),
          ),
          Positioned(
            left: AppSpacing.sm,
            top: feeTop,
            width: 320,
            height: 21,
            child: Text(
              'Tx Fee: $feeText',
              style: AppTypography.bodyMediumStrong.copyWith(
                color: colors.text.accent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SendReviewStatusBadge extends StatelessWidget {
  const _SendReviewStatusBadge({required this.isShielded});

  final bool isShielded;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          isShielded ? 'Shielded' : 'Transparent',
          style: AppTypography.labelLarge.copyWith(
            color: isShielded ? colors.text.success : colors.text.muted,
          ),
        ),
        const SizedBox(width: AppSpacing.xxs),
        if (isShielded)
          _SendShieldedBadgeIcon()
        else
          AppIcon(
            AppIcons.transparentBalance,
            size: 20,
            color: colors.icon.muted,
          ),
      ],
    );
  }
}

class _SendReviewFieldTitle extends StatelessWidget {
  const _SendReviewFieldTitle({required this.label, this.rightLabel});

  final String label;
  final Widget? rightLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: AppTypography.labelMedium.copyWith(
              color: colors.text.secondary,
            ),
          ),
        ),
        if (rightLabel != null) ...[rightLabel!],
      ],
    );
  }
}

class _SendReviewCopyAction extends StatelessWidget {
  const _SendReviewCopyAction({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Copy',
              style: AppTypography.labelMedium.copyWith(
                color: colors.text.secondary,
              ),
            ),
            const SizedBox(width: AppSpacing.xxs),
            AppIcon(
              AppIcons.copy,
              size: AppIconSize.medium,
              color: colors.icon.muted,
            ),
          ],
        ),
      ),
    );
  }
}

class _SendReviewMessageToggle extends StatelessWidget {
  const _SendReviewMessageToggle({required this.expanded, required this.onTap});

  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              expanded ? 'Collapse' : 'Expand',
              style: AppTypography.labelMedium.copyWith(
                color: colors.text.secondary,
              ),
            ),
            const SizedBox(width: AppSpacing.xxs),
            AppIcon(
              expanded ? AppIcons.collapsed : AppIcons.expand,
              size: 16,
              color: colors.icon.muted,
            ),
          ],
        ),
      ),
    );
  }
}

class _SendShieldedBadgeIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = context.appTheme == AppThemeData.dark;
    final patternAsset = isDark
        ? 'assets/illustrations/send_review_receipt_pattern_dark.png'
        : 'assets/illustrations/send_review_receipt_pattern.png';
    return SizedBox(
      width: 20,
      height: 20,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          IgnorePointer(
            child: OverflowBox(
              minWidth: 500.755,
              maxWidth: 500.755,
              minHeight: 562.605,
              maxHeight: 562.605,
              child: Image.asset(
                patternAsset,
                width: 500.755,
                height: 562.605,
                fit: BoxFit.fill,
              ),
            ),
          ),
          AppIcon(AppIcons.shieldKeyhole, size: 20, color: colors.icon.success),
        ],
      ),
    );
  }
}
