part of '../ironwood_migration_flow_screen.dart';

class _MigrationBatchOverview extends StatelessWidget {
  const _MigrationBatchOverview({
    required this.values,
    required this.totalZatoshi,
    required this.feeZatoshi,
    required this.completionLabel,
  });

  final List<BigInt> values;
  final BigInt totalZatoshi;
  final BigInt feeZatoshi;
  final String completionLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text.rich(
                TextSpan(
                  text: 'Migration',
                  style: AppTypography.bodyLarge.copyWith(
                    color: colors.text.accent,
                  ),
                  children: [
                    TextSpan(
                      text: values.length == 1
                          ? '  1 note'
                          : '  ${values.length} notes',
                      style: AppTypography.bodyMedium.copyWith(
                        color: colors.text.secondary,
                      ),
                    ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${_formatMigrationTotal(totalZatoshi)} ZEC',
              maxLines: 1,
              style: AppTypography.bodyLarge.copyWith(
                color: colors.text.accent,
              ),
            ),
          ],
        ),
        const SizedBox(height: 13),
        _MigrationProgressSegmentRow(
          values: values,
          totalZatoshi: totalZatoshi,
          statuses: const [],
          progresses: const [],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.zero,
            itemCount: values.length,
            itemBuilder: (context, index) => _MigrationBatchRow(
              key: ValueKey('ironwood_migration_batch_$index'),
              index: index,
              value: values[index],
              totalZatoshi: totalZatoshi,
              status: _MigrationBatchStatus.none,
            ),
          ),
        ),
        const SizedBox(height: 20),
        _MigrationBatchFooter(
          completionLabel: completionLabel,
          secondLabel: 'Fees (estimate)',
          secondValue: '~${_formatZecAmountCompact(feeZatoshi)} ZEC',
        ),
      ],
    );
  }
}

class _MigrationBatchFooter extends StatelessWidget {
  const _MigrationBatchFooter({
    required this.completionLabel,
    required this.secondLabel,
    required this.secondValue,
  });

  final String completionLabel;
  final String secondLabel;
  final String secondValue;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _MigrationBatchFooterRow(
          label: 'Est. completion',
          value: completionLabel,
        ),
        const SizedBox(height: 4),
        _MigrationBatchFooterRow(label: secondLabel, value: secondValue),
      ],
    );
  }
}

