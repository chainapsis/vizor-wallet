import 'package:flutter/widgets.dart';

import '../../theme/app_theme.dart';
import 'mobile_bottom_scroll_fade.dart';
import 'mobile_top_nav.dart';

/// The gap between a page's bottom buttons and the bottom safe-area inset
/// (the home indicator, or Android's navigation bar). Every page's bottom
/// action sits this far above it, floating or docked: the Send flow's
/// distance, 46pt from the bottom edge on a current iPhone.
///
/// A page whose body sits in a bottom [SafeArea] pads its bottom buttons by
/// this; one whose body runs to the edge uses
/// [MobileStickyBottomAction.bottomOffset], which adds the inset.
const double kMobileFooterGap = AppSpacing.s;

/// A page's main action pinned to the bottom, floating over the page's scroll
/// view: rows dissolve into the window behind it with the tab roots' bottom
/// fade, and the strip it sits in takes the touches. A page whose content
/// fits shows no fade, so this is also the footer for pages that do not
/// scroll.
///
/// Every floating bottom button uses this, so they all share one distance
/// from the bottom edge ([bottomOffset]) and one fade. Place it where the
/// page's body runs to the bottom edge (no bottom [SafeArea] above it), and
/// give the scroll view [contentInset] of bottom padding so its last row can
/// scroll clear of the action.
class MobileStickyBottomAction extends StatelessWidget {
  const MobileStickyBottomAction({
    required this.action,
    required this.child,
    this.actionHeight = AppButtonSizing.largeHeight,
    this.horizontalMargin = kMobilePageMargin,
    super.key,
  });

  /// Usually one full-width [AppButton]; a column of two works too.
  final Widget action;

  /// The action's height, which sizes the fade behind it.
  final double actionHeight;

  /// Side inset of the action; 0 where the page already insets its body.
  final double horizontalMargin;

  /// The page's scroll view.
  final Widget child;

  /// How far the action's bottom edge sits above the screen's: the bottom
  /// safe-area inset plus [kMobileFooterGap]. The inset is the padding, so
  /// above a raised keyboard the action keeps only the gap.
  static double bottomOffset(BuildContext context) =>
      MediaQuery.paddingOf(context).bottom + kMobileFooterGap;

  /// Bottom padding for the scroll view, so its last row rests above the
  /// action with the usual section gap.
  static double contentInset(
    BuildContext context, {
    double actionHeight = AppButtonSizing.largeHeight,
  }) => actionHeight + bottomOffset(context) + AppSpacing.md;

  @override
  Widget build(BuildContext context) {
    final offset = bottomOffset(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        MobileBottomScrollFade(
          // As under the tab bar: the band covers the action and the room
          // below it, then dissolves rows over a further 32px above it.
          height: actionHeight + offset + AppSpacing.base,
          child: child,
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Listener(
            // Rows scrolled under the strip are not tappable there.
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                horizontalMargin,
                0,
                horizontalMargin,
                offset,
              ),
              child: action,
            ),
          ),
        ),
      ],
    );
  }
}
