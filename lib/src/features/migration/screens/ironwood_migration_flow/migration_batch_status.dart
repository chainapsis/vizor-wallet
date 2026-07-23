part of '../ironwood_migration_flow_screen.dart';

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
  });

  final List<BigInt> values;
  final BigInt totalZatoshi;
  final List<_MigrationBatchStatus> statuses;
  final List<double> progresses;
  final List<String> progressKeys;

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

String _migrationSpendableBalanceLabel({
  required List<BigInt> values,
  required List<_MigrationBatchStatus> statuses,
}) {
  var spendable = BigInt.zero;
  for (var i = 0; i < values.length; i++) {
    if (i < statuses.length && statuses[i] == _MigrationBatchStatus.complete) {
      spendable += values[i];
    }
  }
  return '${_formatZecAmountCompact(spendable)} ZEC';
}

List<rust_sync.MigrationPartStatus> _displayMigrationParts(
  rust_sync.MigrationStatus status,
) => [...status.parts];
