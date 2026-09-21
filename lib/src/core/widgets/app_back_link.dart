import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../navigation/app_back_resolver.dart';
import '../theme/app_theme.dart';
import 'app_icon.dart';

class AppBackLink extends StatefulWidget {
  const AppBackLink({
    required this.label,
    required this.onTap,
    this.minWidth = 0,
    this.semanticsLabel,
    super.key,
  });

  static const height = 32.0;

  final String label;
  final FutureOr<void> Function() onTap;
  final double minWidth;
  final String? semanticsLabel;

  @override
  State<AppBackLink> createState() => _AppBackLinkState();
}

class _AppBackLinkState extends State<AppBackLink> {
  static const _activationShortcuts = <ShortcutActivator, Intent>{
    SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
  };

  bool _hovered = false;
  bool _focused = false;

  static const _labelStyle = TextStyle(
    fontFamily: 'Geist',
    fontWeight: FontWeight.w500,
    fontSize: 14,
    height: 16 / 14,
    letterSpacing: -0.06,
  );

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final contentColor = colors.button.ghost.label;

    return Semantics(
      button: true,
      label: widget.semanticsLabel ?? 'Back to ${widget.label}',
      onTap: _activate,
      child: ExcludeSemantics(
        child: FocusableActionDetector(
          mouseCursor: SystemMouseCursors.click,
          onShowFocusHighlight: _setFocused,
          shortcuts: _activationShortcuts,
          actions: <Type, Action<Intent>>{
            ActivateIntent: CallbackAction<Intent>(
              onInvoke: (_) {
                _activate();
                return null;
              },
            ),
          },
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => _setHovered(true),
            onExit: (_) => _setHovered(false),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _activate,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 120),
                opacity: _hovered ? 0.75 : 1,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: widget.minWidth),
                  child: SizedBox(
                    height: AppBackLink.height,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(AppRadii.full),
                        border: _focused
                            ? Border.all(
                                color: colors.state.focusRing,
                                width: 2,
                                strokeAlign: BorderSide.strokeAlignOutside,
                              )
                            : null,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.s,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AppIcon(
                              AppIcons.chevronBackward,
                              size: 16,
                              color: contentColor,
                            ),
                            const SizedBox(width: AppSpacing.xxs),
                            Text(
                              widget.label,
                              style: _labelStyle.copyWith(color: contentColor),
                            ),
                          ],
                        ),
                      ),
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

  void _activate() => unawaited(Future<void>.value(widget.onTap()));

  void _setHovered(bool hovered) {
    if (_hovered == hovered) return;
    setState(() {
      _hovered = hovered;
    });
  }

  void _setFocused(bool focused) {
    if (_focused == focused) return;
    setState(() {
      _focused = focused;
    });
  }
}

class AppRouteBackLink extends StatelessWidget {
  const AppRouteBackLink({this.onBeforeNavigate, this.minWidth = 0, super.key});

  final FutureOr<void> Function()? onBeforeNavigate;
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    final target = AppBackResolver.resolve(context);
    return AppBackLink(
      label: target.label,
      minWidth: minWidth,
      onTap: () async {
        final before = onBeforeNavigate;
        if (before != null) {
          await Future<void>.value(before());
        }
        if (!context.mounted) return;
        target.navigate(context);
      },
    );
  }
}
