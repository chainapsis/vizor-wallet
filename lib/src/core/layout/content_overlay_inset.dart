import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Left inset (logical px) that top-anchored, window-level content overlays —
/// e.g. the network-fallback toast — should leave clear so they align with the
/// content pane instead of the whole window.
///
/// The value is `0` when no sidebar shell is mounted (welcome, unlock, mobile)
/// and the sidebar's reserved width when one is (so overlays center over the
/// trailing pane). Shells publish their inset by mounting a
/// [ContentOverlayInset]; the most recently mounted shell wins, which during a
/// route transition is the incoming screen.
///
/// Kept as a process-global [ValueListenable] (rather than a provider) so the
/// publishing shells stay free of any `ProviderScope` requirement.
ValueListenable<double> get contentOverlayLeftInset => _leftInset;

final ValueNotifier<double> _leftInset = ValueNotifier<double>(0);
final List<_InsetEntry> _entries = <_InsetEntry>[];

void _pushInset(Object token, double inset) {
  final index = _entries.indexWhere((entry) => entry.token == token);
  if (index >= 0) {
    _entries[index].inset = inset;
  } else {
    _entries.add(_InsetEntry(token, inset));
  }
  _sync();
}

void _releaseInset(Object token) {
  _entries.removeWhere((entry) => entry.token == token);
  _sync();
}

void _sync() {
  _leftInset.value = _entries.isEmpty ? 0 : _entries.last.inset;
}

class _InsetEntry {
  _InsetEntry(this.token, this.inset);

  final Object token;
  double inset;
}

/// Publishes [leftInset] to [contentOverlayLeftInset] while mounted.
///
/// Wrap a sidebar shell with this so window-level overlays can clear the
/// sidebar. Mutations are deferred to post-frame callbacks so the global
/// notifier never fires while the widget tree is mid-build (which would
/// otherwise trigger a `setState during build` from listeners).
class ContentOverlayInset extends StatefulWidget {
  const ContentOverlayInset({
    required this.leftInset,
    required this.child,
    super.key,
  });

  final double leftInset;
  final Widget child;

  @override
  State<ContentOverlayInset> createState() => _ContentOverlayInsetState();
}

class _ContentOverlayInsetState extends State<ContentOverlayInset> {
  final Object _token = Object();

  @override
  void initState() {
    super.initState();
    _schedulePush();
  }

  @override
  void didUpdateWidget(ContentOverlayInset oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.leftInset != widget.leftInset) {
      _schedulePush();
    }
  }

  void _schedulePush() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _pushInset(_token, widget.leftInset);
    });
  }

  @override
  void dispose() {
    final token = _token;
    WidgetsBinding.instance.addPostFrameCallback((_) => _releaseInset(token));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
