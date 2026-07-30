part of 'mobile_ironwood_migration_flow_screen.dart';

/// System-back handler for the flat, top-level migration routes.
///
/// Every migration route lives outside the tab shell, and the flow moves
/// between them with `context.go`, which replaces the router stack with the
/// destination page. On that stack there is nothing left to pop, so Android's
/// back gesture fell through to the exit hint and iOS's edge swipe was
/// disabled outright. This scope gives a back press the same destination the
/// screen's on-screen chevron already uses.
///
/// [onFallback] is that destination. A null [onFallback] means the screen is
/// deliberately holding back — work is in flight — so the pop is refused for
/// pushed entries too, not just for replaced ones.
class _MobileIronwoodMigrationBackScope extends StatelessWidget {
  const _MobileIronwoodMigrationBackScope({
    required this.child,
    this.onFallback,
  });

  final Widget child;

  /// Where a back press goes when the router stack cannot pop.
  ///
  /// Null blocks the back press entirely.
  final VoidCallback? onFallback;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      key: const ValueKey('mobile_ironwood_migration_back_scope'),
      // A pushed entry (home -> intro, status -> schedule) keeps popping
      // normally, which is what preserves the iOS edge swipe.
      canPop: onFallback != null && GoRouter.of(context).canPop(),
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        onFallback?.call();
      },
      child: child,
    );
  }
}
