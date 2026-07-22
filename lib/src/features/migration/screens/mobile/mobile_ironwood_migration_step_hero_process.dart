part of 'mobile_ironwood_migration_flow_screen.dart';

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
