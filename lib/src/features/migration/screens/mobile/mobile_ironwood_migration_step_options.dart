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
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      selected: selected,
      enabled: onTap != null,
      button: onTap != null,
      child: AnimatedOpacity(
        key: ValueKey('mobile_ironwood_${icon.name}_option_opacity'),
        opacity: onTap == null ? 0.5 : 1,
        duration: const Duration(milliseconds: 150),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
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
                                  Flexible(
                                    child: DecoratedBox(
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
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: AppTypography.labelLarge
                                              .copyWith(
                                                color: const Color(0xFFD3FFE4),
                                                fontWeight: FontWeight.w600,
                                              ),
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
