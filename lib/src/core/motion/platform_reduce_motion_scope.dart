import 'package:flutter/widgets.dart';

/// Folds the platform "Reduce Motion" flag into
/// [MediaQueryData.disableAnimations] for everything below it.
///
/// iOS reports Settings › Accessibility › Motion › Reduce Motion only as
/// `AccessibilityFeatures.reduceMotion`; Flutter leaves
/// `MediaQuery.disableAnimations` false there. Every reduced-motion gate
/// in this app reads `disableAnimations`, so the bridge lives once, at the
/// app root, instead of in each gate.
///
/// `MediaQuery` does not rebuild when only `reduceMotion` changes, so the
/// scope listens to [WidgetsBindingObserver.didChangeAccessibilityFeatures]
/// itself. It always returns a `MediaQuery` so toggling the setting never
/// remounts the subtree.
class PlatformReduceMotionScope extends StatefulWidget {
  const PlatformReduceMotionScope({required this.child, super.key});

  final Widget child;

  @override
  State<PlatformReduceMotionScope> createState() =>
      _PlatformReduceMotionScopeState();
}

class _PlatformReduceMotionScopeState extends State<PlatformReduceMotionScope>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAccessibilityFeatures() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final reduceMotion = View.of(
      context,
    ).platformDispatcher.accessibilityFeatures.reduceMotion;
    return MediaQuery(
      data: media.copyWith(
        disableAnimations: media.disableAnimations || reduceMotion,
      ),
      child: widget.child,
    );
  }
}
