import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';

/// Visual style variant of an [AppButton]. Mapped onto our semantic color
/// tokens — not onto Figma's variant naming (which calls primary "Accent").
enum AppButtonVariant { primary, secondary, ghost, destructive }

/// Vertical density. Large uses 20px icons while Medium/Small use the
/// form-factor token from the Figma component; label family/weight stays
/// consistent, with Small using the reduced label token.
enum AppButtonSize { large, medium, small }

class _Sizing {
  const _Sizing({
    required this.height,
    required this.padding,
    required this.gap,
    required this.iconSize,
    required this.labelStyle,
  });

  /// Fixed pill height pinned by the Figma component. Intrinsic sizing
  /// from padding + content alone undershoots Medium and overshoots
  /// Small, so an explicit height matches the design — see
  /// `AppButton.build` for why the Small variant also needs
  /// `clipBehavior` + centered alignment to land visually.
  final double height;
  final EdgeInsets padding;
  final double gap;
  final double iconSize;
  final TextStyle labelStyle;
}

// Large button — the primary CTA. Uses Figma `Label M`.
const _largeSizing = _Sizing(
  height: AppButtonSizing.largeHeight,
  padding: EdgeInsets.symmetric(
    horizontal: AppSpacing.sm,
    vertical: AppSpacing.xs,
  ),
  gap: AppSpacing.xxs,
  iconSize: 20,
  labelStyle: AppTypography.labelLarge,
);

// Medium button — standard inline action. Uses Figma `Label M`.
const _mediumSizing = _Sizing(
  height: 32,
  padding: EdgeInsets.symmetric(
    horizontal: AppSpacing.xs,
    vertical: AppSpacing.xxs,
  ),
  gap: AppSpacing.xxs,
  iconSize: AppButtonSizing.mediumSmallIconSize,
  labelStyle: AppTypography.labelLarge,
);

// Small (compact) button — inline/dense actions. Uses Figma `Label S`.
const _smallSizing = _Sizing(
  height: 24,
  padding: EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
  gap: AppSpacing.xxs,
  iconSize: AppButtonSizing.mediumSmallIconSize,
  labelStyle: AppTypography.labelSmall,
);

class _VariantPalette {
  const _VariantPalette({
    required this.bg,
    required this.bgHover,
    required this.bgPressed,
    required this.border,
    required this.borderHover,
    required this.borderPressed,
    required this.borderWidth,
    required this.label,
    required this.labelHover,
    required this.focusRing,
    required this.focusRingHover,
  });

  final Color bg;
  final Color bgHover;
  final Color bgPressed;
  final Color border;
  final Color borderHover;
  final Color borderPressed;
  final double borderWidth;
  final Color label;
  final Color labelHover;
  final Color focusRing;
  final Color focusRingHover;
}

_VariantPalette _paletteFor(AppButtonVariant variant, AppColors c) {
  switch (variant) {
    case AppButtonVariant.primary:
      return _VariantPalette(
        bg: c.button.primary.bg,
        bgHover: c.button.primary.bgHover,
        bgPressed: c.button.primary.bgPressed,
        border: c.button.primary.border,
        borderHover: c.button.primary.borderHover,
        borderPressed: c.button.primary.borderPressed,
        borderWidth: 1.5,
        label: c.button.primary.label,
        labelHover: c.button.primary.labelHover,
        focusRing: c.button.primary.bg,
        focusRingHover: c.button.primary.bgHover,
      );
    case AppButtonVariant.secondary:
      return _VariantPalette(
        bg: c.button.secondary.bg,
        bgHover: c.button.secondary.bgHover,
        bgPressed: c.button.secondary.bgPressed,
        border: c.background.ground.withValues(alpha: 0),
        borderHover: c.background.ground.withValues(alpha: 0),
        borderPressed: c.background.ground.withValues(alpha: 0),
        borderWidth: 0,
        label: c.button.secondary.label,
        labelHover: c.button.secondary.label,
        focusRing: c.state.focusRing,
        focusRingHover: c.state.focusRing,
      );
    case AppButtonVariant.ghost:
      // Ghost's visible base is transparent regardless of the nominal token
      // value — that way it composes correctly over any surface.
      return _VariantPalette(
        bg: c.background.ground.withValues(alpha: 0),
        bgHover: c.button.ghost.bgHover,
        bgPressed: c.button.ghost.bgHover,
        border: c.background.ground.withValues(alpha: 0),
        borderHover: c.background.ground.withValues(alpha: 0),
        borderPressed: c.background.ground.withValues(alpha: 0),
        borderWidth: 0,
        label: c.button.ghost.label,
        labelHover: c.button.ghost.label,
        focusRing: c.state.focusRing,
        focusRingHover: c.state.focusRing,
      );
    case AppButtonVariant.destructive:
      return _VariantPalette(
        bg: c.button.destructive.bg,
        bgHover: c.button.destructive.bgHover,
        bgPressed: c.button.destructive.bgPressed,
        border: c.button.destructive.border,
        borderHover: c.button.destructive.borderHover,
        borderPressed: c.button.destructive.borderPressed,
        borderWidth: 1.5,
        label: c.button.destructive.label,
        labelHover: c.button.destructive.label,
        focusRing: c.state.focusRingDestructive,
        focusRingHover: c.state.focusRingDestructive,
      );
  }
}

