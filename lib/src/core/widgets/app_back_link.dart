import 'dart:async';

import 'package:flutter/widgets.dart';

import '../navigation/app_back_resolver.dart';
import '../theme/app_theme.dart';
import 'app_icon.dart';

class AppBackLink extends StatefulWidget {
  const AppBackLink({
    required this.label,
    required this.onTap,
    this.minWidth = 0,
    super.key,
  });

  final String label;
  final FutureOr<void> Function() onTap;
  final double minWidth;

  @override
  State<AppBackLink> createState() => _AppBackLinkState();
}

class _AppBackLinkState extends State<AppBackLink> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Semantics(
      button: true,
      label: 'Back to ${widget.label}',
      child: ExcludeSemantics(
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => _setHovered(true),
          onExit: (_) => _setHovered(false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => unawaited(Future<void>.value(widget.onTap())),
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 120),
              opacity: _hovered ? 0.75 : 1,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: widget.minWidth),
                child: SizedBox(
                  height: 32,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppIcon(
                        AppIcons.chevronBackward,
                        size: 16,
                        color: colors.icon.accent,
                      ),
                      const SizedBox(width: AppSpacing.xxs),
                      Text(
                        widget.label,
                        style: AppTypography.labelLarge.copyWith(
                          color: colors.text.accent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _setHovered(bool hovered) {
    if (_hovered == hovered) return;
    setState(() {
      _hovered = hovered;
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
