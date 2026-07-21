part of 'mobile_ironwood_migration_flow_screen.dart';

class _MobileMigrationStepScaffold extends StatelessWidget {
  const _MobileMigrationStepScaffold({
    required this.onBack,
    required this.title,
    required this.child,
    required this.bottom,
    this.subtitle,
    this.topGap = 31,
    this.childGap = 28,
  });

  final VoidCallback onBack;
  final String title;
  final String? subtitle;
  final Widget child;
  final Widget bottom;
  final double topGap;
  final double childGap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.background.window,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Transform.translate(
              offset: const Offset(0, 20),
              child: MobileTopNav.steps(
                progress: _migrationProgress,
                onBack: onBack,
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.sm,
                  topGap,
                  AppSpacing.sm,
                  AppSpacing.md,
                ),
                child: Column(
                  children: [
                    Text(
                      title,
                      textAlign: TextAlign.start,
                      style: AppTypography.headlineLarge.copyWith(
                        color: colors.text.accent,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        subtitle!,
                        textAlign: TextAlign.start,
                        style: AppTypography.bodyMediumStrong.copyWith(
                          color: colors.text.accent,
                        ),
                      ),
                    ],
                    SizedBox(height: childGap),
                    child,
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.sm,
                0,
                AppSpacing.sm,
                AppSpacing.s,
              ),
              child: bottom,
            ),
          ],
        ),
      ),
    );
  }
}

class _MobilePrivateReviewScaffold extends StatelessWidget {
  const _MobilePrivateReviewScaffold({
    required this.onBack,
    required this.child,
    required this.bottom,
  });

