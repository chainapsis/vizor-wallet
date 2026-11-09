import 'dart:ui' as ui;
import 'package:flutter/widgets.dart';

/// Presentation clock only; device work and cancellation keep their own owners.
class ShieldHardwareMotion {
  double mix = 0;
  double footer = 0;
  bool _shown = false;
  double _from = 0, _footerFrom = 0, _at = 0;
  double _duration = 0.18;
  bool reduceMotion = false;

  bool get active => _shown || mix > 0;
  bool get interactive => _shown && footer >= 0.999;
  double get footerDy => reduceMotion || !_shown ? 0 : 6 * (1 - footer);

  void configure(bool shown, double time) {
    if (_shown == shown) return;
    _shown = shown;
    _from = mix;
    _footerFrom = footer;
    _at = time;
    _duration = reduceMotion
        ? 0.12
        : shown
        ? 0.18
        : 0.28;
  }

  void update(double time) {
    final p = ((time - _at) / _duration).clamp(0.0, 1.0);
    mix = ui.lerpDouble(_from, _shown ? 1 : 0, Curves.easeInOut.transform(p))!;
    final footerDuration = reduceMotion
        ? 0.12
        : _shown
        ? 0.16
        : 0.14;
    final delay = !reduceMotion && _shown ? 0.02 : 0.0;
    final f = ((time - _at - delay) / footerDuration).clamp(0.0, 1.0);
    footer = ui.lerpDouble(
      _footerFrom,
      _shown ? 1 : 0,
      Curves.easeOut.transform(f),
    )!;
  }
}

/// Lets the existing Ledger content keep its owners while the scene supplies
/// bounded layout, shared timing, and immediate input gating on an exit.
class ShieldHardwarePresentation extends InheritedWidget {
  const ShieldHardwarePresentation({
    required this.mix,
    required this.footerOpacity,
    required this.footerDy,
    required this.interactive,
    required super.child,
    super.key,
  });
  final double mix;
  final double footerOpacity;
  final double footerDy;
  final bool interactive;
  static ShieldHardwarePresentation? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShieldHardwarePresentation>();
  @override
  bool updateShouldNotify(ShieldHardwarePresentation old) =>
      mix != old.mix ||
      footerOpacity != old.footerOpacity ||
      footerDy != old.footerDy ||
      interactive != old.interactive;
}

/// Fades labels in place. Outgoing content is never exposed to accessibility.
class ShieldStageTransition extends StatelessWidget {
  const ShieldStageTransition({
    required this.child,
    required this.identity,
    super.key,
  });
  final Widget child;
  final Object identity;
  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: Duration(
      milliseconds: MediaQuery.disableAnimationsOf(context) ? 120 : 140,
    ),
    layoutBuilder: (current, previous) => Stack(
      alignment: Alignment.center,
      children: [
        for (final old in previous)
          ExcludeSemantics(child: IgnorePointer(child: old)),
        ?current,
      ],
    ),
    child: KeyedSubtree(key: ValueKey(identity), child: child),
  );
}
