import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Horizontal insets (logical px) that window-level content overlays — the
/// network-fallback toast, the app-level payment-request card — should leave
/// clear so they align with the content pane instead of the whole window.
///
/// Both sides are `EdgeInsets.zero` when no sidebar shell is mounted (welcome,
/// unlock, mobile) and the pane's own margins when one is: the left inset
/// covers the outer padding plus the sidebar plus the gap, the right inset the
/// pane's trailing margin. Shells publish their insets by mounting a
/// [ContentOverlayInset]; the most recently mounted shell wins, which during a
/// route transition is the incoming screen.
///
/// Kept as a process-global [ValueListenable] (rather than a provider) so the
/// publishing shells stay free of any `ProviderScope` requirement.
ValueListenable<EdgeInsets> get contentOverlayInsets => _insets;

/// Just the left inset, for overlays that pin themselves to the pane's leading
/// edge rather than centering inside it.
ValueListenable<double> get contentOverlayLeftInset => _leftInset;

final ValueNotifier<EdgeInsets> _insets = ValueNotifier<EdgeInsets>(
  EdgeInsets.zero,
);
final ValueNotifier<double> _leftInset = ValueNotifier<double>(0);
final List<_InsetEntry> _entries = <_InsetEntry>[];

void _pushInset(Object token, EdgeInsets inset) {
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
  final inset = _entries.isEmpty ? EdgeInsets.zero : _entries.last.inset;
  _insets.value = inset;
  _leftInset.value = inset.left;
}

class _InsetEntry {
  _InsetEntry(this.token, this.inset);

  final Object token;
  EdgeInsets inset;
}

/// Publishes [leftInset] and [rightInset] to [contentOverlayInsets] while
/// mounted.
///
/// Wrap a sidebar shell with this so window-level overlays can clear the
/// sidebar. Mutations are deferred to post-frame callbacks so the global
/// notifier never fires while the widget tree is mid-build (which would
/// otherwise trigger a `setState during build` from listeners).
class ContentOverlayInset extends StatefulWidget {
  const ContentOverlayInset({
    required this.leftInset,
    required this.child,
    this.rightInset = 0,
    super.key,
  });

  final double leftInset;

  /// The pane's trailing margin. Only overlays that center themselves inside
  /// the pane need it; leading-pinned overlays read [leftInset] alone.
  final double rightInset;

  final Widget child;

  EdgeInsets get _edgeInsets =>
      EdgeInsets.only(left: leftInset, right: rightInset);

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
    if (oldWidget._edgeInsets != widget._edgeInsets) {
      _schedulePush();
    }
  }

  void _schedulePush() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _pushInset(_token, widget._edgeInsets);
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

/// Pads [child] with the mounted shell's pane insets so that a *centering*
/// parent — an `Align`, a `Center`, `AppPaneModalOverlay` — lands it on the
/// content pane's center rather than the window's.
///
/// Centering a box padded by `left` and `right` inside a window of width `W`
/// puts its center at `W / 2 + (left - right) / 2`, which is exactly
/// `left + (W - left - right) / 2` — the pane's center. With no shell mounted
/// both insets are zero and this is a no-op, which is what onboarding, unlock
/// and every mobile route get.
class ContentPaneCenteringPadding extends StatelessWidget {
  const ContentPaneCenteringPadding({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<EdgeInsets>(
      valueListenable: contentOverlayInsets,
      builder: (context, insets, child) =>
          Padding(padding: insets, child: child),
      child: child,
    );
  }
}
