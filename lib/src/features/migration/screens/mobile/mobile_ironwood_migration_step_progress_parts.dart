part of 'mobile_ironwood_migration_flow_screen.dart';

class _MobileMigrationRailSegment extends StatelessWidget {
  const _MobileMigrationRailSegment({
    required this.width,
    required this.status,
    this.progress,
    this.height = _mobileMigrationPlanFinalBarHeight,
    this.morphProgress = 1,
    super.key,
  });

  final double width;
  final MobileIronwoodMigrationPartStatus status;
  final double? progress;
  final double height;
  final double morphProgress;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: _MobileMigrationRailSegmentPainter(
          status: status,
          progress: progress,
          morphProgress: morphProgress,
          initialColor: colors.background.inverse,
          successColor: colors.icon.success,
          inputColor: colors.text.brandCrimson,
          pendingFill: colors.icon.success.withValues(alpha: 0.12),
        ),
      ),
    );
  }
}

class _MobileMigrationRailSegmentPainter extends CustomPainter {
  const _MobileMigrationRailSegmentPainter({
    required this.status,
    required this.morphProgress,
    required this.initialColor,
    required this.successColor,
    required this.inputColor,
    required this.pendingFill,
    this.progress,
  });

  final MobileIronwoodMigrationPartStatus status;
  final double morphProgress;
  final Color initialColor;
  final Color successColor;
  final Color inputColor;
  final Color pendingFill;
  final double? progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final morph = morphProgress.clamp(0.0, 1.0);
    final bounds = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular((size.height / 2) * morph),
    );
    final accent = status == MobileIronwoodMigrationPartStatus.needsInput
        ? inputColor
        : successColor;

    switch (status) {
      case MobileIronwoodMigrationPartStatus.complete:
        canvas.drawRRect(bounds, Paint()..color = accent);
      case MobileIronwoodMigrationPartStatus.pending:
        canvas.drawRRect(
          bounds,
          Paint()..color = Color.lerp(initialColor, pendingFill, morph)!,
        );
        if (morph > 0) {
          _drawDashedRailBorder(
            canvas,
            bounds,
            accent.withValues(alpha: morph),
          );
        }
      case MobileIronwoodMigrationPartStatus.active:
      case MobileIronwoodMigrationPartStatus.needsInput:
        canvas.drawRRect(
          bounds,
          Paint()..color = accent.withValues(alpha: 0.14),
        );
        canvas.save();
        canvas.clipRRect(bounds);
        final fill = (progress ?? 0.35).clamp(0.0, 1.0);
        canvas.drawRect(
          Rect.fromLTWH(0, 0, size.width * fill, size.height),
          Paint()..color = accent,
        );
        final hatch = Paint()
          ..color = accent.withValues(alpha: 0.35)
          ..strokeWidth = 1;
        for (double x = -size.height; x < size.width; x += 5) {
          canvas.drawLine(
            Offset(x, size.height),
            Offset(x + size.height, 0),
            hatch,
          );
        }
        canvas.restore();
    }
  }

  void _drawDashedRailBorder(Canvas canvas, RRect bounds, Color color) {
    final path = Path()..addRRect(bounds.deflate(1));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = math.min(distance + 3, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + 3;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MobileMigrationRailSegmentPainter oldDelegate) {
    return oldDelegate.status != status ||
        oldDelegate.progress != progress ||
        oldDelegate.morphProgress != morphProgress ||
        oldDelegate.initialColor != initialColor ||
        oldDelegate.successColor != successColor ||
        oldDelegate.inputColor != inputColor ||
        oldDelegate.pendingFill != pendingFill;
  }
}

class _MobileMigrationPartList extends StatelessWidget {
  const _MobileMigrationPartList({
    required this.transfers,
    required this.totalZatoshi,
    required this.initialDelayBlocks,
    required this.reveal,
  });

  final List<rust_sync.MigrationScheduledTransfer> transfers;
  final BigInt totalZatoshi;
  final int initialDelayBlocks;
  final Animation<double> reveal;

