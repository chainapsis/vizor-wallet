import 'package:flutter/material.dart' show Theme;
import 'package:flutter/widgets.dart';

import '../../../core/layout/app_layout.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';

enum TransactionReceiptPhase { loading, sending, pending, succeeded, failed }

EdgeInsets get transactionReceiptIllustrationReservedPadding {
  if (isDesktopLayoutPlatform) {
    return const EdgeInsets.only(right: 255);
  }
  return EdgeInsets.zero;
}

class TransactionReceiptBlockData {
  const TransactionReceiptBlockData({
    required this.title,
    required this.child,
    this.onCopy,
    this.titleTrailing,
  }) : assert(
         onCopy == null || titleTrailing == null,
         'Use either onCopy or titleTrailing, not both.',
       );

  final String title;
  final Widget child;
  final VoidCallback? onCopy;

  /// Optional right-side title action. Mutually exclusive with [onCopy].
  final Widget? titleTrailing;
}

class TransactionReceiptView extends StatelessWidget {
  const TransactionReceiptView({
    required this.phase,
    required this.amountText,
    required this.primaryBlock,
    required this.dateText,
    required this.feeText,
    this.extraBlocks = const [],
    this.error,
    this.failureFallbackText = 'Transaction failed',
    this.useFailedReceiptLayout = false,
    this.showPrimaryCopyAction = false,
    this.pinActionsToBottom = false,
    this.onTransactionHashPressed,
    this.onBackToWallet,
    super.key,
  });

  final TransactionReceiptPhase phase;
  final String amountText;
  final TransactionReceiptBlockData primaryBlock;
  final List<TransactionReceiptBlockData> extraBlocks;
  final String dateText;
  final String feeText;
  final String? error;
  final String failureFallbackText;
  final bool useFailedReceiptLayout;
  final bool showPrimaryCopyAction;

  /// Expands the receipt to its bounded parent height and pins the action
  /// stack to the bottom. Do not use inside an unbounded vertical scroll view.
  final bool pinActionsToBottom;
  final VoidCallback? onTransactionHashPressed;
  final VoidCallback? onBackToWallet;

  @override
  Widget build(BuildContext context) {
    final showFailedReceipt =
        useFailedReceiptLayout && phase == TransactionReceiptPhase.failed;
    final content = SizedBox(
      width: 328,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _TransactionReceiptHeadline(
            phase: phase,
            amountText: amountText,
            useFailedReceiptLayout: showFailedReceipt,
          ),
          const SizedBox(height: AppSpacing.md),
          _TransactionReceiptBlock(
            title: primaryBlock.title,
            onCopy: showFailedReceipt || showPrimaryCopyAction
                ? primaryBlock.onCopy
                : null,
            titleTrailing: primaryBlock.titleTrailing,
            child: primaryBlock.child,
          ),
          for (final block in extraBlocks) ...[
            const SizedBox(height: AppSpacing.md),
            _TransactionReceiptBlock(
              title: block.title,
              onCopy: block.onCopy,
              titleTrailing: block.titleTrailing,
              child: block.child,
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: _TransactionReceiptBlock(
                  title: 'Date',
                  child: Text(
                    dateText,
                    style: AppTypography.bodyMedium.copyWith(
                      color: context.colors.text.accent,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _TransactionReceiptBlock(
                  title: 'Tx Fee',
                  child: Text(
                    feeText,
                    style: AppTypography.bodyMedium.copyWith(
                      color: context.colors.text.accent,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    final actions = showFailedReceipt
        ? null
        : SizedBox(width: 256, child: _TransactionReceiptActions(view: this));

    if (pinActionsToBottom) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Align(alignment: Alignment.centerLeft, child: content),
          ),
          if (actions != null) ...[
            const SizedBox(height: AppSpacing.md),
            actions,
          ],
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        content,
        if (actions != null) ...[
          const SizedBox(height: AppSpacing.md),
          actions,
        ],
      ],
    );
  }
}

class TransactionReceiptMessageText extends StatelessWidget {
  const TransactionReceiptMessageText({
    required this.memo,
    required this.expanded,
    this.expandedMaxHeight = 156,
    super.key,
  });

  final String memo;
  final bool expanded;

  /// Figma's expanded message body height; matches the send preview receipt.
  final double expandedMaxHeight;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      memo,
      maxLines: expanded ? null : 3,
      overflow: expanded ? TextOverflow.visible : TextOverflow.ellipsis,
      style: AppTypography.bodyMedium.copyWith(
        color: context.colors.text.accent,
      ),
    );

    if (!expanded) return text;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: expandedMaxHeight),
      child: SingleChildScrollView(child: text),
    );
  }
}

class TransactionReceiptMessageToggle extends StatelessWidget {
  const TransactionReceiptMessageToggle({
    required this.expanded,
    required this.onTap,
    super.key,
  });

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
              size: AppIconSize.medium,
              color: colors.icon.regular,
            ),
          ],
        ),
      ),
    );
  }
}

