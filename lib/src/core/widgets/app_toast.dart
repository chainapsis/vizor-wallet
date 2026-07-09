import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';
import 'app_icon.dart';

enum AppToastTone { neutral, destructive }

class AppToast extends StatelessWidget {
  const AppToast({
    required this.message,
    this.iconName = AppIcons.checkCircle,
    this.tone = AppToastTone.neutral,
    super.key,
  });

  static const defaultDuration = Duration(seconds: 2);

  final String message;
  final String iconName;
  final AppToastTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final backgroundColor = switch (tone) {
      AppToastTone.neutral => colors.background.inverse,
      AppToastTone.destructive => colors.background.utilityDestructiveStrong,
    };
    final textColor = colors.text.inverse;
    final iconColor = colors.icon.inverse;
    final textStyle = switch (tone) {
      AppToastTone.neutral => AppTypography.labelLarge,
      AppToastTone.destructive => AppTypography.labelLarge.copyWith(
        fontWeight: FontWeight.w400,
      ),
    };
    return DefaultTextStyle.merge(
      style: const TextStyle(decoration: TextDecoration.none),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(AppRadii.small),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s,
            vertical: AppSpacing.xs,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AppIcon(iconName, size: AppIconSize.medium, color: iconColor),
              const SizedBox(width: AppSpacing.xxs),
              // Flexible so long messages wrap inside the pill instead of
              // overflowing the row off-screen.
              Flexible(
                child: Text(
                  message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: textStyle.copyWith(color: textColor),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AppToastHost extends StatefulWidget {
  const AppToastHost({required this.child, super.key});

  final Widget child;

  @override
  State<AppToastHost> createState() => _AppToastHostState();
}

class _AppToastHostState extends State<AppToastHost> {
  static final List<_AppToastHostState> _activeStates = [];
  static OverlayEntry? _fallbackOverlayEntry;

  static _AppToastHostState? get _lastActiveState {
    for (final state in _activeStates.reversed) {
      if (state.mounted) return state;
    }
    return null;
  }

  String? _message;
  String _iconName = AppIcons.checkCircle;
  AppToastTone _tone = AppToastTone.neutral;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _activeStates.add(this);
  }

  void show(
    String message, {
    Duration duration = AppToast.defaultDuration,
    String iconName = AppIcons.checkCircle,
    AppToastTone tone = AppToastTone.neutral,
  }) {
    _timer?.cancel();
    setState(() {
      _message = message;
      _iconName = iconName;
      _tone = tone;
    });
    _timer = Timer(duration, () {
      if (!mounted) return;
      setState(() {
        _message = null;
      });
    });
  }

  @override
  void dispose() {
    _activeStates.remove(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final message = _message;
    // Hosts mounted outside a SafeArea (the mobile screens) must keep
    // the toast clear of the status bar / notch; inside a SafeArea the
    // ambient padding is already consumed and this resolves to the
    // original 32px offset, so desktop is unchanged.
    final topInset = math.max(
      AppSpacing.base,
      MediaQuery.paddingOf(context).top + AppSpacing.xs,
    );
    return _AppToastScope(
      state: this,
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (message != null)
            Positioned(
              top: topInset,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                    ),
                    child: AppToast(
                      message: message,
                      iconName: _iconName,
                      tone: _tone,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

void showAppToast(
  BuildContext context,
  String message, {
  Duration duration = AppToast.defaultDuration,
  String iconName = AppIcons.checkCircle,
  AppToastTone tone = AppToastTone.neutral,
}) {
  // 1. A direct host scope (the toast renders inside the nearest
  //    AppToastHost, which is under the app's AppTheme).
  final element =
      context.getElementForInheritedWidgetOfExactType<_AppToastScope>();
  final scope = element?.widget as _AppToastScope?;
  if (scope != null) {
    scope.state.show(
      message,
      duration: duration,
      iconName: iconName,
      tone: tone,
    );
    return;
  }

  // 2. No direct host scope. If the most-recently-active host lives on the
  //    SAME route as the caller, it is not covered by a modal — render there
  //    (it sits under the app's AppTheme).
  final fallbackState = _AppToastHostState._lastActiveState;
  if (fallbackState != null &&
      _canUseToastHostForContext(context, fallbackState.context)) {
    fallbackState.show(
      message,
      duration: duration,
      iconName: iconName,
      tone: tone,
    );
    return;
  }

  // 3. The host is covered by a modal route / bottom sheet (or there is no
  //    host): render in the root overlay so the toast floats ABOVE the modal
  //    — e.g. copying an address from the accounts sheet on mobile home. The
  //    root overlay is mounted above the app's AppTheme, so capture the
  //    ambient theme here and re-provide it around the overlay toast;
  //    otherwise AppToast.build cannot resolve tokens and throws.
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay != null) {
    final themeElement =
        context.getElementForInheritedWidgetOfExactType<AppTheme>();
    final theme = (themeElement?.widget as AppTheme?)?.data;
    _showOverlayToast(
      overlay,
      message,
      duration: duration,
      iconName: iconName,
      tone: tone,
      theme: theme,
    );
    return;
  }

  // 4. Last resort for overlay-less subtrees: the most recently active host,
  //    even if it is covered.
  if (fallbackState != null) {
    fallbackState.show(
      message,
      duration: duration,
      iconName: iconName,
      tone: tone,
    );
    return;
  }
  assert(
    fallbackState != null,
    'showAppToast called without an AppToastHost ancestor.',
  );
}

bool _canUseToastHostForContext(
  BuildContext toastContext,
  BuildContext hostContext,
) {
  final toastRoute = ModalRoute.of(toastContext);
  final hostRoute = ModalRoute.of(hostContext);
  if (toastRoute == null || hostRoute == null) return true;
  return identical(toastRoute, hostRoute);
}

void _showOverlayToast(
  OverlayState overlay,
  String message, {
  required Duration duration,
  required String iconName,
  required AppToastTone tone,
  required AppThemeData? theme,
}) {
  final previousEntry = _AppToastHostState._fallbackOverlayEntry;
  if (previousEntry?.mounted ?? false) {
    previousEntry?.remove();
  }
  _AppToastHostState._fallbackOverlayEntry = null;

  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder:
        (_) => _OverlayAppToast(
          message: message,
          iconName: iconName,
          tone: tone,
          duration: duration,
          theme: theme,
          onDismiss: () {
            if (_AppToastHostState._fallbackOverlayEntry == entry) {
              _AppToastHostState._fallbackOverlayEntry = null;
            }
            if (entry.mounted) {
              entry.remove();
            }
          },
          onDisposed: () {
            if (_AppToastHostState._fallbackOverlayEntry == entry) {
              _AppToastHostState._fallbackOverlayEntry = null;
            }
          },
        ),
  );

  _AppToastHostState._fallbackOverlayEntry = entry;
  overlay.insert(entry);
}

class _OverlayAppToast extends StatefulWidget {
  const _OverlayAppToast({
    required this.message,
    required this.iconName,
    required this.tone,
    required this.duration,
    required this.theme,
    required this.onDismiss,
    required this.onDisposed,
  });

  final String message;
  final String iconName;
  final AppToastTone tone;
  final Duration duration;
  final AppThemeData? theme;
  final VoidCallback onDismiss;
  final VoidCallback onDisposed;

  @override
  State<_OverlayAppToast> createState() => _OverlayAppToastState();
}

class _OverlayAppToastState extends State<_OverlayAppToast> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.duration, widget.onDismiss);
  }

  @override
  void didUpdateWidget(_OverlayAppToast oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.duration != widget.duration ||
        oldWidget.onDismiss != widget.onDismiss) {
      _timer?.cancel();
      _timer = Timer(widget.duration, widget.onDismiss);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.onDisposed();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topInset = math.max(
      AppSpacing.base,
      MediaQuery.paddingOf(context).top + AppSpacing.xs,
    );
    final theme = widget.theme;
    Widget toast = AppToast(
      message: widget.message,
      iconName: widget.iconName,
      tone: widget.tone,
    );
    // The root overlay sits above the app's AppTheme, so re-provide the
    // ambient theme captured at call time; otherwise AppToast cannot resolve
    // tokens here.
    if (theme != null) {
      toast = AppTheme(data: theme, child: toast);
    }
    return Positioned(
      top: topInset,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: toast,
          ),
        ),
      ),
    );
  }
}

class _AppToastScope extends InheritedWidget {
  const _AppToastScope({required this.state, required super.child});

  final _AppToastHostState state;

  @override
  bool updateShouldNotify(_AppToastScope oldWidget) => state != oldWidget.state;
}
