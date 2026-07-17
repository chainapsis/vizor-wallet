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
                      textAlign: TextAlign.center,
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
                          height: 24 / 16,
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

class _MobileMigrationReviewScaffold extends StatelessWidget {
  const _MobileMigrationReviewScaffold({
    required this.onBack,
    required this.icon,
    required this.title,
    required this.amount,
    required this.child,
    required this.bottom,
    this.topGap = 29,
    this.iconTitleGap = 36,
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
              child: Row(
                children: [
                  AppProfilePicture(
                    profilePictureId: data.profilePictureId,
                    size: AppProfilePictureSize.navLarge,
                  ),
                  Expanded(
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          height: 3,
                          margin: const EdgeInsets.symmetric(horizontal: 1),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFB8B8B8), Color(0xFF00A460)],
                            ),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        DecoratedBox(
                          decoration: const ShapeDecoration(
                            color: Color(0xFF00A460),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.all(
                                Radius.circular(6),
                              ),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.xs,
                              vertical: 6,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const AppIcon(
                                  AppIcons.shieldKeyhole,
                                  size: 20,
                                  color: Color(0xFFEAFEEF),
                                ),
                                const SizedBox(width: AppSpacing.xxs),
                                Text(
                                  'Migration',
                                  style: AppTypography.labelLarge.copyWith(
                                    color: const Color(0xFFEAFEEF),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  AppProfilePicture(
                    profilePictureId: data.profilePictureId,
                    size: AppProfilePictureSize.navLarge,
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
                            color: colors.text.secondary,
                          ),
                        ),
                        Text(
                          'Orchard Pool',
                          style: AppTypography.bodyMediumStrong.copyWith(
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
                          style: AppTypography.bodyMediumStrong.copyWith(
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

class _MobileMigrationProcessCard extends StatelessWidget {
  const _MobileMigrationProcessCard({
    required this.amount,
    required this.plan,
    required this.isHardware,
  });

  final String amount;
  final rust_sync.OrchardMigrationPrivatePlan? plan;
  final bool isHardware;

  @override
  Widget build(BuildContext context) {
    return _MobileReviewCard(
      padding: const EdgeInsets.fromLTRB(20, 29, 16, 42),
      borderRadius: 32,
      child: Column(
        children: [
          _ProcessRow(
            icon: _ProcessIcon.split,
            title: 'Split funds',
            body: plan == null
                ? 'Vizor will calculate the split transactions and migration '
                      'batches from your current Orchard notes.'
                : migrationPlanPreparationDescription(
                    plan: plan!,
                    amountText: amount,
                  ),
          ),
          const Divider(height: 33),
          const _ProcessRow(
            icon: _ProcessIcon.schedule,
            title: 'Schedule',
            body:
                'Transactions dispatch at irregular intervals instead of all '
                'at once.',
          ),
          const Divider(height: 33),
          _ProcessRow(
            icon: _ProcessIcon.sign,
            title: isHardware ? 'Sign with Keystone twice' : 'Sign once',
            body: isHardware
                ? 'First approve the split transactions. After they confirm, '
                      'return to approve the Ironwood migration transactions.'
                : 'You grant permission at the start, and Vizor executes the '
                      'remaining steps.',
          ),
        ],
      ),
    );
  }
}

enum _ProcessIcon { split, schedule, sign }

class _ProcessRow extends StatelessWidget {
  const _ProcessRow({
    required this.icon,
    required this.title,
    required this.body,
  });

  final _ProcessIcon icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 24,
          height: 24,
          child: CustomPaint(
            painter: _ProcessIconPainter(icon, const Color(0xFF00A460)),
          ),
        ),
        const SizedBox(width: AppSpacing.s),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppTypography.bodyMediumStrong.copyWith(
                  color: colors.text.accent,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                body,
                style: AppTypography.bodyMedium.copyWith(
                  color: colors.text.secondary,
                  height: 25 / 16,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProcessIconPainter extends CustomPainter {
  const _ProcessIconPainter(this.kind, this.color);

  final _ProcessIcon kind;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    switch (kind) {
      case _ProcessIcon.split:
        canvas.drawLine(const Offset(5, 5), const Offset(5, 11), paint);
        canvas.drawLine(const Offset(5, 11), const Offset(12, 11), paint);
        canvas.drawLine(const Offset(12, 11), const Offset(12, 16), paint);
        canvas.drawLine(const Offset(12, 11), const Offset(16, 7), paint);
      case _ProcessIcon.schedule:
        canvas.drawCircle(const Offset(10, 10), 6.5, paint);
        canvas.drawLine(const Offset(10, 10), const Offset(10, 6), paint);
        canvas.drawLine(const Offset(10, 10), const Offset(13, 12), paint);
      case _ProcessIcon.sign:
        canvas.drawLine(const Offset(4, 15), const Offset(16, 15), paint);
        canvas.drawLine(const Offset(5, 12), const Offset(8, 6), paint);
        canvas.drawLine(const Offset(8, 6), const Offset(12, 12), paint);
        canvas.drawLine(const Offset(12, 12), const Offset(15, 5), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ProcessIconPainter oldDelegate) =>
      oldDelegate.kind != kind || oldDelegate.color != color;
}

enum _MigrationChoiceIcon { private, immediate }

class _MobileMigrationOptionCard extends StatelessWidget {
  const _MobileMigrationOptionCard({
    required this.title,
    required this.body,
    required this.selected,
    required this.icon,
    this.enabled = true,
    super.key,
  });

  final String title;
  final String body;
  final bool selected;
  final _MigrationChoiceIcon icon;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Opacity(
      opacity: enabled ? 1 : 0.96,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.background.ground,
          borderRadius: BorderRadius.circular(24),
          border: selected
              ? Border.all(color: const Color(0xFF00A460), width: 2)
              : null,
          boxShadow: appSurfaceShadow(colors),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 16, 18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: icon == _MigrationChoiceIcon.private
                    ? AppIcon(
                        AppIcons.shieldKeyhole,
                        color: colors.icon.regular,
                      )
                    : CustomPaint(
                        painter: _ImmediateMigrationIconPainter(
                          colors.icon.disabled,
                        ),
                      ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTypography.bodyLarge.copyWith(
                        color: colors.text.accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      body,
                      style: AppTypography.bodyMedium.copyWith(
                        color: colors.text.secondary,
                        height: 25 / 16,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected
                      ? colors.background.inverse
                      : colors.background.overlay,
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

class _ImmediateMigrationIconPainter extends CustomPainter {
  const _ImmediateMigrationIconPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(size.width * 0.56, 0)
      ..lineTo(size.width * 0.18, size.height * 0.54)
      ..lineTo(size.width * 0.48, size.height * 0.54)
      ..lineTo(size.width * 0.37, size.height)
      ..lineTo(size.width * 0.84, size.height * 0.39)
      ..lineTo(size.width * 0.57, size.height * 0.39)
      ..close();
    canvas.drawPath(path, paint);
    canvas.drawLine(
      Offset.zero,
      Offset(size.width * 0.22, 0),
      Paint()
        ..color = color
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _ImmediateMigrationIconPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _MobilePrivatePlan extends StatelessWidget {
  const _MobilePrivatePlan({required this.plan, required this.arrivalLabel});

  final rust_sync.OrchardMigrationPrivatePlan plan;
  final String arrivalLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final orchardRemainder = plan.orchardChangeZatoshi ?? BigInt.zero;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MobileReviewCard(
          child: Column(
            children: [
              _ReviewRow(
                label: plannedMigrationBatchesLabel(plan.plannedBatchCount),
                value: 'View  ›',
                strongLabel: true,
              ),
              const SizedBox(height: AppSpacing.s),
              _ReviewRow(label: 'Dispatch window', value: arrivalLabel),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _MobileReviewCard(
          child: Column(
            children: [
              _ReviewRow(
                label: 'Fees (estimate)',
                value:
                    'Total, ~${_compactZec(plan.estimatedTotalFeeZatoshi)} ZEC',
              ),
              const SizedBox(height: AppSpacing.s),
              _ReviewRow(
                label: 'Orchard remains',
                value: '${_compactZec(orchardRemainder)} ZEC',
                showInfo: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        Text(
          'Privacy',
          style: AppTypography.bodyMediumStrong.copyWith(
            color: colors.text.accent,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Transactions are scheduled across the shown window instead of all '
          'at once. Amounts and timing remain visible, so this is not a '
          'privacy guarantee.',
          style: AppTypography.bodyMedium.copyWith(
            color: colors.text.accent,
            height: 25 / 16,
          ),
        ),
      ],
    );
  }
}

class _MobileReviewCard extends StatelessWidget {
  const _MobileReviewCard({
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 25),
    this.borderRadius = 24,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.background.ground,
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: appSurfaceShadow(colors),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({
    required this.label,
    required this.value,
    this.strongLabel = false,
    this.showInfo = false,
  });

  final String label;
  final String value;
  final bool strongLabel;
  final bool showInfo;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        Text(
          label,
          style:
              (strongLabel
                      ? AppTypography.bodyMediumStrong
                      : AppTypography.bodyMedium)
                  .copyWith(
                    color: strongLabel
                        ? colors.text.accent
                        : colors.text.secondary,
                  ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
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
                AppIcon(AppIcons.help, size: 14, color: colors.icon.regular),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
