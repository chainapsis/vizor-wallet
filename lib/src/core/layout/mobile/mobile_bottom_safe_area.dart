import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/widgets.dart';

/// Minimum content bottom padding that clears the iOS home indicator.
/// The indicator occupies the bottom ~13pt of the screen (8pt offset +
/// 5pt bar height), so 16px of empty padding lets it float without
/// touching the content above.
const double kIosHomeIndicatorClearance = 16;

/// Bottom-edge [SafeArea] for surfaces that already carry their own
/// bottom padding — sheet bodies and the floating tab bar.
///
/// On iOS, adding the 34pt home-indicator inset on top of a sufficient
/// [bottomPadding] makes the bottom gap visually heavier than the
/// sides; the indicator is an overlay, not a bar, so it can float
/// inside the padding instead. When [bottomPadding] >=
/// [kIosHomeIndicatorClearance] the inset is skipped and the side ==
/// bottom proportion is kept. Android always honors the inset — its
/// navigation bar modes vary per device and occupy real space.
class MobileBottomSafeArea extends StatelessWidget {
  const MobileBottomSafeArea({
    required this.bottomPadding,
    required this.child,
    super.key,
  });

  /// The bottom padding the wrapped content provides by itself, below
  /// its last control.
  final double bottomPadding;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final skipInset =
        defaultTargetPlatform == TargetPlatform.iOS &&
        bottomPadding >= kIosHomeIndicatorClearance;
    return SafeArea(top: false, bottom: !skipInset, child: child);
  }
}
