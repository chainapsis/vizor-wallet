/// What a flip asks of privacy mode.
enum FlipToHideAction { hide, show }

/// Flip to hide: turning the phone screen-down hides amounts at once, and it
/// stays hidden when turned back. With amounts hidden, a flip down and back
/// up within [showWindow] shows them again. A phone left screen-down longer
/// (on a table, in a bag) only ever hides, so picking it up never reveals
/// the balance.
///
/// Readings are gravity along the screen's normal (`screenFacingEvents`):
/// -1 with the screen straight up, 1 straight down.
class FlipToHideDetector {
  /// Screen-down: within about 40° of straight down.
  static const screenDownAt = 0.75;

  /// Back from screen-down once the screen faces above the horizon, so a
  /// wobble near [screenDownAt] is not a second flip.
  static const screenUpAt = 0.0;

  /// A flip turns from screen-up to screen-down within this. A phone that
  /// ends up screen-down slowly, such as one held overhead lying down, is
  /// not a flip.
  static const flipWindow = Duration(seconds: 1);

  /// How soon a flip must come back up to show hidden amounts.
  static const showWindow = Duration(seconds: 2);

  Duration? _lastUpAt;
  bool _screenDown = false;
  bool _flipHid = false;
  Duration _downAt = Duration.zero;

  /// Feeds one [facing] reading taken at [at] on a monotonic clock, with
  /// whether amounts are [hidden] now. Returns the change to make, if any.
  FlipToHideAction? add(
    double facing, {
    required Duration at,
    required bool hidden,
  }) {
    if (facing <= screenUpAt) {
      _lastUpAt = at;
      if (!_screenDown) return null;
      _screenDown = false;
      // Only a flip that found amounts hidden shows them, and only when it
      // came straight back.
      final show = !_flipHid && hidden && at - _downAt <= showWindow;
      return show ? FlipToHideAction.show : null;
    }
    if (_screenDown || facing < screenDownAt) return null;
    // A phone already screen-down when listening starts has no turn from
    // screen-up behind it, so it is not a flip either.
    final lastUpAt = _lastUpAt;
    if (lastUpAt == null || at - lastUpAt > flipWindow) return null;
    _screenDown = true;
    _downAt = at;
    _flipHid = !hidden;
    return hidden ? null : FlipToHideAction.hide;
  }
}
