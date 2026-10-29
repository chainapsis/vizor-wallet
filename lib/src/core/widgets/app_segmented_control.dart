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

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final index = segments.indexWhere((segment) => segment.value == selected);
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
              child: AnimatedAlign(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 160),
                curve: Curves.easeOut,
                alignment: AlignmentDirectional(
                  segments.length == 1
                      ? 0
                      : -1 + 2 * index / (segments.length - 1),
                  0,
                ),
                child: FractionallySizedBox(
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
                ),
              ),
            ),
            Row(
              children: [
                for (final segment in segments)
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
                        enabledLabelColor: segment.value == selected
                            ? selectedForeground ?? colors.text.inverse
                            : colors.text.accent,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (segment.icon != null) ...[
                              ExcludeSemantics(
                                child: AppIcon(
                                  segment.icon!,
                                  size: iconSize,
                                  color: segment.value == selected
                                      ? selectedForeground ??
                                            colors.text.inverse
                                      : colors.text.accent,
                                ),
                              ),
                              SizedBox(width: iconGap),
                            ],
                            Flexible(
                              child: Text(
                                segment.label,
                                textAlign: TextAlign.center,
                                style: (labelStyle ?? AppTypography.labelMedium)
                                    .copyWith(
                                      color: segment.value == selected
                                          ? selectedForeground ??
                                                colors.text.inverse
                                          : colors.text.accent,
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
          ],
        ),
      ),
    );
  }
}
