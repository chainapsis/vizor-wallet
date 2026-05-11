import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';

class KeystoneTransactionProgressPanel extends StatelessWidget {
  const KeystoneTransactionProgressPanel({
    this.label = 'Submitting the transaction',
    this.showCameraRow = false,
    this.cameraLabel,
    super.key,
  });

  static const width = 456.0;
  static const height = 316.0;
  static const radius = 20.0;

  final String label;
  final bool showCameraRow;
  final String? cameraLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.background.inverse.withValues(alpha: 0.94),
              ),
              child: SizedBox(
                height: height,
                child: Center(
                  child: KeystoneTransactionProgressLabel(label: label),
                ),
              ),
            ),
          ),
          if (showCameraRow) ...[
            const SizedBox(height: AppSpacing.s),
            _CameraStatusRow(label: cameraLabel ?? 'Camera'),
          ],
        ],
      ),
    );
  }
}

class KeystoneTransactionProgressOverlay extends StatelessWidget {
  const KeystoneTransactionProgressOverlay({
    this.label = 'Submitting the transaction',
    this.borderRadius = BorderRadius.zero,
    super.key,
  });

  final String label;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.background.inverse.withValues(alpha: 0.78),
          ),
          child: Center(child: KeystoneTransactionProgressLabel(label: label)),
        ),
      ),
    );
  }
}

class KeystoneTransactionProgressLabel extends StatelessWidget {
  const KeystoneTransactionProgressLabel({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AppIcon(
          AppIcons.loader,
          size: 20,
          color: colors.icon.inverse,
          semanticLabel: label,
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodyMediumStrong.copyWith(
              color: colors.text.inverse,
            ),
          ),
        ),
      ],
    );
  }
}

class _CameraStatusRow extends StatelessWidget {
  const _CameraStatusRow({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      height: 24,
      child: Row(
        children: [
          Text(
            'Camera',
            style: AppTypography.bodyMediumStrong.copyWith(
              color: colors.text.accent,
            ),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
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
