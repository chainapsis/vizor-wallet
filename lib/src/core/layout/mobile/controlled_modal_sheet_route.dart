import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show ValueListenable;

/// Opt-in dismissal control for sheets whose operation can become busy after
/// presentation. PopScope alone does not stop BottomSheet's drag pop.
class ControlledModalSheetRoute<T> extends ModalBottomSheetRoute<T> {
  ControlledModalSheetRoute({
    required super.builder,
    required super.isScrollControlled,
    super.capturedThemes,
    super.modalBarrierColor,
    super.barrierLabel,
    super.barrierOnTapHint,
    super.isDismissible,
    super.enableDrag,
    super.useSafeArea,
    super.backgroundColor,
    super.elevation,
    this.canDismiss,
  });

  final ValueListenable<bool>? canDismiss;

  @override
  bool get barrierDismissible =>
      super.barrierDismissible && (canDismiss?.value ?? true);

  @override
  bool get enableDrag => super.enableDrag && (canDismiss?.value ?? true);

  @override
  void install() {
    super.install();
    canDismiss?.addListener(_dismissalChanged);
  }

  void _dismissalChanged() => changedInternalState();

  @override
  bool didPop(T? result) {
    if (!(canDismiss?.value ?? true)) return false;
    return super.didPop(result);
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final control = canDismiss;
    if (control == null) {
      return super.buildPage(context, animation, secondaryAnimation);
    }
    // ModalRoute caches its page. Rebuild the BottomSheet itself, as well as
    // the barrier, so enableDrag follows the operation without losing content.
    return ValueListenableBuilder<bool>(
      valueListenable: control,
      builder: (context, allowed, _) => PopScope(
        canPop: allowed,
        child: super.buildPage(context, animation, secondaryAnimation),
      ),
    );
  }

  @override
  void dispose() {
    canDismiss?.removeListener(_dismissalChanged);
    super.dispose();
  }
}
