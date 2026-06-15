import 'dart:async';

import 'package:flutter/widgets.dart';

import '../layout/content_overlay_inset.dart';
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
              maxLines: 1,
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
    return _NetworkFallbackToastScope(
      state: this,
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          // Align with the content pane: a mounted sidebar shell publishes its
          // left inset, so the toast clears the sidebar; with no sidebar the
          // inset is 0 and the toast centers over the full window.
          ValueListenableBuilder<double>(
            valueListenable: contentOverlayLeftInset,
            builder: (context, leftInset, child) {
              return Positioned(
                top: AppSpacing.base,
                left: leftInset,
                right: 0,
                child: child!,
              );
            },
            child: IgnorePointer(
              child: Center(
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
