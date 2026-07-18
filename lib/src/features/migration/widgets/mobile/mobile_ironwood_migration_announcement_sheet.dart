import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_icon.dart';

/// Mobile Ironwood announcement content for the shared floating modal shell.
///
/// The 522px content height matches the 393x852 Figma frame when the shared
/// sheet applies its 32px bottom gap: the card begins at y=298 and ends at
/// y=820.
class MobileIronwoodMigrationAnnouncementSheet extends StatelessWidget {
  const MobileIronwoodMigrationAnnouncementSheet({
    required this.onStartMigration,
    required this.onOpenReleaseNotes,
    super.key,
  });

  static const height = 522.0;

  final VoidCallback onStartMigration;
  final VoidCallback onOpenReleaseNotes;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return SizedBox(
      key: const ValueKey('mobile_ironwood_announcement_sheet'),
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const Positioned(
            left: 0,
            top: 0,
            right: 0,
            height: 204,
            child: Image(
              image: AssetImage(
                'assets/illustrations/ironwood_migration_modal_background.png',
              ),
              fit: BoxFit.cover,
            ),
          ),
          const Positioned(
            top: 32,
            left: 0,
            right: 0,
            height: 152,
            child: Center(
              child: Image(
                image: AssetImage(
                  'assets/illustrations/ironwood_migration_modal_symbol.png',
                ),
                width: 140,
                height: 152,
                fit: BoxFit.contain,
              ),
            ),
          ),
          Positioned(
            top: 216,
            left: AppSpacing.sm,
            right: AppSpacing.sm,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SvgPicture.asset(
                  'assets/illustrations/ironwood_wordmark.svg',
                  width: 240,
                  height: 32.3,
                  colorFilter: ColorFilter.mode(
                    colors.text.accent,
                    BlendMode.srcIn,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Ironwood is the latest Zcash shielded pool.\n'
                  "It’s the first formally verified pool with\n"
                  'cutting edge cryptography.',
                  textAlign: TextAlign.center,
                  style: AppTypography.bodyMediumStrong.copyWith(
                    color: colors.text.accent,
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: AppSpacing.sm,
            right: AppSpacing.sm,
            top: 379,
            child: AppButton(
              key: const ValueKey('mobile_ironwood_start_migration_button'),
              expand: true,
              constrainContent: true,
              height: 50,
              onPressed: onStartMigration,
              trailing: const AppIcon(AppIcons.chevronForward, size: 20),
              child: const Text('Start migration'),
            ),
          ),
          Positioned(
            left: AppSpacing.sm,
            right: AppSpacing.sm,
            top: 447,
            child: AppButton(
              key: const ValueKey('mobile_ironwood_release_notes_button'),
              expand: true,
              constrainContent: true,
              height: 50,
              variant: AppButtonVariant.ghost,
              onPressed: onOpenReleaseNotes,
              child: const Text('Official release note'),
            ),
          ),
        ],
      ),
    );
  }
}
