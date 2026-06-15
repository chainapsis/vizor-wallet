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
