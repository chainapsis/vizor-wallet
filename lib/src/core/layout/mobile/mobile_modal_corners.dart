import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../services/native_modal_corners.dart';
import '../../theme/app_radii.dart';
import 'prepared_modal_sheet_route.dart';

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
  bool _ready = false;
  bool _animate = false;
  BorderRadius _target = _fallback;
  _Geometry? _request;
  Animation<double>? _routeAnimation;
  PreparedModalSheetRoute<dynamic>? _preparedRoute;
  bool _scheduled = false;
  bool _pending = false;
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
      _invalidate();
    }
    if (_keyboard != keyboard) {
      _keyboard = keyboard;
      _invalidate();
    }
    final route = ModalRoute.of(context);
    _preparedRoute = route is PreparedModalSheetRoute ? route : null;
    final animation = route?.animation;
    if (_routeAnimation != animation) {
      _routeAnimation?.removeStatusListener(_routeStatusChanged);
      _routeAnimation = animation;
      animation?.addStatusListener(_routeStatusChanged);
      _invalidate();
    }
    if (_keyboard || !widget.followsScreenCorners) {
      _target = _fallback;
      _animate = _ready;
      _ready = true;
      _preparedRoute?.cornersReady();
    }
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

  void _invalidate() {
    _epoch++;
    _request = null;
    _pending = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    _invalidate();
    if (_active) {
      _schedule();
      WidgetsBinding.instance.ensureVisualUpdate();
    }
  }

  void _routeStatusChanged(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _schedule();
    } else {
      // A settled-frame response must not alter a dismissing/dragged sheet.
      if (_pending) {
        _invalidate();
      } else {
        _epoch++;
      }
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
    if (box is! RenderBox || !box.hasSize || box.size.isEmpty) {
      _setTarget(_fallback);
      return;
    }
    final view = View.of(context);
    final geometry = (
      rect: box.localToGlobal(Offset.zero) & box.size,
      viewSize: view.physicalSize / view.devicePixelRatio,
      scale: view.devicePixelRatio,
    );
    if (_request == geometry) return;
    _request = geometry;
    final epoch = ++_epoch;
    _pending = true;
    // Native owns the process-wide/persistent cache and validates the host on
    // every read. Never expose the fallback while awaiting the initial result.
    final radii = await NativeModalCorners.resolve(
      rect: geometry.rect,
      viewSize: geometry.viewSize,
      scale: geometry.scale,
    ).timeout(const Duration(milliseconds: 100), onTimeout: () => null);
    if (epoch == _epoch) _pending = false;
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
    _setTarget(target);
  }

  void _setTarget(BorderRadius target) {
    if (!_ready) {
      setState(() {
        _ready = true;
        _animate = false;
        _target = target;
      });
      _preparedRoute?.cornersReady();
    } else if (_target != target) {
      setState(() {
        _animate = true;
        _target = target;
      });
    }
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
            child: ExcludeSemantics(
              excluding: !_ready,
              child: IgnorePointer(
                ignoring: !_ready,
                child: Opacity(
                  opacity: _ready ? 1 : 0,
                  child: TweenAnimationBuilder<BorderRadius?>(
                    tween: BorderRadiusTween(begin: _fallback, end: _target),
                    duration:
                        !_animate || MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : _duration,
                    curve: Curves.easeOutCubic,
                    builder: (context, radius, _) =>
                        widget.builder(context, radius!),
                  ),
                ),
              ),
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
