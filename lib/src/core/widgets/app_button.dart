import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';

/// Visual style variant of an [AppButton]. Mapped onto our semantic color
/// tokens — not onto Figma's variant naming (which calls primary "Accent").
///
/// `destructive` is intentionally omitted. The design system defines
/// `button.destructive` color tokens but the Figma Button component
/// (node 54:81) does not expose a destructive variant, so this enum
/// mirrors the component's actual surface. Add a value here if/when the
/// designer introduces a destructive variant in Figma.
enum AppButtonVariant { primary, secondary, ghost }

/// Vertical density. Both variants use the same icon size (16) and same
/// label family/weight; they differ in padding and label font size.
enum AppButtonSize { medium, small }

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

// Medium (default) button — the large CTA. Uses `labelMedium` (12px).
const _mediumSizing = _Sizing(
  height: 40,
  padding: EdgeInsets.symmetric(
    horizontal: AppSpacing.sm,
    vertical: AppSpacing.xs,
  ),
  gap: AppSpacing.xxs,
  iconSize: AppIconSize.medium,
  labelStyle: AppTypography.labelMedium,
);

// Small (compact) button — inline/dense actions. Uses `labelLarge` (14px).
// Counter-intuitive naming: Figma's Small button is *physically shorter*
// but carries the *larger* label size for readability inside the tight
// 24dp height. label-L's 18dp line-box technically overshoots the
// 16dp inner area by 2dp, but the overflow is leading / invisible
// empty space above and below the glyphs, so no clip is necessary.
const _smallSizing = _Sizing(
  height: 24,
  padding: EdgeInsets.all(AppSpacing.xxs),
  gap: AppSpacing.xxs,
  iconSize: AppIconSize.medium,
  labelStyle: AppTypography.labelLarge,
);

class _VariantPalette {
  const _VariantPalette({
    required this.bg,
    required this.bgHover,
    required this.bgPressed,
    required this.label,
    required this.focusRing,
  });

  final Color bg;
  final Color bgHover;
  final Color bgPressed;
  final Color label;
  final Color focusRing;
}

_VariantPalette _paletteFor(AppButtonVariant variant, AppColors c) {
  switch (variant) {
    case AppButtonVariant.primary:
      return _VariantPalette(
        bg: c.button.primary.bg,
        bgHover: c.button.primary.bgHover,
        bgPressed: c.button.primary.bgPressed,
        label: c.button.primary.label,
        focusRing: c.state.focusRingBrand,
      );
    case AppButtonVariant.secondary:
      return _VariantPalette(
        bg: c.button.secondary.bg,
        bgHover: c.button.secondary.bgHover,
        bgPressed: c.button.secondary.bgPressed,
        label: c.button.secondary.label,
        focusRing: c.state.focusRing,
      );
    case AppButtonVariant.ghost:
      // Ghost's visible base is transparent regardless of the nominal token
      // value — that way it composes correctly over any surface. Hover and
      // pressed fills are deliberately the same as secondary's per the
      // Figma spec (button/ghost/bg-hover references secondary/bg-hover).
      return _VariantPalette(
        bg: const Color(0x00000000),
        bgHover: c.button.secondary.bgHover,
        bgPressed: c.button.secondary.bgPressed,
        label: c.button.ghost.label,
        focusRing: c.state.focusRing,
      );
  }
}