class _MigrationBatchFooterRow extends StatelessWidget {
  const _MigrationBatchFooterRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textColor = context.colors.text.primary;
    return SizedBox(
      height: 24,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Padding(
            padding: const EdgeInsets.all(4),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.labelLarge.copyWith(
                color: textColor,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Flexible(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: AppTypography.labelLarge.copyWith(color: textColor),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

const _migrationProgressSegmentGap = 4.0;
const _migrationProgressSegmentPreferredMinWidth = 16.0;

class _MigrationProgressSegmentRow extends StatelessWidget {
  const _MigrationProgressSegmentRow({
    required this.values,
    required this.totalZatoshi,
    required this.statuses,
    required this.progresses,
    this.progressKeys = const [],
    this.preparingStyle = false,
    this.allowDashedBorder = true,
  });

  final List<BigInt> values;
  final BigInt totalZatoshi;
  final List<_MigrationBatchStatus> statuses;
  final List<double> progresses;
  final List<String> progressKeys;
  final bool preparingStyle;
  final bool allowDashedBorder;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 12,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final layout = _migrationSegmentRowLayout(
            values: values,
            totalZatoshi: totalZatoshi,
            maxWidth: constraints.maxWidth,
          );
          return Row(
            children: [
              for (var i = 0; i < values.length; i++) ...[
                if (i > 0) SizedBox(width: layout.gap),
                SizedBox(
                  width: i < layout.widths.length ? layout.widths[i] : 0,
                  child: _MigrationProgressSegment(
                    key: ValueKey(
                      'ironwood_migration_segment_${i < progressKeys.length ? progressKeys[i] : i}',
                    ),
                    index: i,
                    status: i < statuses.length
                        ? statuses[i]
                        : _MigrationBatchStatus.none,
                    progress: i < progresses.length ? progresses[i] : 0,
                    preparingStyle: preparingStyle,
                    allowDashedBorder: allowDashedBorder,
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _MigrationSegmentRowLayout {
  const _MigrationSegmentRowLayout({required this.gap, required this.widths});

  final double gap;
  final List<double> widths;
}

class _MigrationProgressSegment extends StatelessWidget {
  const _MigrationProgressSegment({
    super.key,
    required this.index,
    required this.status,
    required this.progress,
    required this.preparingStyle,
    required this.allowDashedBorder,
  });

  final int index;
  final _MigrationBatchStatus status;
  final double progress;
  final bool preparingStyle;
  final bool allowDashedBorder;

  @override
  Widget build(BuildContext context) {
    final effectiveProgress = status == _MigrationBatchStatus.complete
        ? 1.0
        : progress.clamp(0, 1).toDouble();

    return TweenAnimationBuilder<double>(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
      tween: Tween<double>(end: effectiveProgress),
      builder: (context, animatedProgress, child) {
        final visibleProgress = _migrationSegmentVisibleProgress(
          status,
          animatedProgress,
        );
        return Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(
              key: ValueKey('ironwood_migration_segment_painter_$index'),
              painter: _MigrationProgressSegmentPainter(
                status: status,
                progress: animatedProgress,
                isDark: context.appTheme == AppThemeData.dark,
                preparingStyle: preparingStyle,
                allowDashedBorder: allowDashedBorder,
              ),
            ),
            SizedBox.expand(
              key: ValueKey('ironwood_migration_segment_track_$index'),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: visibleProgress.clamp(0, 1).toDouble(),
                heightFactor: 1,
                child: SizedBox.expand(
                  key: ValueKey('ironwood_migration_segment_fill_$index'),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MigrationProgressSegmentPainter extends CustomPainter {
  const _MigrationProgressSegmentPainter({
    required this.status,
    required this.progress,
    required this.isDark,
    required this.preparingStyle,
    required this.allowDashedBorder,
  });

  static const _green = GreenPrimitives.p500Light;
  static const _greenStripe = Color(0xFF008752);
  static const _greenSoftFill = Color(0x400DC87D);
  static const _purple = Color(0xFFB83AD9);
  static const _purpleStripe = Color(0xFF8F25AB);
  static const _strokeWidth = 1.5;

  final _MigrationBatchStatus status;
  final double progress;
  final bool isDark;
  final bool preparingStyle;
  final bool allowDashedBorder;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final outlineRect = Offset.zero & size;
    final borderRect = outlineRect.deflate(_strokeWidth / 2);
    final radius = Radius.circular(size.height / 2);
    final outline = RRect.fromRectAndRadius(outlineRect, radius);
    final border = RRect.fromRectAndRadius(borderRect, radius);
    final clipPath = Path()..addRRect(outline);
    final borderPath = Path()..addRRect(border);

    switch (status) {
      case _MigrationBatchStatus.complete:
        _drawFilledPill(canvas, outline, _green);
        break;
      case _MigrationBatchStatus.none:
        _drawFilledPill(canvas, outline, _greenSoftFill);
        if (allowDashedBorder) {
          _drawDashedBorder(canvas, borderPath, _green);
        }
        break;
      case _MigrationBatchStatus.preparing:
        if (preparingStyle) {
          _drawDashedProgressSegment(canvas, clipPath, borderPath, outlineRect);
          break;
        }
        _drawProgressFill(
          canvas,
          clipPath,
          outlineRect,
          progress,
          fillColor: _green,
        );
        if (allowDashedBorder) {
          _drawDashedBorder(canvas, borderPath, _green);
        }
        break;
      case _MigrationBatchStatus.scheduled:
        if (preparingStyle) {
          _drawDashedProgressSegment(canvas, clipPath, borderPath, outlineRect);
          break;
        }
        _drawStripedBackground(
          canvas,
          clipPath,
          outlineRect,
          fillColor: _greenSoftFill,
          stripeColor: _scheduledStripeColor,
        );
        break;
      case _MigrationBatchStatus.migrating:
      case _MigrationBatchStatus.confirming:
        if (preparingStyle) {
          _drawDashedProgressSegment(canvas, clipPath, borderPath, outlineRect);
          break;
        }
        _drawStripedBackground(
          canvas,
          clipPath,
          outlineRect,
          fillColor: _activeStripeFillColor,
          stripeColor: _activeStripeColor,
        );
        final solidProgress = math.min(
          progress.clamp(0, 1).toDouble(),
          _scheduledBlockProgressCap,
        );
        _drawProgressFill(
          canvas,
          clipPath,
          outlineRect,
          solidProgress,
          fillColor: _green,
        );
        break;
      case _MigrationBatchStatus.needsInput:
        _drawStripedBackground(
          canvas,
          clipPath,
          outlineRect,
          fillColor: _purple.withValues(alpha: 0.22),
          stripeColor: _purpleStripe.withValues(alpha: 0.44),
        );
        final solidProgress = math.min(
          math.max(progress, 0.18).clamp(0, 1).toDouble(),
          0.18,
        );
        _drawProgressFill(
          canvas,
          clipPath,
          outlineRect,
          solidProgress,
          fillColor: _purple,
        );
        break;
    }
  }

  void _drawFilledPill(Canvas canvas, RRect rrect, Color color) {
    canvas.drawRRect(rrect, Paint()..color = color);
  }

  Color get _activeStripeFillColor =>
      isDark ? const Color(0x590DC87D) : _greenSoftFill;

  Color get _activeStripeColor => isDark
      ? _green.withValues(alpha: 0.42)
      : _greenStripe.withValues(alpha: 0.48);

  Color get _scheduledStripeColor => isDark
      ? _green.withValues(alpha: 0.34)
      : _greenStripe.withValues(alpha: 0.28);

  void _drawStripedBackground(
    Canvas canvas,
    Path clipPath,
    Rect rect, {
    required Color fillColor,
    required Color stripeColor,
  }) {
    canvas.save();
    canvas.clipPath(clipPath);
    canvas.drawRect(rect, Paint()..color = fillColor);
    _drawDiagonalStripes(canvas, rect, stripeColor);
    canvas.restore();
  }

  void _drawDashedProgressSegment(
    Canvas canvas,
    Path clipPath,
    Path borderPath,
    Rect rect,
  ) {
    _drawFilledPill(
      canvas,
      RRect.fromRectAndRadius(rect, Radius.circular(rect.height / 2)),
      _greenSoftFill,
    );
    final solidProgress = math.min(
      progress.clamp(0, 1).toDouble(),
      _scheduledBlockProgressCap,
    );
    _drawProgressFill(canvas, clipPath, rect, solidProgress, fillColor: _green);
    _drawDashedBorder(canvas, borderPath, _green);
  }

  void _drawProgressFill(
    Canvas canvas,
    Path clipPath,
    Rect rect,
    double progress, {
    double startProgress = 0,
    required Color fillColor,
    Color? stripeColor,
  }) {
    final clampedStart = startProgress.clamp(0, 1).toDouble();
    final clampedProgress = progress.clamp(0, 1).toDouble();
    if (clampedProgress <= clampedStart) return;

    final fillRect = Rect.fromLTWH(
      rect.left + rect.width * clampedStart,
      rect.top,
      rect.width * (clampedProgress - clampedStart),
      rect.height,
    );

    canvas.save();
    canvas.clipPath(clipPath);
    final fillPath = _progressFillPath(rect, fillRect, clampedStart);
    canvas.drawPath(fillPath, Paint()..color = fillColor);
    if (stripeColor != null) {
      canvas.save();
      canvas.clipPath(fillPath);
      _drawDiagonalStripes(canvas, fillRect, stripeColor);
      canvas.restore();
    }
    canvas.restore();
  }

  Path _progressFillPath(Rect trackRect, Rect fillRect, double startProgress) {
    final radius = trackRect.height / 2;
    if (fillRect.width <= 0) return Path();

    final leftRadius = startProgress <= 0 ? radius : 0.0;
    return Path()..addRRect(
      RRect.fromRectAndCorners(
        fillRect,
        topLeft: Radius.circular(leftRadius),
        bottomLeft: Radius.circular(leftRadius),
        topRight: Radius.circular(radius),
        bottomRight: Radius.circular(radius),
      ),
    );
  }

  void _drawDiagonalStripes(Canvas canvas, Rect rect, Color color) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    const spacing = 4.0;
    final diagonal = rect.height * 1.45;
    for (
      var x = rect.left - diagonal;
      x < rect.right + diagonal;
      x += spacing
    ) {
      canvas.drawLine(
        Offset(x, rect.bottom),
        Offset(x + diagonal, rect.top),
        paint,
      );
    }
  }

  void _drawDashedBorder(Canvas canvas, Path path, Color color) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = _strokeWidth
      ..style = PaintingStyle.stroke;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      const dash = 3.5;
      const gap = 2.5;
      while (distance < metric.length) {
        final next = math.min(distance + dash, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MigrationProgressSegmentPainter oldDelegate) {
    return oldDelegate.status != status ||
        oldDelegate.progress != progress ||
        oldDelegate.isDark != isDark ||
        oldDelegate.preparingStyle != preparingStyle ||
        oldDelegate.allowDashedBorder != allowDashedBorder;
  }
}

double _migrationSegmentProgress({
  required List<BigInt> values,
  required BigInt totalZatoshi,
  required List<_MigrationBatchStatus> statuses,
  required List<double> progresses,
  required int index,
}) {
  if (index >= values.length) return 0;
  if (statuses.isEmpty) return 0;
  if (index >= statuses.length) return 0;

  final status = statuses[index];
  if (status == _MigrationBatchStatus.complete) return 1;

  final rawProgress = index < progresses.length
      ? progresses[index].clamp(0, 1).toDouble()
      : 0.0;

  final hasSharedPreparingProgress =
      rawProgress > 0 &&
      statuses.every((status) => status == _MigrationBatchStatus.preparing) &&
      progresses.isNotEmpty;
  if (!hasSharedPreparingProgress) return rawProgress;

  return _distributedMigrationSegmentProgress(
    values: values,
    totalZatoshi: totalZatoshi,
    progress: rawProgress,
    index: index,
  );
}

double _distributedMigrationSegmentProgress({
  required List<BigInt> values,
  required BigInt totalZatoshi,
  required double progress,
  required int index,
}) {
  if (totalZatoshi <= BigInt.zero) return progress;
  var before = BigInt.zero;
  for (var i = 0; i < index; i++) {
    before += values[i];
  }
  final current = values[index];
  if (current <= BigInt.zero) return 0;

  final start = before / totalZatoshi;
  final end = (before + current) / totalZatoshi;
  if (end <= start) return progress;
  return ((progress - start) / (end - start)).clamp(0, 1).toDouble();
}

double _migrationSegmentVisibleProgress(
  _MigrationBatchStatus status,
  double progress,
) {
  return switch (status) {
    _MigrationBatchStatus.none => 0,
    _MigrationBatchStatus.complete => 1,
    _MigrationBatchStatus.needsInput => math.max(progress, 0.18),
    _ => progress,
  };
}

enum _MigrationBatchStatus {
  none,
  preparing,
  scheduled,
  migrating,
  confirming,
  complete,
  needsInput,
}

bool _isPendingMigrationBatchStatus(_MigrationBatchStatus status) =>
    status == _MigrationBatchStatus.preparing ||
    status == _MigrationBatchStatus.scheduled;

class _MigrationBatchRow extends StatelessWidget {
  const _MigrationBatchRow({
    super.key,
    required this.index,
    required this.value,
    required this.totalZatoshi,
    required this.status,
  });

  final int index;
  final BigInt value;
  final BigInt totalZatoshi;
  final _MigrationBatchStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final statusLabel = switch (status) {
      _MigrationBatchStatus.none => null,
      _MigrationBatchStatus.preparing => 'Preparing',
      _MigrationBatchStatus.scheduled => 'Scheduled',
      _MigrationBatchStatus.migrating => 'Migrating...',
      _MigrationBatchStatus.confirming => 'Confirming...',
      _MigrationBatchStatus.complete => 'Completed',
      _MigrationBatchStatus.needsInput => 'Needs input',
    };
    return SizedBox(
      height: 40,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.border.subtle)),
        ),
        child: Row(
          children: [
            Text(
              'Part ${index + 1}',
              style: AppTypography.bodyMedium.copyWith(
                color: _isPendingMigrationBatchStatus(status)
                    ? colors.text.secondary
                    : colors.text.accent,
              ),
            ),
            const Spacer(),
            SizedBox(
              width: statusLabel == null ? 150 : 108,
              child: Text(
                '${_formatZecAmountCompact(value)} ZEC '
                '${_migrationPercentage(value, totalZatoshi)}',
                textAlign: TextAlign.right,
                style: AppTypography.bodyMedium.copyWith(
                  color: _isPendingMigrationBatchStatus(status)
                      ? colors.text.secondary
                      : colors.text.accent,
                ),
              ),
            ),
            if (statusLabel != null)
              SizedBox(
                width: 120,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (status == _MigrationBatchStatus.complete) ...[
                      const AppIcon(AppIcons.checkCircle, size: 14),
                      const SizedBox(width: 5),
                    ],
                    Flexible(
                      child: Text(
                        statusLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodyMedium.copyWith(
                          color: status == _MigrationBatchStatus.needsInput
                              ? const Color(0xFFB83AD9)
                              : _isPendingMigrationBatchStatus(status)
                              ? colors.text.secondary
                              : colors.text.accent,
                        ),
                      ),
                    ),
                    if (status == _MigrationBatchStatus.needsInput) ...[
                      const SizedBox(width: 4),
                      const AppIcon(AppIcons.chevronForward, size: 14),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MigrationStatusBatchPanel extends StatelessWidget {
  const _MigrationStatusBatchPanel({
    required this.values,
    required this.partNumbers,
    required this.totalZatoshi,
    required this.statuses,
    required this.progresses,
    required this.progressKeys,
    required this.completionLabel,
    required this.spendableLabel,
  });

  final List<BigInt> values;
  final List<int> partNumbers;
  final BigInt totalZatoshi;
  final List<_MigrationBatchStatus> statuses;
  final List<double> progresses;
  final List<String> progressKeys;
  final String completionLabel;
  final String spendableLabel;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 396,
      height: 540,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 57.5,
            width: 396,
            height: 329,
            child: _MigrationStatusBatchWrap(
              values: values,
              partNumbers: partNumbers,
              totalZatoshi: totalZatoshi,
              statuses: statuses,
              progresses: progresses,
              progressKeys: progressKeys,
            ),
          ),
          Positioned(
            left: 0,
            top: 410.5,
            width: 396,
            height: 52,
            child: _MigrationBatchFooter(
              completionLabel: completionLabel,
              secondLabel: 'Currently Spendable Balance',
              secondValue: spendableLabel,
            ),
          ),
          const Positioned(
            left: 83,
            top: 486.5,
            width: 230,
            height: 40,
            child: _MigrationStatusInfo(),
          ),
        ],
      ),
    );
  }
}

class _MigrationStatusBatchWrap extends StatelessWidget {
  const _MigrationStatusBatchWrap({
    required this.values,
    required this.partNumbers,
    required this.totalZatoshi,
    required this.statuses,
    required this.progresses,
    required this.progressKeys,
  });

  final List<BigInt> values;
  final List<int> partNumbers;
  final BigInt totalZatoshi;
  final List<_MigrationBatchStatus> statuses;
  final List<double> progresses;
  final List<String> progressKeys;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          left: 0,
          top: 12,
          width: 396,
          height: 65,
          child: _MigrationStatusBatchChart(
            values: values,
            totalZatoshi: totalZatoshi,
            statuses: statuses,
            progresses: progresses,
            progressKeys: progressKeys,
          ),
        ),
        Positioned(
          left: 0,
          top: 101,
          width: 396,
          height: 216,
          child: _MigrationStatusBatchRows(
            values: values,
            partNumbers: partNumbers,
            totalZatoshi: totalZatoshi,
            statuses: statuses,
          ),
        ),
      ],
    );
  }
}

class _MigrationStatusBatchChart extends StatelessWidget {
  const _MigrationStatusBatchChart({
    required this.values,
    required this.totalZatoshi,
    required this.statuses,
    required this.progresses,
    required this.progressKeys,
    this.preparingStyle = false,
  });

  final List<BigInt> values;
  final BigInt totalZatoshi;
  final List<_MigrationBatchStatus> statuses;
  final List<double> progresses;
  final List<String> progressKeys;
  final bool preparingStyle;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Stack(
      children: [
        Positioned(
          left: 0,
          top: 8,
          width: 396,
          height: 29,
          child: Row(
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    text: 'Migration',
                    style: AppTypography.bodyLarge.copyWith(
                      color: colors.text.accent,
                    ),
                    children: [
                      TextSpan(
                        text: values.length == 1
                            ? '  1 note'
                            : '  ${values.length} notes',
                        style: AppTypography.bodyMedium.copyWith(
                          color: colors.text.secondary,
                        ),
                      ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${_formatMigrationTotal(totalZatoshi)} ZEC',
                maxLines: 1,
                style: AppTypography.bodyLarge.copyWith(
                  color: colors.text.accent,
                ),
              ),
            ],
          ),
        ),
        Positioned(
          left: 0,
          top: 45,
          width: 396,
          height: 12,
          child: _MigrationProgressSegmentRow(
            values: values,
            totalZatoshi: totalZatoshi,
            statuses: statuses,
            progresses: progresses,
            progressKeys: progressKeys,
            preparingStyle: preparingStyle,
            allowDashedBorder: preparingStyle,
          ),
        ),
      ],
    );
  }
}

class _MigrationStatusBatchRows extends StatelessWidget {
  const _MigrationStatusBatchRows({
    required this.values,
    required this.partNumbers,
    required this.totalZatoshi,
    required this.statuses,
  });

  final List<BigInt> values;
  final List<int> partNumbers;
  final BigInt totalZatoshi;
  final List<_MigrationBatchStatus> statuses;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: EdgeInsets.zero,
      physics: const ClampingScrollPhysics(),
      itemCount: values.length,
      itemBuilder: (context, index) {
        final isLast = index == values.length - 1;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _MigrationStatusBatchRow(
              key: ValueKey('ironwood_migration_status_batch_$index'),
              partNumber: index < partNumbers.length
                  ? partNumbers[index]
                  : index + 1,
              value: values[index],
              totalZatoshi: totalZatoshi,
              status: index < statuses.length
                  ? statuses[index]
                  : _MigrationBatchStatus.none,
            ),
            if (!isLast) ...[
              const SizedBox(height: 12),
              Divider(
                height: 1,
                thickness: 1,
                color: context.colors.border.subtle,
              ),
              const SizedBox(height: 11),
            ],
          ],
        );
      },
    );
  }
}

class _MigrationStatusBatchRow extends StatelessWidget {
  const _MigrationStatusBatchRow({
    super.key,
    required this.partNumber,
    required this.value,
    required this.totalZatoshi,
    required this.status,
  });

  final int partNumber;
  final BigInt value;
  final BigInt totalZatoshi;
  final _MigrationBatchStatus status;

  @override
  Widget build(BuildContext context) {
    final opacity = status == _MigrationBatchStatus.scheduled ? 0.5 : 1.0;
    return Opacity(
      opacity: opacity,
      child: SizedBox(
        height: 16,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            SizedBox(
              width: 90,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  'Part $partNumber',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.labelLarge.copyWith(
                    color: context.colors.text.accent,
                  ),
                ),
              ),
            ),
            SizedBox(
              width: 140,
              child: _MigrationBatchAmountLabel(
                value: value,
                totalZatoshi: totalZatoshi,
              ),
            ),
            SizedBox(
              width: 130,
              child: _MigrationBatchStatusLabel(status: status),
            ),
          ],
        ),
      ),
    );
  }
}

class _MigrationBatchAmountLabel extends StatelessWidget {
  const _MigrationBatchAmountLabel({
    required this.value,
    required this.totalZatoshi,
  });