/// A pill-shaped button with three style variants and three size variants.
///
/// Width and height are intrinsic — the button wraps the leading icon +
/// label + trailing icon and centers them both axes. Only the pill radius
/// is fixed; padding and typography determine the rest.
///
/// States handled:
/// * default / hover / pressed — ambient fill swaps via [_Sizing] + palette
/// * focused — ring painted outside the pill using the per-variant
///   focus-ring color (2dp on large/medium, 1.5dp on small)
/// * disabled — `onPressed == null` switches to the explicit disabled
///   palette from Figma and removes pointer/focus interaction
class AppButton extends StatefulWidget {
  const AppButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.variant = AppButtonVariant.primary,
    this.size = AppButtonSize.large,
    this.height,
    this.contentPadding,
    this.leading,
    this.trailing,
    this.minWidth,
    this.iconGap,
    this.focusRingColor,
    this.disabledBackgroundColor,
    this.enabledBorderColor,
    this.focusNode,
    this.autofocus = false,
    this.expand = false,
    this.constrainContent = false,
  });

  /// Tap handler. `null` disables the button.
  final VoidCallback? onPressed;

  /// Label content. Usually a [Text] but any widget is allowed (e.g. a
  /// [Row] with a badge). The size's [TextStyle] is merged in as the
  /// ambient [DefaultTextStyle].
  final Widget child;

  final AppButtonVariant variant;
  final AppButtonSize size;

  /// Optional visual height override for one-off composed components that
  /// use the button palette but have a different fixed height in Figma.
  final double? height;

  /// Optional override for the button's internal padding. Default (`null`)
  /// keeps the design-system sizing for all regular buttons; narrow composed
  /// rows can opt in without changing the global component metrics.
  final EdgeInsets? contentPadding;

  /// Optional widget shown before [child]. Auto-sized to 16×16 and tinted
  /// to the label color via [IconTheme].
  final Widget? leading;

  /// Optional widget shown after [child]. Same auto-sizing/tint as [leading].
  final Widget? trailing;

  /// Optional minimum width. Default (`null`) keeps the button fully
  /// intrinsic — content drives size. Callers opt in to a floor when a
  /// specific screen or layout demands a consistent button width.
  final double? minWidth;

  /// Optional gap between the label and any leading/trailing icon. Defaults
  /// to the size token's gap.
  final double? iconGap;

  /// Optional focus ring color override for one-off surface-specific cases.
  final Color? focusRingColor;

  /// Optional disabled fill override for one-off surface-specific cases.
  final Color? disabledBackgroundColor;

  /// Optional border color override for enabled states.
  final Color? enabledBorderColor;

  final FocusNode? focusNode;
  final bool autofocus;

  /// Opt-in full-width behavior. The pill normally stays intrinsic even
  /// under tight constraints (the focus-ring Stack loosens them); with
  /// `expand: true` the incoming constraints pass through, so wrapping
  /// in `Expanded` or a stretched `Column` makes the pill fill — the
  /// mobile Figma frames use full-width primary CTAs throughout.
  final bool expand;

  /// Allows the label area to shrink inside bounded/expanded layouts instead
  /// of letting long text overflow the pill. Intended for one-line CTAs in
  /// narrow mobile rows; default keeps the historical intrinsic layout.
  final bool constrainContent;

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> {
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;

  bool get _enabled => widget.onPressed != null;

  void _setHovered(bool value) {
    if (_hovered != value) setState(() => _hovered = value);
  }

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  void _handleFocusChange(bool value) {
    if (_focused != value) setState(() => _focused = value);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final palette = _paletteFor(widget.variant, colors);
    final sizing = switch (widget.size) {
      AppButtonSize.large => _largeSizing,
      AppButtonSize.medium => _mediumSizing,
      AppButtonSize.small => _smallSizing,
    };
    final height = widget.height ?? sizing.height;
    final isGhost = widget.variant == AppButtonVariant.ghost;

    final disabled = colors.button.disabled;

    // Fill priority: disabled > pressed > hover > default.
    final Color currentBg = !_enabled
        ? widget.disabledBackgroundColor ?? disabled.bg
        : _pressed
        ? palette.bgPressed
        : _hovered
        ? palette.bgHover
        : palette.bg;

    final Color labelColor = !_enabled
        ? disabled.label
        : _pressed || _hovered
        ? palette.labelHover
        : palette.label;
    final Color stateBorderColor = _pressed
        ? palette.borderPressed
        : _hovered
        ? palette.borderHover
        : palette.border;
    final Color borderColor = !_enabled
        ? palette.border
        : widget.enabledBorderColor ?? stateBorderColor;
    final borderWidth = _enabled ? palette.borderWidth : 0.0;
    final iconGap = widget.iconGap ?? sizing.gap;
    final contentPadding = widget.contentPadding ?? sizing.padding;

    final rowChildren = <Widget>[];
    if (widget.leading != null) {
      rowChildren
        ..add(
          SizedBox(
            width: sizing.iconSize,
            height: sizing.iconSize,
            child: widget.leading,
          ),
        )
        ..add(SizedBox(width: iconGap));
    }
    final label = DefaultTextStyle.merge(
      style: sizing.labelStyle.copyWith(color: labelColor),
      child: widget.child,
    );
    final labelSlot = widget.size == AppButtonSize.small
        ? label
        : Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
            child: label,
          );
    rowChildren.add(
      widget.constrainContent
          ? Flexible(fit: FlexFit.loose, child: labelSlot)
          : labelSlot,
    );
    if (widget.trailing != null) {
      rowChildren
        ..add(SizedBox(width: iconGap))
        ..add(
          SizedBox(
            width: sizing.iconSize,
            height: sizing.iconSize,
            child: widget.trailing,
          ),
        );
    }

    // Always wrap in ConstrainedBox — toggling wrappers conditionally would
    // change the widget tree's shape and force Flutter to unmount/remount
    // the AnimatedContainer below (losing its animation state) whenever
    // `minWidth` transitions between null and a value. With a constant
    // wrapper, only the constraints value updates in place.
    //
    // The default `BoxConstraints()` has `minWidth: 0` and is effectively a
    // no-op pass-through, so callers that leave `minWidth` null keep the
    // pre-existing fully-intrinsic behavior.
    final pill = ConstrainedBox(
      constraints: widget.minWidth != null
          ? BoxConstraints(minWidth: widget.minWidth!)
          : const BoxConstraints(),
      child: AnimatedContainer(
        duration: isGhost ? Duration.zero : const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        height: height,
        decoration: ShapeDecoration(
          color: currentBg,
          shape: StadiumBorder(
            side: borderWidth == 0
                ? BorderSide.none
                : BorderSide(color: borderColor, width: borderWidth),
          ),
        ),
        padding: contentPadding,
        child: IconTheme.merge(
          data: IconThemeData(color: labelColor, size: sizing.iconSize),
          child: Row(
            mainAxisSize: widget.constrainContent
                ? MainAxisSize.max
                : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: rowChildren,
          ),
        ),
      ),
    );

    final focusRingWidth = widget.size == AppButtonSize.small ? 1.5 : 2.0;
    final focusRingColor =
        widget.focusRingColor ??
        (_hovered ? palette.focusRingHover : palette.focusRing);
    final focusRingOutset = switch (widget.variant) {
      AppButtonVariant.primary =>
        widget.size == AppButtonSize.large ? 3.5 : 3.0,
      AppButtonVariant.destructive => 3.5,
      AppButtonVariant.secondary || AppButtonVariant.ghost => 2.0,
    };

    // Keep the stack's layout size equal to the pill's design height and
    // paint the focus ring outside via overflow. Reserving outer padding
    // here would inflate the button's real layout box by 4px.
    final focusShell = Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      fit: widget.expand ? StackFit.passthrough : StackFit.loose,
      children: [
        pill,
        Positioned(
          left: -focusRingOutset,
          top: -focusRingOutset,
          right: -focusRingOutset,
          bottom: -focusRingOutset,
          child: IgnorePointer(
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOut,
              opacity: (_focused && _enabled) ? 1.0 : 0.0,
              child: DecoratedBox(
                decoration: ShapeDecoration(
                  shape: StadiumBorder(
                    side: BorderSide(
                      color: focusRingColor,
                      width: focusRingWidth,
                      strokeAlign: BorderSide.strokeAlignOutside,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );

    final pointer = MouseRegion(
      cursor: _enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: _enabled ? (_) => _setHovered(true) : null,
      onExit: _enabled ? (_) => _setHovered(false) : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: _enabled ? (_) => _setPressed(true) : null,
        onTapUp: _enabled
            ? (_) {
                _setPressed(false);
                widget.onPressed!.call();
              }
            : null,
        onTapCancel: _enabled ? () => _setPressed(false) : null,
        child: focusShell,
      ),
    );

    return Focus(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      canRequestFocus: _enabled,
      onFocusChange: _handleFocusChange,
      onKeyEvent: _handleKeyEvent,
      child: pointer,
    );
  }

  /// Keyboard activation — mirrors standard button behavior in browsers and
  /// desktop toolkits: Space and Enter (including numpad Enter) activate the
  /// focused button. Pressed state tracks key-down so the fill visibly
  /// reacts while the key is held; the actual tap callback fires on key-up
  /// to match how `onTapUp` behaves for mouse clicks.
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (!_enabled) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final isActivate =
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.space;
    if (!isActivate) return KeyEventResult.ignored;

    if (event is KeyDownEvent) {
      _setPressed(true);
      return KeyEventResult.handled;
    }
    if (event is KeyUpEvent) {
      if (_pressed) {
        _setPressed(false);
        widget.onPressed?.call();
      }
      return KeyEventResult.handled;
    }
    // KeyRepeatEvent — swallow to prevent holding Enter from firing
    // `onPressed` multiple times.
    return KeyEventResult.handled;
  }
}
