import 'package:flutter/material.dart' show Material, showModalBottomSheet;
import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

import '../../theme/app_theme.dart';
import '../../widgets/app_icon.dart';

// ---------------------------------------------------------------------------
// Layout & motion tuning for the standard mobile sheet. Grouped here so the
// feel can be adjusted in one place.
// ---------------------------------------------------------------------------

/// Fraction of the screen height the sheet stops below the top, so the page
/// title stays visible behind it and the status bar is never covered.
/// Larger reveals more of the page; smaller makes the sheet taller.
const double _kTopGapFraction = 0.15;

/// Grabber pill dimensions.
const double _kGrabberWidth = 36;
const double _kGrabberHeight = 5;

/// Circular close button and its icon.
const double _kCloseButtonSize = 40;
const double _kCloseIconSize = 18;

/// Over-pull: furthest the sheet rubber-bands taller when dragged up, plus
/// how far the spring may overshoot that while settling.
const double _kMaxOverpull = 30;
const double _kOverpullOvershoot = 12;

/// Dismiss: downward drag distance / fling velocity past which releasing
/// dismisses, and how long the slide-off-screen close takes.
const double _kDismissDragThreshold = 110;
const double _kDismissFlingVelocity = 800;
const Duration _kDismissSlideDuration = Duration(milliseconds: 180);

/// Spring-back after an over-pull. Lower damping = livelier bounce;
/// 15.5 (ratio ~0.40) settles with a small overshoot.
const SpringDescription _kSpringBack = SpringDescription(
  mass: 1,
  stiffness: 380,
  damping: 15.5,
);
const double _kMaxSpringVelocity = 2000;

/// Floor height for a content-sized sheet, so short forms / empty states
/// don't render as a cramped sliver.
const double _kMinContentHeight = 400;

/// Over-pull height gain for a drag [value] (negative = pulled up), eased and
/// capped at the rubber-band limit plus its settle overshoot.
double _overpullStretch(double value) =>
    value < 0 ? (-value).clamp(0.0, _kMaxOverpull + _kOverpullOvershoot) : 0.0;

/// Downward slide for a drag [value] (positive = pulled down toward dismiss).
double _slideDown(double value) => value > 0 ? value : 0.0;

/// The tallest a sheet may stand: the full screen minus the top gap (so the
/// page title stays visible) and the keyboard inset.
double _sheetCapHeight(double screenHeight, double keyboardInset) =>
    screenHeight - keyboardInset - screenHeight * _kTopGapFraction;

/// Shows the standard mobile modal: a full-screen, edge-to-edge bottom
/// sheet. It rises from the bottom to just below the status bar, with the
/// top corners rounded and the bottom flush with the screen edge.
///
/// Dismiss by swiping down, tapping the scrim, Android back, or the
/// [MobileSheetScaffold] close button. Pair the [builder] with
/// [MobileSheetScaffold] for the grabber + header chrome and the
/// over-pull / drag-to-dismiss behavior.
///
/// This is the platform-standard counterpart to the floating
/// [showAppMobileSheet] card; new modals should adopt this presentation.
Future<T?> showMobileSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isDismissible = true,
}) {
  final colors = context.colors;
  return showModalBottomSheet<T>(
    context: context,
    isDismissible: isDismissible,
    isScrollControlled: true,
    // Root navigator so the sheet and its scrim cover the floating tab
    // bar (the shell paints the bar outside the branch navigators).
    useRootNavigator: true,
    // The scaffold draws its own surface, radius and grabber, so the
    // sheet itself is transparent with no default elevation.
    backgroundColor: const Color(0x00000000),
    elevation: 0,
    barrierColor: colors.background.neutralScrim,
    builder: builder,
  );
}

/// The chrome for a full-screen [showMobileSheet]: a top-rounded,
/// edge-to-edge surface that fills from just below the status bar to the
/// screen bottom, with a drag grabber, a header ([title] + a floating
/// close button or [trailing]) and the [child] body.
///
/// The top chrome (grabber + header) is the drag zone: pull up for a
/// rubber-band expand that springs back, pull down to dismiss. The body
/// owns its own padding; the scaffold supplies the surface, grabber,
/// header, keyboard avoidance and gesture behavior.
class MobileSheetScaffold extends StatefulWidget {
  const MobileSheetScaffold({
    required this.title,
    required this.child,
    this.trailing,
    this.onBack,
    this.expand = false,
    this.fillBody = false,
    this.formBody = false,
    super.key,
  });

  final String title;
  final Widget child;

  /// Right-aligned action. Defaults to a circular close button that pops
  /// the sheet.
  final Widget? trailing;

