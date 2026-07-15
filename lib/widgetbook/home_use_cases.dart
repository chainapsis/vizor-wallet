// ignore_for_file: depend_on_referenced_packages
// widgetbook is dev-only; see `widgetbook.dart` for the boundary.

import 'package:flutter/widgets.dart';

import '../src/core/theme/app_theme.dart';
import '../src/features/migration/widgets/ironwood_migration_announcement_modal.dart';
import '../src/features/home/widgets/pay_floating_badge.dart';

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
  return ColoredBox(
    color: const Color(0xFFFFFFFF),
    child: Center(
      child: IronwoodMigrationAnnouncementModal(
        onStartMigration: () {},
        onOpenReleaseNotes: () {},
      ),
    ),
  );
}
