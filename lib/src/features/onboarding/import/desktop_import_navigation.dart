import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Keeps selector origin separate from the typed setup payload in route extras.
/// Only these two desktop entries can change an import flow's return screen.
String preserveDesktopImportEntry(Uri origin, String destination) {
  final entry = origin.queryParameters['entry'];
  if (entry != 'import-method' && entry != 'hardware-method') {
    return destination;
  }
  final target = Uri.parse(destination);
  return target
      .replace(
        queryParameters: {
          ...target.queryParameters,
          'entry': entry,
          if (origin.queryParameters['from'] == 'add-account')
            'from': 'add-account',
        },
      )
      .toString();
}

String desktopImportLocation(BuildContext context, String destination) {
  final router = GoRouter.maybeOf(context);
  if (router == null) return destination;
  return preserveDesktopImportEntry(
    router.routeInformationProvider.value.uri,
    destination,
  );
}

String? desktopImportSelectionLocation(Uri origin) {
  final destination = switch (origin.queryParameters['entry']) {
    'import-method' => '/import/method',
    'hardware-method' => '/import/hardware',
    _ => null,
  };
  if (destination == null) return null;
  return Uri(
    path: destination,
    queryParameters: origin.queryParameters['from'] == 'add-account'
        ? {'from': 'add-account'}
        : null,
  ).toString();
}
