import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';
import 'app_icon.dart';

/// A floating action menu surface (the visual "dropdown" shown on a row's
/// overflow button).
///
/// ## Auto-flip / edge containment
///
/// Call sites anchor this menu with a `CompositedTransformFollower` that uses a
/// *fixed* downward offset from the trigger button. That follower has no
/// awareness of the overlay/pane bounds, so a menu opened on a row near the
/// bottom of the pane would paint past the bottom edge and clip.
///
/// To keep call sites unchanged, the containment logic lives here: after the
/// menu lays out, [AppContextMenu] measures its own global rectangle against
/// the ambient [Overlay] bounds (falling back to the [MediaQuery] screen size)
/// and self-corrects via an internal [Transform.translate]:
///
/// * **Vertical overflow → flip upward.** If the menu's natural bottom would
///   spill past the available bottom edge, the whole menu is translated up so
///   it opens *above* the anchor instead of below it. Flipping is preferred
///   over clamping; clamping the top edge is only a last resort if the flipped
///   placement would itself overflow the top.
/// * **Horizontal overflow → shift in-bounds.** If the menu's left/right edge
///   spills past the available horizontal edge, it is shifted just enough to
///   sit inside the bounds. (Both current call sites edge-align the menu to the
///   trigger, so a clamp keeps the menu attached to the button; a horizontal
///   flip is unnecessary.)
///
/// When the menu already fits, the applied correction is exactly [Offset.zero],
/// so the default placement is byte-identical to a plain (non-flipping) menu —
/// no layout, hit-test, or `getTopLeft` difference, and no visible shift.
class AppContextMenu extends StatefulWidget {
  const AppContextMenu({
    required this.children,
    this.width = 160,
    this.anchorSpan = _defaultAnchorSpan,
    this.edgeMargin = AppSpacing.xs,
    super.key,
  });

  final List<Widget> children;
  final double width;

  /// Vertical distance, in logical pixels, from the trigger button's top edge
  /// down to this menu's natural top edge. Used when flipping the menu upward
  /// so the flipped menu clears the trigger by the same gap it uses when
  /// opening downward. Defaults to the follower gap used by the call sites
  /// (button height + the `Offset(0, 22)` drop), which keeps a flipped menu
  /// visually symmetric with a downward one.
  final double anchorSpan;

  /// Minimum gap kept between the menu and the containing edge when it has to
  /// shift or clamp to stay in bounds.
  final double edgeMargin;

  /// Button height (20) + follower drop (22). See [anchorSpan].
  static const double _defaultAnchorSpan = 42;

  @override
  State<AppContextMenu> createState() => _AppContextMenuState();
}

