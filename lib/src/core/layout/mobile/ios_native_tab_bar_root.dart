import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../navigation/route_owned_redirect.dart';
import '../app_form_factor.dart';
import 'ios_native_tab_bar.dart';
import 'mobile_navigation_scope.dart';

bool get _nativeCandidate =>
    kAppFormFactor == AppFormFactor.mobile &&
    !kIsWeb &&
    defaultTargetPlatform == TargetPlatform.iOS;

void _ignoreSelection(String _) {}

/// App-level native surface, above ordinary router and payment overlays.
/// Security and privacy hosts stay above this host and can suppress it at once.
class IosNativeTabBarRootHost extends StatefulWidget {
  const IosNativeTabBarRootHost({
    required this.child,
    this.hideImmediately = false,
    this.covered = false,
    this.sessionIdentity,
    this.canInteract,
    super.key,
  });

  final Widget child;
  final bool hideImmediately;
  final bool covered;
  final Object? sessionIdentity;
  final bool Function()? canInteract;

  @override
  State<IosNativeTabBarRootHost> createState() =>
      _IosNativeTabBarRootHostState();
}

class _IosNativeTabBarRootHostState extends State<IosNativeTabBarRootHost> {
  final _coordinator = IosNativeTabBarCoordinator();

  @override
  void dispose() {
    _coordinator.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _coordinator._environment(
      suppressed: widget.hideImmediately,
      covered: widget.covered,
      sessionIdentity: widget.sessionIdentity,
      canInteract: widget.canInteract,
    );
    return IosNativeTabBarScope(
      coordinator: _coordinator,
      child: ListenableBuilder(
        listenable: _coordinator,
        builder: (context, _) {
          final visual = _coordinator._visual;
          final owner = _coordinator._active;
          final hasOwner = owner?._latest != null;
          final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
          final hidden =
              widget.hideImmediately ||
              widget.covered ||
              !hasOwner ||
              visual == null ||
              visual.mode != MobileNavigationMode.bottomTabs ||
              visual.covered ||
              visual.configuration.hidden ||
              !visual.configuration.inputEnabled ||
              _coordinator._overlayCovered ||
              keyboard;
          // Keep the router/payment subtree in the same first-child position
          // while capability, ownership and native presentation change.
          return Stack(
            fit: StackFit.expand,
            clipBehavior: Clip.none,
            children: [
              widget.child,
              if (_nativeCandidate && visual != null)
                Positioned(
                  left: visual.viewport.left,
                  width: visual.viewport.width,
                  bottom:
                      MediaQuery.sizeOf(context).height -
                      visual.viewport.bottom,
                  child: MediaQuery(
                    data: visual.media.copyWith(
                      viewInsets: MediaQuery.viewInsetsOf(context),
                    ),
                    child: IosNativeTabBarHost(
                      configuration: IosNativeTabBarConfiguration(
                        items: visual.configuration.items,
                        selectedId: visual.configuration.selectedId,
                        hidden: hidden,
                        hideImmediately:
                            hidden &&
                            (widget.hideImmediately ||
                                visual.configuration.hideImmediately),
                        inputEnabled: !hidden && _coordinator._maySelect,
                        onSelect: _coordinator.select,
                        readSelectedId: _coordinator._readSelectedId,
                      ),
                      onHeightChanged: _coordinator._setHeight,
                      builder: (_, nativeBar) {
                        _coordinator._availability(nativeBar != null);
                        return nativeBar ?? const SizedBox.shrink();
                      },
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class IosNativeTabBarScope
    extends InheritedNotifier<IosNativeTabBarCoordinator> {
  const IosNativeTabBarScope({
    required IosNativeTabBarCoordinator coordinator,
    required super.child,
    super.key,
  }) : super(notifier: coordinator);

  static IosNativeTabBarCoordinator? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<IosNativeTabBarScope>()
      ?.notifier;
}

/// Leases invalidate callbacks synchronously; visual publications notify only
/// after the current frame, so child builds never mutate a provider/ancestor.
class IosNativeTabBarCoordinator extends ChangeNotifier {
  IosNativeTabBarOwnerLease? _active;
  _Publication? _visual;
  Object? _visualOwner;
  final _overlays = <IosNativeTabBarOverlayLease>{};
  bool _suppressed = false;
  bool _covered = false;
  Object? _sessionIdentity;
  bool Function()? _canInteract;
  bool? _nativeAvailable;
  double? _height;
  bool _scheduled = false;
  bool _disposed = false;

  bool get usesNativeLayout => _nativeCandidate && _nativeAvailable != false;
  double heightFor(MediaQueryData media) =>
      _height ?? 49 + media.viewPadding.bottom;
  bool get _overlayCovered => _overlays.any((overlay) => overlay._displayed);

  IosNativeTabBarOwnerLease acquireOwner({required bool Function() canSelect}) {
    final lease = IosNativeTabBarOwnerLease._(this, canSelect);
    _active = lease;
    _changed();
    return lease;
  }

  IosNativeTabBarOverlayLease acquireOverlay() {
    final lease = IosNativeTabBarOverlayLease._(this);
    _overlays.add(lease);
    return lease;
  }

  void _environment({
    required bool suppressed,
    required bool covered,
    required Object? sessionIdentity,
    required bool Function()? canInteract,
  }) {
    final changed =
        _suppressed != suppressed ||
        _covered != covered ||
        _sessionIdentity != sessionIdentity;
    _suppressed = suppressed;
    _covered = covered;
    _sessionIdentity = sessionIdentity;
    _canInteract = canInteract;
    if (changed) _changed();
  }

  bool get _maySelect {
    final owner = _active;
    final publication = owner?._latest;
    return !_disposed &&
        !_suppressed &&
        !_covered &&
        !_overlayCovered &&
        (_canInteract?.call() ?? true) &&
        owner != null &&
        owner._alive &&
        publication != null &&
        publication.sessionIdentity == _sessionIdentity &&
        publication.mode == MobileNavigationMode.bottomTabs &&
        !publication.covered &&
        !publication.configuration.hidden &&
        publication.configuration.inputEnabled &&
        owner._canSelect();
  }

  void select(String id) {
    if (!_maySelect) return;
    final configuration = _active!._latest!.configuration;
    if (!configuration.items.any((item) => item.id == id)) return;
    configuration.onSelect(id);
  }

  String _readSelectedId() {
    final owner = _active;
    final publication = owner?._latest;
    if (owner != null &&
        owner._alive &&
        publication != null &&
        publication.sessionIdentity == _sessionIdentity) {
      return publication.configuration.readSelectedId?.call() ??
          publication.configuration.selectedId;
    }
    return _visual!.configuration.selectedId;
  }

  void _publish(IosNativeTabBarOwnerLease owner, _Publication publication) {
    if (_disposed || !owner._alive || !identical(owner, _active)) return;
    owner._latest = publication;
    final visual = publication.withoutCallback();
    if (identical(_visualOwner, owner._token) &&
        _visual?.sameAs(visual) == true) {
      return;
    }
    _visual = visual;
    _visualOwner = owner._token;
    _changed();
  }

  void _release(IosNativeTabBarOwnerLease owner) {
    owner._latest = null;
    if (!identical(_active, owner)) return;
    _active = null;
    // Only immutable icon/title/geometry data survives for the normal exit.
    _changed();
  }

  void _availability(bool native) {
    if (_nativeAvailable == native) return;
    _nativeAvailable = native;
    _changed();
  }

  void _setHeight(double height) {
    if (_height != null && (_height! - height).abs() < 0.5) return;
    _height = height;
    _changed();
  }

  void _changed() {
    if (_scheduled || _disposed) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!_disposed) notifyListeners();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void dispose() {
    _disposed = true;
    _active?._latest = null;
    _active = null;
    _overlays.clear();
    super.dispose();
  }
}

class IosNativeTabBarOwnerLease {
  IosNativeTabBarOwnerLease._(this._coordinator, this._canSelect);
  final IosNativeTabBarCoordinator _coordinator;
  final bool Function() _canSelect;
  final _token = Object();
  bool _alive = true;
  _Publication? _latest;

  void publish({
    required IosNativeTabBarConfiguration configuration,
    required Rect viewport,
    required MediaQueryData media,
    required MobileNavigationMode mode,
    bool covered = false,
  }) => _coordinator._publish(
    this,
    _Publication(
      configuration: configuration,
      viewport: viewport,
      media: media,
      mode: mode,
      covered: covered,
      sessionIdentity: _coordinator._sessionIdentity,
    ),
  );

  void release() {
    if (!_alive) return;
    _alive = false;
    _coordinator._release(this);
  }
}

class IosNativeTabBarOverlayLease {
  IosNativeTabBarOverlayLease._(this._coordinator);
  final IosNativeTabBarCoordinator _coordinator;
  bool _alive = true;
  bool _displayed = false;

  void setDisplayed(bool displayed) {
    if (!_alive || displayed == _displayed) return;
    _displayed = displayed;
    _coordinator._changed();
  }

  void release() {
    if (!_alive) return;
    _alive = false;
    _coordinator._overlays.remove(this);
    _coordinator._changed();
  }
}

class _Publication {
  const _Publication({
    required this.configuration,
    required this.viewport,
    required this.media,
    required this.mode,
    required this.covered,
    required this.sessionIdentity,
  });
  final IosNativeTabBarConfiguration configuration;
  final Rect viewport;
  final MediaQueryData media;
  final MobileNavigationMode mode;
  final bool covered;
  final Object? sessionIdentity;

  _Publication withoutCallback() => _Publication(
    configuration: IosNativeTabBarConfiguration(
      items: List.unmodifiable(configuration.items),
      selectedId: configuration.selectedId,
      onSelect: _ignoreSelection,
      hidden: configuration.hidden,
      inputEnabled: configuration.inputEnabled,
      hideImmediately: configuration.hideImmediately,
    ),
    viewport: viewport,
    media: media,
    mode: mode,
    covered: covered,
    sessionIdentity: sessionIdentity,
  );

  bool sameAs(_Publication other) =>
      viewport == other.viewport &&
      media == other.media &&
      mode == other.mode &&
      covered == other.covered &&
      sessionIdentity == other.sessionIdentity &&
      configuration.selectedId == other.configuration.selectedId &&
      configuration.hidden == other.configuration.hidden &&
      configuration.inputEnabled == other.configuration.inputEnabled &&
      configuration.hideImmediately == other.configuration.hideImmediately &&
      listEquals(
        [
          for (final item in configuration.items)
            (item.id, item.iconName, item.label),
        ],
        [
          for (final item in other.configuration.items)
            (item.id, item.iconName, item.label),
        ],
      );
}

/// The tab shell publishes ownership and leaves only a transparent fitting slot.
class IosNativeTabBarRegistration extends StatefulWidget {
  const IosNativeTabBarRegistration({
    required this.configuration,
    required this.builder,
    super.key,
  });
  final IosNativeTabBarConfiguration configuration;
  final Widget Function(BuildContext context, Widget? nativeSlot) builder;

  @override
  State<IosNativeTabBarRegistration> createState() =>
      _IosNativeTabBarRegistrationState();
}

class _IosNativeTabBarRegistrationState
    extends State<IosNativeTabBarRegistration> {
  IosNativeTabBarCoordinator? _coordinator;
  IosNativeTabBarOwnerLease? _lease;
  final _observers = <RouteOwnedNavigationObserver>{};
  final _animations = <Animation<double>>{};
  List<ModalRoute<dynamic>> _routes = [];
  bool _scheduled = false;

  bool get _routeReady =>
      _routes.every(
        (route) =>
            route.isActive &&
            route.isCurrent &&
            (route.secondaryAnimation?.value ?? 0) <= 0.0001,
      ) &&
      _observers.every((observer) => !observer.hasDepartingRoutes);

  bool _canSelect() =>
      mounted &&
      _routeReady &&
      TickerMode.valuesOf(context).enabled &&
      widget.configuration.inputEnabled &&
      !widget.configuration.hidden &&
      MediaQuery.viewInsetsOf(context).bottom == 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final coordinator = IosNativeTabBarScope.maybeOf(context)!;
    if (!identical(_coordinator, coordinator)) {
      _lease?.release();
      _coordinator = coordinator;
      _lease = coordinator.acquireOwner(canSelect: _canSelect);
    }
    final routes = <ModalRoute<dynamic>>[];
    var route = ModalRoute.of(context);
    while (route != null) {
      routes.add(route);
      final parent = route.navigator?.context;
      route = parent == null ? null : ModalRoute.of(parent);
    }
    _routes = routes;
    final observers = {
      for (final route in routes)
        ...?route.navigator?.widget.observers
            .whereType<RouteOwnedNavigationObserver>(),
    };
    for (final observer in _observers.difference(observers)) {
      observer.removeListener(_schedule);
    }
    for (final observer in observers.difference(_observers)) {
      observer.addListener(_schedule);
    }
    _observers
      ..clear()
      ..addAll(observers);
    final animations = {
      for (final route in routes) ...[
        ?route.animation,
        ?route.secondaryAnimation,
      ],
    };
    for (final animation in _animations.difference(animations)) {
      animation.removeStatusListener(_animationChanged);
    }
    for (final animation in animations.difference(_animations)) {
      animation.addStatusListener(_animationChanged);
    }
    _animations
      ..clear()
      ..addAll(animations);
    _schedule();
  }

  void _animationChanged(AnimationStatus _) => _schedule();

  @override
  void didUpdateWidget(covariant IosNativeTabBarRegistration oldWidget) {
    super.didUpdateWidget(oldWidget);
    _schedule();
  }

  void _schedule() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) return;
      final navigation = MobileNavigationScope.maybeOf(context);
      final media = MediaQuery.of(context);
      _lease!.publish(
        configuration: widget.configuration,
        viewport: navigation?.viewportRect ?? Offset.zero & media.size,
        media: media,
        mode: navigation?.mode ?? MobileNavigationMode.bottomTabs,
        covered: !_routeReady || !TickerMode.valuesOf(context).enabled,
      );
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void dispose() {
    _lease?.release();
    for (final observer in _observers) {
      observer.removeListener(_schedule);
    }
    for (final animation in _animations) {
      animation.removeStatusListener(_animationChanged);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _schedule();
    final coordinator = IosNativeTabBarScope.maybeOf(context)!;
    final mode =
        MobileNavigationScope.maybeOf(context)?.mode ??
        MobileNavigationMode.bottomTabs;
    return widget.builder(
      context,
      coordinator.usesNativeLayout && mode == MobileNavigationMode.bottomTabs
          ? SizedBox(
              key: const ValueKey('ios_native_tab_bar_slot'),
              height: coordinator.heightFor(MediaQuery.of(context)),
            )
          : null,
    );
  }
}