  /// When set, a back chevron is shown at the top-left (for a 2nd-level
  /// view inside the same sheet). The title shifts right to clear it.
  final VoidCallback? onBack;

  /// When true the sheet fills the screen (minus the top gap) and [child]
  /// must take an [Expanded]-friendly slot — for long, scrollable content
  /// like a list. When false (default) the sheet hugs [child]'s height for
  /// short forms; over-pull lifts it rather than expanding.
  final bool expand;

  /// Content-sized only: when true, [child] is stretched to a fixed (min)
  /// height and given an [Expanded]-friendly slot. Use for a body that owns
  /// its own scroll (e.g. a bounded `ListView` with a centered empty state)
  /// where the content has no single natural height to hug.
  final bool fillBody;

  /// Content-sized adaptive form: pair with a [MobileSheetFormBody] child.
  /// The sheet height follows the content across three levels — short
  /// content sits at the [_kMinContentHeight] floor with the body centered;
  /// taller content grows the sheet to hug it; content past the top-gap cap
  /// pins the sheet at full height and scrolls the body. In every case the
  /// [MobileSheetFormBody] actions stay pinned to the very bottom.
  final bool formBody;

  @override
  State<MobileSheetScaffold> createState() => _MobileSheetScaffoldState();
}

class _MobileSheetScaffoldState extends State<MobileSheetScaffold>
    with SingleTickerProviderStateMixin {
  /// Drag position: 0 at rest, negative when pulled up (expands), positive
  /// when pulled down (slides toward dismiss).
  late final AnimationController _overpull;
  double _rawDrag = 0;

  @override
  void initState() {
    super.initState();
    _overpull = AnimationController.unbounded(vsync: this);
  }

  @override
  void dispose() {
    _overpull.dispose();
    super.dispose();
  }

  void _onDragStart(DragStartDetails _) {
    _overpull.stop();
    _rawDrag = 0;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    _rawDrag += details.delta.dy;
    // Up: resisted over-pull (expands the sheet). Down: follow the finger
    // 1:1 toward dismiss.
    _overpull.value = _rawDrag < 0 ? -_rubberBand(-_rawDrag) : _rawDrag;
  }

  void _onDragEnd(DragEndDetails details) {
    final velocity = details.velocity.pixelsPerSecond.dy;
    // Dragged/flung down far enough → dismiss; otherwise spring back.
    if (_rawDrag > _kDismissDragThreshold ||
        velocity > _kDismissFlingVelocity) {
      _dismiss();
      return;
    }
    _overpull.animateWith(
      SpringSimulation(
        _kSpringBack,
        _overpull.value,
        0,
        velocity.clamp(-_kMaxSpringVelocity, _kMaxSpringVelocity),
      ),
    );
  }

  void _dismiss() {
    // Slide the rest of the way down, then pop — a continuous close rather
    // than snapping back before the route's exit transition.
    _overpull
        .animateTo(
          MediaQuery.of(context).size.height,
          duration: _kDismissSlideDuration,
          curve: Curves.easeIn,
        )
        .whenComplete(() {
          if (mounted) Navigator.of(context).pop();
        });
  }

  /// Asymptotic damping: tracks the finger early, eases to [_kMaxOverpull].
  double _rubberBand(double distance) =>
      _kMaxOverpull * (1 - 1 / (distance / _kMaxOverpull + 1));

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final media = MediaQuery.of(context);
    final keyboardInset = media.viewInsets.bottom;

    return widget.expand
        ? _buildExpanded(context, colors, media, keyboardInset)
        : _buildHugging(context, colors, keyboardInset);
  }

  /// Full-screen variant: fills the screen below a top gap, body lives in an
  /// [Expanded], and over-pull EXPANDS the sheet so it reveals more content
  /// with no bottom gap.
  Widget _buildExpanded(
    BuildContext context,
    AppColors colors,
    MediaQueryData media,
    double keyboardInset,
  ) {
    // Stop short of the very top (keeps the page title visible behind the
    // sheet, never covers the status bar). When the keyboard is open, shrink
    // by its height AND lift above it so the sheet fills the gap-to-keyboard
    // band instead of collapsing to the middle.
    final height = _sheetCapHeight(media.size.height, keyboardInset);
    final surface = _surface(
      colors,
      Expanded(child: widget.child),
      expand: true,
    );
    return AnimatedBuilder(
      animation: _overpull,
      builder: (context, sheet) {
        final value = _overpull.value;
        return Transform.translate(
          offset: Offset(0, _slideDown(value)),
          child: Padding(
            padding: EdgeInsets.only(bottom: keyboardInset),
            child: SizedBox(
              height: height + _overpullStretch(value),
              width: double.infinity,
              child: sheet,
            ),
          ),
        );
      },
      child: surface,
    );
  }

  /// Content-sized variant: hugs [child]'s height at the bottom. There's no
  /// extra content to reveal, so over-pull lifts the whole sheet (resisted)
  /// and springs back; pull-down still dismisses.
  Widget _buildHugging(
    BuildContext context,
    AppColors colors,
    double keyboardInset,
  ) {
    final media = MediaQuery.of(context);
    final screenHeight = media.size.height;
    // Read the home-indicator inset from the raw view (the modal zeroes
    // MediaQuery padding) so the hugging content clears it.
    final bottomSafe = MediaQueryData.fromView(View.of(context)).padding.bottom;
    return AnimatedBuilder(
      animation: _overpull,
      builder: (context, _) {
        final value = _overpull.value;
        // Up: grow the body's bottom padding so the sheet stretches taller
        // while staying anchored to the screen edge — the form lifts with the
        // finger and the sheet's own surface fills below it (no scrim gap).
        // Down: slide the whole sheet toward dismiss.
        final stretch = _overpullStretch(value);
        final slideDown = _slideDown(value);
        // The adaptive form sheet keeps its overpull as a height gain (the
        // floor and cap both grow with `stretch`) rather than bottom padding,
        // so the body re-centres in the taller surface. Other modes still pad
        // the bottom for the over-pull lift + home-indicator clearance.
        if (widget.formBody) {
          final effMax = _sheetCapHeight(screenHeight, keyboardInset) + stretch;
          final effMin = (_kMinContentHeight + stretch).clamp(0.0, effMax);
          final formSized = ConstrainedBox(
            constraints: BoxConstraints(maxHeight: effMax),
            child: _SheetFormMetrics(
              // The body only needs the floor↔cap slack to know how far it
              // may shrink below the cap before it must centre / pin.
              slack: effMax - effMin,
              child: _surface(
                colors,
                Padding(
                  padding: EdgeInsets.only(bottom: bottomSafe),
                  child: widget.child,
                ),
                expand: false,
                flexBody: true,
              ),
            ),
          );
          return Transform.translate(
            offset: Offset(0, slideDown),
            child: Padding(
              padding: EdgeInsets.only(bottom: keyboardInset),
              child: formSized,
            ),
          );
        }

        final body = Padding(
          padding: EdgeInsets.only(bottom: bottomSafe + stretch),
          child: widget.child,
        );

        final Widget sized;
        if (widget.fillBody) {
          // Give the body a fixed (min) height so a body that ends in
          // buttons keeps them pinned to the very bottom; the body itself
          // scrolls if its content is taller. Capped to stay below the top
          // gap and above the keyboard.
          final maxHeight = _sheetCapHeight(screenHeight, keyboardInset);
          final target = _kMinContentHeight + stretch;
          final fillHeight = target < maxHeight ? target : maxHeight;
          sized = SizedBox(
            height: fillHeight,
            width: double.infinity,
            child: _surface(colors, Expanded(child: body), expand: true),
          );
        } else {
          // Hug the content, but never below the min — and grow that min with
          // the over-pull so a short sheet still visibly stretches.
          sized = ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: _kMinContentHeight + stretch,
            ),
            child: SizedBox(
              width: double.infinity,
              child: _surface(colors, body, expand: false),
            ),
          );
        }
        return Transform.translate(
          offset: Offset(0, slideDown),
          child: Padding(
            padding: EdgeInsets.only(bottom: keyboardInset),
            child: sized,
          ),
        );
      },
    );
  }

  Widget _surface(
    AppColors colors,
    Widget body, {
    required bool expand,
    bool flexBody = false,
  }) {
    final hasBack = widget.onBack != null;
    final dragZone = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragStart: _onDragStart,
      onVerticalDragUpdate: _onDragUpdate,
      onVerticalDragEnd: _onDragEnd,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _SheetGrabber(),
          _SheetHeader(title: widget.title),
        ],
      ),
    );
    // The adaptive form body holds its own `Flexible` content slot, so it must
    // receive a bounded height — a bare non-flex child of a Column is given
    // unbounded main-axis constraints. `Flexible(loose)` bounds it to the
    // leftover height while still letting the sheet hug shorter content.
    final bodySlot = flexBody
        ? Flexible(fit: FlexFit.loose, child: body)
        : body;
    return Material(
      color: colors.background.base,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadii.xLarge),
        ),
      ),
      child: Stack(
        children: [
          Column(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            children: [dragZone, bodySlot],
          ),
          // Back chevron for a 2nd-level view, mirrored to the close button.
          if (hasBack)
            Positioned(
              top: AppSpacing.sm,
              left: AppSpacing.sm,
              child: _SheetCornerButton(
                semanticLabel: 'Back',
                iconName: AppIcons.chevronBackward,
                keyValue: 'mobile_sheet_back_button',
                onTap: widget.onBack!,
              ),
            ),
          Positioned(
            top: AppSpacing.sm,
            right: AppSpacing.sm,
            child:
                widget.trailing ??
                _SheetCornerButton(
                  semanticLabel: 'Close',
                  iconName: AppIcons.cross,
                  keyValue: 'mobile_sheet_close_button',
                  onTap: () => Navigator.of(context).pop(),
                ),
          ),
        ],
      ),
    );
  }
}

