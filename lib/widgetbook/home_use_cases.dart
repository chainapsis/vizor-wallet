// ignore_for_file: depend_on_referenced_packages
// widgetbook is dev-only; see `widgetbook.dart` for the boundary.

import 'package:flutter/widgets.dart';

import '../src/core/theme/app_theme.dart';
import '../src/features/home/widgets/pay_floating_badge.dart';
import 'screen_use_cases.dart'
    show buildDesktopHomeIronwoodMigrationAnnouncementUseCase;

Widget buildPayFloatingBadgeUseCase(BuildContext context) {
  return ColoredBox(
    color: context.colors.background.ground,
    child: const Center(
      child: SizedBox(
        width: 269,
        height: 244,
        child: Center(child: PayFloatingBadge()),
      ),
    ),
  );
}

Widget buildIronwoodMigrationAnnouncementModalUseCase(BuildContext context) {
  return buildDesktopHomeIronwoodMigrationAnnouncementUseCase(context);
}
