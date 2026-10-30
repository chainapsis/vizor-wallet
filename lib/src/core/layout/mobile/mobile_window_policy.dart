import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// One mobile window decision, made before a sidebar or keyboard resizes pages.
/// A portrait or square window keeps the ordinary mobile composition.
@immutable
class MobileWindowPolicy {
  const MobileWindowPolicy._(this.windowSize, this.safeRect);

  static const minimumSidebarWidth = 200.0;
  static const minimumContentWidth = 320.0;
  static const paneSpacing = 16.0;
  static const minimumWideWidth =
      minimumSidebarWidth + minimumContentWidth + paneSpacing * 3;
  static const minimumWideHeight = 160.0;

  factory MobileWindowPolicy.resolve(MediaQueryData media) {
    // viewPadding stays stable when the keyboard consumes padding.bottom.
    final insets = media.viewPadding;
    return MobileWindowPolicy._(
      media.size,
      Rect.fromLTRB(
        insets.left,
        insets.top,
        math.max(insets.left, media.size.width - insets.right),
        math.max(insets.top, media.size.height - insets.bottom),
      ),
    );
  }

  final Size windowSize;
  final Rect safeRect;

  bool get usesWideLayout =>
      // Removing a status bar from a near-square portrait window must not
      // change its composition. Safety affects fitting, not the window shape.
      windowSize.width > windowSize.height &&
      safeRect.width >= minimumWideWidth &&
      safeRect.height >= minimumWideHeight;
}

/// Keeps the root decision available inside the narrower wallet Navigator.
/// Full-window entry pages and standalone previews use the same resolver.
class MobileWindowPolicyScope extends InheritedWidget {
  const MobileWindowPolicyScope({
    required this.policy,
    required super.child,
    super.key,
  });

  final MobileWindowPolicy policy;

  static MobileWindowPolicy of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<MobileWindowPolicyScope>()
          ?.policy ??
      MobileWindowPolicy.resolve(MediaQuery.of(context));

  @override
  bool updateShouldNotify(MobileWindowPolicyScope oldWidget) =>
      policy.windowSize != oldWidget.policy.windowSize ||
      policy.safeRect != oldWidget.policy.safeRect;
}
