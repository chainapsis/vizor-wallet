import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';
import 'app_button.dart';
import 'app_icon.dart';

class AppSegment<T> {
  const AppSegment({
    required this.value,
    required this.label,
    this.icon,
    this.key,
  });

  final T value;
  final String label;
  final String? icon;
  final Key? key;
}

/// The pill selector used for receive pools and other mutually exclusive choices.
class AppSegmentedControl<T> extends StatelessWidget {
  const AppSegmentedControl({
    required this.segments,
    required this.selected,
    required this.onChanged,
    required this.height,
    this.width,
    this.indicatorKey,
    this.selectedBackground,
    this.selectedForeground,
    this.iconSize = AppIconSize.medium,
    this.iconGap = AppSpacing.xxs,
    this.labelStyle,
    this.labelFontWeight = FontWeight.w400,
    this.position,
    super.key,
  });

  final List<AppSegment<T>> segments;
  final T selected;
  final ValueChanged<T> onChanged;
  final double height;
  final double? width;
  final Key? indicatorKey;
  final Color? selectedBackground;
  final Color? selectedForeground;
  final double iconSize;
  final double iconGap;
  final TextStyle? labelStyle;
  final FontWeight? labelFontWeight;

  /// Fractional segment index that places the indicator directly, so it can
  /// follow a pager mid-swipe. Null animates the indicator to [selected].
  final double? position;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final index = segments.indexWhere((segment) => segment.value == selected);
    final tracked = position?.clamp(0.0, segments.length - 1.0);
    final indicatorIndex = tracked ?? index.toDouble();
    final selectedColor = selectedForeground ?? colors.text.inverse;
    Color labelColor(int i) =>
        tracked == null && i == index ? selectedColor : colors.text.accent;
    final alignment = AlignmentDirectional(
      segments.length == 1
          ? 0
          : -1 + 2 * indicatorIndex / (segments.length - 1),
      0,
    );
    final indicator = FractionallySizedBox(
      widthFactor: 1 / segments.length,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: DecoratedBox(
          key: indicatorKey,
          decoration: ShapeDecoration(
            color: selectedBackground ?? colors.background.inverse,
            shape: const StadiumBorder(),
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
    return SizedBox(
      width: width,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: colors.background.raised,
          shape: const StadiumBorder(),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: tracked != null
                  ? Align(alignment: alignment, child: indicator)
                  : AnimatedAlign(
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 160),
                      curve: Curves.easeOut,
                      alignment: alignment,
                      child: indicator,
                    ),
            ),
            _trackedLabels(
              context,
              tracked: tracked,
              accent: colors.text.accent,
              selected: selectedColor,
              child: Row(
                children: [
                  for (final (i, segment) in segments.indexed)
                    Expanded(
                      child: Semantics(
                        container: true,
                        button: true,
                        selected: segment.value == selected,
                        child: AppButton(
                          key: segment.key,
                          onPressed: () => onChanged(segment.value),
                          variant: AppButtonVariant.ghost,
                          size: AppButtonSize.small,
                          height: height,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.xs,
                          ),
                          expand: true,
                          constrainContent: true,
                          growWithContent: true,
                          // A press fill would take the label mask's colour.
                          pressedBackgroundColor: tracked == null
                              ? null
                              : const Color(0x00000000),
                          enabledLabelColor: labelColor(i),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (segment.icon != null) ...[
                                ExcludeSemantics(
                                  child: AppIcon(
                                    segment.icon!,
                                    size: iconSize,
                                    color: labelColor(i),
                                  ),
                                ),
                                SizedBox(width: iconGap),
                              ],
                              Flexible(
                                child: Text(
                                  segment.label,
                                  textAlign: TextAlign.center,
                                  style:
                                      (labelStyle ?? AppTypography.labelMedium)
                                          .copyWith(
                                            color: labelColor(i),
                                            fontWeight: labelFontWeight,
                                          ),
                                ),
                              ),
                            ],
                          ),
                        ),
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

  /// While tracking, recolours the labels by where the indicator sits, so a
  /// label half under it reads inverse inside and accent outside.
  Widget _trackedLabels(
    BuildContext context, {
    required double? tracked,
    required Color accent,
    required Color selected,
    required Widget child,
  }) {
    if (tracked == null) return child;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) {
        final segment = bounds.width / segments.length;
        final start = rtl
            ? bounds.width - (tracked + 1) * segment
            : tracked * segment;
        // Matches the indicator's 2px inset.
        final left = ((start + 2) / bounds.width).clamp(0.0, 1.0);
        final right = ((start + segment - 2) / bounds.width).clamp(0.0, 1.0);
        return LinearGradient(
          colors: [accent, accent, selected, selected, accent, accent],
          stops: [0, left, left, right, right, 1],
        ).createShader(bounds);
      },
      child: child,
    );
  }
}
