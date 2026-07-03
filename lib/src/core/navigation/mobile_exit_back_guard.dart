import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemNavigator;

import '../../../l10n/app_localizations.dart';
import '../layout/app_form_factor.dart';
import '../theme/app_theme.dart';

class MobileExitBackGuard {
  MobileExitBackGuard({TargetPlatform? platform, DateTime Function()? now})
    : _platform = platform,
      _now = now ?? DateTime.now;

  static const exitHintMessage = 'Go back again to exit';
  static const confirmationWindow = Duration(seconds: 2);

  final TargetPlatform? _platform;
  final DateTime Function() _now;

  DateTime? _lastBackAt;
  String? _lastLocation;
  Timer? _resetTimer;

  bool get enabled =>
      kAppFormFactor == AppFormFactor.mobile &&
      (_platform ?? defaultTargetPlatform) == TargetPlatform.android;

  bool requestExit(
    BuildContext context, {
    required String location,
    OverlayState? overlay,
  }) {
    if (!enabled) return true;

    final now = _now();
    final previousBackAt = _lastBackAt;
    final confirmed =
        _lastLocation == location &&
        previousBackAt != null &&
        now.difference(previousBackAt) <= confirmationWindow;

    if (confirmed) {
      reset();
      _MobileExitBackHintOverlay.dismiss();
      return true;
    }

    _lastBackAt = now;
    _lastLocation = location;
    _scheduleReset();
    _MobileExitBackHintOverlay.show(context, overlay: overlay);
    return false;
  }

  void reset() {
    _resetTimer?.cancel();
    _resetTimer = null;
    _lastBackAt = null;
    _lastLocation = null;
  }

  void _scheduleReset() {
    _resetTimer?.cancel();
    _resetTimer = Timer(confirmationWindow, () {
      _resetTimer = null;
      _lastBackAt = null;
      _lastLocation = null;
    });
  }

  static void dismissVisibleHint() {
    _MobileExitBackHintOverlay.dismiss();
  }
}

class MobileExitBackDispatcher extends RootBackButtonDispatcher {
  MobileExitBackDispatcher({
    required MobileExitBackGuard exitBackGuard,
    required GlobalKey<NavigatorState> navigatorKey,
    required bool Function() canPop,
    required String Function() currentLocation,
  }) : _exitBackGuard = exitBackGuard,
       _navigatorKey = navigatorKey,
       _canPop = canPop,
       _currentLocation = currentLocation {
    if (_exitBackGuard.enabled) {
      _lifecycleListener = AppLifecycleListener(
        onInactive: _clearExitBackGuard,
        onHide: _clearExitBackGuard,
        onPause: _clearExitBackGuard,
        onShow: _clearExitBackGuard,
        onResume: _clearExitBackGuard,
      );
    }
  }

  final MobileExitBackGuard _exitBackGuard;
  final GlobalKey<NavigatorState> _navigatorKey;
  final bool Function() _canPop;
  final String Function() _currentLocation;
  AppLifecycleListener? _lifecycleListener;

  bool handleNavigationNotification(NavigationNotification notification) {
    if (!_exitBackGuard.enabled) {
      unawaited(
        SystemNavigator.setFrameworkHandlesBack(notification.canHandlePop),
      );
      return true;
    }

    unawaited(SystemNavigator.setFrameworkHandlesBack(true));
    return true;
  }

  @override
  Future<bool> invokeCallback(Future<bool> defaultValue) async {
    if (!_exitBackGuard.enabled) {
      return super.invokeCallback(defaultValue);
    }

    if (_canPop()) {
      final handledByRoute = await super.invokeCallback(
        Future<bool>.value(false),
      );
      if (handledByRoute) {
        _clearExitBackGuard();
        return true;
      }
    }

    final context = _navigatorKey.currentContext;
    final overlay = _navigatorKey.currentState?.overlay;
    if (context == null || overlay == null) return false;
    if (!context.mounted) return false;

    if (_exitBackGuard.requestExit(
      context,
      location: _currentLocation(),
      overlay: overlay,
    )) {
      unawaited(SystemNavigator.pop());
    }
    return true;
  }

  void dispose() {
    _lifecycleListener?.dispose();
    _clearExitBackGuard();
  }

  void _clearExitBackGuard() {
    _exitBackGuard.reset();
    MobileExitBackGuard.dismissVisibleHint();
  }
}

class _MobileExitBackHintOverlay {
  static OverlayEntry? _entry;
  static Timer? _timer;

  static void show(BuildContext context, {OverlayState? overlay}) {
    final targetOverlay =
        overlay ?? Overlay.maybeOf(context, rootOverlay: true);
    if (targetOverlay == null) return;

    final themeElement = context
        .getElementForInheritedWidgetOfExactType<AppTheme>();
    final theme =
        (themeElement?.widget as AppTheme?)?.data ??
        (MediaQuery.platformBrightnessOf(context) == Brightness.dark
            ? AppThemeData.dark
            : AppThemeData.light);

    dismiss();

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => AppTheme(
        data: theme,
        child: _MobileExitBackHint(
          message:
              Localizations.of<AppLocalizations>(
                context,
                AppLocalizations,
              )?.mobileExitBackHint ??
              MobileExitBackGuard.exitHintMessage,
        ),
      ),
    );
    _entry = entry;
    targetOverlay.insert(entry);
    _timer = Timer(MobileExitBackGuard.confirmationWindow, dismiss);
  }

  static void dismiss() {
    _timer?.cancel();
    _timer = null;
    final entry = _entry;
    _entry = null;
    if (entry?.mounted ?? false) {
      entry?.remove();
    }
  }
}

class _MobileExitBackHint extends StatelessWidget {
  const _MobileExitBackHint({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final bottomInset = math.max(
      MediaQuery.viewInsetsOf(context).bottom,
      MediaQuery.viewPaddingOf(context).bottom,
    );

    return Positioned.fill(
      child: IgnorePointer(
        child: SafeArea(
          minimum: EdgeInsets.fromLTRB(
            AppSpacing.sm,
            AppSpacing.sm,
            AppSpacing.sm,
            bottomInset + AppSpacing.sm,
          ),
          child: Align(
            alignment: const Alignment(0, 0.35),
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: 1),
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) => Opacity(
                opacity: value,
                child: Transform.translate(
                  offset: Offset(0, (1 - value) * AppSpacing.xs),
                  child: child,
                ),
              ),
              child: DecoratedBox(
                key: const ValueKey('mobile_exit_back_hint_surface'),
                decoration: BoxDecoration(
                  color: colors.background.inverse,
                  borderRadius: BorderRadius.circular(AppRadii.small),
                  boxShadow: [
                    BoxShadow(
                      color: colors.shadows.regular,
                      offset: const Offset(0, 8),
                      blurRadius: 24,
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.s,
                  ),
                  child: Text(
                    message,
                    key: const ValueKey('mobile_exit_back_hint_text'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: AppTypography.labelLarge.copyWith(
                      color: colors.text.inverse,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
