import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/app_security_provider.dart';
import '../../providers/payment_request_flow_provider.dart';
import '../../providers/sync_keep_awake_provider.dart';
import '../../providers/wallet_provider.dart';
import '../navigation/external_action_guard_provider.dart';
import 'app_review.dart';

/// Root sheets/dialogs and imperative routes must not be covered by a review.
class AppReviewRouteObserver extends NavigatorObserver with ChangeNotifier {
  final Set<Route<dynamic>> _transient = {};
  bool _disposed = false;
  bool get isBlocked => _transient.isNotEmpty;

  void _changed() => scheduleMicrotask(() {
    if (!_disposed) notifyListeners();
  });

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route.settings is! Page) _transient.add(route);
    _changed();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _transient.remove(route);
    _changed();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _transient.remove(route);
    _changed();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _transient.remove(oldRoute);
    if (newRoute != null && newRoute.settings is! Page) {
      _transient.add(newRoute);
    }
    _changed();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

final appReviewRouteObserverProvider = Provider<AppReviewRouteObserver>((ref) {
  final observer = AppReviewRouteObserver();
  ref.onDispose(observer.dispose);
  return observer;
});

final appReviewSurfaceSafeProvider = Provider<bool>((ref) {
  final security = ref.watch(appSecurityProvider);
  return security.isPasswordConfigured &&
      security.isUnlocked &&
      (ref.watch(walletProvider).value?.hasWallet ?? false) &&
      ref.watch(paymentRequestFlowProvider) == null &&
      !ref.watch(syncKeepAwakePrivacyLockProvider).isLocked &&
      !ref.watch(externalActionGuardProvider).blocks(ExternalAction.appReview);
});

/// Lives above the router to observe tab-bar interactions as well as home.
/// The indexed-stack home remaining mounted is not sufficient for visibility.
class AppReviewHost extends ConsumerWidget {
  const AppReviewHost({required this.router, required this.child, super.key});
  final GoRouter router;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(appReviewEnabledProvider)) return child;
    final hadWalletAtStartup = ref.watch(appReviewStartupWalletProvider);
    if (hadWalletAtStartup == null) return child;
    return AppReviewInteractionHost(
      router: router,
      controller: ref.watch(appReviewControllerProvider),
      observer: ref.watch(appReviewRouteObserverProvider),
      safe: ref.watch(appReviewSurfaceSafeProvider),
      readSafety: () => ref.read(appReviewSurfaceSafeProvider),
      hadWalletAtStartup: hadWalletAtStartup,
      child: child,
    );
  }
}

class AppReviewInteractionHost extends StatefulWidget {
  const AppReviewInteractionHost({
    required this.router,
    required this.controller,
    required this.observer,
    required this.safe,
    required this.readSafety,
    required this.child,
    this.hadWalletAtStartup = false,
    super.key,
  });
  final GoRouter router;
  final AppReviewController controller;
  final AppReviewRouteObserver observer;
  final bool safe;
  // Async continuations can run before the next frame updates [safe].
  final bool Function() readSafety;
  final Widget child;
  final bool hadWalletAtStartup;

  @override
  State<AppReviewInteractionHost> createState() =>
      _AppReviewInteractionHostState();
}

class _AppReviewInteractionHostState extends State<AppReviewInteractionHost>
    with WidgetsBindingObserver {
  Timer? _idle;
  int _epoch = 0;
  final Set<int> _pointers = {};

  // RouteMatchList.uri omits imperative pushes; state includes the top page.
  String get _path => widget.router.routerDelegate.state.uri.path;
  bool get _canPresent =>
      mounted &&
      widget.safe &&
      widget.readSafety() &&
      _path == '/home' &&
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed &&
      !widget.observer.isBlocked &&
      !widget.controller.isBusy &&
      _pointers.isEmpty &&
      (View.of(context).viewInsets.bottom == 0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_changed);
    widget.observer.addListener(_changed);
    widget.router.routerDelegate.addListener(_routeChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _foreground();
    });
  }

  void _foreground() {
    if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      unawaited(
        widget.controller.recordLaunch(
          hadWalletAtStartup: widget.hadWalletAtStartup,
        ),
      );
    }
    _changed();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      // A native interruption can swallow pointer-up events.
      _pointers.clear();
    }
    _foreground();
  }

  @override
  void didChangeMetrics() => _changed();

  @override
  void didUpdateWidget(AppReviewInteractionHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.safe != widget.safe) _changed();
  }

  void _routeChanged() {
    widget.controller.observePath(_path);
    _changed();
  }

  void _changed() {
    _epoch++;
    _idle?.cancel();
    if (!_canPresent || !widget.controller.isDue) return;
    final epoch = _epoch;
    _idle = Timer(const Duration(seconds: 2), () {
      if (epoch != _epoch || !_canPresent) return;
      unawaited(
        widget.controller.requestIfDue(() => epoch == _epoch && _canPresent),
      );
    });
  }

  bool _onScroll(ScrollNotification event) {
    if (_path != '/home' || widget.observer.isBlocked) return false;
    if (event is ScrollUpdateNotification &&
        event.dragDetails != null &&
        event.scrollDelta != 0 &&
        widget.readSafety()) {
      widget.controller.recordUse();
    }
    // Every update, including ballistic/programmatic scrolling, restarts the
    // idle window. No scroll-end latch: a covering sheet can swallow that end.
    _changed();
    return false;
  }

  @override
  void dispose() {
    _epoch++;
    _idle?.cancel();
    widget.controller.removeListener(_changed);
    widget.observer.removeListener(_changed);
    widget.router.routerDelegate.removeListener(_routeChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: (event) {
      _pointers.add(event.pointer);
      _changed();
    },
    onPointerMove: (_) => _changed(),
    onPointerUp: (event) {
      _pointers.remove(event.pointer);
      _changed();
    },
    onPointerCancel: (event) {
      _pointers.remove(event.pointer);
      _changed();
    },
    child: NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: widget.child,
    ),
  );
}