  final VoidCallback onBack;
  final Widget child;
  final Widget bottom;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final compact = MediaQuery.sizeOf(context).height < 650;
    return Scaffold(
      backgroundColor: colors.background.window,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Transform.translate(
              offset: const Offset(0, 20),
              child: MobileTopNav.steps(
                progress: _migrationProgress,
                onBack: onBack,
              ),
            ),
            SizedBox(height: compact ? 24 : 43),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              child: Text(
                'Review Migration Plan',
                style: AppTypography.headlineLarge.copyWith(
                  color: colors.text.accent,
                ),
              ),
            ),
            SizedBox(height: compact ? 24 : 42),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                child: child,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.sm,
                AppSpacing.xs,
                AppSpacing.sm,
                AppSpacing.s,
              ),
              child: bottom,
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileMigrationReviewScaffold extends StatelessWidget {
  const _MobileMigrationReviewScaffold({
    required this.onBack,
    required this.icon,
    required this.title,
    required this.amount,
    required this.child,
    required this.bottom,
    this.topGap = 29,
    this.iconTitleGap = 32,
  });

  final VoidCallback onBack;
  final Widget icon;
  final String title;
  final String amount;
  final Widget child;
  final Widget bottom;
  final double topGap;
  final double iconTitleGap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.background.window,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Transform.translate(
              offset: const Offset(0, 20),
              child: MobileTopNav.steps(
                progress: _migrationProgress,
                onBack: onBack,
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.sm,
                  topGap,
                  AppSpacing.sm,
                  AppSpacing.md,
                ),
                child: Column(
                  children: [
                    icon,
                    SizedBox(height: iconTitleGap),
                    Text(
                      title,
                      style: AppTypography.bodyLarge.copyWith(
                        color: colors.text.accent,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      amount,
                      style: AppTypography.displayLarge.copyWith(
                        color: colors.text.accent,
                      ),
                    ),
                    const SizedBox(height: 32),
                    child,
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.sm,
                0,
                AppSpacing.sm,
                AppSpacing.s,
              ),
              child: bottom,
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileMigrationPrimaryButton extends StatelessWidget {
  const _MobileMigrationPrimaryButton({
    required this.label,
    required this.onPressed,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return AppButton(
      expand: true,
      constrainContent: true,
      height: 50,
      onPressed: onPressed,
      trailing: const AppIcon(AppIcons.chevronForward, size: 20),
      child: Text(label),
    );
  }
}

class _MobileMigrationProgressTrack extends StatelessWidget {
  const _MobileMigrationProgressTrack({required this.value, super.key});

  final double value;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final clampedValue = value.clamp(0.0, 1.0);
    return SizedBox(
      width: 196,
      height: 12,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
        child: ColoredBox(
          color: colors.background.neutralSubtleOpacity,
          child: Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: clampedValue,
              child: ColoredBox(color: colors.background.inverse),
            ),
          ),
        ),
      ),
    );
  }
}

class _MobilePoolMigrationHero extends StatelessWidget {
  const _MobilePoolMigrationHero({required this.data});

  final IronwoodMigrationFlowData data;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final amount = '${data.amountText} $kZcashDefaultCurrencyTicker';
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.xLarge),
      child: ColoredBox(
        color: colors.background.ground,
        child: Stack(
          children: [
            Positioned(
              left: 16,
              right: 16,
              top: 16,
              child: Stack(
                children: [
                  Row(
                    children: [
                      AppProfilePicture(
                        profilePictureId: data.profilePictureId,
                        size: AppProfilePictureSize.navLarge,
                      ),
                      Expanded(
                        child: Transform.translate(
                          offset: const Offset(0, 5),
                          child: Row(
                            children: [
                              Expanded(
                                child: Container(
                                  height: 3,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFB8B8B8),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),
                              DecoratedBox(
                                decoration: const ShapeDecoration(
                                  color: Color(0xFF00A460),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.all(
                                      Radius.circular(AppRadii.xSmall),
                                    ),
                                  ),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.xs,
                                    vertical: AppSpacing.xxs,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const AppIcon(
                                        AppIcons.shieldKeyhole,
                                        size: 20,
                                        color: Color(0xFFFFFFFF),
                                      ),
                                      const SizedBox(width: AppSpacing.xxs),
                                      Text(
                                        'Migration',
                                        style: AppTypography.bodyMediumStrong
                                            .copyWith(
                                              color: const Color(0xFFFFFFFF),
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Container(
                                  height: 3,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF00A460),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      AppProfilePicture(
                        profilePictureId: data.profilePictureId,
                        size: AppProfilePictureSize.navLarge,
                      ),
                    ],
                  ),
                  const Positioned(
                    left: 32,
                    top: 17,
                    child: _MigrationConnectionDot(
                      key: ValueKey('mobile_ironwood_legacy_connection_dot'),
                      color: Color(0xFFB8B8B8),
                    ),
                  ),
                  const Positioned(
                    right: 32,
                    top: 17,
                    child: _MigrationConnectionDot(
                      key: ValueKey('mobile_ironwood_target_connection_dot'),
                      color: Color(0xFF00A460),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '(Legacy)',
                          style: AppTypography.labelLarge.copyWith(
                            color: colors.text.muted,
                          ),
                        ),
                        Text(
                          'Orchard Pool',
                          style: AppTypography.labelLarge.copyWith(
                            color: colors.text.accent,
                          ),
                        ),
                        Text(
                          amount,
                          style: AppTypography.labelLarge.copyWith(
                            color: colors.text.accent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'Ironwood Pool',
                          style: AppTypography.labelLarge.copyWith(
                            color: const Color(0xFF00A460),
                          ),
                        ),
                        Text(
                          amount,
                          style: AppTypography.labelLarge.copyWith(
                            color: colors.text.accent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MigrationConnectionDot extends StatelessWidget {
  const _MigrationConnectionDot({required this.color, super.key});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFFFFFFF), width: 3),
      ),
    );
  }
}

class _MobileMigrationProcessCard extends StatelessWidget {
  const _MobileMigrationProcessCard();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      children: [
        _MobileReviewCard(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
          borderRadius: 24,
          showShadow: false,
          child: const Column(
            children: [
              _ProcessRow(
                number: 1,
                title: 'Choose how you migrate',
                body:
                    'Compare a privacy-optimized schedule with a faster '
                    'migration.',
              ),
              SizedBox(height: AppSpacing.base),
              _ProcessRow(
                number: 2,
                title: 'Prepare your balance',
                body:
                    'Vizor reorganizes your balance into common-sized parts '
                    'before migration begins.',
              ),
              SizedBox(height: AppSpacing.base),
              _ProcessRow(
                number: 3,
                title: 'Move to Ironwood',
                body:
                    'Privacy-optimized migrations send parts at staggered '
                    'times to reduce linkability.',
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        DecoratedBox(
          decoration: BoxDecoration(
            color: colors.background.homeCard,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 22, 20, 22),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AppIcon(
                  AppIcons.wallet,
                  size: 20,
                  color: Color(0xFF00CF82),
                ),
                const SizedBox(width: AppSpacing.s),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Spend as funds arrive',
                        style: AppTypography.bodyLarge.copyWith(
                          color: colors.text.homeCard,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Each confirmed Ironwood amount is available to spend '
                        'while the rest continues.',
                        style: AppTypography.bodyMedium.copyWith(
                          color: colors.text.homeCard,
                          height: 24 / 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ProcessRow extends StatelessWidget {
  const _ProcessRow({
    required this.number,
    required this.title,
    required this.body,
  });

  final int number;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DecoratedBox(
          key: ValueKey('mobile_ironwood_process_step_$number'),
          decoration: BoxDecoration(
            color: colors.background.neutralSubtleOpacity,
            shape: BoxShape.circle,
          ),
          child: SizedBox.square(
            dimension: 24,
            child: Center(
              child: Text(
                '$number',
                style: AppTypography.labelMedium.copyWith(
                  color: colors.text.secondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppTypography.labelLarge.copyWith(
                  color: colors.text.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                body,
                style: AppTypography.bodyMedium.copyWith(
                  color: colors.text.secondary,
                  height: 24 / 16,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

enum _MigrationChoiceIcon { private, immediate }

class _MobileMigrationOptionCard extends StatelessWidget {
  const _MobileMigrationOptionCard({
    required this.title,
    required this.body,
    required this.selected,
    required this.icon,
    this.enabled = true,
    this.recommended = false,
    super.key,
  });

  final String title;
  final String body;
  final bool selected;
  final _MigrationChoiceIcon icon;
  final bool enabled;
  final bool recommended;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Opacity(
      opacity: enabled || selected ? 1 : 0.62,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.background.ground,
          borderRadius: BorderRadius.circular(AppRadii.large),
          border: selected
              ? Border.all(color: colors.border.strong, width: 2)
              : null,
          boxShadow: appSurfaceShadow(colors),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 17, 14, 17),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox.square(
                dimension: 28,
                child: Center(
                  child: AppIcon(
                    switch (icon) {
                      _MigrationChoiceIcon.private => AppIcons.shieldKeyhole,
                      _MigrationChoiceIcon.immediate => AppIcons.migrationFast,
                    },
                    key: ValueKey('mobile_ironwood_${icon.name}_icon'),
                    size: 20,
                    color: colors.icon.accent,
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: AppSpacing.xs),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            title,
                            style: AppTypography.bodyLarge.copyWith(
                              color: colors.text.accent,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (recommended) ...[
                            const SizedBox(width: AppSpacing.xs),
                            DecoratedBox(
                              key: const ValueKey(
                                'mobile_ironwood_recommended_badge',
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF00CF82),
                                borderRadius: BorderRadius.circular(
                                  AppRadii.xSmall,
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(AppSpacing.xxs),
                                child: Text(
                                  'Recommended',
                                  style: AppTypography.labelLarge.copyWith(
                                    color: const Color(0xFF15362A),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        body,
                        style: AppTypography.bodyMedium.copyWith(
                          color: colors.text.secondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Container(
                key: ValueKey(
                  selected
                      ? 'mobile_ironwood_selected_radio'
                      : 'mobile_ironwood_unselected_radio',
                ),
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected
                      ? colors.background.inverse
                      : colors.background.neutralSubtleOpacity,
                ),
                child: selected
                    ? AppIcon(
                        AppIcons.check,
                        size: 16,
                        color: colors.text.inverse,
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MobilePrivatePlan extends StatelessWidget {
  const _MobilePrivatePlan({required this.plan, required this.arrivalLabel});

  final rust_sync.OrchardMigrationPrivatePlan plan;
  final String arrivalLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final total = _mobilePlanTotalZatoshi(plan);
    final transfers = plan.scheduledTransfers;
    final noteCount = transfers.isNotEmpty
        ? transfers.length
        : plan.plannedBatchCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Migration $noteCount notes',
                style: AppTypography.bodyLarge.copyWith(
                  color: colors.text.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              '${_compactZec(total)} ZEC',
              style: AppTypography.bodyLarge.copyWith(
                color: colors.text.accent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        _MobileMigrationPartBars(transfers: transfers, totalZatoshi: total),
        const SizedBox(height: AppSpacing.md),
        Expanded(
          child: _MobileMigrationPartList(
            transfers: transfers,
            totalZatoshi: total,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _ReviewRow(label: 'Est. completion', value: arrivalLabel),
        const SizedBox(height: AppSpacing.xs),
        _ReviewRow(
          label: 'Fees (estimate)',
          value: '${_compactZec(plan.estimatedTotalFeeZatoshi)} ZEC',
        ),
      ],
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
    required this.totalZatoshi,
  });

  final List<rust_sync.MigrationScheduledTransfer> transfers;
  final BigInt totalZatoshi;

  @override
  Widget build(BuildContext context) {
    if (transfers.isEmpty) return const SizedBox(height: 20);
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = math.max(0.0, constraints.maxWidth - 4);
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const ClampingScrollPhysics(),
          child: Row(
            children: [
              for (var index = 0; index < transfers.length; index++) ...[
                _MobileMigrationRailSegment(
                  key: ValueKey('mobile_ironwood_part_bar_$index'),
                  width: _mobileRailSegmentWidth(
                    available: available,
                    value: transfers[index].valueZatoshi,
                    total: totalZatoshi,
                    count: transfers.length,
                  ),
                  status: MobileIronwoodMigrationPartStatus.pending,
                ),
                if (index < transfers.length - 1) const SizedBox(width: 4),
              ],
            ],
          ),
        );
      },
    );
  }
}

double _mobileRailSegmentWidth({
  required double available,
  required BigInt value,
  required BigInt total,
  required int count,
}) {
  if (count <= 0) return 0;
  final gaps = math.max(0, count - 1) * 4;
  final usable = math.max(0, available - gaps);
  if (total <= BigInt.zero) return math.max(20, usable / count);
  return math.max(12, usable * value.toDouble() / total.toDouble());
}

class _MobileMigrationRailSegment extends StatelessWidget {
  const _MobileMigrationRailSegment({
    required this.width,
    required this.status,
    this.progress,
    super.key,
  });

  final double width;
  final MobileIronwoodMigrationPartStatus status;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: width,
      height: 20,
      child: CustomPaint(
        painter: _MobileMigrationRailSegmentPainter(
          status: status,
          progress: progress,
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
    required this.successColor,
    required this.inputColor,
    required this.pendingFill,
    this.progress,
  });

  final MobileIronwoodMigrationPartStatus status;
  final Color successColor;
  final Color inputColor;
  final Color pendingFill;
  final double? progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final bounds = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.height / 2),
    );
    final accent = status == MobileIronwoodMigrationPartStatus.needsInput
        ? inputColor
        : successColor;

    switch (status) {
      case MobileIronwoodMigrationPartStatus.complete:
        canvas.drawRRect(bounds, Paint()..color = accent);
      case MobileIronwoodMigrationPartStatus.pending:
        canvas.drawRRect(bounds, Paint()..color = pendingFill);
        _drawDashedRailBorder(canvas, bounds, accent);
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
        oldDelegate.successColor != successColor ||
        oldDelegate.inputColor != inputColor ||
        oldDelegate.pendingFill != pendingFill;
  }
}

class _MobileMigrationPartList extends StatelessWidget {
  const _MobileMigrationPartList({
    required this.transfers,
    required this.totalZatoshi,
  });

  final List<rust_sync.MigrationScheduledTransfer> transfers;
  final BigInt totalZatoshi;

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
    return ListView.separated(
      physics: transfers.length > 4
          ? const ClampingScrollPhysics()
          : const NeverScrollableScrollPhysics(),
      itemCount: transfers.length,
      separatorBuilder: (_, _) =>
          Divider(height: 1, color: colors.border.subtle),
      itemBuilder: (context, index) {
        final transfer = transfers[index];
        final percentage = _mobileMigrationPercentage(
          transfer.valueZatoshi,
          totalZatoshi,
        );
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              SizedBox(
                width: 70,
                child: Text(
                  'Part ${index + 1}',
                  style: AppTypography.bodyMediumStrong.copyWith(
                    color: colors.text.accent,
                  ),
                ),
              ),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    style: AppTypography.bodyMedium.copyWith(
                      color: colors.text.accent,
                    ),
                    children: [
                      TextSpan(
                        text: '${_compactZec(transfer.valueZatoshi)} ZEC',
                      ),
                      if (percentage != null)
                        TextSpan(
                          text: ' $percentage',
                          style: TextStyle(color: colors.text.secondary),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                migrationBlockOffsetLabel(transfer.blockOffset),
                style: AppTypography.bodyMedium.copyWith(
                  color: colors.text.secondary,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

String? _mobileMigrationPercentage(BigInt value, BigInt total) {
  if (value < BigInt.zero || total <= BigInt.zero) return null;
  final percentage = value.toDouble() * 100 / total.toDouble();
  final fixed = percentage.toStringAsFixed(1);
  return '${fixed.endsWith('.0') ? fixed.substring(0, fixed.length - 2) : fixed}%';
}

class _MobileReviewCard extends StatelessWidget {
  const _MobileReviewCard({
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 25),
    this.borderRadius = 24,
    this.showShadow = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final bool showShadow;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.background.ground,
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: showShadow ? appSurfaceShadow(colors) : null,
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({
    required this.label,
    required this.value,
    this.showInfo = false,
  });

  final String label;
  final String value;
  final bool showInfo;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodyMedium.copyWith(
              color: colors.text.secondary,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Flexible(
          flex: 2,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Flexible(
                child: Text(
                  value,
                  textAlign: TextAlign.end,
                  style: AppTypography.bodyMedium.copyWith(
                    color: colors.text.accent,
                  ),
                ),
              ),
              if (showInfo) ...[
                const SizedBox(width: AppSpacing.xxs),
                AppIcon(AppIcons.help, size: 16, color: colors.icon.regular),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
