import 'package:flutter/widgets.dart';

/// Keeps a covered route's layout still while a sheet's keyboard moves.
///
/// Mobile sheets are root routes, and a text field in one raises the
/// keyboard over the whole window. The screen beneath would otherwise
/// resize and lay out again on every frame of the keyboard animation, behind
/// the scrim. While another route covers this one, and the keyboard was down
/// when it did, [child] sees no keyboard. Uncovered again, it keeps seeing
/// none while that keyboard goes down, and follows the keyboard as soon as it
/// rises for this route.
///
/// A route covered while its own keyboard is up follows the keyboard as
/// before. Only the bottom keyboard inset and bottom padding are held; every
/// other metric stays live.
class CoveredRouteKeyboardHold extends StatefulWidget {
  const CoveredRouteKeyboardHold({required this.child, super.key});

  final Widget child;

  @override
  State<CoveredRouteKeyboardHold> createState() =>
      _CoveredRouteKeyboardHoldState();
}

class _CoveredRouteKeyboardHoldState extends State<CoveredRouteKeyboardHold> {
  bool _covered = false;
  double _lastInset = 0;

  /// The bottom padding [child] keeps while held, or null when not held.
  double? _heldPadding;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final inset = media.viewInsets.bottom;
    final covered = !(ModalRoute.isCurrentOf(context) ?? true);
    if (covered && !_covered) {
      _heldPadding = inset == 0 ? media.padding.bottom : null;
    } else if (!covered && (inset == 0 || inset > _lastInset)) {
      _heldPadding = null;
    }
    _covered = covered;
    _lastInset = inset;

    final heldPadding = _heldPadding;
    // The same structure either way, so the subtree keeps its state; while
    // held, the data stays equal across keyboard frames and notifies nothing.
    return MediaQuery(
      data: heldPadding == null
          ? media
          : media.copyWith(
              viewInsets: media.viewInsets.copyWith(bottom: 0),
              padding: media.padding.copyWith(bottom: heldPadding),
            ),
      child: widget.child,
    );
  }
}