  @override
  Widget build(BuildContext context) {
    if (transfers.isEmpty) {
      return Center(
        child: Text(
          'Migration parts are still being prepared.',
          textAlign: TextAlign.center,
          style: AppTypography.bodyMedium.copyWith(
            color: context.colors.text.secondary,
          ),
        ),
      );
    }
    final colors = context.colors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final contentHeight = _mobileMigrationPartListContentHeight(
          transfers.length,
        );
        final canScroll = contentHeight > constraints.maxHeight + 0.5;
        final flexibleColumnScale = math.min(
          1.0,
          math.max(0.0, constraints.maxWidth - _mobileMigrationPartLabelWidth) /
              (_mobileMigrationPartValueWidth +
                  _mobileMigrationPartStatusWidth),
        );
        final valueWidth = _mobileMigrationPartValueWidth * flexibleColumnScale;
        final statusWidth =
            _mobileMigrationPartStatusWidth * flexibleColumnScale;
        return ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(
            dragDevices: {
              ...ScrollConfiguration.of(context).dragDevices,
              PointerDeviceKind.mouse,
            },
          ),
          child: ListView.builder(
            key: const ValueKey('mobile_ironwood_part_list'),
            padding: EdgeInsets.zero,
            physics: canScroll
                ? const ClampingScrollPhysics()
                : const NeverScrollableScrollPhysics(),
            itemCount: transfers.length,
            itemBuilder: (context, index) {
              final transfer = transfers[index];
              final percentage = _mobileMigrationPercentage(
                transfer.valueZatoshi,
                totalZatoshi,
              );
              final rowReveal = _mobileMigrationPartRowReveal(reveal, index);
              return FadeTransition(
                key: ValueKey('mobile_ironwood_part_row_reveal_$index'),
                opacity: rowReveal,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.12),
                    end: Offset.zero,
                  ).animate(rowReveal),
                  child: SizedBox(
                    height: index == transfers.length - 1
                        ? _mobileMigrationPartRowContentExtent
                        : _mobileMigrationPartRowExtent,
                    child: Column(
                      children: [
                        SizedBox(
                          height: _mobileMigrationPartRowContentExtent,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              SizedBox(
                                key: ValueKey(
                                  'mobile_ironwood_part_label_cell_$index',
                                ),
                                width: _mobileMigrationPartLabelWidth,
                                child: Padding(
                                  padding: const EdgeInsets.only(
                                    left: AppSpacing.xxs,
                                  ),
                                  child: Text(
                                    'Part ${index + 1}',
                                    style: AppTypography.labelLarge.copyWith(
                                      color: colors.text.accent,
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(
                                key: ValueKey(
                                  'mobile_ironwood_part_value_cell_$index',
                                ),
                                width: valueWidth,
                                child: Text.rich(
                                  TextSpan(
                                    style: AppTypography.labelLarge.copyWith(
                                      color: colors.text.accent,
                                    ),
                                    children: [
                                      TextSpan(
                                        text:
                                            '${_compactZec(transfer.valueZatoshi)} ZEC',
                                      ),
                                      if (percentage != null)
                                        TextSpan(
                                          text: ' $percentage',
                                          style: TextStyle(
                                            color: colors.text.secondary,
                                          ),
                                        ),
                                    ],
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.end,
                                ),
                              ),
                              SizedBox(
                                key: ValueKey(
                                  'mobile_ironwood_part_status_cell_$index',
                                ),
                                width: statusWidth,
                                child: Text(
                                  migrationBlockOffsetDurationLabel(
                                    initialDelayBlocks + transfer.blockOffset,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.end,
                                  style: AppTypography.labelLarge.copyWith(
                                    color: colors.text.secondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (index < transfers.length - 1)
                          Expanded(
                            child: Center(
                              child: Divider(
                                height: 1,
                                color: colors.border.subtle,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

Animation<double> _mobileMigrationPartRowReveal(
  Animation<double> parent,
  int index,
) {
  final delay = math.min(
    index * _mobileMigrationPlanRowStaggerMilliseconds,
    _mobileMigrationPlanRowMaxDelayMilliseconds,
  );
  return _mobileMigrationPlanRevealAnimation(
    parent,
    startMilliseconds: _mobileMigrationPlanRowStartMilliseconds + delay,
    durationMilliseconds: 420,
  );
}

String? _mobileMigrationPercentage(BigInt value, BigInt total) {
  if (value < BigInt.zero || total <= BigInt.zero) return null;
  final percentage = value.toDouble() * 100 / total.toDouble();
  final fixed = percentage.toStringAsFixed(1);
  return '${fixed.endsWith('.0') ? fixed.substring(0, fixed.length - 2) : fixed}%';
}