/// Body layout for a content-sized adaptive form sheet (use with
/// [MobileSheetScaffold] `formBody: true`): [content] occupies the space
/// above [actions], which stay pinned to the very bottom.
///
/// The body drives the sheet's height across three levels:
/// 1. **Short content** — the sheet rests at its [_kMinContentHeight] floor
///    and the content is vertically centred in the slack above the actions.
/// 2. **Medium content** — the sheet grows to hug the content exactly.
/// 3. **Tall content** — the sheet caps at the top-gap height and the content
///    scrolls; the actions remain pinned.
///
/// `Flexible(loose)` lets the body hug (levels 1–2) rather than fill, while a
/// floor derived from the scaffold's slack ([_SheetFormMetrics]) keeps the
/// content centred at the minimum height and the actions on the bottom edge.
class MobileSheetFormBody extends StatelessWidget {
  const MobileSheetFormBody({
    required this.content,
    required this.actions,
    super.key,
  });

  final Widget content;
  final Widget actions;

  @override
  Widget build(BuildContext context) {
    final slack = _SheetFormMetrics.of(context).slack;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Flexible(
          fit: FlexFit.loose,
          child: LayoutBuilder(
            builder: (context, constraints) {
              // `maxHeight` is the room left for the content after the actions
              // and chrome. Subtracting the slack yields the content-area
              // height when the sheet sits at its floor — the minimum the
              // scroll area must occupy so short content centres and the
              // actions stay pinned at the bottom.
              final contentFloor = (constraints.maxHeight - slack).clamp(
                0.0,
                constraints.maxHeight,
              );
              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: contentFloor),
                  // IntrinsicHeight lets the content centre within (or grow
                  // past) the floor without a flex child.
                  child: IntrinsicHeight(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [content],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        actions,
      ],
    );
  }
}

/// Carries the adaptive form sheet's floor↔cap slack from
/// [MobileSheetScaffold] down to its [MobileSheetFormBody], so the body can
/// compute the content-area floor without re-deriving the screen geometry.
class _SheetFormMetrics extends InheritedWidget {
  const _SheetFormMetrics({required this.slack, required super.child});

