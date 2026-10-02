import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter/material.dart'
    show TextButton, IconButton, ButtonStyle, MaterialTapTargetSize;

import '../theme/app_theme.dart';
import 'app_icon.dart';

enum AppToastTone { neutral, destructive }

class AppToastAction {
  const AppToastAction({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;
}

const _kToastIconSize = 20.0;
const _kDestructiveToastForeground = Color(0xFFFFFFFF);

class AppToast extends StatelessWidget {
  const AppToast({
    required this.message,
    this.iconName = AppIcons.checkCircle,
    this.tone = AppToastTone.neutral,
    this.action,
    this.onDismiss,
    super.key,
  });

  static const defaultDuration = Duration(seconds: 2);

  final String message;
  final String iconName;
  final AppToastTone tone;
  final AppToastAction? action;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final backgroundColor = switch (tone) {
      AppToastTone.neutral => colors.background.inverse,
      AppToastTone.destructive => colors.background.utilityDestructiveStrong,
    };
    final textColor = switch (tone) {
      AppToastTone.neutral => colors.text.inverse,
      AppToastTone.destructive => _kDestructiveToastForeground,
    };
    final iconColor = switch (tone) {
      AppToastTone.neutral => colors.icon.inverse,
      AppToastTone.destructive => _kDestructiveToastForeground,
    };
    final textStyle = switch (tone) {
      AppToastTone.neutral => AppTypography.labelLarge,
      AppToastTone.destructive => AppTypography.labelLarge.copyWith(
        fontWeight: FontWeight.w400,
      ),
    };
    final dismissButton = onDismiss == null
        ? null
        : IconButton(
            onPressed: onDismiss,
            constraints: const BoxConstraints.tightFor(width: 44, height: 44),
            style: const ButtonStyle(
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: Semantics(
              label: 'Dismiss notification',
              excludeSemantics: true,
              child: AppIcon(
                AppIcons.cross,
                size: _kToastIconSize,
                color: iconColor,
              ),
            ),
          );
    final action = this.action;
    return Semantics(
      container: true,
      liveRegion: true,
      child: DefaultTextStyle.merge(
        style: const TextStyle(decoration: TextDecoration.none),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(AppRadii.small),
          ),
          child: Padding(
            padding: EdgeInsetsDirectional.fromSTEB(
              AppSpacing.s,
              AppSpacing.xs,
              action != null && dismissButton != null ? 0 : AppSpacing.s,
              AppSpacing.xs,
            ),
            child: action != null
                ? _actionContent(
                    context,
                    action: action,
                    dismissButton: dismissButton,
                    textColor: textColor,
                    iconColor: iconColor,
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ExcludeSemantics(
                        child: AppIcon(
                          iconName,
                          size: _kToastIconSize,
                          color: iconColor,
                        ),
                      ),
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
                      ?dismissButton,
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _actionContent(
    BuildContext context, {
    required AppToastAction action,
    required Widget? dismissButton,
    required Color textColor,
    required Color iconColor,
  }) {
    final messageStyle = AppTypography.bodySmall.copyWith(color: textColor);
    final actionStyle = AppTypography.labelMedium.copyWith(
      color: textColor,
      decoration: TextDecoration.underline,
      decorationColor: textColor,
    );
    final textScaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    double textWidth(String value, TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(text: value, style: style),
        textDirection: direction,
        textScaler: textScaler,
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    }

    final actionWidth = math.max(44, textWidth(action.label, actionStyle));
    // Keep the compact row while the message can occupy roughly two lines.
    // Large text or longer labels get an action below the same leading edge.
    final minimumMessageWidth = textWidth(message, messageStyle) / 2;
    final icon = ExcludeSemantics(
      child: AppIcon(iconName, size: _kToastIconSize, color: iconColor),
    );
    final messageText = Text(message, style: messageStyle);
    final actionButton = TextButton(
      onPressed: action.onPressed,
      style: ButtonStyle(
        foregroundColor: WidgetStatePropertyAll(textColor),
        textStyle: WidgetStatePropertyAll(actionStyle),
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        minimumSize: const WidgetStatePropertyAll(Size(44, 44)),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        alignment: AlignmentDirectional.centerStart,
      ),
      child: Text(action.label),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final controlsWidth =
            _kToastIconSize +
            AppSpacing.xs * 2 +
            actionWidth +
            (dismissButton == null ? 0 : 44);
        if (constraints.maxWidth - controlsWidth >= minimumMessageWidth) {
          return Row(
            children: [
              icon,
              const SizedBox(width: AppSpacing.xs),
              Expanded(child: messageText),
              const SizedBox(width: AppSpacing.xs),
              actionButton,
              ?dismissButton,
            ],
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                icon,
                const SizedBox(width: AppSpacing.xs),
                Expanded(child: messageText),
                ?dismissButton,
              ],
            ),
            Padding(
              padding: const EdgeInsetsDirectional.only(
                start: _kToastIconSize + AppSpacing.xs,
              ),
              child: actionButton,
            ),
          ],
        );
      },
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
  AppToastAction? _action;
  bool _dismissible = false;
  Timer? _timer;
  Object? _toastId;

  @override
  void initState() {
    super.initState();
    _activeStates.add(this);
  }

  VoidCallback show(
    String message, {
    Duration? duration = AppToast.defaultDuration,
    String iconName = AppIcons.checkCircle,
    AppToastTone tone = AppToastTone.neutral,
    AppToastAction? action,
  }) {
    _timer?.cancel();
    final toastId = _toastId = Object();
    setState(() {
      _message = message;
      _iconName = iconName;
      _tone = tone;
      _action = action;
      _dismissible = duration == null;
    });
    _timer = duration == null ? null : Timer(duration, dismiss);
    return () {
      if (identical(_toastId, toastId)) dismiss();
    };
  }

  void dismiss() {
    _timer?.cancel();
    _toastId = null;
    if (mounted) setState(() => _message = null);
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
                ignoring: _action == null && !_dismissible,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                    ),
                    child: AppToast(
                      message: message,
                      iconName: _iconName,
                      tone: _tone,
                      onDismiss: _dismissible ? dismiss : null,
                      action: _action == null
                          ? null
                          : AppToastAction(
                              label: _action!.label,
                              onPressed: () {
                                final action = _action!;
                                dismiss();
                                action.onPressed();
                              },
                            ),
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

/// Returns a dismissal callback scoped to this notification. Callers that keep
/// an actionable toast visible can dismiss it when its screen becomes hidden.
VoidCallback? showAppToast(
  BuildContext context,
  String message, {
  Duration? duration = AppToast.defaultDuration,
  String iconName = AppIcons.checkCircle,
  AppToastTone tone = AppToastTone.neutral,
  AppToastAction? action,
}) {
  // 1. A direct host scope (the toast renders inside the nearest
  //    AppToastHost, which is under the app's AppTheme).
  final element = context
      .getElementForInheritedWidgetOfExactType<_AppToastScope>();
  final scope = element?.widget as _AppToastScope?;
  if (scope != null) {
    return scope.state.show(
      message,
      duration: duration,
      iconName: iconName,
      tone: tone,
      action: action,
    );
  }

  // 2. No direct host scope. If the most-recently-active host lives on the
  //    SAME route as the caller, it is not covered by a modal — render there
  //    (it sits under the app's AppTheme).
  final fallbackState = _AppToastHostState._lastActiveState;
  if (fallbackState != null &&
      _canUseToastHostForContext(context, fallbackState.context)) {
    return fallbackState.show(
      message,
      duration: duration,
      iconName: iconName,
      tone: tone,
      action: action,
    );
  }

  // 3. The host is covered by a modal route / bottom sheet (or there is no
  //    host): render in the root overlay so the toast floats ABOVE the modal
  //    — e.g. copying an address from the accounts sheet on mobile home. The
  //    root overlay is mounted above the app's AppTheme, so capture the
  //    ambient theme here and re-provide it around the overlay toast;
  //    otherwise AppToast.build cannot resolve tokens and throws.
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay != null) {
    final themeElement = context
        .getElementForInheritedWidgetOfExactType<AppTheme>();
    final theme = (themeElement?.widget as AppTheme?)?.data;
    return _showOverlayToast(
      overlay,
      message,
      duration: duration,
      iconName: iconName,
      tone: tone,
      theme: theme,
      action: action,
    );
  }

  // 4. Last resort for overlay-less subtrees: the most recently active host,
  //    even if it is covered.
  if (fallbackState != null) {
    return fallbackState.show(
      message,
      duration: duration,
      iconName: iconName,
      tone: tone,
      action: action,
    );
  }
  assert(
    fallbackState != null,
    'showAppToast called without an AppToastHost ancestor.',
  );
  return null;
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

VoidCallback _showOverlayToast(
  OverlayState overlay,
  String message, {
  required Duration? duration,
  required String iconName,
  required AppToastTone tone,
  required AppThemeData? theme,
  AppToastAction? action,
}) {
  final previousEntry = _AppToastHostState._fallbackOverlayEntry;
  if (previousEntry?.mounted ?? false) {
    previousEntry?.remove();
  }
  _AppToastHostState._fallbackOverlayEntry = null;

  late final OverlayEntry entry;
  void dismiss() {
    if (_AppToastHostState._fallbackOverlayEntry == entry) {
      _AppToastHostState._fallbackOverlayEntry = null;
    }
    if (entry.mounted) entry.remove();
  }

  entry = OverlayEntry(
    builder: (_) => _OverlayAppToast(
      message: message,
      iconName: iconName,
      tone: tone,
      duration: duration,
      theme: theme,
      action: action,
      onDismiss: dismiss,
      onDisposed: () {
        if (_AppToastHostState._fallbackOverlayEntry == entry) {
          _AppToastHostState._fallbackOverlayEntry = null;
        }
      },
    ),
  );

  _AppToastHostState._fallbackOverlayEntry = entry;
  overlay.insert(entry);
  return dismiss;
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
    this.action,
  });

  final String message;
  final String iconName;
  final AppToastTone tone;
  final Duration? duration;
  final AppThemeData? theme;
  final AppToastAction? action;
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
    final duration = widget.duration;
    if (duration != null) _timer = Timer(duration, widget.onDismiss);
  }

  @override
  void didUpdateWidget(_OverlayAppToast oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.duration != widget.duration ||
        oldWidget.onDismiss != widget.onDismiss) {
      _timer?.cancel();
      final duration = widget.duration;
      _timer = duration == null ? null : Timer(duration, widget.onDismiss);
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
      onDismiss: widget.duration == null ? widget.onDismiss : null,
      action: widget.action == null
          ? null
          : AppToastAction(
              label: widget.action!.label,
              onPressed: () {
                widget.onDismiss();
                widget.action!.onPressed();
              },
            ),
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
        ignoring: widget.action == null && widget.duration != null,
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
