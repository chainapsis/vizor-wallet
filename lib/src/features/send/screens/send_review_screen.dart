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
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_back_link.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_decorative_divider.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../providers/account_provider.dart';
import '../../../rust/api/sync.dart' as rust_sync;

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
  bool _messageExpanded = false;

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
    if (!_handoffToKeystone) {
      _scheduleDiscard();
    }
    super.dispose();
  }

  void _scheduleDiscard() {
    if (_discardScheduled) return;
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
    return ZecAmount.fromZatoshi(zatoshi).pretty().amountText;
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
      _handoffToKeystone = true;
      context.go('/send/keystone/confirm', extra: widget.args);
      return;
    }

    await context.push('/send/status', extra: widget.args);
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

    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
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
                      onCopyAddress: () => unawaited(_copyRecipientAddress()),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    SizedBox(
                      width: 256,
                      child: AppButton(
                        key: const ValueKey('send_confirm_button'),
                        onPressed: _handleSend,
                        variant: AppButtonVariant.primary,
                        minWidth: 256,
                        trailing: AppIcon(
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
            child: Image.asset(
              'assets/illustrations/send_review_receipt_mask.png',
              fit: BoxFit.fill,
            ),
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
                Text(
                  amountText,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.visible,
                  style: AppTypography.displayLarge.copyWith(
                    color: colors.text.accent,
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
              'Tx Fee: $feeText ZEC',
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
                'assets/illustrations/send_review_receipt_pattern.png',
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