  final BigInt value;
  final BigInt totalZatoshi;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        text: '${_formatZecAmountCompact(value)} ZEC',
        style: AppTypography.labelLarge.copyWith(
          color: context.colors.text.accent,
        ),
        children: [
          TextSpan(
            text: ' ${_migrationPercentage(value, totalZatoshi)}',
            style: AppTypography.labelLarge.copyWith(
              color: context.colors.text.secondary,
            ),
          ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.right,
    );
  }
}

class _MigrationBatchStatusLabel extends StatelessWidget {
  const _MigrationBatchStatusLabel({required this.status});

  final _MigrationBatchStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final label = switch (status) {
      _MigrationBatchStatus.none => null,
      _MigrationBatchStatus.preparing => 'Preparing',
      _MigrationBatchStatus.scheduled => 'Scheduled',
      _MigrationBatchStatus.migrating => 'Migrating...',
      _MigrationBatchStatus.confirming => 'Confirming...',
      _MigrationBatchStatus.complete => 'Completed',
      _MigrationBatchStatus.needsInput => 'Needs input',
    };
    if (label == null) return const SizedBox.shrink();

    final isScheduled = status == _MigrationBatchStatus.scheduled;
    final textColor = status == _MigrationBatchStatus.needsInput
        ? const Color(0xFFB83AD9)
        : isScheduled
        ? colors.text.primary
        : colors.text.accent;
    final textStyle = AppTypography.labelLarge.copyWith(
      color: textColor,
      fontWeight: isScheduled ? FontWeight.w400 : FontWeight.w500,
    );

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (status == _MigrationBatchStatus.complete) ...[
          AppIcon(AppIcons.checkCircle, size: 16, color: colors.icon.regular),
          const SizedBox(width: 4),
        ] else if (status == _MigrationBatchStatus.migrating ||
            status == _MigrationBatchStatus.confirming) ...[
          AppIcon(AppIcons.loader, size: 16, color: colors.icon.regular),
          const SizedBox(width: 4),
        ],
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: textStyle,
          ),
        ),
        if (status == _MigrationBatchStatus.needsInput) ...[
          const SizedBox(width: 4),
          const AppIcon(
            AppIcons.chevronForward,
            size: 16,
            color: Color(0xFFB83AD9),
          ),
        ],
      ],
    );
  }
}

