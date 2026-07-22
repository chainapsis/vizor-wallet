part of 'mobile_ironwood_migration_flow_screen.dart';

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
    this.onInfoPressed,
    this.height = 25,
  });

  final String label;
  final String value;
  final bool showInfo;
  final VoidCallback? onInfoPressed;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: height),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xxs,
          vertical: AppSpacing.xxs,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              flex: 3,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  label,
                  maxLines: 1,
                  style: AppTypography.labelLarge.copyWith(
                    color: colors.text.secondary,
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              flex: 2,
              child: Row(
                key: ValueKey('mobile_ironwood_review_value_$label'),
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        value,
                        maxLines: 1,
                        textAlign: TextAlign.end,
                        style: AppTypography.labelLarge.copyWith(
                          color: colors.text.accent,
                        ),
                      ),
                    ),
                  ),
                  if (showInfo) ...[
                    const SizedBox(width: AppSpacing.xxs),
                    Semantics(
                      button: onInfoPressed != null,
                      label: 'About estimated completion',
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: onInfoPressed,
                        child: SizedBox.square(
                          dimension: onInfoPressed == null ? 20 : 44,
                          child: Center(
                            child: AppIcon(
                              AppIcons.help,
                              size: 16,
                              color: colors.icon.regular,
                            ),
                          ),
                        ),
                      ),
                    ),
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
