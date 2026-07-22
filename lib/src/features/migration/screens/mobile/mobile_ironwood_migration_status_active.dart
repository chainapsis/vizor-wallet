part of 'mobile_ironwood_migration_flow_screen.dart';

class _MobileIronwoodActiveStatus extends StatelessWidget {
  const _MobileIronwoodActiveStatus({
    required this.parts,
    // ignore: unused_element_parameter
    this.onPartTap,
  });

  final List<MobileIronwoodMigrationPartPresentation> parts;
  final ValueChanged<int>? onPartTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final total = parts.fold<BigInt>(
          BigInt.zero,
          (sum, part) => sum + (_mobilePartValueZatoshi(part) ?? BigInt.zero),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _MobileMigrationStatusRail(parts: parts),
            const SizedBox(height: 47),
            Expanded(
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(context).copyWith(
                  dragDevices: {
                    ...ScrollConfiguration.of(context).dragDevices,
                    PointerDeviceKind.mouse,
                  },
                ),
                child: ListView.builder(
                  key: const ValueKey('mobile_ironwood_active_part_list'),
                  padding: EdgeInsets.zero,
                  physics: const ClampingScrollPhysics(),
                  itemCount: parts.length,
                  itemBuilder: (context, index) => _MobileMigrationPartRow(
                    key: ValueKey('mobile_ironwood_part_row_$index'),
                    part: parts[index],
                    totalZatoshi: total,
                    isLast: index == parts.length - 1,
                    onTap: onPartTap == null ? null : () => onPartTap!(index),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MobileMigrationStatusRail extends StatelessWidget {
  const _MobileMigrationStatusRail({required this.parts});

  final List<MobileIronwoodMigrationPartPresentation> parts;

  @override
  Widget build(BuildContext context) {
    if (parts.isEmpty) return const SizedBox(height: 20);
    return LayoutBuilder(
      builder: (context, constraints) {
        final widths = _mobileStatusRailSegmentWidths(
          available: constraints.maxWidth,
          values: [
            for (final part in parts)
              _mobilePartValueZatoshi(part) ?? BigInt.one,
          ],
        );
        return ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(
            dragDevices: {
              ...ScrollConfiguration.of(context).dragDevices,
              PointerDeviceKind.mouse,
            },
          ),
          child: SingleChildScrollView(
            key: const ValueKey('mobile_ironwood_status_rail_scroll'),
            scrollDirection: Axis.horizontal,
            physics: const ClampingScrollPhysics(),
            child: Row(
              children: [
                for (var index = 0; index < parts.length; index++) ...[
                  Semantics(
                    label: parts[index].progress == null
                        ? null
                        : '${parts[index].label} progress '
                              '${(parts[index].progress! * 100).round()}%',
                    child: _MobileMigrationRailSegment(
                      width: widths[index],
                      status: parts[index].status,
                      progress: parts[index].progress,
                    ),
                  ),
                  if (index < parts.length - 1)
                    const SizedBox(width: _mobileMigrationPlanBarGap),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MobileMigrationPartRow extends StatelessWidget {
  const _MobileMigrationPartRow({
    required this.part,
    required this.totalZatoshi,
    required this.isLast,
    this.onTap,
    super.key,
  });

  final MobileIronwoodMigrationPartPresentation part;
  final BigInt totalZatoshi;
  final bool isLast;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final value = _mobilePartValueZatoshi(part);
    final percentage = value == null
        ? null
        : _mobileMigrationPercentage(value, totalZatoshi);
    final availableWidth = math.max(
      0.0,
      MediaQuery.sizeOf(context).width - (AppSpacing.sm * 2),
    );
    final flexibleColumnScale = math.min(
      1.0,
      math.max(0.0, availableWidth - _mobileMigrationPartLabelWidth) /
          (_mobileMigrationPartValueWidth + _mobileMigrationPartStatusWidth),
    );
    final valueWidth = _mobileMigrationPartValueWidth * flexibleColumnScale;
    final statusWidth = _mobileMigrationPartStatusWidth * flexibleColumnScale;
    return Semantics(
      button: onTap != null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          height: isLast
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
                      width: _mobileMigrationPartLabelWidth,
                      child: Padding(
                        padding: const EdgeInsets.only(left: AppSpacing.xxs),
                        child: Text(
                          part.label,
                          style: AppTypography.labelLarge.copyWith(
                            color: colors.text.accent,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: valueWidth,
                      child: Text.rich(
                        TextSpan(
                          style: AppTypography.labelLarge.copyWith(
                            color: colors.text.accent,
                          ),
                          children: [
                            if (part.detail != null)
                              TextSpan(text: part.detail),
                            if (percentage != null)
                              TextSpan(
                                text: ' $percentage',
                                style: TextStyle(color: colors.text.secondary),
                              ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                      ),
                    ),
                    SizedBox(
                      width: statusWidth,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: _MobileMigrationPartStatusLabel(part: part),
                      ),
                    ),
                  ],
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Center(
                    child: Divider(height: 1, color: colors.border.subtle),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MobileMigrationPartStatusLabel extends StatelessWidget {
  const _MobileMigrationPartStatusLabel({required this.part});

  final MobileIronwoodMigrationPartPresentation part;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final style = AppTypography.labelLarge.copyWith(
      color: part.status == MobileIronwoodMigrationPartStatus.needsInput
          ? colors.text.brandCrimson
          : colors.text.secondary,
    );
    return switch (part.status) {
      MobileIronwoodMigrationPartStatus.complete => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIcon(AppIcons.checkCircle, size: 18, color: colors.icon.success),
          const SizedBox(width: AppSpacing.xxs),
          Flexible(
            child: Text(
              'Done',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
        ],
      ),
      MobileIronwoodMigrationPartStatus.needsInput => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              'Action needed',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
          const SizedBox(width: AppSpacing.xxs),
          AppIcon(
            AppIcons.chevronForward,
            size: 18,
            color: colors.text.brandCrimson,
          ),
        ],
      ),
      MobileIronwoodMigrationPartStatus.active => Text(
        part.eta ?? 'Sending',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      ),
      MobileIronwoodMigrationPartStatus.pending => Text(
        part.eta ?? 'Queued',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      ),
    };
  }
}

BigInt? _mobilePartValueZatoshi(MobileIronwoodMigrationPartPresentation part) {
  final value = part.valueZatoshi;
  if (value != null) return value;
  final detail = part.detail;
  if (detail == null) return null;
  return parseZecAmount(detail.replaceAll('ZEC', '').trim());
}