/// A pill-shaped button with four style variants and two size variants.
///
/// Width and height are intrinsic — the button wraps the leading icon +
/// label + trailing icon and centers them both axes. Only the pill radius
/// is fixed; padding and typography determine the rest.
///
/// States handled:
/// * default / hover / pressed — ambient fill swaps via [_Sizing] + palette
/// * focused — 2dp ring painted outside the pill using the per-variant
///   focus-ring color (brand purple for primary, neutral for the rest)
/// * disabled — `onPressed == null` dims the whole widget to 50% and
///   removes pointer/focus interaction. TODO(theme): Figma does not define
///   a disabled token; replace the opacity hack once the design spec adds
///   one.
class AppButton extends StatefulWidget {
  const AppButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.variant = AppButtonVariant.primary,
    this.size = AppButtonSize.medium,
    this.leading,
    this.trailing,
    this.minWidth,
    this.focusNode,
    this.autofocus = false,
  });

  /// Tap handler. `null` disables the button.
  final VoidCallback? onPressed;

  /// Label content. Usually a [Text] but any widget is allowed (e.g. a
  /// [Row] with a badge). The size's [TextStyle] is merged in as the
  /// ambient [DefaultTextStyle].
  final Widget child;

  final AppButtonVariant variant;
  final AppButtonSize size;

  /// Optional widget shown before [child]. Auto-sized to 16×16 and tinted
  /// to the label color via [IconTheme].
  final Widget? leading;

  /// Optional widget shown after [child]. Same auto-sizing/tint as [leading].
  final Widget? trailing;

  /// Optional minimum width. Default (`null`) keeps the button fully
  /// intrinsic — content drives size. Callers opt in to a floor when a
  /// specific screen or layout demands a consistent button width.
  final double? minWidth;

  final FocusNode? focusNode;
  final bool autofocus;

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
    final sizing = widget.size == AppButtonSize.medium
        ? _mediumSizing
        : _smallSizing;

    // Fill priority: pressed > hover > default. Disabled skips all of this
    // (we dim the whole widget via Opacity instead).
    final Color currentBg = !_enabled
        ? palette.bg
        : _pressed
        ? palette.bgPressed
        : _hovered
        ? palette.bgHover
        : palette.bg;

    // Figma quirk: Primary + Medium swaps label to text/inverse whenever
    // the button is in a hover/focus state. Small does NOT swap and other
    // variants do not swap either. Faithfully reproduced here; flagged for
    // design review in case this was an editor oversight.
    final bool swapLabel =
        widget.variant == AppButtonVariant.primary &&
        widget.size == AppButtonSize.medium &&
        _enabled &&
        (_hovered || _focused);
    final Color labelColor = swapLabel ? colors.text.inverse : palette.label;

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
        ..add(SizedBox(width: sizing.gap));
    }
    rowChildren.add(
      DefaultTextStyle.merge(
        style: sizing.labelStyle.copyWith(color: labelColor),
        child: widget.child,
      ),
    );
    if (widget.trailing != null) {
      rowChildren
        ..add(SizedBox(width: sizing.gap))
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
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        height: sizing.height,
        decoration: ShapeDecoration(
          color: currentBg,
          shape: const StadiumBorder(),
        ),
        padding: sizing.padding,
        child: IconTheme.merge(
          data: IconThemeData(color: labelColor, size: sizing.iconSize),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: rowChildren,
          ),
        ),
      ),
    );

    // Always reserve a small gap on every side so the ring can be painted
    // without shifting the button's layout when focus toggles. The 2-pixel
    // inset is tighter than AppSpacing's smallest step (4), so it stays as
    // a literal.
    //
    // The ring is rendered via a [Stack] overlay rather than via a
    // containing `decoration` — letting the border live on the same
    // container as the padding causes Flutter to add the border's stroke
    // inset to the layout (`ShapeDecoration.padding == shape.dimensions`),
    // which produces a 1-pixel jitter every time focus toggles. With the
    // overlay approach, the ring paints independently of layout.
    final focusShell = Stack(
      alignment: Alignment.center,
      children: [
        Padding(padding: const EdgeInsets.all(2), child: pill),
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOut,
              opacity: (_focused && _enabled) ? 1.0 : 0.0,
              child: DecoratedBox(
                decoration: ShapeDecoration(
                  shape: StadiumBorder(
                    side: BorderSide(color: palette.focusRing, width: 1),
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

    return Opacity(
      opacity: _enabled ? 1.0 : 0.5,
      child: Focus(
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        canRequestFocus: _enabled,
        onFocusChange: _handleFocusChange,
        onKeyEvent: _handleKeyEvent,
        child: pointer,
      ),
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
