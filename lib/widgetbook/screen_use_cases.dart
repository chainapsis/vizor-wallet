// ignore_for_file: depend_on_referenced_packages
// widgetbook is dev-only; see `widgetbook.dart` for the boundary.

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../src/core/layout/app_layout.dart';
import '../src/features/onboarding/welcome.dart';

/// Welcome screen in its large-layout form. Wrapped in a `ProviderScope`
/// with `appLayoutProvider` overridden to a no-op so the dev window does
/// not get reshaped by the screen's on-mount `setMode(large)` call, and
/// in a minimal `GoRouter` so the in-screen `context.go(...)` calls
/// resolve instead of throwing if a reviewer taps a button during the
/// preview.
Widget buildWelcomeLargeUseCase(BuildContext context) {
  return ProviderScope(
    overrides: [
      appLayoutProvider.overrideWith(_NoOpLayoutNotifier.new),
    ],
    child: _WelcomeHarness(),
  );
}

class _NoOpLayoutNotifier extends AppLayoutNotifier {
  @override
  AppLayoutState build() => const AppLayoutState(AppLayoutMode.large);

  @override
  Future<void> setMode(AppLayoutMode mode) async {
    // Intentional no-op: `AppLayoutNotifier.setMode` would reshape the
    // native window via `window_manager`, which is disruptive in a
    // Widgetbook preview where the window belongs to the dev tool.
  }
}

class _WelcomeHarness extends StatefulWidget {
  @override
  State<_WelcomeHarness> createState() => _WelcomeHarnessState();
}

class _WelcomeHarnessState extends State<_WelcomeHarness> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = GoRouter(
      initialLocation: '/welcome',
      routes: [
        GoRoute(path: '/welcome', builder: (_, _) => const WelcomeScreen()),
        // Stub destinations so buttons in the preview don't throw when
        // tapped. They render nothing meaningful — the point is just to
        // satisfy the router.
        GoRoute(
          path: '/create',
          builder: (_, _) => const _PreviewRoutePlaceholder(label: '/create'),
        ),
        GoRoute(
          path: '/import',
          builder: (_, _) => const _PreviewRoutePlaceholder(label: '/import'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Router.withConfig(config: _router);
  }
}

class _PreviewRoutePlaceholder extends StatelessWidget {
  const _PreviewRoutePlaceholder({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(child: Text('Navigated to $label'));
  }
}
