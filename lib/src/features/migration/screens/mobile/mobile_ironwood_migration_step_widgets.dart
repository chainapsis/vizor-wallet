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
                        textAlign: TextAlign.center,
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
    return Scaffold(
      backgroundColor: colors.background.window,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact =
                constraints.maxHeight < _mobileMigrationReviewCompactHeight;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Transform.translate(
                  offset: const Offset(0, 20),
                  child: MobileTopNav.steps(
                    progress: _migrationProgress,
                    onBack: onBack,
                  ),
                ),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                  ),
                  child: Text(
                    'Review Migration Plan',
                    textAlign: TextAlign.center,
                    style: AppTypography.headlineLarge.copyWith(
                      color: colors.text.accent,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                SizedBox(height: compact ? 24 : 42),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                    ),
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
            );
          },
        ),
      ),
    );
  }
}

class _MobileMigrationReviewScaffold extends StatelessWidget {
  const _MobileMigrationReviewScaffold({
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
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.sm,
                  39,
                  AppSpacing.sm,
                  AppSpacing.md,
                ),
                child: Column(
                  children: [
                    Text(
                      'Review Migration Plan',
                      textAlign: TextAlign.center,
                      style: AppTypography.headlineLarge.copyWith(
                        color: colors.text.accent,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 24),
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
    return Semantics(
      label: 'Migration plan analysis',
      value: '${(clampedValue * 100).round()}%',
      child: SizedBox(
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
                heightFactor: 1,
                child: ColoredBox(
                  key: const ValueKey(
                    'mobile_ironwood_migration_analysis_progress_fill',
                  ),
                  color: colors.background.inverse,
                ),
              ),
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
          surfaceKey: const ValueKey('mobile_ironwood_process_surface'),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.base,
          ),
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
              SizedBox(height: AppSpacing.sm),
              _ProcessRow(
                number: 2,
                title: 'Prepare your balance',
                body:
                    'Vizor reorganizes your balance into common-sized parts '
                    'before migration begins.',
              ),
              SizedBox(height: AppSpacing.sm),
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
        const SizedBox(height: AppSpacing.s),
        DecoratedBox(
          key: const ValueKey('mobile_ironwood_spend_surface'),
          decoration: BoxDecoration(
            color: colors.background.homeCard,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.md,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AppIcon(
                  AppIcons.wallet,
                  size: 20,
                  color: Color(0xFF00A460),
                ),
                const SizedBox(width: AppSpacing.s),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Spend as funds arrive',
                        style: AppTypography.labelLarge.copyWith(
                          color: colors.text.homeCard,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Each confirmed Ironwood amount is available to spend '
                        'while the rest continues.',
                        style: AppTypography.bodyMedium.copyWith(
                          color: colors.text.homeCard,
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
                style: AppTypography.labelLarge.copyWith(
                  color: colors.text.secondary,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.s),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppTypography.labelLarge.copyWith(
                  color: colors.text.accent,
                ),
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
    this.onTap,
    super.key,
  });

  final String title;
  final String body;
  final bool selected;
  final _MigrationChoiceIcon icon;
  final bool enabled;
  final bool recommended;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      selected: selected,
      enabled: enabled,
      button: onTap != null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
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
            padding: const EdgeInsets.fromLTRB(12, 16, 16, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Opacity(
                  opacity: selected ? 1 : 0.5,
                  child: SizedBox.square(
                    dimension: 32,
                    child: Center(
                      child: AppIcon(
                        switch (icon) {
                          _MigrationChoiceIcon.private =>
                            AppIcons.shieldKeyhole,
                          _MigrationChoiceIcon.immediate =>
                            AppIcons.migrationFast,
                        },
                        key: ValueKey('mobile_ironwood_${icon.name}_icon'),
                        size: 20,
                        color: colors.icon.accent,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs,
                      vertical: AppSpacing.xxs,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          height: 24,
                          child: Row(
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
                                    color: const Color(0xFF00A460),
                                    borderRadius: BorderRadius.circular(
                                      AppRadii.xSmall,
                                    ),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: AppSpacing.xs,
                                      vertical: AppSpacing.xxs,
                                    ),
                                    child: Text(
                                      'Recommended',
                                      style: AppTypography.labelLarge.copyWith(
                                        color: const Color(0xFFD3FFE4),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          body,
                          style: AppTypography.bodyMediumStrong.copyWith(
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
      ),
    );
  }
}

const _mobileMigrationPlanRevealDuration = Duration(milliseconds: 2000);
const _mobileMigrationReviewCompactHeight = 760.0;
const _mobileMigrationReviewCompactContentHeight = 430.0;
const _mobileMigrationPlanBarMorphStartMilliseconds = 420;
const _mobileMigrationPlanBarMorphMilliseconds = 700;
const _mobileMigrationPlanBarStyleStaggerMilliseconds = 70;
const _mobileMigrationPlanBarStyleMaxDelayMilliseconds = 350;
const _mobileMigrationPlanRowStartMilliseconds = 1200;
const _mobileMigrationPlanRowStaggerMilliseconds = 70;
const _mobileMigrationPlanRowMaxDelayMilliseconds = 350;
const _mobileMigrationPlanInitialBarWidth = 196.0;
const _mobileMigrationPlanInitialBarHeight = 12.0;
const _mobileMigrationPlanFinalBarHeight = 20.0;
const _mobileMigrationPlanBarGap = 8.0;
const _mobileMigrationPlanBarMorphCurve = Cubic(0.77, 0, 0.175, 1);
const _mobileMigrationPartRowExtent = 48.0;
const _mobileMigrationPartRowContentExtent = 24.0;
const _mobileMigrationPartListMaxHeight = 264.0;
const _mobileMigrationPlanSummaryLayoutGap = 41.0;
const _mobileMigrationPlanSummaryVisualOffset = 12.5;
const _mobileMigrationPartLabelWidth = 70.0;
const _mobileMigrationPartValueWidth = 130.0;
const _mobileMigrationPartStatusWidth = 130.0;

double _mobileMigrationPartListContentHeight(int count) {
  if (count <= 0) return 0;
  return ((count - 1) * _mobileMigrationPartRowExtent) +
      _mobileMigrationPartRowContentExtent;
}

Animation<double> _mobileMigrationPlanRevealAnimation(
  Animation<double> parent, {
  required int startMilliseconds,
  required int durationMilliseconds,
  Curve curve = _migrationAnalysisEaseOut,
}) {
  final totalMilliseconds = _mobileMigrationPlanRevealDuration.inMilliseconds
      .toDouble();
  final begin = (startMilliseconds / totalMilliseconds).clamp(0.0, 1.0);
  final end = ((startMilliseconds + durationMilliseconds) / totalMilliseconds)
      .clamp(0.0, 1.0);
  return CurvedAnimation(
    parent: parent,
    curve: Interval(begin, end, curve: curve),
  );
}

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
    required this.reveal,
  });

  final List<rust_sync.MigrationScheduledTransfer> transfers;
  final BigInt totalZatoshi;
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
                                  migrationBlockOffsetLabel(
                                    transfer.blockOffset,
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

class _MobileReviewCard extends StatelessWidget {
  const _MobileReviewCard({
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 25),
    this.borderRadius = 24,
    this.showShadow = true,
    this.surfaceKey,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final bool showShadow;
  final Key? surfaceKey;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      key: surfaceKey,
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
    this.height = 25,
  });

  final String label;
  final String value;
  final bool showInfo;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xxs,
          vertical: AppSpacing.xxs,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.labelLarge.copyWith(
                  color: colors.text.secondary,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Row(
              key: ValueKey('mobile_ironwood_review_value_$label'),
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  value,
                  textAlign: TextAlign.end,
                  style: AppTypography.labelLarge.copyWith(
                    color: colors.text.accent,
                  ),
                ),
                if (showInfo) ...[
                  const SizedBox(width: AppSpacing.xxs),
                  AppIcon(AppIcons.help, size: 16, color: colors.icon.regular),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
