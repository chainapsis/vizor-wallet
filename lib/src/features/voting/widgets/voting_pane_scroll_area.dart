import 'package:flutter/material.dart';

import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_pane_scroll_scaffold.dart';

class VotingPaneListView extends StatefulWidget {
  const VotingPaneListView.separated({
    required this.maxWidth,
    required this.itemCount,
    required this.itemBuilder,
    required this.separatorBuilder,
    this.padding = EdgeInsets.zero,
    super.key,
  });

  final double maxWidth;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final IndexedWidgetBuilder separatorBuilder;
  final EdgeInsets padding;

  @override
  State<VotingPaneListView> createState() => _VotingPaneListViewState();
}

class _VotingPaneListViewState extends State<VotingPaneListView> {
  @override
  Widget build(BuildContext context) {
    final padding = widget.padding;
    final horizontalPadding = EdgeInsets.only(
      left: padding.left,
      right: padding.right,
    );
    // Shared pane overlay scrollbar (6px capsule, surface.scrollbarThumb).
    return AppPaneScrollbar(
      builder: (context, controller) => ListView.separated(
        controller: controller,
        primary: false,
        padding: EdgeInsets.only(top: padding.top, bottom: padding.bottom),
        itemCount: widget.itemCount,
        separatorBuilder: (context, index) => _centeredTrack(
          maxWidth: widget.maxWidth,
          padding: horizontalPadding,
          child: widget.separatorBuilder(context, index),
        ),
        itemBuilder: (context, index) => _centeredTrack(
          maxWidth: widget.maxWidth,
          padding: horizontalPadding,
          child: widget.itemBuilder(context, index),
        ),
      ),
    );
  }
}

class VotingPaneScrollView extends StatefulWidget {
  const VotingPaneScrollView({
    required this.maxWidth,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.scrollPadding = EdgeInsets.zero,
    super.key,
  });

  final double maxWidth;
  final Widget child;
  final EdgeInsets padding;
  final EdgeInsets scrollPadding;

  @override
  State<VotingPaneScrollView> createState() => _VotingPaneScrollViewState();
}

class _VotingPaneScrollViewState extends State<VotingPaneScrollView> {
  @override
  Widget build(BuildContext context) {
    return AppPaneScrollbar(
      builder: (context, controller) => SingleChildScrollView(
        controller: controller,
        primary: false,
        padding: widget.scrollPadding,
        child: _centeredTrack(
          maxWidth: widget.maxWidth,
          padding: widget.padding,
          child: widget.child,
        ),
      ),
    );
  }
}

class VotingPaneCenteredScrollView extends StatefulWidget {
  const VotingPaneCenteredScrollView({
    required this.maxWidth,
    required this.child,
    this.minHeight = 0,
    this.padding = EdgeInsets.zero,
    super.key,
  });

  final double maxWidth;
  final double minHeight;
  final Widget child;
  final EdgeInsets padding;

  @override
  State<VotingPaneCenteredScrollView> createState() =>
      _VotingPaneCenteredScrollViewState();
}

class _VotingPaneCenteredScrollViewState
    extends State<VotingPaneCenteredScrollView> {
  @override
  Widget build(BuildContext context) {
    return AppPaneScrollbar(
      builder: (context, controller) => SingleChildScrollView(
        controller: controller,
        primary: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: widget.minHeight),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: widget.maxWidth),
              child: Padding(padding: widget.padding, child: widget.child),
            ),
          ),
        ),
      ),
    );
  }
}

/// Standard full-pane voting loading indicator: a centered
/// [CircularProgressIndicator] filling the content area. Use this for every
/// full-pane async-loading branch in the voting feature so the spinner
/// treatment (and any future skeleton/token the redesign specifies) lives in
/// one place. The toolbar band, where a screen keeps one present during
/// loading, is rendered by the calling screen — this widget is just the
/// content-area spinner. Intentionally not used for the inline indicators
/// (voting-power meta, step-row progress bubble), whose size/stroke differ.
class VotingPaneLoading extends StatelessWidget {
  const VotingPaneLoading({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}

/// Renders a non-data pane state ([child] — a loading spinner, error, or
/// empty message) below the standard 48px [AppPaneToolbar] band, so every
/// voting pane screen keeps a back affordance and anchors its loading/error
/// content to the same region the data state occupies. The data branches keep
/// rendering their own toolbar; use this only for the toolbar-less states.
class VotingPaneStateView extends StatelessWidget {
  const VotingPaneStateView({
    required this.child,
    this.backLinkMinWidth = 0,
    super.key,
  });

  final Widget child;
  final double backLinkMinWidth;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppPaneToolbar(backLinkMinWidth: backLinkMinWidth),
        Expanded(child: child),
      ],
    );
  }
}

Widget _centeredTrack({
  required double maxWidth,
  required EdgeInsets padding,
  required Widget child,
}) {
  return Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Padding(padding: padding, child: child),
    ),
  );
}
