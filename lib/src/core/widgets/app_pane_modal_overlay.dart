import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';

class AppPaneModalOverlay extends StatelessWidget {
  const AppPaneModalOverlay({
    required this.child,
    required this.onDismiss,
    this.borderRadius,
    this.alignment = Alignment.center,
    super.key,
  });

  final Widget child;
  final VoidCallback onDismiss;
  final BorderRadius? borderRadius;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Positioned.fill(
      child: PopScope<void>(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) onDismiss();
        },
        child: Focus(
          autofocus: true,
          onKeyEvent: (_, event) {
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.escape) {
              onDismiss();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: _ModalClip(
            borderRadius: borderRadius,
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 15, sigmaY: 15),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onDismiss,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.background.neutralScrim,
                  ),
                  child: Align(
                    alignment: alignment,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {},
                      child: child,
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

class _ModalClip extends StatelessWidget {
  const _ModalClip({required this.child, this.borderRadius});

  final Widget child;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final borderRadius = this.borderRadius;
    if (borderRadius == null) {
      return ClipRect(child: child);
    }
    return ClipRRect(borderRadius: borderRadius, child: child);
  }
}
