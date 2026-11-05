import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../l10n/l10n.dart';

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
  static AppBackTarget _homeTarget(AppLocalizations l10n) => AppBackTarget(
    label: l10n.navHome,
    fallbackPath: '/home',
    preferPop: false,
  );

  static final _routeLabels = <String, String Function(AppLocalizations)>{
    '/home': (l) => l.navHome,
    '/send': (l) => l.appBackSend,
    '/send/amount': (l) => l.appBackAmount,
    '/send/review': (l) => l.appBackReview,
    '/send/keystone/scan': (_) => 'Keystone', // l10n-ignore: device name
    '/send/status': (l) => l.appBackStatus,
    '/donation': (l) => l.appBackDonation,
    '/swap': (l) => l.navSwap,
    '/swap/review': (l) => l.appBackReview,
    '/receive': (l) => l.appBackReceive,
    '/address-book': (l) => l.appBackContacts,
    '/activity': (l) => l.navActivity,
    '/activity/tx/:txid': (l) => l.appBackTransaction,
    '/accounts': (l) => l.accountsTitle,
    '/settings': (l) => l.navSettings,
    '/settings/secret-passphrase': (l) => l.settingsRowSecretPassphrase,
    '/settings/viewing-key': (l) => l.settingsViewingKeyTitle,
    '/settings/change-password': (l) => l.settingsRowChangePassword,
    '/settings/endpoint': (l) => l.settingsEndpointTitle,
    '/settings/explorer': (l) => l.settingsExplorerTitle,
    '/settings/uninstall': (l) => l.settingsUninstallTitle,
    '/onboarding/keystone': (l) => l.onboardingConnectKeystone,
    '/voting': (l) => l.navVote,
    '/voting/poll/:roundId': (l) => l.appBackVotingRound,
    '/voting/poll/:roundId/review': (l) => l.appBackReview,
    '/voting/poll/:roundId/status': (l) => l.appBackStatus,
    '/voting/poll/:roundId/submitted': (l) => l.appBackSubmitted,
    '/voting/poll/:roundId/results': (l) => l.appBackResults,
    '/voting/keystone/scan': (_) => 'Keystone', // l10n-ignore: device name
  };

  static AppBackTarget resolve(BuildContext context) {
    final l10n = context.l10n;
    final stack = _routeStackFor(context);
    final current = stack.isEmpty ? null : stack.last;
    if (_forcesHome(current)) return _homeTarget(l10n);
    if (!context.canPop()) return _homeTarget(l10n);

    final previous = stack.length >= 2 ? stack[stack.length - 2] : null;
    if (previous == null) {
      return AppBackTarget(
        label: l10n.commonBack,
        fallbackPath: '/home',
        preferPop: true,
      );
    }

    return AppBackTarget(
      label: _labelFor(l10n, previous) ?? l10n.commonBack,
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

  static String? _labelFor(AppLocalizations l10n, _RouteStackEntry entry) {
    final label =
        _routeLabels[entry.routePath] ??
        _routeLabels[entry.location] ??
        _dynamicRouteLabel(entry.location);
    return label?.call(l10n);
  }

  static String Function(AppLocalizations)? _dynamicRouteLabel(
    String location,
  ) {
    if (location.startsWith('/activity/tx/')) {
      return _routeLabels['/activity/tx/:txid'];
    }
    if (location.startsWith('/voting/poll/')) {
      if (location.endsWith('/review')) {
        return _routeLabels['/voting/poll/:roundId/review'];
      }
      if (location.endsWith('/status')) {
        return _routeLabels['/voting/poll/:roundId/status'];
      }
      if (location.endsWith('/submitted')) {
        return _routeLabels['/voting/poll/:roundId/submitted'];
      }
      if (location.endsWith('/results')) {
        return _routeLabels['/voting/poll/:roundId/results'];
      }
      return _routeLabels['/voting/poll/:roundId'];
    }
    return null;
  }
}
