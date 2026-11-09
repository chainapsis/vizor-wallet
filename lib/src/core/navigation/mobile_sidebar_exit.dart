import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../layout/mobile/mobile_navigation_scope.dart';

/// Screen-owned permission and cleanup for the persistent expanded sidebar.
/// Unlike a back press, a sidebar selection leaves the entire current flow.
class MobileSidebarExitController extends ChangeNotifier {
  final _entries = <_ExitEntry>[];
  bool _scheduled = false;
  bool _disposed = false;
  bool busy = false;

  List<_ExitEntry> _current(String path) => _entries
      .where((entry) => entry.path == path && entry.route.isCurrent)
      .toList();

  /// Route identity protects against a newer payload replacing the same URI.
  Object? routeIdentity(String path) => _current(path).firstOrNull?.route;

  bool canNavigate(String path, {required bool requiresPolicy}) {
    final entries = _current(path);
    return !busy &&
        (entries.isEmpty
            ? !requiresPolicy
            : entries.every((entry) => entry.scope.canNavigate));
  }

  bool canSwitchAccount(String path, {required bool requiresPolicy}) {
    final entries = _current(path);
    return !busy &&
        (entries.isEmpty
            ? !requiresPolicy
            : entries.every((entry) => entry.scope.canSwitchAccount));
  }

  Future<bool> prepareLeave(String path, {required bool requiresPolicy}) async {
    if (!canNavigate(path, requiresPolicy: requiresPolicy)) return false;
    final entries = _current(path);
    busy = true;
    _changed();
    try {
      for (final entry in entries) {
        if (!await (entry.scope.onExit?.call() ?? Future.value(true))) {
          return false;
        }
      }
      return true;
    } finally {
      busy = false;
      _changed();
    }
  }

  void _changed() {
    if (_scheduled || _disposed) return;
    _scheduled = true;
    WidgetsBinding.instance.ensureVisualUpdate();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!_disposed) notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _entries.clear();
    super.dispose();
  }
}

/// No effect outside the adaptive wallet shell, including compact navigation.
/// Account changes are separate: a cancellable editor need not allow its
/// active account to change while it remains mounted.
class MobileSidebarExitScope extends StatefulWidget {
  const MobileSidebarExitScope({
    required this.child,
    this.canNavigate = true,
    this.canSwitchAccount = false,
    this.onExit,
    super.key,
  });
  final Widget child;
  final bool canNavigate;
  final bool canSwitchAccount;
  final Future<bool> Function()? onExit;

  @override
  State<MobileSidebarExitScope> createState() => _MobileSidebarExitScopeState();
}

class _ExitEntry {
  _ExitEntry(this.path, this.route, this.scope);
  final String path;
  final ModalRoute<dynamic> route;
  MobileSidebarExitScope scope;
}

class _MobileSidebarExitScopeState extends State<MobileSidebarExitScope> {
  MobileSidebarExitController? _controller;
  _ExitEntry? _entry;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = MobileNavigationScope.maybeOf(context)?.sidebarExit;
    final route = ModalRoute.of(context);
    if (identical(controller, _controller) && identical(route, _entry?.route)) {
      return;
    }
    _detach();
    if (controller == null || route == null) return;
    final String path;
    try {
      path = GoRouterState.of(context).matchedLocation;
    } on GoError {
      // An inner non-router Navigator can own a scanner/modal. Its outer
      // owner already supplies the policy for the actual wallet route.
      return;
    }
    _controller = controller;
    _entry = _ExitEntry(path, route, widget);
    controller._entries.add(_entry!);
    controller._changed();
  }

  @override
  void didUpdateWidget(covariant MobileSidebarExitScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    _entry?.scope = widget;
    if (oldWidget.canNavigate != widget.canNavigate ||
        oldWidget.canSwitchAccount != widget.canSwitchAccount) {
      _controller?._changed();
    }
  }

  void _detach() {
    if (_entry != null) {
      _controller?._entries.remove(_entry);
      _controller?._changed();
    }
    _controller = null;
    _entry = null;
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
