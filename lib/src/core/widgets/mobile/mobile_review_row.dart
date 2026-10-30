import 'package:flutter/widgets.dart';

import '../../theme/app_theme.dart';

// Leading badges for the mobile transaction-status and send review rows,
// laid out by the core `ReviewInfoRow`.

/// The round ZEC coin — Figma `Asset Image` with the ZEC network logo.
class MobileReviewZecBadge extends StatelessWidget {
  const MobileReviewZecBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.full),
      child: Image.asset(
        'assets/swap/tokens/zec.webp',
        width: 32,
        height: 32,
        fit: BoxFit.cover,
      ),
    );
  }
}

/// 40px circular badge on the neutral subtle-opacity fill — the generic
/// wallet/counterparty leading slot. Circular (not a stadium/pill) to match
/// the desktop receipt's `ReviewInfoIconCircle` and the 40px contact avatar.
class MobileReviewIconBadge extends StatelessWidget {
  const MobileReviewIconBadge({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: context.colors.background.neutralSubtleOpacity,
        shape: BoxShape.circle,
      ),
      child: Center(child: child),
    );
  }
}