class _MigrationStatusInfo extends StatelessWidget {
  const _MigrationStatusInfo();

  @override
  Widget build(BuildContext context) {
    final style = AppTypography.labelLarge.copyWith(
      color: context.colors.text.secondary,
    );
    return Column(
      children: [
        Text(
          'You can leave this screen.',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: style,
        ),
        const SizedBox(height: 8),
        Text(
          'But keep Vizor open & running.',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: style,
        ),
      ],
    );
  }
}

int _migrationSegmentFlex(BigInt value, BigInt total) {
  if (total <= BigInt.zero) return 1;
  final flex = ((value * BigInt.from(1000)) ~/ total).toInt();
  return flex.clamp(1, 1000);
}

_MigrationSegmentRowLayout _migrationSegmentRowLayout({
  required List<BigInt> values,
  required BigInt totalZatoshi,
  required double maxWidth,
}) {
  if (values.isEmpty || !maxWidth.isFinite || maxWidth <= 0) {
    return const _MigrationSegmentRowLayout(gap: 0, widths: []);
  }

  final segmentCount = values.length;
  if (segmentCount == 1) {
    return _MigrationSegmentRowLayout(gap: 0, widths: [maxWidth]);
  }

  final availableForGaps = math.max(0.0, maxWidth - segmentCount);
  final gap = math.min(
    _migrationProgressSegmentGap,
    availableForGaps / (segmentCount - 1),
  );
  final drawableWidth = math.max(0.0, maxWidth - gap * (segmentCount - 1));
  if (drawableWidth <= 0) {
    return _MigrationSegmentRowLayout(
      gap: gap,
      widths: List<double>.filled(segmentCount, 0),
    );
  }

  final effectiveMinWidth = math.min(
    _migrationProgressSegmentPreferredMinWidth,
    drawableWidth / segmentCount,
  );
  final weights = [
    for (final value in values)
      math.max(1, _migrationSegmentFlex(value, totalZatoshi)).toDouble(),
  ];
  final widths = List<double>.filled(segmentCount, 0);
  final locked = List<bool>.filled(segmentCount, false);

  var remainingWidth = drawableWidth;
  var remainingWeight = weights.fold<double>(0, (sum, weight) => sum + weight);
  var changed = true;
  while (changed && remainingWeight > 0 && remainingWidth > 0) {
    changed = false;
    for (var i = 0; i < segmentCount; i++) {
      if (locked[i]) continue;
      final share = remainingWidth * weights[i] / remainingWeight;
      if (share < effectiveMinWidth) {
        widths[i] = effectiveMinWidth;
        locked[i] = true;
        remainingWidth -= effectiveMinWidth;
        remainingWeight -= weights[i];
        changed = true;
      }
    }
  }

  final unlockedIndexes = [
    for (var i = 0; i < segmentCount; i++)
      if (!locked[i]) i,
  ];
  if (unlockedIndexes.isNotEmpty) {
    if (remainingWeight <= 0) {
      final equalWidth = remainingWidth / unlockedIndexes.length;
      for (final index in unlockedIndexes) {
        widths[index] = equalWidth;
      }
    } else {
      for (final index in unlockedIndexes) {
        widths[index] = remainingWidth * weights[index] / remainingWeight;
      }
    }
  }

  final widthSum = widths.fold<double>(0, (sum, width) => sum + width);
  if (widthSum > drawableWidth && widthSum > 0) {
    final scale = drawableWidth / widthSum;
    for (var i = 0; i < widths.length; i++) {
      widths[i] *= scale;
    }
  }

  return _MigrationSegmentRowLayout(gap: gap, widths: widths);
}

String _migrationPercentage(BigInt value, BigInt total) {
  if (total <= BigInt.zero) return '';
  final tenths = ((value * BigInt.from(1000)) ~/ total).toInt();
  final whole = tenths ~/ 10;
  final decimal = tenths % 10;
  return decimal == 0 ? '$whole%' : '$whole.$decimal%';
}

String _formatMigrationTotal(BigInt zatoshi) {
  final whole = zatoshi ~/ BigInt.from(100000000);
  final hundredths =
      (zatoshi.remainder(BigInt.from(100000000)) ~/ BigInt.from(1000000))
          .toString()
          .padLeft(2, '0');
  return '$whole.$hundredths';
}
