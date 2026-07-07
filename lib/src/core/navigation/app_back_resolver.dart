import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_localizations.dart';

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

  static Map<String, String> _routeLabels(AppLocalizations l10n) => {
    '/home': l10n.navHome,
    '/send': l10n.navSend,
    '/send/amount': l10n.navAmount,
    '/send/review': l10n.navReview,
    '/send/keystone/scan': 'Keystone',
    '/send/status': l10n.navStatus,
    '/swap': l10n.navSwap,
    '/swap/review': l10n.navReview,
    '/receive': l10n.navReceive,
    '/address-book': l10n.settingsContacts,
    '/activity': l10n.navActivity,
    '/activity/tx/:txid': l10n.navTransaction,
    '/accounts': l10n.navAccounts,
    '/settings': l10n.settingsTitle,
    '/settings/secret-passphrase': l10n.settingsSecretPassphrase,
    '/settings/change-password': l10n.navChangePassword,
    '/settings/endpoint': l10n.settingsEndpoint,
    '/settings/uninstall': l10n.settingsUninstallVizor,
    '/onboarding/keystone': l10n.navConnectKeystone,
    '/voting': l10n.navVote,
    '/voting/poll/:roundId': l10n.navVotingRound,
    '/voting/poll/:roundId/review': l10n.navReview,
    '/voting/poll/:roundId/status': l10n.navStatus,
    '/voting/poll/:roundId/submitted': l10n.navSubmitted,
    '/voting/poll/:roundId/results': l10n.navResults,
    '/voting/keystone/scan': 'Keystone',
  };

  static AppBackTarget resolve(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
      label: _labelFor(previous, l10n) ?? l10n.commonBack,
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

  static String? _labelFor(_RouteStackEntry entry, AppLocalizations l10n) {
    final labels = _routeLabels(l10n);
    return labels[entry.routePath] ??
        labels[entry.location] ??
        _dynamicRouteLabel(entry.location, labels);
  }

  static String? _dynamicRouteLabel(
    String location,
    Map<String, String> labels,
  ) {
    if (location.startsWith('/activity/tx/')) {
      return labels['/activity/tx/:txid'];
    }
    if (location.startsWith('/voting/poll/')) {
      if (location.endsWith('/review')) {
        return labels['/voting/poll/:roundId/review'];
      }
      if (location.endsWith('/status')) {
        return labels['/voting/poll/:roundId/status'];
      }
      if (location.endsWith('/submitted')) {
        return labels['/voting/poll/:roundId/submitted'];
      }
      if (location.endsWith('/results')) {
        return labels['/voting/poll/:roundId/results'];
      }
      return labels['/voting/poll/:roundId'];
    }
    return null;
  }
}
