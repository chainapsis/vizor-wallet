import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';
import 'app_icon.dart';

/// Shielded / Transparent pool badge — the icon-plus-label pair every surface
/// in the product uses to state which pool an address belongs to.
///
/// Shielded takes the crimson glyph; transparent takes the muted one. The
/// label stays in the secondary text colour in both cases, so the badge reads
/// as an attribute of the value beside it rather than as a status of its own.
///
/// It was promoted out of the payment request card when the Receive request
/// flow needed the same badge under its QR: two copies of a privacy label is
/// exactly the kind of drift that ends with the two surfaces disagreeing.
class PoolBadge extends StatelessWidget {
  const PoolBadge({required this.isShielded, super.key});

  final bool isShielded;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppIcon(
          isShielded ? AppIcons.shieldKeyhole : AppIcons.transparentBalance,
          size: AppIconSize.medium,
          color: isShielded ? colors.text.brandCrimson : colors.text.secondary,
        ),
        const SizedBox(width: AppSpacing.xxs),
        Flexible(
          child: Text(
            isShielded ? 'Shielded' : 'Transparent',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.labelSmall.copyWith(
              color: colors.text.secondary,
            ),
          ),
        ),
      ],
    );
  }
}
