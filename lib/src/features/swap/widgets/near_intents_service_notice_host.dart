import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/layout/app_form_factor.dart';
import '../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../core/navigation/route_owned_redirect.dart';
import '../../../core/widgets/app_pane_modal_overlay.dart';
import '../domain/near_intents_service_status.dart';
import '../models/swap_models.dart';
import '../providers/near_intents_service_status_provider.dart';
import 'near_intents_service_notice.dart';

/// Owns one dismissible advisory on the first Swap/Pay screen. It keeps the
/// status subscription alive under its own mobile route, without making any
/// service status part of quote, payment or button eligibility.
class NearIntentsServiceNoticeHost extends ConsumerStatefulWidget {
  const NearIntentsServiceNoticeHost({
    required this.direction,
    required this.externalAsset,
    required this.child,
    this.enabled = true,
    this.blocked = false,
    this.payMode = false,
    super.key,
  });

  final SwapDirection direction;
  final SwapAsset externalAsset;
  final Widget child;
  final bool enabled;
  final bool blocked;
  final bool payMode;

  @override
  ConsumerState<NearIntentsServiceNoticeHost> createState() =>
      _NoticeHostState();
}

class _NoticeHostState extends ConsumerState<NearIntentsServiceNoticeHost> {
  final _seen = <String>{};
  final _presented = ValueNotifier<NearIntentsServiceNoticeData?>(null);
  List<ModalRoute<dynamic>> _pages = [];
  final _animations = <Animation<double>>{};
  final _observers = <RouteOwnedNavigationObserver>{};
  ModalRoute<void>? _mobileRoute;
  bool _closing = false;
  NearIntentsServiceNoticeData? _candidate;
  ProviderSubscription<NearIntentsServiceStatus>? _statusSubscription;
  NearIntentsServiceStatus? _status;
  bool _tickerEnabled = true;
  bool _scheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // go_router's retained tab navigators disable TickerMode when inactive.
    // A transparent sheet above this page leaves its ticker mode enabled.
    _tickerEnabled = TickerMode.valuesOf(context).enabled;
    final pages = <ModalRoute<dynamic>>[];
    var route = ModalRoute.of(context);
    while (route != null) {
      pages.add(route);
      final parent = route.navigator?.context;
      route = parent == null ? null : ModalRoute.of(parent);
    }
    _pages = pages;
    final observers = {
      for (final page in pages)
        ...?page.navigator?.widget.observers
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
    for (final animation in _animations) {
      animation.removeStatusListener(_animationChanged);
    }
    _animations
      ..clear()
      ..addAll({for (final page in pages) ?page.animation});
    for (final animation in _animations) {
      animation.addStatusListener(_animationChanged);
    }
  }

  void _animationChanged(AnimationStatus _) => _schedule();

  bool get _shouldPoll =>
      widget.enabled &&
      !widget.blocked &&
      _tickerEnabled &&
      _pages.every(
        (page) =>
            page.isActive &&
            (page.isCurrent ||
                (_mobileRoute?.isCurrent == true &&
                    page.navigator == _mobileRoute?.navigator)),
      );

  bool get _eligible =>
      _shouldPoll &&
      _observers.every((observer) => !observer.hasDepartingRoutes) &&
      _animations.every(
        (animation) => animation.status == AnimationStatus.completed,
      );

  void _schedule() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) return;
      _reconcile();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _reconcile() {
    // Navigation observers also wake this path when a nested parent route
    // changes without rebuilding the composer. Keep the subscription here so
    // route coverage and retained tabs govern polling as well as presentation.
    if (!_shouldPoll) {
      _statusSubscription?.close();
      _statusSubscription = null;
      _status = null;
    } else {
      _statusSubscription ??= ref.listenManual<NearIntentsServiceStatus>(
        nearIntentsServiceStatusProvider,
        (_, value) {
          _status = value;
          _schedule();
        },
        fireImmediately: true,
      );
    }
    _candidate = _status?.noticeFor(
      inputChain: widget.direction.fromAsset(widget.externalAsset).chainTicker,
      outputChain: widget.direction.toAsset(widget.externalAsset).chainTicker,
    );
    // A normal sheet pop keeps its contents throughout the exit animation.
    // The shared route's completion releases the data and our ownership.
    if (_closing || (_mobileRoute != null && !_mobileRoute!.isActive)) return;
    final notice = _candidate;
    if (!_eligible || notice == null) {
      _dismiss();
      return;
    }
    if (_presented.value == null &&
        notice.issues.every((issue) => _seen.contains(issue.noticeKey))) {
      return;
    }
    _seen.addAll(notice.issues.map((issue) => issue.noticeKey));
    _presented.value = notice;
    if (kAppFormFactor == AppFormFactor.mobile && _mobileRoute == null) {
      FocusManager.instance.primaryFocus?.unfocus();
      final popped = showAppMobileSheet<void>(
        context: context,
        onRouteCreated: (route) => _mobileRoute = route,
        builder: (_) => ValueListenableBuilder(
          valueListenable: _presented,
          builder: (_, value, _) => !mounted || value == null
              ? const SizedBox.shrink()
              : NearIntentsServiceNoticeContent(
                  notice: value,
                  payMode: widget.payMode,
                  onClose: _dismiss,
                  onDetails: _openDetails,
                ),
        ),
      );
      final route = _mobileRoute!;
      unawaited(
        popped.whenComplete(() async {
          await route.completed;
          if (!mounted || !identical(_mobileRoute, route)) return;
          _mobileRoute = null;
          _closing = false;
          _presented.value = null;
          _schedule();
        }),
      );
    }
  }

  void _dismiss() {
    if (!mounted) return;
    final route = _mobileRoute;
    if (route == null) {
      _presented.value = null;
      return;
    }
    if (_closing || !route.isActive) return;
    _closing = true;
    if (route.isCurrent) {
      route.navigator?.pop();
    } else {
      // A newer root screen owns the top of the stack. Remove only our sheet.
      route.navigator?.removeRoute(route);
    }
  }

  Future<void> _openDetails() async {
    try {
      await ref.read(nearIntentsServiceStatusPageLauncherProvider)(
        nearIntentsServiceStatusPage,
      );
    } catch (_) {
      // Optional external details must not interrupt the user's draft.
    }
  }

  Widget _modal(NearIntentsServiceNoticeData notice) =>
      NearIntentsServiceNoticeModal(
        notice: notice,
        payMode: widget.payMode,
        onClose: _dismiss,
        onDetails: _openDetails,
      );

  @override
  void dispose() {
    _statusSubscription?.close();
    for (final observer in _observers) {
      observer.removeListener(_schedule);
    }
    for (final animation in _animations) {
      animation.removeStatusListener(_animationChanged);
    }
    final route = _mobileRoute;
    if (route != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (route.isActive) route.navigator?.removeRoute(route);
      });
    }
    _presented.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _schedule();
    if (kAppFormFactor == AppFormFactor.mobile) return widget.child;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        ValueListenableBuilder(
          valueListenable: _presented,
          builder: (_, notice, _) => notice == null
              ? const SizedBox.shrink()
              : AppPaneModalOverlay(onDismiss: _dismiss, child: _modal(notice)),
        ),
      ],
    );
  }
}
