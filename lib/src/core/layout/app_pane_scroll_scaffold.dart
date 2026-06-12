import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';

/// Shared desktop Trailing Pane scroll scaffold.
///
/// Implements the pane scroll model verified across the Figma desktop
/// windows (About / Settings / Activity / Endpoint / Secret phrase):
///
/// * The pane scrolls as ONE full-height surface. The 48px page [toolbar]
///   (back-link band) is pinned at the pane top and content scrolls
///   underneath it; the scroll content is top-padded by [toolbarHeight] so
///   nothing hides under the band at rest.
/// * The scrollbar is an overlay spanning the FULL pane height — toolbar
///   band included — pinned at the right pane edge. Per the Figma Scrollbar
///   component (2915:219497): 18px transparent track (nothing is painted in
///   the gutter), 6px capsule thumb centered in the track (6px inset on both
///   sides), 12px top/bottom thumb end margins.
/// * The thumb uses the solid `surface.scrollbarThumb` token (`#393E3E`
///   dark / `#E1E1E1` light). The design defines no hover/pressed thumb
///   styles.
/// * The scrollbar is hidden when the content fits (the design hides the
///   instance on non-scrolling screens) and otherwise shows while the
///   pointer hovers the pane, mirroring the Mac OS Window "Show Scroll"
///   boolean.
class AppPaneScrollScaffold extends StatefulWidget {
  const AppPaneScrollScaffold({
    required this.toolbar,
    required this.child,
    this.controller,
    this.padding,
    super.key,
  });

  /// Pinned toolbar band, typically an `AppPaneToolbar`. Laid out at the
  /// pane top with [toolbarHeight]; its transparent regions let the scrolled
  /// content show through and stay clickable.
  final Widget toolbar;

  /// Scroll content. It is laid out with a minimum height equal to the
  /// visible area below the toolbar band, so consumers can vertically
  /// center (`Center`) or pin to the top (`Align(topCenter)`) themselves.
  final Widget child;

  /// Optional external scroll controller. When null the scaffold manages
  /// its own.
  final ScrollController? controller;

  /// Extra content padding inside the scroll view, applied in addition to
  /// the [toolbarHeight] top reserve (e.g. a measured bottom reserve for a
  /// floating bar).
  final EdgeInsetsGeometry? padding;

  /// Height of the pinned toolbar band. Matches `AppPaneToolbar`'s default
  /// height.
  static const double toolbarHeight = 48;

  /// Full overlay track width: 6px thumb + 6px inset on each side.
  static const double scrollbarTrackWidth = 18;

  static const Key scrollbarKey = ValueKey('app_pane_scrollbar');
  static const Key scrollViewKey = ValueKey('app_pane_scroll_view');

  @override
  State<AppPaneScrollScaffold> createState() => _AppPaneScrollScaffoldState();
}

class _AppPaneScrollScaffoldState extends State<AppPaneScrollScaffold> {
  @override
  Widget build(BuildContext context) {
    final userPadding = (widget.padding ?? EdgeInsets.zero).resolve(
      Directionality.of(context),
    );
    final contentPadding =
        const EdgeInsets.only(top: AppPaneScrollScaffold.toolbarHeight) +
        userPadding;

    return LayoutBuilder(
      builder: (context, constraints) {
        final minHeight = constraints.hasBoundedHeight
            ? math.max(
                0.0,
                constraints.maxHeight -
                    AppPaneScrollScaffold.toolbarHeight -
                    userPadding.vertical,
              )
            : 0.0;
        return Stack(
          fit: StackFit.expand,
          children: [
            // Full-pane scroll surface. The scrollbar wraps the whole pane
            // area, so its overlay track spans the full pane height
            // (toolbar band included), pinned at the right edge.
            AppPaneScrollbar(
              controller: widget.controller,
              scrollbarKey: AppPaneScrollScaffold.scrollbarKey,
              builder: (context, controller) => SingleChildScrollView(
                key: AppPaneScrollScaffold.scrollViewKey,
                controller: controller,
                padding: contentPadding,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: minHeight),
                  child: widget.child,
                ),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: AppPaneScrollScaffold.toolbarHeight,
              child: widget.toolbar,
            ),
          ],
        );
      },
    );
  }
}

/// The pane overlay scrollbar on its own, for panes that bring their own
/// scroll view (e.g. the home backdrop pane's sliver scroll).
///
/// Same model as [AppPaneScrollScaffold]: 6px capsule thumb centered in an
/// 18px transparent gutter at the right edge, hidden while the content fits,
/// shown while the pointer hovers the pane. The [builder] receives the
/// controller the scrollbar tracks; attach it to the scroll view.
class AppPaneScrollbar extends StatefulWidget {
  const AppPaneScrollbar({
    required this.builder,
    this.controller,
    this.scrollbarKey,
    super.key,
  });

  /// Builds the scroll view; must attach [ScrollController] to it.
  final Widget Function(BuildContext context, ScrollController controller)
  builder;

  /// Optional external scroll controller. When null the scrollbar manages
  /// its own.
  final ScrollController? controller;

  /// Key applied to the underlying [RawScrollbar] (for tests).
  final Key? scrollbarKey;

  @override
  State<AppPaneScrollbar> createState() => _AppPaneScrollbarState();
}

class _AppPaneScrollbarState extends State<AppPaneScrollbar> {
  late final ScrollController _internalController;
  bool _isHovered = false;
  bool _canScroll = false;

  ScrollController get _effectiveController =>
      widget.controller ?? _internalController;

  @override
  void initState() {
    super.initState();
    _internalController = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _updateCanScroll();
    });
  }

  @override
  void didUpdateWidget(covariant AppPaneScrollbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _updateCanScroll();
    });
  }

  @override
  void dispose() {
    _internalController.dispose();
    super.dispose();
  }

  void _updateCanScroll() {
    final controller = _effectiveController;
    if (!controller.hasClients) return;
    final canScroll = controller.positions.any(
      (position) =>
          position.hasContentDimensions && position.maxScrollExtent > 0,
    );
    if (canScroll == _canScroll) return;
    setState(() {
      _canScroll = canScroll;
    });
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (_) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _updateCanScroll();
        });
        return false;
      },
      child: MouseRegion(
        onEnter: (_) {
          if (_isHovered) return;
          setState(() {
            _isHovered = true;
          });
        },
        onExit: (_) {
          if (!_isHovered) return;
          setState(() {
            _isHovered = false;
          });
        },
        child: RawScrollbar(
          key: widget.scrollbarKey,
          controller: _effectiveController,
          thumbVisibility: _isHovered && _canScroll,
          thickness: 6,
          radius: const Radius.circular(AppRadii.full),
          crossAxisMargin: 6,
          mainAxisMargin: 12,
          thumbColor: context.colors.surface.scrollbarThumb,
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(
              context,
            ).copyWith(scrollbars: false),
            child: widget.builder(context, _effectiveController),
          ),
        ),
      ),
    );
  }
}
