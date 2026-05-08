import 'dart:async';

import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';
import 'app_icon.dart';

class AppToast extends StatelessWidget {
  const AppToast({
    required this.message,
    this.iconName = AppIcons.checkCircle,
    super.key,
  });

  static const defaultDuration = Duration(seconds: 2);

  final String message;
  final String iconName;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.background.inverse,
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
            AppIcon(
              iconName,
              size: AppIconSize.medium,
              color: colors.icon.inverse,
            ),
            const SizedBox(width: AppSpacing.xxs),
            Text(
              message,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: AppTypography.labelLarge.copyWith(
                color: colors.text.inverse,
              ),
            ),
          ],
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

  String? _message;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _activeStates.add(this);
  }

  void show(String message, {Duration duration = AppToast.defaultDuration}) {
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
    return _AppToastScope(
      state: this,
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (message != null)
            Positioned(
              top: AppSpacing.base,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Center(child: AppToast(message: message)),
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
}) {
  final element = context
      .getElementForInheritedWidgetOfExactType<_AppToastScope>();
  final scope = element?.widget as _AppToastScope?;
  final state =
      scope?.state ??
      (_AppToastHostState._activeStates.isEmpty
          ? null
          : _AppToastHostState._activeStates.last);
  assert(
    state != null,
    'showAppToast called without an AppToastHost ancestor.',
  );
  state?.show(message, duration: duration);
}

class _AppToastScope extends InheritedWidget {
  const _AppToastScope({required this.state, required super.child});

  final _AppToastHostState state;

  @override
  bool updateShouldNotify(_AppToastScope oldWidget) => state != oldWidget.state;
}