class TransactionReceiptIllustration extends StatelessWidget {
  const TransactionReceiptIllustration({this.failed = false, super.key});

  final bool failed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final assetName = failed
        ? 'send_status_failed_illustration'
        : 'send_status_illustration';
    final assetPath =
        'assets/illustrations/${assetName}_${isDark ? 'dark' : 'light'}.png';
    return Stack(
      children: [
        Positioned.fill(
          child: Align(
            alignment: Alignment.centerRight,
            child: Image.asset(
              assetPath,
              fit: BoxFit.fitHeight,
              alignment: Alignment.centerRight,
              height: double.infinity,
            ),
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(color: colors.fade.illustration),
          ),
        ),
      ],
    );
  }
}

class TransactionReceiptAddressText extends StatelessWidget {
  const TransactionReceiptAddressText({
    required this.address,
    this.highlightEdges = false,
    this.compact = false,
    this.highlightColor,
    super.key,
  });

  static const _prefixHighlightLength = 6;
  static const _compactLeadingPlainLength = 33;
  static const _compactTrailingPlainLength = 33;
  static const _suffixHighlightLength = 5;

  final String address;
  final bool highlightEdges;

  /// Shortens long shielded-style addresses to the two-line memo layout.
  /// Shorter addresses keep the regular full-address rendering.
  final bool compact;
  final Color? highlightColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final trimmed = address.trim();
    final baseStyle = AppTypography.bodyMedium.copyWith(
      color: colors.text.accent,
    );

    if (!highlightEdges || trimmed.length <= 12) {
      return Text(trimmed, style: baseStyle);
    }

    final highlightStyle = baseStyle.copyWith(
      color: highlightColor ?? colors.text.destructive,
    );

    if (compact &&
        trimmed.length >
            _prefixHighlightLength +
                _compactLeadingPlainLength +
                _compactTrailingPlainLength +
                _suffixHighlightLength) {
      final leadingEnd = _prefixHighlightLength + _compactLeadingPlainLength;
      final trailingStart =
          trimmed.length - _suffixHighlightLength - _compactTrailingPlainLength;
      final suffixStart = trimmed.length - _suffixHighlightLength;

      return RichText(
        softWrap: false,
        overflow: TextOverflow.clip,
        text: TextSpan(
          style: baseStyle,
          children: [
            TextSpan(
              text: trimmed.substring(0, _prefixHighlightLength),
              style: highlightStyle,
            ),
            TextSpan(
              text: trimmed.substring(_prefixHighlightLength, leadingEnd),
            ),
            const TextSpan(text: '\n... '),
            TextSpan(text: trimmed.substring(trailingStart, suffixStart)),
            TextSpan(
              text: trimmed.substring(suffixStart),
              style: highlightStyle,
            ),
          ],
        ),
      );
    }

    final middle = trimmed.substring(
      _prefixHighlightLength,
      trimmed.length - _suffixHighlightLength,
    );

    return RichText(
      text: TextSpan(
        style: baseStyle,
        children: [
          TextSpan(
            text: trimmed.substring(0, _prefixHighlightLength),
            style: highlightStyle,
          ),
          TextSpan(text: middle),
          TextSpan(
            text: trimmed.substring(trimmed.length - _suffixHighlightLength),
            style: highlightStyle,
          ),
        ],
      ),
    );
  }
}

class _TransactionReceiptActions extends StatelessWidget {
  const _TransactionReceiptActions({required this.view});

  final TransactionReceiptView view;

