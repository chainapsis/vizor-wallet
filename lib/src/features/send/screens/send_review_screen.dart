import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../main.dart' show log;
import '../../../core/formatting/zec_amount.dart';
import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_layout.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_decorative_divider.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../rust/api/sync.dart' as rust_sync;

class SendReviewArgs {
  const SendReviewArgs({
    required this.proposalId,
    required this.proposalAccountUuid,
    required this.address,
    required this.addressType,
    required this.amountZatoshi,
    required this.feeZatoshi,
    required this.needsSaplingParams,
    this.memo,
  });

  final BigInt proposalId;
  final String proposalAccountUuid;
  final String address;
  final String addressType;
  final BigInt amountZatoshi;
  final BigInt feeZatoshi;
  final bool needsSaplingParams;
  final String? memo;

  bool get isShielded => addressType == 'unified' || addressType == 'sapling';
}

class SendReviewScreen extends ConsumerStatefulWidget {
  const SendReviewScreen({super.key, required this.args});

  final SendReviewArgs args;

  @override
  ConsumerState<SendReviewScreen> createState() => _SendReviewScreenState();
}

class _SendReviewScreenState extends ConsumerState<SendReviewScreen> {
  bool _discardScheduled = false;

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
    _scheduleDiscard();
    super.dispose();
  }

  void _scheduleDiscard() {
    if (_discardScheduled) return;
    _discardScheduled = true;
    unawaited(
      rust_sync
          .discardProposal(proposalId: widget.args.proposalId)
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
    return '${formatZecAmount(zatoshi, minFractionDigits: 2)} zec';
  }

  String _formatFee(BigInt zatoshi) {
    return formatZecAmount(zatoshi);
  }

  List<TextSpan> _addressSpans(BuildContext context, String line) {
    final colors = context.colors;
    if (!widget.args.isShielded || line.length < 8) {
      return [
        TextSpan(
          text: line,
          style: AppTypography.labelLarge.copyWith(color: colors.text.accent),
        ),
      ];
    }
    final prefix = line.substring(0, 7);
    final suffix = line.length > 8 ? line.substring(line.length - 8) : '';
    final middle = line.substring(prefix.length, line.length - suffix.length);
    return [
      TextSpan(
        text: prefix,
        style: AppTypography.labelLarge.copyWith(
          color: colors.text.brandCrimson,
        ),
      ),
      TextSpan(
        text: middle,
        style: AppTypography.labelLarge.copyWith(color: colors.text.accent),
      ),
      if (suffix.isNotEmpty)
        TextSpan(
          text: suffix,
          style: AppTypography.labelLarge.copyWith(
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

  Future<void> _handleBack() async {
    _scheduleDiscard();
    if (!mounted) return;
    context.pop();
  }

  Future<void> _handleSend() async {
    await context.push('/send/status', extra: widget.args);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          children: [
            _SendReviewBackRow(onTap: _handleBack),
            Expanded(
              child: Center(
                child: SizedBox(
                  width: 352,
                  child: Column(
                    children: [
                      Expanded(
                        child: Center(
                          child: _SendReviewReceiptCard(
                            args: widget.args,
                            amountText: _formatReceiptAmount(
                              widget.args.amountZatoshi,
                            ),
                            feeText: _formatFee(widget.args.feeZatoshi),
                            addressLines: _splitAddress(),
                            addressSpanBuilder: (line) =>
                                _addressSpans(context, line),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 256,
                        child: AppButton(
                          onPressed: _handleSend,
                          variant: AppButtonVariant.primary,
                          minWidth: 256,
                          trailing: AppIcon(
                            AppIcons.plane,
                            color: colors.button.primary.label,
                          ),
                          child: const Text('Send'),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SendReviewBackRow extends StatelessWidget {
  const _SendReviewBackRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Align(
      alignment: Alignment.centerLeft,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            height: 32,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIcon(
                  AppIcons.chevronBackward,
                  size: 16,
                  color: colors.icon.accent,
                ),
                const SizedBox(width: AppSpacing.xxs),
                Text(
                  'Back',
                  style: AppTypography.labelLarge.copyWith(
                    color: colors.text.accent,
                  ),
                ),
              ],
            ),
          ),
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
    required this.addressLines,
    required this.addressSpanBuilder,
  });

  final SendReviewArgs args;
  final String amountText;
  final String feeText;
  final List<String> addressLines;
  final List<TextSpan> Function(String line) addressSpanBuilder;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final hasMemo = args.memo != null && args.memo!.trim().isNotEmpty;

    return SizedBox(
      width: 352,
      height: 404,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned(
            left: 0,
            top: 0,
            width: 352,
            height: 484,
            child: Image.asset(
              'assets/illustrations/send_review_receipt_mask.png',
              fit: BoxFit.fill,
            ),
          ),
          Positioned(
            top: 24,
            right: 18,
            child: _SendReviewStatusBadge(isShielded: args.isShielded),
          ),
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.sm,
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
              ),
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
                    style: AppTypography.displayMedium.copyWith(
                      color: colors.text.accent,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  const _SendReviewFieldTitle(label: 'To'),
                  const SizedBox(height: AppSpacing.xs),
                  for (final line in addressLines)
                    RichText(
                      text: TextSpan(children: addressSpanBuilder(line)),
                    ),
                  if (hasMemo) ...[
                    const SizedBox(height: AppSpacing.sm),
                    _SendReviewFieldTitle(
                      label: 'Message',
                      rightLabel: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Expand',
                            style: AppTypography.labelMedium.copyWith(
                              color: colors.text.secondary,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xxs),
                          AppIcon(
                            AppIcons.expand,
                            size: 16,
                            color: colors.icon.regular,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    SizedBox(
                      height: 62,
                      child: Text(
                        args.memo!,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodyMediumStrong.copyWith(
                          color: colors.text.accent,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  const AppDecorativeDivider(width: 320),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Tx Fee: $feeText ZEC',
                    style: AppTypography.bodyMediumStrong.copyWith(
                      color: colors.text.accent,
                    ),
                  ),
                ],
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
            color: isShielded ? colors.text.brandCrimson : colors.text.muted,
          ),
        ),
        const SizedBox(width: AppSpacing.xxs),
        if (isShielded)
          _SendShieldedBadgeIcon()
        else
          AppIcon(AppIcons.eye, size: 16, color: colors.text.muted),
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

class _SendShieldedBadgeIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: 16,
      height: 16,
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
          AppIcon(
            AppIcons.shieldKeyhole,
            size: 16,
            color: colors.text.brandCrimson,
          ),
        ],
      ),
    );
  }
}
