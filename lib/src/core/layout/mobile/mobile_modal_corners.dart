import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../services/native_modal_corners.dart';
import '../../theme/app_radii.dart';

typedef _Geometry = ({Rect rect, Size viewSize, double scale});

/// Resolves settled modal geometry, never the intermediate translated frame
/// of a sheet entrance/drag. Animation and all painting remain in Flutter.
class MobileModalCorners extends StatefulWidget {
  const MobileModalCorners({
    required this.followsScreenCorners,
    required this.builder,
    super.key,
  });

  final bool followsScreenCorners;
  final Widget Function(BuildContext, BorderRadius) builder;

  @override
  State<MobileModalCorners> createState() => _MobileModalCornersState();
}

class _MobileModalCornersState extends State<MobileModalCorners>
    with WidgetsBindingObserver {
  static const _fallback = BorderRadius.all(Radius.circular(AppRadii.xLarge));
  static const _duration = Duration(milliseconds: 250);
  final _surfaceKey = GlobalKey();
  final _cache = <_Geometry, BorderRadius>{};
  BorderRadius _target = _fallback;
  _Geometry? _request;
  Animation<double>? _routeAnimation;
  bool _scheduled = false;
  bool _keyboard = false;
  bool _active = true;
  int _epoch = 0;
  Size? _viewSize;
  double? _scale;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final view = View.of(context);
    final size = view.physicalSize / view.devicePixelRatio;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    if (_viewSize != size || _scale != view.devicePixelRatio) {
      _viewSize = size;
      _scale = view.devicePixelRatio;
      _invalidate(clearCache: true);
    }
    if (_keyboard != keyboard) {
      _keyboard = keyboard;
      _invalidate();
    }
    final animation = ModalRoute.of(context)?.animation;
    if (_routeAnimation != animation) {
      _routeAnimation?.removeStatusListener(_routeStatusChanged);
      _routeAnimation = animation;
      animation?.addStatusListener(_routeStatusChanged);
      _invalidate();
    }
    if (_keyboard || !widget.followsScreenCorners) _target = _fallback;
    _schedule();
  }

  @override
  void didUpdateWidget(MobileModalCorners oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.followsScreenCorners != oldWidget.followsScreenCorners) {
      _invalidate();
      _target = _fallback;
    }
    _schedule();
  }

  void _invalidate({bool clearCache = false}) {
    _epoch++;
    _request = null;
    if (clearCache) _cache.clear();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    _invalidate(clearCache: true);
    if (mounted) setState(() => _target = _fallback);
    if (_active) _schedule();
  }

  void _routeStatusChanged(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _schedule();
    } else {
      // A settled-frame response must not alter a dismissing/dragged sheet.
      _invalidate();
    }
  }

  void _schedule() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted) _resolve();
    });
  }

  Future<void> _resolve() async {
    if (!_active ||
        _keyboard ||
        !widget.followsScreenCorners ||
        (_routeAnimation != null &&
            _routeAnimation!.status != AnimationStatus.completed)) {
      return;
    }
    final box = _surfaceKey.currentContext?.findRenderObject();
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
    final cached = _cache[geometry];
    if (cached != null) {
      _setTarget(cached);
      return;
    }
    final radii = await NativeModalCorners.resolve(
      rect: geometry.rect,
      viewSize: geometry.viewSize,
      scale: geometry.scale,
    );
    if (!mounted ||
        epoch != _epoch ||
        !_active ||
        _keyboard ||
        !widget.followsScreenCorners) {
      return;
    }
    final target = radii == null
        ? _fallback
        : _fallback.copyWith(
            bottomLeft: Radius.circular(math.max(AppRadii.xLarge, radii.left)),
            bottomRight: Radius.circular(
              math.max(AppRadii.xLarge, radii.right),
            ),
          );
    // Keep only a few successful geometries (e.g. before/after content growth).
    // Failures deduplicate until the layout/lifecycle changes, but are not cached.
    if (radii != null) {
      if (_cache.length == 4) _cache.remove(_cache.keys.first);
      _cache[geometry] = target;
    }
    _setTarget(target);
  }

  void _setTarget(BorderRadius target) {
    if (_target != target) setState(() => _target = target);
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<SizeChangedLayoutNotification>(
        onNotification: (_) {
          _schedule();
          return false;
        },
        child: SizeChangedLayoutNotifier(
          child: KeyedSubtree(
            key: _surfaceKey,
            child: TweenAnimationBuilder<BorderRadius?>(
              tween: BorderRadiusTween(begin: _fallback, end: _target),
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : _duration,
              curve: Curves.easeOutCubic,
              builder: (context, radius, _) => widget.builder(context, radius!),
            ),
          ),
        ),
      );

  @override
  void dispose() {
    _epoch++;
    _routeAnimation?.removeStatusListener(_routeStatusChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
