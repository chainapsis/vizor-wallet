part of 'mobile_ironwood_migration_flow_screen.dart';

class _MobilePrivatePlan extends StatefulWidget {
  const _MobilePrivatePlan({required this.plan, required this.arrivalLabel});

  final rust_sync.OrchardMigrationPrivatePlan plan;
  final String arrivalLabel;

  @override
  State<_MobilePrivatePlan> createState() => _MobilePrivatePlanState();
}

class _MobilePrivatePlanState extends State<_MobilePrivatePlan>
    with SingleTickerProviderStateMixin {
  late final AnimationController _revealController = AnimationController(
    vsync: this,
    duration: _mobileMigrationPlanRevealDuration,
  );
  bool? _animationsDisabled;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animationsDisabled = MediaQuery.disableAnimationsOf(context);
    if (animationsDisabled) {
      _revealController.value = 1;
    } else if (_animationsDisabled != false && _revealController.value == 0) {
      _revealController.forward();
    }
    _animationsDisabled = animationsDisabled;
  }

  @override
  void dispose() {
    _revealController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final total = _mobilePlanTotalZatoshi(widget.plan);
    final transfers = widget.plan.scheduledTransfers;
    final noteCount = transfers.isNotEmpty
        ? transfers.length
        : widget.plan.plannedBatchCount;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxHeight < _mobileMigrationReviewCompactContentHeight;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      style: AppTypography.bodyLarge.copyWith(
                        color: colors.text.accent,
                        fontWeight: FontWeight.w600,
                      ),
                      children: [
                        const TextSpan(text: 'Migration '),
                        TextSpan(
                          text: '$noteCount notes',
                          style: TextStyle(color: colors.text.secondary),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.xxs),
                  child: Text(
                    '${_compactZec(total)} ZEC',
                    style: AppTypography.labelLarge.copyWith(
                      color: colors.text.accent,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: compact ? AppSpacing.xs : AppSpacing.xs + 4),
            _MobileMigrationPartBars(
              transfers: transfers,
              reveal: _revealController,
            ),
            SizedBox(height: compact ? AppSpacing.sm : AppSpacing.md * 2),
            Flexible(
              fit: FlexFit.loose,
              child: SizedBox(
                height: transfers.isEmpty
                    ? 120
                    : math.min(
                        _mobileMigrationPartListContentHeight(transfers.length),
                        compact ? 120 : _mobileMigrationPartListMaxHeight,
                      ),
                child: _MobileMigrationPartList(
                  transfers: transfers,
                  totalZatoshi: total,
                  initialDelayBlocks: migrationPlanPreparationDelayBlocks(
                    widget.plan,
                  ),
                  reveal: _revealController,
                ),
              ),
            ),
            SizedBox(
              height: compact
                  ? AppSpacing.sm - 1
                  : _mobileMigrationPlanSummaryLayoutGap,
            ),
            Transform.translate(
              offset: Offset(
                0,
                compact ? 0 : _mobileMigrationPlanSummaryVisualOffset,
              ),
              child: Column(
                children: [
                  _ReviewRow(
                    label: 'Est. completion',
                    value: widget.arrivalLabel,
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  _ReviewRow(
                    label: 'Fees (estimate)',
                    value:
                        '${_compactZec(widget.plan.estimatedTotalFeeZatoshi)} ZEC',
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

BigInt _mobilePlanTotalZatoshi(rust_sync.OrchardMigrationPrivatePlan plan) {
  if (plan.totalMigratableZatoshi > BigInt.zero) {
    return plan.totalMigratableZatoshi;
  }
  return plan.scheduledTransfers.fold<BigInt>(
    BigInt.zero,
    (sum, transfer) => sum + transfer.valueZatoshi,
  );
}

class _MobileMigrationPartBars extends StatelessWidget {
  const _MobileMigrationPartBars({
    required this.transfers,
    required this.reveal,
  });

  final List<rust_sync.MigrationScheduledTransfer> transfers;
  final Animation<double> reveal;

  @override
  Widget build(BuildContext context) {
    if (transfers.isEmpty) {
      return const SizedBox(height: _mobileMigrationPlanFinalBarHeight);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = math.max(0.0, constraints.maxWidth);
        final finalWidths = _mobileRailSegmentWidths(
          available: available,
          transfers: transfers,
        );
        final finalSegmentsWidth = finalWidths.fold<double>(0, (a, b) => a + b);
        final initialScale = finalSegmentsWidth <= 0
            ? 1.0
            : math.min(
                1.0,
                _mobileMigrationPlanInitialBarWidth / finalSegmentsWidth,
              );
        final morph = _mobileMigrationPlanRevealAnimation(
          reveal,
          startMilliseconds: _mobileMigrationPlanBarMorphStartMilliseconds,
          durationMilliseconds: _mobileMigrationPlanBarMorphMilliseconds,
          curve: _mobileMigrationPlanBarMorphCurve,
        );
        return AnimatedBuilder(
          key: const ValueKey('mobile_ironwood_part_bar_morph'),
          animation: reveal,
          builder: (context, _) {
            final scale = initialScale + ((1 - initialScale) * morph.value);
            final gap = _mobileMigrationPlanBarGap * morph.value;
            final height =
                _mobileMigrationPlanInitialBarHeight +
                ((_mobileMigrationPlanFinalBarHeight -
                        _mobileMigrationPlanInitialBarHeight) *
                    morph.value);
            final contentWidth =
                (finalSegmentsWidth * scale) +
                (math.max(0, transfers.length - 1) * gap);
            final leading = math.max(0.0, (available - contentWidth) / 2);
            final singleTrackOpacity = (1 - (morph.value / 0.35)).clamp(
              0.0,
              1.0,
            );
            return SizedBox(
              height: height,
              child: Stack(
                children: [
                  ScrollConfiguration(
                    behavior: ScrollConfiguration.of(context).copyWith(
                      dragDevices: {
                        ...ScrollConfiguration.of(context).dragDevices,
                        PointerDeviceKind.mouse,
                      },
                    ),
                    child: SingleChildScrollView(
                      key: const ValueKey('mobile_ironwood_part_bar_scroll'),
                      scrollDirection: Axis.horizontal,
                      physics: const ClampingScrollPhysics(),
                      child: Padding(
                        padding: EdgeInsets.only(left: leading),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(height / 2),
                          child: Row(
                            children: [
                              for (
                                var index = 0;
                                index < transfers.length;
                                index++
                              ) ...[
                                Builder(
                                  builder: (context) {
                                    final delay = math.min(
                                      index *
                                          _mobileMigrationPlanBarStyleStaggerMilliseconds,
                                      _mobileMigrationPlanBarStyleMaxDelayMilliseconds,
                                    );
                                    final styleReveal =
                                        _mobileMigrationPlanRevealAnimation(
                                          reveal,
                                          startMilliseconds:
                                              _mobileMigrationPlanBarMorphStartMilliseconds +
                                              delay,
                                          durationMilliseconds: 350,
                                        );
                                    return _MobileMigrationRailSegment(
                                      key: ValueKey(
                                        'mobile_ironwood_part_bar_$index',
                                      ),
                                      width: finalWidths[index] * scale,
                                      height: height,
                                      status: MobileIronwoodMigrationPartStatus
                                          .pending,
                                      morphProgress: styleReveal.value,
                                    );
                                  },
                                ),
                                if (index < transfers.length - 1)
                                  SizedBox(width: gap),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Center(
                        child: Opacity(
                          key: const ValueKey(
                            'mobile_ironwood_part_bar_single_track',
                          ),
                          opacity: singleTrackOpacity,
                          child: Container(
                            width: math.min(contentWidth, available),
                            height: height,
                            decoration: BoxDecoration(
                              color: context.colors.background.inverse,
                              borderRadius: BorderRadius.circular(height / 2),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

List<double> _mobileRailSegmentWidths({
  required double available,
  required List<rust_sync.MigrationScheduledTransfer> transfers,
}) {
  final count = transfers.length;
  if (count <= 0) return const [];
  final values = [
    for (final transfer in transfers)
      math.max(0.0, transfer.valueZatoshi.toDouble()),
  ];
  final valueTotal = values.fold<double>(0, (sum, value) => sum + value);

  if (count > 6) {
    if (valueTotal <= 0) {
      return List<double>.filled(count, 12);
    }
    return [
      for (final value in values) math.max(12, available * value / valueTotal),
    ];
  }

  final gaps = math.max(0, count - 1) * _mobileMigrationPlanBarGap;
  final usable = math.max(0.0, available - gaps);
  if (usable <= 0) return List<double>.filled(count, 0);
  if (valueTotal <= 0) return List<double>.filled(count, usable / count);

  const minimumWidth = 8.0;
  if (usable < minimumWidth * count) {
    return List<double>.filled(count, usable / count);
  }

  final widths = List<double>.filled(count, 0);
  final remaining = <int>{for (var index = 0; index < count; index++) index};
  var remainingWidth = usable;
  var remainingValue = valueTotal;
  while (remaining.isNotEmpty) {
    final belowMinimum = [
      for (final index in remaining)
        if (remainingValue <= 0 ||
            remainingWidth * values[index] / remainingValue < minimumWidth)
          index,
    ];
    if (belowMinimum.isEmpty) {
      for (final index in remaining) {
        widths[index] = remainingWidth * values[index] / remainingValue;
      }
      break;
    }
    for (final index in belowMinimum) {
      widths[index] = minimumWidth;
      remainingWidth -= minimumWidth;
      remainingValue -= values[index];
      remaining.remove(index);
    }
  }
  return widths;
}

List<double> _mobileStatusRailSegmentWidths({
  required double available,
  required List<BigInt> values,
}) {
  final count = values.length;
  if (count <= 0) return const [];
  final total = values.fold<BigInt>(BigInt.zero, (sum, value) => sum + value);
  if (count > 6) {
    if (total <= BigInt.zero) return List<double>.filled(count, 12);
    return [
      for (final value in values)
        math.max(12, available * value.toDouble() / total.toDouble()),
    ];
  }

  final gaps = math.max(0, count - 1) * _mobileMigrationPlanBarGap;
  final usable = math.max(0.0, available - gaps);
  if (usable <= 0) return List<double>.filled(count, 0);
  if (total <= BigInt.zero) return List<double>.filled(count, usable / count);

  const minimumWidth = 8.0;
  final doubleTotal = total.toDouble();
  final widths = [
    for (final value in values)
      math.max(minimumWidth, usable * value.toDouble() / doubleTotal),
  ];
  final widthTotal = widths.fold<double>(0, (sum, width) => sum + width);
  if (widthTotal <= usable) return widths;
  final scale = usable / widthTotal;
  return [for (final width in widths) width * scale];
}
