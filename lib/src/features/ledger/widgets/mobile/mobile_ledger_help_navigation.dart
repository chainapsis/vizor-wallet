import 'package:flutter/widgets.dart';

/// Lets the operation's existing Back handler return through help without
/// dismissing the operation. Close/scrim/drag still use the owner's cancellation.
class MobileLedgerHelpNavigation {
  Object? _owner;
  VoidCallback? _previous;

  void attach(Object owner, VoidCallback previous) {
    _owner = owner;
    _previous = previous;
  }

  void detach(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    _previous = null;
  }

  bool previous() {
    final previous = _previous;
    if (previous == null) return false;
    previous();
    return true;
  }
}

class MobileLedgerHelpScope extends InheritedWidget {
  const MobileLedgerHelpScope({
    required this.navigation,
    required super.child,
    super.key,
  });

  final MobileLedgerHelpNavigation navigation;

  static MobileLedgerHelpNavigation? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<MobileLedgerHelpScope>()
      ?.navigation;

  @override
  bool updateShouldNotify(MobileLedgerHelpScope oldWidget) =>
      navigation != oldWidget.navigation;
}
