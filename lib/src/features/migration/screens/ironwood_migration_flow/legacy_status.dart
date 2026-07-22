part of '../ironwood_migration_flow_screen.dart';

// ignore: unused_element
class _PrivateMigrationTransferStatusContent extends StatelessWidget {
  const _PrivateMigrationTransferStatusContent({
    required this.status,
    required this.presentation,
    required this.footerText,
  });

  final rust_sync.MigrationStatus status;
  final _StatusPresentation presentation;
  final String footerText;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final progress = _transferProgress(status);
    final percent = (progress * 100).round().clamp(0, 100);
    final plannedBatchCount = _plannedTransferBatchCount(status);
    final currentBatchIndex = _currentTransferBatchIndex(status);
    final currentBatchAmount = _currentTransferBatchAmount(
      status,
      plannedBatchCount: plannedBatchCount,
    );
    final leftToTransfer = _leftToTransferAmount(status, progress: progress);

    return SizedBox(
      key: ValueKey('ironwood_migration_status_${status.phase}'),
      width: 420,
      height: 656,
      child: Stack(
        children: [
          Positioned(
            left: 38,
            top: 42,
            width: 344,
            height: 130,
            child: CustomPaint(
              painter: _MigrationProgressArcPainter(
                progress: progress,
                trackColor: colors.icon.muted.withValues(alpha: 0.20),
                progressColor: GreenPrimitives.p500Light,
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: 143,
            width: 420,
            child: Column(
              children: [
                Text(
                  presentation.title,
                  textAlign: TextAlign.center,
                  style: AppTypography.bodyMediumStrong.copyWith(
                    color: colors.text.accent,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$percent%',
                  textAlign: TextAlign.center,
                  style: appSerifDisplayStyle(
                    color: colors.text.accent,
                  ).copyWith(fontSize: 45, height: 48 / 45),
                ),
                const SizedBox(height: 4),
                Text(
                  'Left to transfer: '
                  '${leftToTransfer.isEstimated ? '~' : ''}'
                  '${_formatZecAmountCompact(leftToTransfer.value)} ZEC',
                  textAlign: TextAlign.center,
                  style: AppTypography.bodyMedium.copyWith(
                    color: colors.text.accent,
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 12,
            top: 278,
            width: 396,
            child: _MigrationTransferBatchCard(
              plannedBatchCount: plannedBatchCount,
              currentBatchIndex: currentBatchIndex,
              currentBatchValue: currentBatchAmount.value,
              currentBatchValueIsEstimated: currentBatchAmount.isEstimated,
              currentBatchStatus: _currentTransferBatchStatus(status),
              estimatedArrival: _transferEstimatedArrival(status),
            ),
          ),
          Positioned(
            left: 70,
            top: 552,
            width: 280,
            child: Text(
              footerText,
              textAlign: TextAlign.center,
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

class _MigrationProgressArcPainter extends CustomPainter {
  const _MigrationProgressArcPainter({
    required this.progress,
    required this.trackColor,
    required this.progressColor,
  });

  final double progress;
  final Color trackColor;
  final Color progressColor;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(18, 12, size.width - 36, size.height * 1.8);
    const startAngle = math.pi * 1.14;
    const sweepAngle = math.pi * 0.72;
    final trackPaint = Paint()
      ..color = trackColor
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawArc(rect, startAngle, sweepAngle, false, trackPaint);

    if (progress <= 0) return;
    final progressPaint = Paint()
      ..color = progressColor
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawArc(
      rect,
      startAngle,
      sweepAngle * progress.clamp(0, 1),
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _MigrationProgressArcPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.progressColor != progressColor;
  }
}

class _MigrationTransferBatchCard extends StatelessWidget {
  const _MigrationTransferBatchCard({
    required this.plannedBatchCount,
    required this.currentBatchIndex,
    required this.currentBatchValue,
    required this.currentBatchValueIsEstimated,
    required this.currentBatchStatus,
    required this.estimatedArrival,
  });

  final int plannedBatchCount;
  final int currentBatchIndex;
  final BigInt currentBatchValue;
  final bool currentBatchValueIsEstimated;
  final String currentBatchStatus;
  final String estimatedArrival;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.background.ground,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: colors.shadows.regular,
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 16, 24),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '$plannedBatchCount Planned batches',
                    style: AppTypography.labelLarge.copyWith(
                      color: colors.text.accent,
                    ),
                  ),
                ),
                Text(
                  'View',
                  style: AppTypography.labelLarge.copyWith(
                    color: colors.text.accent,
                  ),
                ),
                const SizedBox(width: 8),
                AppIcon(
                  AppIcons.chevronForward,
                  size: 16,
                  color: colors.icon.regular,
                ),
              ],
            ),
            const SizedBox(height: 24),
            Divider(height: 1, thickness: 1, color: colors.border.subtle),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Current Batch',
                    style: AppTypography.bodyMedium.copyWith(
                      color: colors.text.accent,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Text(
                  currentBatchIndex.toString().padLeft(2, '0'),
                  style: AppTypography.bodyMedium.copyWith(
                    color: colors.text.secondary,
                  ),
                ),
                const SizedBox(width: 8),
                DecoratedBox(
                  decoration: const ShapeDecoration(
                    color: GoldPrimitives.p300Light,
                    shape: OvalBorder(),
                  ),
                  child: const SizedBox(
                    width: 18,
                    height: 18,
                    child: Center(
                      child: AppIcon(
                        AppIcons.zcashCurrency,
                        size: 12,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${currentBatchValueIsEstimated ? '~' : ''}'
                    '${_formatZecAmountCompact(currentBatchValue)} ZEC',
                    style: AppTypography.bodyMediumStrong.copyWith(
                      color: colors.text.accent,
                    ),
                  ),
                ),
                Text(
                  currentBatchStatus,
                  style: AppTypography.bodyMedium.copyWith(
                    color: colors.text.accent,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Divider(height: 1, thickness: 1, color: colors.border.subtle),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Estimated arrival time',
                    style: AppTypography.bodyMedium.copyWith(
                      color: colors.text.accent,
                    ),
                  ),
                ),
                Text(
                  estimatedArrival,
                  style: AppTypography.bodyMedium.copyWith(
                    color: colors.text.accent,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
