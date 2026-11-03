import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/layout/app_form_factor.dart';
import '../../../core/theme/app_theme.dart';
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
  RawDialogRoute<void>? _mobileRoute;
  NearIntentsServiceNoticeData? _candidate;
  bool _scheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
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

  bool get _eligible =>
      widget.enabled &&
      !widget.blocked &&
      _pages.every(
        (page) =>
            page.isActive &&
            (page.isCurrent ||
                (_mobileRoute?.isCurrent == true &&
                    page.navigator == _mobileRoute?.navigator)),
      ) &&
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
    if (_mobileRoute != null && !_mobileRoute!.isActive) {
      _mobileRoute = null;
      _presented.value = null;
    }
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
      final theme = context.appTheme;
      final route = RawDialogRoute<void>(
        barrierDismissible: true,
        barrierLabel: 'Dismiss service notice',
        barrierColor: context.colors.background.neutralScrim,
        transitionDuration: Duration.zero,
        pageBuilder: (routeContext, _, _) {
          ModalRoute.isCurrentOf(routeContext);
          _schedule();
          return AppTheme(
            data: theme,
            child: ValueListenableBuilder(
              valueListenable: _presented,
              builder: (context, value, _) => !mounted || value == null
                  ? const SizedBox.shrink()
                  : SafeArea(bottom: false, child: _modal(value)),
            ),
          );
        },
      );
      _mobileRoute = route;
      unawaited(
        Navigator.of(context, rootNavigator: true).push(route).whenComplete(() {
          if (!mounted || !identical(_mobileRoute, route)) return;
          _mobileRoute = null;
          _presented.value = null;
        }),
      );
    }
  }

  void _dismiss() {
    if (!mounted) return;
    _presented.value = null;
    final route = _mobileRoute;
    _mobileRoute = null;
    if (route != null && route.isActive) route.navigator?.removeRoute(route);
  }

  Widget _modal(NearIntentsServiceNoticeData notice) =>
      NearIntentsServiceNoticeModal(
        notice: notice,
        payMode: widget.payMode,
        onClose: _dismiss,
        onDetails: () async {
          try {
            await ref.read(nearIntentsServiceStatusPageLauncherProvider)(
              nearIntentsServiceStatusPage,
            );
          } catch (_) {
            // Optional external details must not interrupt the user's draft.
          }
        },
      );

  @override
  void dispose() {
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
    final status = widget.enabled
        ? ref.watch(nearIntentsServiceStatusProvider)
        : null;
    _candidate = status?.noticeFor(
      inputChain: widget.direction.fromAsset(widget.externalAsset).chainTicker,
      outputChain: widget.direction.toAsset(widget.externalAsset).chainTicker,
    );
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
