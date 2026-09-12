import 'package:flutter/widgets.dart';

/// Gives a modal mounted above the router its own [Overlay] ancestor for
/// tooltips and text selection. Keep the routed background outside this scope
/// so opening the modal does not remount the underlying screen.
class AppModalOverlayScope extends StatefulWidget {
  const AppModalOverlayScope({required this.child, super.key});

  final Widget child;

  @override
  State<AppModalOverlayScope> createState() => _AppModalOverlayScopeState();
}

class _AppModalOverlayScopeState extends State<AppModalOverlayScope> {
  // initialEntries is read once; always render the current child.
  late final OverlayEntry _entry = OverlayEntry(builder: (_) => widget.child);

  @override
  void didUpdateWidget(covariant AppModalOverlayScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.child, widget.child)) _entry.markNeedsBuild();
  }

  @override
  Widget build(BuildContext context) => Overlay(initialEntries: [_entry]);
}
