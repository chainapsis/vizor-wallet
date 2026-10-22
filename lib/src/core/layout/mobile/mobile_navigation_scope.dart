import 'package:flutter/widgets.dart';
import '../../navigation/mobile_sidebar_exit.dart';

/// Runtime window layout never changes the build-time mobile design tokens.
enum MobileNavigationMode { bottomTabs, systemSideTabs, sidebar }

/// The router stays mounted while this controller delegates to its existing
/// StatefulNavigationShell. No branch history is recreated on a resize.
class MobileBranchNavigation {
  Object? _owner;
  ValueChanged<String>? _select;

  void attach(Object owner, ValueChanged<String> select) {
    _owner = owner;
    _select = select;
  }

  void detach(Object owner) {
    if (!identical(owner, _owner)) return;
    _owner = null;
    _select = null;
  }

  bool select(String path) {
    final select = _select;
    if (select == null) return false;
    select(path);
    return true;
  }
}

class MobileNavigationScope extends InheritedWidget {
  const MobileNavigationScope({
    required this.mode,
    required this.navigation,
    required super.child,
    this.railRect,
    this.contentRect,
    this.availableContentRect,
    this.sidebarExit,
    super.key,
  });

  final MobileNavigationMode mode;
  final Rect? railRect;

  /// Content bounds in the wallet Navigator's coordinates, before animations.
  final Rect? contentRect;

  /// Safe contiguous bounds before the ordinary mobile page width cap.
  final Rect? availableContentRect;
  final MobileSidebarExitController? sidebarExit;
  final MobileBranchNavigation navigation;

  static MobileNavigationScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MobileNavigationScope>();

  static bool isSidebarOf(BuildContext context) =>
      maybeOf(context)?.mode == MobileNavigationMode.sidebar;

  // Only the expanded layout loses its bottom-bar clearance. The closed
  // system-side layout deliberately keeps the original content geometry.
  static double bottomClearanceOf(BuildContext context, double original) =>
      isSidebarOf(context)
      ? MediaQuery.paddingOf(context).bottom.clamp(24, double.infinity)
      : original;

  @override
  bool updateShouldNotify(MobileNavigationScope oldWidget) =>
      mode != oldWidget.mode ||
      railRect != oldWidget.railRect ||
      contentRect != oldWidget.contentRect ||
      availableContentRect != oldWidget.availableContentRect ||
      sidebarExit != oldWidget.sidebarExit ||
      navigation != oldWidget.navigation;
}