  @override
  Widget build(BuildContext context) {
    final transactionHashButton = view.onTransactionHashPressed == null
        ? null
        : AppButton(
            onPressed: view.onTransactionHashPressed,
            variant: AppButtonVariant.secondary,
            minWidth: 256,
            trailing: AppIcon(
              AppIcons.arrowTopRight,
              color: context.colors.button.secondary.label,
            ),
            child: const Text('Transaction Hash'),
          );

    return switch (view.phase) {
      TransactionReceiptPhase.loading ||
      TransactionReceiptPhase.sending => const SizedBox(height: 40),
      TransactionReceiptPhase.pending || TransactionReceiptPhase.succeeded =>
        transactionHashButton ?? const SizedBox(height: 40),
      TransactionReceiptPhase.failed => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TransactionReceiptFailureMessage(
            message: view.error ?? view.failureFallbackText,
          ),
          if (transactionHashButton != null) ...[
            const SizedBox(height: AppSpacing.xs),
            transactionHashButton,
          ],
          if (view.onBackToWallet != null) ...[
            const SizedBox(height: AppSpacing.xs),
            AppButton(
              onPressed: view.onBackToWallet,
              variant: AppButtonVariant.secondary,
              minWidth: 256,
              child: const Text('Back to Wallet'),
            ),
          ],
        ],
      ),
    };
  }
}

class _TransactionReceiptHeadline extends StatelessWidget {
  const _TransactionReceiptHeadline({
    required this.phase,
    required this.amountText,
    required this.useFailedReceiptLayout,
  });

  final TransactionReceiptPhase phase;
  final String amountText;
  final bool useFailedReceiptLayout;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final icon = useFailedReceiptLayout
        ? AppIcons.skull
        : switch (phase) {
            TransactionReceiptPhase.loading ||
            TransactionReceiptPhase.sending ||
            TransactionReceiptPhase.pending => AppIcons.loader,
            TransactionReceiptPhase.succeeded => AppIcons.check,
            TransactionReceiptPhase.failed => AppIcons.warning,
          };
    final label = useFailedReceiptLayout
        ? 'Tx Failed'
        : switch (phase) {
            TransactionReceiptPhase.loading => 'Loading...',
            TransactionReceiptPhase.sending => 'Sending...',
            TransactionReceiptPhase.pending => 'In progress',
            TransactionReceiptPhase.succeeded => 'Succeeded',
            TransactionReceiptPhase.failed => 'Failed',
          };
    final labelColor = switch (phase) {
      TransactionReceiptPhase.loading ||
      TransactionReceiptPhase.sending ||
      TransactionReceiptPhase.pending => colors.text.accent,
      TransactionReceiptPhase.succeeded => colors.text.success,
      TransactionReceiptPhase.failed => colors.text.destructive,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.xxs),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(icon, size: 16, color: labelColor),
              const SizedBox(width: AppSpacing.xxs),
              Text(
                label,
                style: AppTypography.labelMedium.copyWith(color: labelColor),
              ),
            ],
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
        if (useFailedReceiptLayout) ...[
          const SizedBox(height: AppSpacing.xs),
          const _TransactionReceiptReturnChip(),
        ],
      ],
    );
  }
}

class _TransactionReceiptReturnChip extends StatelessWidget {
  const _TransactionReceiptReturnChip();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xxs),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIcon(AppIcons.arrowBack, size: 16, color: colors.text.secondary),
          const SizedBox(width: AppSpacing.xxs),
          Text(
            'Returned to your balance',
            style: AppTypography.labelMedium.copyWith(
              color: colors.text.secondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _TransactionReceiptBlock extends StatelessWidget {
  const _TransactionReceiptBlock({
    required this.title,
    required this.child,
    this.onCopy,
    this.titleTrailing,
  });

  final String title;
  final Widget child;
  final VoidCallback? onCopy;
  final Widget? titleTrailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: AppTypography.labelMedium.copyWith(
                  color: colors.text.secondary,
                ),
              ),
            ),
            if (titleTrailing != null)
              titleTrailing!
            else if (onCopy != null)
              _TransactionReceiptCopyAction(onTap: onCopy!),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        child,
      ],
    );
  }
}

class _TransactionReceiptCopyAction extends StatelessWidget {
  const _TransactionReceiptCopyAction({required this.onTap});

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
            AppIcon(AppIcons.copy, size: 16, color: colors.text.secondary),
          ],
        ),
      ),
    );
  }
}

class _TransactionReceiptFailureMessage extends StatelessWidget {
  const _TransactionReceiptFailureMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppIcon(
          AppIcons.warning,
          size: 16,
          color: context.colors.text.destructive,
        ),
        const SizedBox(width: AppSpacing.xxs),
        Expanded(
          child: Text(
            message,
            style: AppTypography.labelMedium.copyWith(
              color: context.colors.text.destructive,
            ),
          ),
        ),
      ],
    );
  }
}
