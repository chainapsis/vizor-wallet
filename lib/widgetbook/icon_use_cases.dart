// ignore_for_file: depend_on_referenced_packages
// widgetbook is dev-only; see `widgetbook.dart` for the boundary.

import 'package:flutter/material.dart';

import '../src/core/theme/app_theme.dart';
import '../src/core/widgets/app_icon.dart';

/// Every name exposed by [AppIcons], listed in alphabetical order so
/// the widgetbook page matches what an IDE autocompletion shows.
const _iconNames = <String>[
  AppIcons.addNew,
  AppIcons.arrowBack,
  AppIcons.arrowBottomLeft,
  AppIcons.arrowDown,
  AppIcons.arrowDownCircle,
  AppIcons.arrowDownward,
  AppIcons.arrowForwardIos,
  AppIcons.arrowTopRight,
  AppIcons.arrowUpward,
  AppIcons.block,
  AppIcons.book,
  AppIcons.calendar,
  AppIcons.check,
  AppIcons.checkCircle,
  AppIcons.chevronBackward,
  AppIcons.chevronForward,
  AppIcons.collapsed,
  AppIcons.cog,
  AppIcons.coins,
  AppIcons.copy,
  AppIcons.cross,
  AppIcons.crystalBall,
  AppIcons.day,
  AppIcons.dragon,
  AppIcons.edit,
  AppIcons.endpoint,
  AppIcons.eye,
  AppIcons.eyeClosed,
  AppIcons.expand,
  AppIcons.help,
  AppIcons.history,
  AppIcons.home,
  AppIcons.importWallet,
  AppIcons.key,
  AppIcons.link,
  AppIcons.loader,
  AppIcons.lock,
  AppIcons.logOut,
  AppIcons.monitor,
  AppIcons.moneyBag,
  AppIcons.night,
  AppIcons.plane,
  AppIcons.qr,
  AppIcons.renew,
  AppIcons.scroll,
  AppIcons.search,
  AppIcons.shieldAsset,
  AppIcons.shieldKeyhole,
  AppIcons.shieldKeyholeOutline,
  AppIcons.skip,
  AppIcons.skull,
  AppIcons.sync,
  AppIcons.theme,
  AppIcons.time,
  AppIcons.transparentBalance,
  AppIcons.unlock,
  AppIcons.users,
  AppIcons.vizor,
  AppIcons.wallet,
  AppIcons.warning,
  AppIcons.zcash,
  AppIcons.zcashCurrency,
];

Widget _iconCard(BuildContext context, String name) {
  final colors = context.colors;
  return Container(
    decoration: BoxDecoration(
      color: colors.surface.card,
      border: Border.all(color: colors.border.subtle, width: 0.5),
      borderRadius: BorderRadius.circular(AppRadii.xSmall),
    ),
    padding: const EdgeInsets.all(AppSpacing.sm),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Row of the same icon at two sizes, both tinted with the ambient
        // icon color — an at-a-glance check that the icon scales cleanly
        // and that color application is actually landing.
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            AppIcon(name, size: AppIconSize.medium, color: colors.icon.regular),
            const SizedBox(width: AppSpacing.sm),
            AppIcon(name, size: AppIconSize.large, color: colors.icon.regular),
            const Spacer(),
            // Warning color demo — catches icons that rely on hard-coded
            // fills and don't actually pick up the color filter.
            AppIcon(name, size: AppIconSize.large, color: colors.icon.warning),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          name,
          style: TextStyle(
            fontFamily: 'Geist Mono',
            fontSize: 11,
            color: colors.text.primary,
          ),
        ),
      ],
    ),
  );
}

/// Grid of every [AppIcon] handle. Two sizes (M / L) side by
/// side plus a warning-tinted instance so a regression in `AppIcon`'s
/// color handling, asset registration, or geometry is immediately
/// visible.
Widget buildIconsAllUseCase(BuildContext context) {
  final colors = context.colors;
  return ColoredBox(
    color: colors.background.ground,
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ICONS',
            style: TextStyle(
              color: colors.text.secondary,
              fontSize: 11,
              letterSpacing: 0.88,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          LayoutBuilder(
            builder: (context, constraints) {
              // Three columns on wide, two on medium, one on narrow.
              const minCard = 220.0;
              final columns = (constraints.maxWidth / minCard).floor().clamp(
                1,
                3,
              );
              const gap = AppSpacing.sm;
              final cardWidth =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final name in _iconNames)
                    SizedBox(width: cardWidth, child: _iconCard(context, name)),
                ],
              );
            },
          ),
        ],
      ),
    ),
  );
}

Widget _buildLoadingIconUseCase(
  BuildContext context, {
  required bool animated,
}) {
  final colors = context.colors;
  return ColoredBox(
    color: colors.background.ground,
    child: Center(
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface.card,
          border: Border.all(color: colors.border.subtle, width: 0.5),
          borderRadius: BorderRadius.circular(AppRadii.small),
        ),
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            AppIcon(
              AppIcons.loader,
              size: AppIconSize.medium,
              color: colors.icon.regular,
              animated: animated,
            ),
            const SizedBox(width: AppSpacing.md),
            AppIcon(
              AppIcons.loader,
              size: AppIconSize.large,
              color: colors.icon.regular,
              animated: animated,
            ),
            const SizedBox(width: AppSpacing.md),
            AppIcon(
              AppIcons.loader,
              size: AppIconSize.large,
              color: colors.icon.warning,
              animated: animated,
            ),
          ],
        ),
      ),
    ),
  );
}

Widget buildLoadingIconAnimatedUseCase(BuildContext context) {
  return _buildLoadingIconUseCase(context, animated: true);
}

Widget buildLoadingIconStaticUseCase(BuildContext context) {
  return _buildLoadingIconUseCase(context, animated: false);
}
