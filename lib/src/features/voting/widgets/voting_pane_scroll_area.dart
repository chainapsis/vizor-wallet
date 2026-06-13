import 'package:flutter/material.dart';

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
