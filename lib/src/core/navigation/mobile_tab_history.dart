import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Path of the tab the user was on immediately before switching to the
/// current one.
///
/// The mobile shell is a [StatefulShellRoute.indexedStack], so switching
/// tabs via `goBranch` keeps no navigator history — a tab root therefore
/// can't `pop` back to where the user came from. The shell records the
/// outgoing tab path here on every switch so a tab root that wants a
/// "back" affordance (e.g. the Swap composer, whose Figma frame shows a
/// leading button) can return to the previous tab. Null until the first
/// in-app tab switch (e.g. a cold start directly on the Swap tab).
class MobilePreviousTabPathNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void record(String path) => state = path;
}

final mobilePreviousTabPathProvider =
    NotifierProvider<MobilePreviousTabPathNotifier, String?>(
      MobilePreviousTabPathNotifier.new,
    );

/// Destination for a mobile tab root's Back affordance: the tab the user came
/// from, falling back to `/home`.
///
/// Guards against [currentPath]: the previous-tab record is only updated on
/// tab-bar switches, not on programmatic `context.go`s, so it can still hold
/// the current tab's own path (e.g. Home→Activity→Settings, then Settings'
/// Back `go('/activity')` leaves the record at `/activity` while the user is
/// back on Activity). Navigating to the current route would be a silent no-op,
/// so fall back to `/home` in that case.
String resolveMobileBackPath(WidgetRef ref, {required String currentPath}) {
  final previous = ref.read(mobilePreviousTabPathProvider);
  if (previous == null || previous == currentPath) return '/home';
  return previous;
}
