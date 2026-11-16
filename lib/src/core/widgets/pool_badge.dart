import 'package:flutter/widgets.dart';

import '../l10n/l10n.dart';
import '../layout/app_form_factor.dart';
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
///
/// On mobile it matches the activity rows' pool line exactly: the icon
/// colours (`icon.brandCrimson`, `icon.muted`) and the 16px label at regular
/// weight.
class PoolBadge extends StatelessWidget {
  const PoolBadge({required this.isShielded, super.key});

  final bool isShielded;

  static const _mobile = kAppFormFactor == AppFormFactor.mobile;

  static final _labelStyle = _mobile
      ? AppTypography.labelLarge.copyWith(fontWeight: FontWeight.w400)
      : AppTypography.labelSmall;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final iconColor = _mobile
        ? (isShielded ? colors.icon.brandCrimson : colors.icon.muted)
        : (isShielded ? colors.text.brandCrimson : colors.text.secondary);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppIcon(
          isShielded ? AppIcons.shieldKeyhole : AppIcons.transparentBalance,
          size: AppIconSize.medium,
          color: iconColor,
        ),
        const SizedBox(width: AppSpacing.xxs),
        Flexible(
          child: Text(
            isShielded
                ? context.l10n.poolShielded
                : context.l10n.poolTransparent,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _labelStyle.copyWith(color: colors.text.secondary),
          ),
        ),
      ],
    );
  }
}
