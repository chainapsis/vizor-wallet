import 'package:flutter/widgets.dart';

/// Minimal click target: button semantics, a click cursor, and an opaque
/// tap region around [child]. The shared form of the local
/// Semantics+MouseRegion+GestureDetector wrappers that grew per feature.
///
/// [enabled] swaps the cursor to basic, drops the tap handler, and marks
/// the semantics node disabled — the recurring `enabled ? click : basic`
/// micro-pattern in one place.
class AppTappable extends StatelessWidget {
  const AppTappable({
    required this.onTap,
    required this.child,
    this.semanticsLabel,
    this.enabled = true,
    this.behavior = HitTestBehavior.opaque,
    super.key,
  });

  final VoidCallback? onTap;
  final Widget child;
  final String? semanticsLabel;
  final bool enabled;
  final HitTestBehavior behavior;

  @override
  Widget build(BuildContext context) {
    final active = enabled && onTap != null;
    return Semantics(
      button: true,
      enabled: active,
      label: semanticsLabel,
      child: MouseRegion(
        cursor: active ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          behavior: behavior,
          onTap: active ? onTap : null,
          child: child,
        ),
      ),
    );
  }
}
