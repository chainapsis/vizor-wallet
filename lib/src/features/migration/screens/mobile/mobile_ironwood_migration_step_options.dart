part of 'mobile_ironwood_migration_flow_screen.dart';

enum _MigrationChoiceIcon { private, immediate }

class _MobileMigrationOptionCard extends StatelessWidget {
  const _MobileMigrationOptionCard({
    required this.title,
    required this.body,
    required this.selected,
    required this.icon,
    this.recommended = false,
    this.onTap,
    super.key,
  });

  final String title;
  final String body;
  final bool selected;
  final _MigrationChoiceIcon icon;
  final bool recommended;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => MobileRadioCard(
    iconName: switch (icon) {
      _MigrationChoiceIcon.private => AppIcons.shieldKeyhole,
      _MigrationChoiceIcon.immediate => AppIcons.migrationFast,
    },
    title: title,
    titleTrailing: recommended ? const _RecommendedBadge() : null,
    description: body,
    selected: selected,
    enabled: onTap != null,
    onTap: onTap,
  );
}

class _RecommendedBadge extends StatelessWidget {
  const _RecommendedBadge();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const ValueKey('mobile_ironwood_recommended_badge'),
      decoration: BoxDecoration(
        color: const Color(0xFF00A460),
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: AppSpacing.xxs,
        ),
        child: Text(
          context.l10n.migrationOptionRecommended,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.labelLarge.copyWith(
            color: const Color(0xFFD3FFE4),
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

const _mobileMigrationPlanFinalBarHeight = 20.0;
const _mobileMigrationPlanBarGap = 8.0;
const _mobileMigrationPartRowExtent = 48.0;
const _mobileMigrationPartRowContentExtent = 24.0;
const _mobileMigrationPartLabelWidth = 70.0;
const _mobileMigrationPartValueWidth = 130.0;
const _mobileMigrationPartStatusWidth = 130.0;