class _AppContextMenuState extends State<AppContextMenu> {
  /// Correction applied to keep the menu inside the available bounds.
  /// [Offset.zero] means "fits as anchored" — the default, byte-identical path.
  Offset _correction = Offset.zero;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reposition());
  }

  @override
  void didUpdateWidget(AppContextMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Item set / sizing can change the menu height; re-measure next frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => _reposition());
  }

  void _reposition() {
    if (!mounted) return;

    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return;

    final bounds = _availableBounds();
    if (bounds == null) return;

    // The applied correction is a [Transform.translate], which offsets the
    // *painted child* but leaves this render box's own origin untouched. So
    // `localToGlobal(Offset.zero)` always reports the natural (un-flipped)
    // top-left regardless of the current correction — measurement is stable and
    // idempotent across repeated reposition passes.
    final naturalTopLeft = renderObject.localToGlobal(Offset.zero);
    final naturalRect = naturalTopLeft & renderObject.size;

    final correction = _computeCorrection(naturalRect, bounds);
    if ((correction - _correction).distanceSquared < 0.01) return;
    setState(() => _correction = correction);
  }

  /// The rectangle (in global coordinates) the menu must stay inside.
  Rect? _availableBounds() {
    final overlay = Overlay.maybeOf(context);
    final overlayBox = overlay?.context.findRenderObject();
    if (overlayBox is RenderBox && overlayBox.hasSize) {
      final topLeft = overlayBox.localToGlobal(Offset.zero);
      return topLeft & overlayBox.size;
    }

    final mediaSize = MediaQuery.maybeSizeOf(context);
    if (mediaSize != null) return Offset.zero & mediaSize;
    return null;
  }

  Offset _computeCorrection(Rect natural, Rect bounds) {
    var dx = 0.0;
    var dy = 0.0;

    // --- Vertical: prefer flipping upward over clamping ---
    final overflowsBottom = natural.bottom > bounds.bottom - widget.edgeMargin;
    if (overflowsBottom) {
      // Flip: translate up so the menu opens above the anchor. The anchor's top
      // edge sits [anchorSpan] above the menu's natural top; mirroring across it
      // puts the flipped menu's bottom [anchorSpan] above that same anchor top.
      final flippedDy = -(natural.height + widget.anchorSpan);
      final flippedTop = natural.top + flippedDy;
      if (flippedTop >= bounds.top + widget.edgeMargin) {
        dy = flippedDy;
      } else {
        // Last resort: the menu is taller than the space on either side, so
        // clamp it to the bottom edge (still better than clipping off-screen).
        dy = (bounds.bottom - widget.edgeMargin) - natural.bottom;
      }
    }

    // --- Horizontal: shift just enough to stay in bounds ---
    if (natural.right > bounds.right - widget.edgeMargin) {
      dx = (bounds.right - widget.edgeMargin) - natural.right;
    }
    if (natural.left + dx < bounds.left + widget.edgeMargin) {
      dx = (bounds.left + widget.edgeMargin) - natural.left;
    }

    return Offset(dx, dy);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    final surface = DefaultTextStyle.merge(
      style: const TextStyle(decoration: TextDecoration.none),
      child: SizedBox(
        width: widget.width,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.background.inverse,
            borderRadius: BorderRadius.circular(AppRadii.small),
            border: Border.all(color: colors.border.subtleOpacity),
            boxShadow: appContextMenuShadow,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xxs,
              vertical: AppSpacing.xs,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: widget.children,
            ),
          ),
        ),
      ),
    );

    // Offset.zero is a no-op transform: identical layout/hit-test/getTopLeft to
    // the un-flipped menu, so the "has room" path stays byte-identical.
    return Transform.translate(offset: _correction, child: surface);
  }
}

class AppContextMenuItem extends StatefulWidget {
  const AppContextMenuItem({
    required this.iconName,
    required this.label,
    required this.onTap,
    this.destructive = false,
    super.key,
  });

  final String iconName;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  @override
  State<AppContextMenuItem> createState() => _AppContextMenuItemState();
}

class _AppContextMenuItemState extends State<AppContextMenuItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final itemColor = widget.destructive
        ? colors.text.destructiveLight
        : colors.text.inverse;
    final iconColor = widget.destructive
        ? colors.icon.destructiveLight
        : colors.icon.inverse;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          height: 26,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xs,
            vertical: AppSpacing.xxs,
          ),
          decoration: BoxDecoration(
            // The menu sits on the inverse surface, so the regular hover
            // tint (a dark alpha in light mode) is invisible here; the
            // inverse-opacity tint flips with the surface in both themes.
            color: _isHovered ? colors.border.inverseOpacity : null,
            borderRadius: BorderRadius.circular(AppSpacing.xxs),
          ),
          child: Row(
            children: [
              AppIcon(
                widget.iconName,
                size: AppIconSize.medium,
                color: iconColor,
              ),
              const SizedBox(width: AppSpacing.xxs),
              Expanded(
                child: Text(
                  widget.label,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.labelMedium.copyWith(color: itemColor),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _setHovered(bool value) {
    if (!mounted) return;
    if (_isHovered == value) return;
    setState(() => _isHovered = value);
  }
}

class AppContextMenuDivider extends StatelessWidget {
  const AppContextMenuDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs / 2),
      child: SizedBox(
        height: 1,
        width: double.infinity,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: context.colors.border.inverseOpacity,
          ),
        ),
      ),
    );
  }
}

const appContextMenuShadow = [
  BoxShadow(color: Color(0x0F000000), offset: Offset(0, 2), blurRadius: 8),
  BoxShadow(color: Color(0x08000000), offset: Offset(0, -6), blurRadius: 12),
  BoxShadow(color: Color(0x14000000), offset: Offset(0, 14), blurRadius: 28),
];
