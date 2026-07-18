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
                      AppProfilePicture(
                        profilePictureId: data.profilePictureId,
                        size: AppProfilePictureSize.navLarge,
                      ),
                    ],
                  ),
                  const Positioned(
                    left: 32,
                    top: 12,
                    child: _MigrationConnectionDot(
                      key: ValueKey('mobile_ironwood_legacy_connection_dot'),
                      color: Color(0xFFB8B8B8),
                    ),
                  ),
                  const Positioned(
                    right: 32,
                    top: 12,
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
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.base,
      ),
      borderRadius: 32,
      showShadow: false,
      child: Column(
        children: [
          _ProcessRow(
            icon: _ProcessIcon.split,
            title: 'Split funds',
            body:
                plan == null
                    ? 'Vizor will calculate the split transactions and migration '
                        'batches from your current Orchard notes.'
                    : migrationPlanPreparationDescription(
                      plan: plan!,
                      amountText: amount,
                    ),
            showDivider: true,
          ),
          const SizedBox(height: AppSpacing.md),
          const _ProcessRow(
            icon: _ProcessIcon.schedule,
            title: 'Schedule',
            body:
                'Transactions dispatch at irregular intervals instead of all '
                'at once.',
            showDivider: true,
          ),
          const SizedBox(height: AppSpacing.md),
          _ProcessRow(
            icon: _ProcessIcon.sign,
            title: isHardware ? 'Sign with Keystone twice' : 'Sign once',
            body:
                isHardware
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
    this.showDivider = false,
  });

  final _ProcessIcon icon;
  final String title;
  final String body;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final iconName = switch (icon) {
      _ProcessIcon.split => AppIcons.migrationSplit,
      _ProcessIcon.schedule => AppIcons.migrationTimer,
      _ProcessIcon.sign => AppIcons.migrationSign,
    };
    final iconKey = switch (icon) {
      _ProcessIcon.split => 'mobile_ironwood_process_split_icon',
      _ProcessIcon.schedule => 'mobile_ironwood_process_schedule_icon',
      _ProcessIcon.sign => 'mobile_ironwood_process_sign_icon',
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppIcon(
          iconName,
          key: ValueKey(iconKey),
          size: 24,
          color: const Color(0xFF00A460),
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
              if (showDivider)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                  child: Container(height: 1, color: colors.border.regular),
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
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.background.ground,
        borderRadius: BorderRadius.circular(AppRadii.large),
        border:
            selected
                ? Border.all(color: const Color(0xFF00A460), width: 2)
                : null,
        boxShadow: appSurfaceShadow(colors),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.s,
          AppSpacing.sm,
          AppSpacing.sm,
          AppSpacing.sm,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 32,
              height: 32,
              child: Center(
                child: Opacity(
                  opacity: enabled ? 1 : 0.5,
                  child: AppIcon(
                    icon == _MigrationChoiceIcon.private
                        ? AppIcons.shieldKeyhole
                        : AppIcons.migrationFast,
                    key: ValueKey(
                      icon == _MigrationChoiceIcon.private
                          ? 'mobile_ironwood_private_icon'
                          : 'mobile_ironwood_immediate_icon',
                    ),
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
                            decoration: const BoxDecoration(
                              color: Color(0xFF00A460),
                              borderRadius: BorderRadius.all(
                                Radius.circular(AppRadii.xSmall),
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(AppSpacing.xxs),
                              child: Text(
                                'Recommended',
                                style: AppTypography.labelLarge.copyWith(
                                  color: const Color(0xFFFFFFFF),
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
                color:
                    selected
                        ? colors.background.inverse
                        : colors.background.neutralSubtleOpacity,
              ),
              child:
                  selected
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
    final orchardRemainder = plan.orchardChangeZatoshi ?? BigInt.zero;
    final migrationFeePerBatch =
        plan.plannedBatchCount > 0
            ? plan.migrationFeeZatoshi ~/ BigInt.from(plan.plannedBatchCount)
            : plan.migrationFeeZatoshi;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MobileReviewCard(
          child: Column(
            children: [
              _ReviewRow(
                label: plannedMigrationBatchesLabel(plan.plannedBatchCount),
                value: 'View',
                strongLabel: true,
                trailing: const AppIcon(AppIcons.chevronForward, size: 16),
              ),
              const SizedBox(height: AppSpacing.s),
              _ReviewRow(label: '~ Arrival time', value: arrivalLabel),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _MobileReviewCard(
          child: Column(
            children: [
              _ReviewRow(
                label: 'Fees (estimate)',
                value: 'Per batch, ~${_compactZec(migrationFeePerBatch)} ZEC',
              ),
              const SizedBox(height: AppSpacing.s),
              _ReviewRow(
                label: 'Orchard remains',
                value: _orchardRemainderLabel(orchardRemainder),
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
          'Separate windows reduce correlation — the total crossing amount '
          'stays publicly visible. Sending is best effort, not a delivery '
          'time.',
          style: AppTypography.bodyMedium.copyWith(
            color: colors.text.accent,
            height: 25 / 16,
          ),
        ),
      ],
    );
  }
}

String _orchardRemainderLabel(BigInt zatoshi) {
  if (zatoshi > BigInt.zero && zatoshi < BigInt.from(100000)) {
    return '<0.001 ZEC';
  }
  return '${_compactZec(zatoshi)} ZEC';
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
    this.strongLabel = false,
    this.showInfo = false,
    this.trailing,
  });

  final String label;
  final String value;
  final bool strongLabel;
  final bool showInfo;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        Text(
          label,
          style: (strongLabel
                  ? AppTypography.bodyMediumStrong
                  : AppTypography.bodyMedium)
              .copyWith(
                color: strongLabel ? colors.text.accent : colors.text.secondary,
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
                AppIcon(AppIcons.help, size: 16, color: colors.icon.regular),
              ],
              if (trailing != null) ...[
                const SizedBox(width: AppSpacing.xxs),
                trailing!,
              ],
            ],
          ),
        ),
      ],
    );
  }
}