  final double slack;

  static _SheetFormMetrics of(BuildContext context) {
    final metrics = context
        .dependOnInheritedWidgetOfExactType<_SheetFormMetrics>();
    assert(metrics != null, 'MobileSheetFormBody requires formBody: true');
    return metrics!;
  }

  @override
  bool updateShouldNotify(_SheetFormMetrics oldWidget) =>
      slack != oldWidget.slack;
}

class _SheetGrabber extends StatelessWidget {
  const _SheetGrabber();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.s, bottom: AppSpacing.xs),
      child: Center(
        child: Container(
          key: const ValueKey('mobile_sheet_grabber'),
          width: _kGrabberWidth,
          height: _kGrabberHeight,
          decoration: BoxDecoration(
            color: colors.border.medium,
            borderRadius: BorderRadius.circular(AppRadii.full),
          ),
        ),
      ),
    );
  }
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      // Symmetric clearance for the absolute corner buttons keeps the title
      // horizontally centered whether or not a back chevron is present.
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.xs,
        AppSpacing.xl,
        AppSpacing.s,
      ),
      child: Text(
        title,
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.headlineSmall.copyWith(
          color: colors.text.accent,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

/// A circular top-corner sheet action (close or back), styled identically.
class _SheetCornerButton extends StatelessWidget {
  const _SheetCornerButton({
    required this.semanticLabel,
    required this.iconName,
    required this.keyValue,
    required this.onTap,
  });

  final String semanticLabel;
  final String iconName;
  final String keyValue;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      label: semanticLabel,
      button: true,
      child: GestureDetector(
        key: ValueKey(keyValue),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: _kCloseButtonSize,
          height: _kCloseButtonSize,
          decoration: BoxDecoration(
            color: colors.background.raised,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: AppIcon(
              iconName,
              size: _kCloseIconSize,
              color: colors.icon.accent,
            ),
          ),
        ),
      ),
    );
  }
}
