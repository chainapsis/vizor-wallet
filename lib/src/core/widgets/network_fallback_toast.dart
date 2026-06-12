import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';

class NetworkFallbackToast extends StatelessWidget {
  const NetworkFallbackToast({required this.message, super.key});

  static const defaultDuration = Duration(seconds: 4);

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = AppTheme.of(context) == AppThemeData.dark;

    return DefaultTextStyle.merge(
      style: const TextStyle(decoration: TextDecoration.none),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.background.ground,
            borderRadius: BorderRadius.circular(AppRadii.small),
            border: isDark ? Border.all(color: colors.border.subtle) : null,
            boxShadow: isDark
                ? null
                : const [
                    BoxShadow(
                      color: Color(0xFFE1E1E1),
                      offset: Offset(0, 2),
                      blurRadius: 2,
                    ),
                    BoxShadow(
                      color: Color(0xFFE1E1E1),
                      offset: Offset(0, 10),
                      blurRadius: 15,
                    ),
                  ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s,
              vertical: AppSpacing.xs,
            ),
            child: Text(
              message,
              // Two lines: the failover messages don't fit one line on
              // a phone width; desktop stays single-line under the
              // 560px cap.
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: AppTypography.labelLarge.copyWith(
                color: colors.text.accent,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class NetworkFallbackToastHost extends StatefulWidget {
  const NetworkFallbackToastHost({required this.child, super.key});

  static const animationDuration = Duration(milliseconds: 220);

  final Widget child;

  @override
  State<NetworkFallbackToastHost> createState() =>
      _NetworkFallbackToastHostState();
}

class _NetworkFallbackToastHostState extends State<NetworkFallbackToastHost> {
  static final List<_NetworkFallbackToastHostState> _activeStates = [];

  String? _message;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _activeStates.add(this);
  }

  void show(
    String message, {
    Duration duration = NetworkFallbackToast.defaultDuration,
  }) {
    _timer?.cancel();
    setState(() {
      _message = message;
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
    // The host mounts in MaterialApp.builder, above every screen and
    // any SafeArea, so it must keep the toast clear of the status bar
    // / Dynamic Island itself; on desktop the window has no top inset
    // and this resolves to the original 32px offset.
    final topInset = math.max(
      AppSpacing.base,
      MediaQuery.paddingOf(context).top + AppSpacing.xs,
    );
    return _NetworkFallbackToastScope(
      state: this,
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          Positioned(
            top: topInset,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Center(
                // The horizontal padding keeps long messages off the
                // screen edges on phones narrower than the 560px cap.
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                  ),
                  child: AnimatedSwitcher(
                    duration: NetworkFallbackToastHost.animationDuration,
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) {
                      final position = Tween<Offset>(
                        begin: const Offset(0, -1),
                        end: Offset.zero,
                      ).animate(animation);
                      return SlideTransition(position: position, child: child);
                    },
                    child: message == null
                        ? const SizedBox.shrink(
                            key: ValueKey('empty-network-fallback-toast'),
                          )
                        : NetworkFallbackToast(
                            key: ValueKey(message),
                            message: message,
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

void showNetworkFallbackToast(
  BuildContext context,
  String message, {
  Duration duration = NetworkFallbackToast.defaultDuration,
}) {
  final element = context
      .getElementForInheritedWidgetOfExactType<_NetworkFallbackToastScope>();
  final scope = element?.widget as _NetworkFallbackToastScope?;
  final state =
      scope?.state ??
      (_NetworkFallbackToastHostState._activeStates.isEmpty
          ? null
          : _NetworkFallbackToastHostState._activeStates.last);
  assert(
    state != null,
    'showNetworkFallbackToast called without a NetworkFallbackToastHost '
    'ancestor.',
  );
  state?.show(message, duration: duration);
}

class _NetworkFallbackToastScope extends InheritedWidget {
  const _NetworkFallbackToastScope({required this.state, required super.child});

  final _NetworkFallbackToastHostState state;

  @override
  bool updateShouldNotify(_NetworkFallbackToastScope oldWidget) =>
      state != oldWidget.state;
}
