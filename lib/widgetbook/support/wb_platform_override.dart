import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Overrides [debugDefaultTargetPlatformOverride] for a Widgetbook fixture.
///
/// Widgetbook can inflate an incoming URI-keyed use case before disposing the
/// outgoing one. Ownership is shared across every fixture so the outgoing
/// fixture cannot clear the incoming fixture's platform.
class WbPlatformOverride extends StatefulWidget {
  const WbPlatformOverride({
    required this.platform,
    required this.child,
    super.key,
  });

  final TargetPlatform? platform;
  final Widget child;

  @override
  State<WbPlatformOverride> createState() => _WbPlatformOverrideState();
}

class _WbPlatformOverrideState extends State<WbPlatformOverride> {
  static final List<_WbPlatformOverrideState> _owners = [];
  static TargetPlatform? _baseline;

  @override
  void initState() {
    super.initState();
    _claim();
  }

  @override
  void didUpdateWidget(WbPlatformOverride oldWidget) {
    super.didUpdateWidget(oldWidget);
    _claim();
  }

  void _claim() {
    if (_owners.isEmpty) {
      _baseline = debugDefaultTargetPlatformOverride;
    } else {
      _owners.remove(this);
    }
    _owners.add(this);
    debugDefaultTargetPlatformOverride = widget.platform ?? _baseline;
  }

  @override
  void dispose() {
    final wasOwner = _owners.isNotEmpty && identical(_owners.last, this);
    _owners.remove(this);
    if (wasOwner) {
      debugDefaultTargetPlatformOverride = _owners.isEmpty
          ? _baseline
          : _owners.last.widget.platform ?? _baseline;
    }
    if (_owners.isEmpty) {
      _baseline = null;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
