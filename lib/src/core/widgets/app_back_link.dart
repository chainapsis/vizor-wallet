import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../l10n/app_localizations.dart';
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
  bool _hovered = false;

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
      label:
          widget.semanticsLabel ??
          AppLocalizations.of(context).backToLabel(widget.label),
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
                  height: AppBackLink.height,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppRadii.full),
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
