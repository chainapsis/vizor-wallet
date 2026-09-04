import 'package:flutter/widgets.dart';

/// Whether nothing sits over [context]'s route in any navigator up to the
/// root. A branch page's own `isCurrent` stays true under a root-navigator
/// sheet, so the walk continues past each enclosing navigator.
bool isRouteTopmost(BuildContext context) {
  var route = ModalRoute.of(context);
  while (route != null) {
    if (!route.isCurrent) return false;
    final navigatorContext = route.navigator?.context;
    if (navigatorContext == null) return true;
    route = ModalRoute.of(navigatorContext);
  }
  return true;
}
