import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_tooltip.dart';
import '../models/one_time_address_role.dart';

export '../models/one_time_address_role.dart';

/// Why the composer waits before the first private swap quote.
const kOneTimeAddressPreparingExplanation =
    'Only the first time after turning on NEAR swap privacy. This can take a '
    'few minutes.';

/// The one-time address on a review or status row, where an ordinary row has
/// its Copy action. Explains itself on tap. Names a refund address in full
/// where the width allows, and falls back to the composer's short label.
class OneTimeAddressLabel extends StatelessWidget {
  const OneTimeAddressLabel({required this.role, super.key});

  final OneTimeAddressRole role;

  // The padding's horizontal sides, the icon and the gap after it.
  static const _chromeWidth =
      AppSpacing.xxs + AppSpacing.xs + 16 + AppSpacing.xxs;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => _build(
        context,
        _fits(context, role.detailLabel, constraints.maxWidth)
            ? role.detailLabel
            : role.label,
        bounded: constraints.hasBoundedWidth,
      ),
    );
  }

  bool _fits(BuildContext context, String text, double maxWidth) {
    if (maxWidth.isInfinite) return true;
    final painter = TextPainter(
      text: TextSpan(text: text, style: AppTypography.labelLarge),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width + _chromeWidth <= maxWidth;
  }

  Widget _build(BuildContext context, String text, {required bool bounded}) {
    final colors = context.colors;
    final label = Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppTypography.labelLarge.copyWith(color: colors.text.accent),
    );
    return AppTooltip(
      message: role.explanation,
      tapToShow: true,
      child: Semantics(
        button: true,
        label: role.detailLabel,
        excludeSemantics: true,
        child: Padding(
          // The row's ghost button geometry (outer 4, label 4), so the text
          // ends where "Copy" does on the other row.
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xxs,
            AppSpacing.xxs,
            AppSpacing.xs,
            AppSpacing.xxs,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(
                AppIcons.linkOff,
                size: 16,
                color: colors.icon.brandCrimson,
              ),
              const SizedBox(width: AppSpacing.xxs),
              // Ellipsized only if even the short label can't fit.
              if (bounded) Flexible(child: label) else label,
            ],
          ),
        ),
      ),
    );
  }
}

/// The composer's ZEC address slot, where the other card shows the address
/// the user entered. Shows the one-time address, or that it is still being
/// prepared, within the slot's own height so the card never grows.
class OneTimeAddressSlot extends StatelessWidget {
  const OneTimeAddressSlot({
    required this.role,
    required this.height,
    this.preparing = false,
    this.fontWeight,
    super.key,
  });

  final OneTimeAddressRole role;
  final double height;

  /// The wallet is still checking the address's history.
  final bool preparing;

  /// Matches the address chip on the other card.
  final FontWeight? fontWeight;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = preparing ? 'Preparing address…' : role.label;
    return AppTooltip(
      message: preparing
          ? kOneTimeAddressPreparingExplanation
          : role.explanation,
      tapToShow: true,
      child: Semantics(
        button: true,
        liveRegion: preparing,
        label: preparing ? 'Preparing one-time address' : text,
        excludeSemantics: true,
        child: Container(
          key: ValueKey('swap_one_time_address_${role.name}'),
          // As wide as the address chip on the other card can grow.
          constraints: const BoxConstraints(maxWidth: 240),
          height: height,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xs,
            vertical: AppSpacing.xxs,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(
                preparing ? AppIcons.loader : AppIcons.linkOff,
                size: 20,
                color: colors.icon.brandCrimson,
              ),
              const SizedBox(width: AppSpacing.xxs),
              Flexible(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.labelLarge.copyWith(
                    color: preparing
                        ? colors.text.secondary
                        : colors.text.accent,
                    fontWeight: preparing ? FontWeight.w400 : fontWeight,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
