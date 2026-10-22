import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../../services/native_modal_corners.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_modal_shape.dart';

typedef _PanelGeometry = ({Rect rect, Size viewSize, double scale});

/// Owns one shared outline for the panel fill and clipping. Only iOS asks
/// UIKit to resolve container-concentric corners at the panel's actual frame.
class MobileSidebarSurface extends StatefulWidget {
  const MobileSidebarSurface({required Widget this.child, super.key})
    : builder = null;

  /// Shares the same resolved corners with content that hugs the panel edge.
  const MobileSidebarSurface.builder({
    required Widget Function(BuildContext context, BorderRadius corners)
    this.builder,
    super.key,
  }) : child = null;

  final Widget? child;
  final Widget Function(BuildContext context, BorderRadius corners)? builder;

  @override
  State<MobileSidebarSurface> createState() => _MobileSidebarSurfaceState();
}

class _MobileSidebarSurfaceState extends State<MobileSidebarSurface>
    with WidgetsBindingObserver {
  static const _fallback = BorderRadius.all(Radius.circular(AppRadii.large));
  final _key = GlobalKey();
  BorderRadius _radius = _fallback;
  _PanelGeometry? _request;
  _PanelGeometry? _resolvedGeometry;
  MediaQueryData? _viewMetrics;
  int _epoch = 0;
  bool _scheduled = false;
  bool _active = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _viewMetrics = MediaQueryData.fromView(View.of(context));
  }

  void _schedule() {
    if (_scheduled || !_active || defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted && _active) _resolve();
    });
  }

  @override
  void didChangeMetrics() {
    final previous = _viewMetrics;
    final next = MediaQueryData.fromView(View.of(context));
    _viewMetrics = next;
    // Padding is derived from viewPadding and viewInsets. Neither the keyboard
    // nor its derived padding changes the display's container-concentric shape.
    final keyboardOnly =
        previous != null &&
        previous.viewInsets != next.viewInsets &&
        previous.copyWith(viewInsets: next.viewInsets, padding: next.padding) ==
            next;
    if (!keyboardOnly) {
      _epoch++;
      _request = null;
    }
    // Still measure the panel: a parent may move it during a keyboard change.
    // Keep both settled corners and in-flight responses if geometry is equal.
    _schedule();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    _epoch++;
    _request = null;
    _resolvedGeometry = null;
    if (_active) {
      _schedule();
      WidgetsBinding.instance.ensureVisualUpdate();
    }
  }

  Future<void> _resolve() async {
    final box = _key.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize || box.size.isEmpty) return;
    final view = View.of(context);
    final geometry = (
      rect: box.localToGlobal(Offset.zero) & box.size,
      viewSize: view.physicalSize / view.devicePixelRatio,
      scale: view.devicePixelRatio,
    );
    if (_request == geometry) return;
    _request = geometry;
    final epoch = ++_epoch;
    // Do not keep the old posture's radius while awaiting a new geometry.
    // iOS can also repeat identical metrics while finishing a keyboard
    // animation. Revalidate those notifications without flashing the fallback
    // for geometry whose corners we have already resolved in this lifecycle.
    if (_resolvedGeometry != geometry && _radius != _fallback) {
      setState(() => _radius = _fallback);
    }
    final radius = await NativeModalCorners.resolveSidebar(
      rect: geometry.rect,
      viewSize: geometry.viewSize,
      scale: geometry.scale,
    );
    if (!mounted || !_active || epoch != _epoch) return;
    _resolvedGeometry = geometry;
    final target = radius ?? _fallback;
    if (_radius != target) setState(() => _radius = target);
  }

  @override
  Widget build(BuildContext context) {
    // Parent positioning can change without resizing the panel itself.
    _schedule();
    final shape = appModalShape(_radius);
    return NotificationListener<SizeChangedLayoutNotification>(
      onNotification: (_) {
        _schedule();
        return false;
      },
      child: SizeChangedLayoutNotifier(
        child: DecoratedBox(
          key: _key,
          decoration: ShapeDecoration(
            color: context.colors.background.raised,
            shape: shape,
          ),
          child: ClipPath(
            clipper: ShapeBorderClipper(shape: shape),
            child: widget.builder?.call(context, _radius) ?? widget.child!,
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _epoch++;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
