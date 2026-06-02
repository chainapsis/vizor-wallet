import 'package:flutter/material.dart';

import '../../../core/layout/app_layout.dart';

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
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final padding = widget.padding;
    final horizontalPadding = EdgeInsets.only(
      left: padding.left,
      right: padding.right,
    );
    return _VotingPaneScrollbar(
      controller: _controller,
      child: ListView.separated(
        controller: _controller,
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
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _VotingPaneScrollbar(
      controller: _controller,
      child: SingleChildScrollView(
        controller: _controller,
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
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _VotingPaneScrollbar(
      controller: _controller,
      child: SingleChildScrollView(
        controller: _controller,
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

class _VotingPaneScrollbar extends StatefulWidget {
  const _VotingPaneScrollbar({required this.controller, required this.child});

  final ScrollController controller;
  final Widget child;

  @override
  State<_VotingPaneScrollbar> createState() => _VotingPaneScrollbarState();
}

class _VotingPaneScrollbarState extends State<_VotingPaneScrollbar> {
  bool _isHovered = false;
  bool _canScroll = false;

  @override
  void initState() {
    super.initState();
    _scheduleCanScrollUpdate();
  }

  @override
  void didUpdateWidget(covariant _VotingPaneScrollbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleCanScrollUpdate();
  }

  void _scheduleCanScrollUpdate() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _updateCanScroll();
    });
  }

  void _updateCanScroll() {
    final canScroll =
        widget.controller.hasClients &&
        widget.controller.position.maxScrollExtent > 0;
    if (canScroll == _canScroll) return;
    setState(() {
      _canScroll = canScroll;
    });
  }

  void _setHovered(bool hovered) {
    if (_isHovered == hovered) return;
    setState(() {
      _isHovered = hovered;
    });
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (_) {
        _scheduleCanScrollUpdate();
        return false;
      },
      child: MouseRegion(
        onEnter: (_) => _setHovered(true),
        onExit: (_) => _setHovered(false),
        child: Scrollbar(
          controller: widget.controller,
          thumbVisibility: isDesktopLayoutPlatform && _isHovered && _canScroll,
          child: widget.child,
        ),
      ),
    );
  }
}
