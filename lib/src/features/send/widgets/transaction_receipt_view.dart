import 'dart:async';

import 'package:flutter/material.dart' show Theme;
import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';

enum TransactionReceiptPhase { loading, sending, pending, succeeded, failed }

class TransactionReceiptBlockData {
  const TransactionReceiptBlockData({required this.title, required this.child});

  final String title;
  final Widget child;
}

class TransactionReceiptBackRow extends StatelessWidget {
  const TransactionReceiptBackRow({required this.onTap, super.key});

  final FutureOr<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Align(
      alignment: Alignment.centerLeft,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => unawaited(Future<void>.value(onTap())),
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
    this.onCopyTxid,
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
  final VoidCallback? onCopyTxid;
  final VoidCallback? onBackToWallet;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 328,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _TransactionReceiptHeadline(phase: phase, amountText: amountText),
              const SizedBox(height: AppSpacing.md),
              _TransactionReceiptBlock(
                title: primaryBlock.title,
                child: primaryBlock.child,
              ),
              for (final block in extraBlocks) ...[
                const SizedBox(height: AppSpacing.md),
                _TransactionReceiptBlock(
                  title: block.title,
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
                        style: AppTypography.labelLarge.copyWith(
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
                        style: AppTypography.labelLarge.copyWith(
                          color: context.colors.text.accent,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        SizedBox(width: 256, child: _TransactionReceiptActions(view: this)),
      ],
    );
  }
}

class TransactionReceiptIllustration extends StatelessWidget {
  const TransactionReceiptIllustration({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final assetPath = isDark
        ? 'assets/illustrations/send_status_illustration_dark.png'
        : 'assets/illustrations/send_status_illustration_light.png';
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

class _TransactionReceiptActions extends StatelessWidget {
  const _TransactionReceiptActions({required this.view});

  final TransactionReceiptView view;

  @override
  Widget build(BuildContext context) {
    final copyButton = view.onCopyTxid == null
        ? null
        : AppButton(
            onPressed: view.onCopyTxid,
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
        copyButton ?? const SizedBox(height: 40),
      TransactionReceiptPhase.failed => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TransactionReceiptFailureMessage(
            message: view.error ?? view.failureFallbackText,
          ),
          if (copyButton != null) ...[
            const SizedBox(height: AppSpacing.xs),
            copyButton,
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
  });

  final TransactionReceiptPhase phase;
  final String amountText;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final icon = switch (phase) {
      TransactionReceiptPhase.loading ||
      TransactionReceiptPhase.sending ||
      TransactionReceiptPhase.pending => AppIcons.loader,
      TransactionReceiptPhase.succeeded => AppIcons.check,
      TransactionReceiptPhase.failed => AppIcons.warning,
    };
    final label = switch (phase) {
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
        Text(
          amountText,
          style: AppTypography.displayMedium.copyWith(
            color: colors.text.accent,
          ),
        ),
      ],
    );
  }
}

class _TransactionReceiptBlock extends StatelessWidget {
  const _TransactionReceiptBlock({required this.title, required this.child});

  final String title;
  final Widget child;

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
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        child,
      ],
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
