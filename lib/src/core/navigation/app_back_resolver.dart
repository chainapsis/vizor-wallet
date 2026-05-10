import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

class AppBackTarget {
  const AppBackTarget({
    required this.label,
    required this.fallbackPath,
    required this.preferPop,
  });

  final String label;
  final String fallbackPath;
  final bool preferPop;

  void navigate(BuildContext context) {
    if (preferPop && context.canPop()) {
      context.pop();
      return;
    }
    context.go(fallbackPath);
  }
}

class _RouteStackEntry {
  const _RouteStackEntry({required this.routePath, required this.location});

  final String routePath;
  final String location;
}

abstract final class AppBackResolver {
  static const _homeTarget = AppBackTarget(
    label: 'Home',
    fallbackPath: '/home',
    preferPop: false,
  );

  static const _routeLabels = <String, String>{
    '/home': 'Home',
    '/send': 'Send',
    '/send/review': 'Review',
    '/send/status': 'Status',
    '/receive': 'Receive',
    '/activity': 'Activity',
    '/activity/tx/:txid': 'Transaction',
    '/settings': 'Settings',
    '/settings/secret-passphrase': 'Secret Passphrase',
    '/settings/change-password': 'Change Password',
    '/settings/endpoint': 'Endpoint',
    '/import-keystone': 'Import Keystone',
  };

  static AppBackTarget resolve(BuildContext context) {
    final stack = _routeStackFor(context);
    final current = stack.isEmpty ? null : stack.last;
    if (_forcesHome(current)) return _homeTarget;
    if (!context.canPop()) return _homeTarget;

    final previous = stack.length >= 2 ? stack[stack.length - 2] : null;
    if (previous == null) {
      return const AppBackTarget(
        label: 'Back',
        fallbackPath: '/home',
        preferPop: true,
      );
    }

    return AppBackTarget(
      label: _labelFor(previous) ?? 'Back',
      fallbackPath: previous.location,
      preferPop: true,
    );
  }

  static bool _forcesHome(_RouteStackEntry? current) {
    if (current == null) return false;
    return current.routePath == '/send/status' ||
        current.location == '/send/status';
  }

  static List<_RouteStackEntry> _routeStackFor(BuildContext context) {
    final configuration = GoRouter.of(
      context,
    ).routerDelegate.currentConfiguration;
    final entries = <_RouteStackEntry>[];
    for (final match in configuration.matches) {
      _appendStackEntry(match, entries);
    }
    return entries;
  }

  static void _appendStackEntry(
    RouteMatchBase match,
    List<_RouteStackEntry> entries,
  ) {
    if (match is ImperativeRouteMatch) {
      final leaf = match.matches.lastOrNull;
      if (leaf != null) entries.add(_entryFor(leaf));
      return;
    }

    if (match is ShellRouteMatch) {
      for (final child in match.matches) {
        _appendStackEntry(child, entries);
      }
      return;
    }

    if (match is RouteMatch) {
      entries.add(_entryFor(match));
    }
  }

  static _RouteStackEntry _entryFor(RouteMatch match) {
    return _RouteStackEntry(
      routePath: match.route.path,
      location: match.matchedLocation,
    );
  }

  static String? _labelFor(_RouteStackEntry entry) {
    return _routeLabels[entry.routePath] ??
        _routeLabels[entry.location] ??
        _dynamicRouteLabel(entry.location);
  }

  static String? _dynamicRouteLabel(String location) {
    if (location.startsWith('/activity/tx/')) {
      return _routeLabels['/activity/tx/:txid'];
    }
    return null;
  }
}
