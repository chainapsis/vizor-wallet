import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';

class IronwoodMigrationAnnouncementModal extends StatelessWidget {
  const IronwoodMigrationAnnouncementModal({
    required this.onStartMigration,
    required this.onOpenReleaseNotes,
    super.key,
  });

  static const width = 312.0;
  static const height = 414.0;
  static const _contentWidth = 280.0;
  static const _heroHeight = 154.0;
  static const _symbolWidth = 92.0;
  static const _symbolHeight = 100.0;

  final VoidCallback onStartMigration;
  final VoidCallback onOpenReleaseNotes;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      key: const ValueKey('ironwood_migration_announcement_modal'),
      width: width,
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.background.ground,
        borderRadius: BorderRadius.circular(AppRadii.large),
        boxShadow: const [
          BoxShadow(
            color: Color(0x18000000),
            offset: Offset(0, 14),
            blurRadius: 34,
          ),
          BoxShadow(
            color: Color(0x0A000000),
            offset: Offset(0, 2),
            blurRadius: 8,
          ),
        ],
      ),
      child: Stack(
        children: [
          const Positioned(
            left: 0,
            top: 0,
            width: width,
            height: _heroHeight,
            child: Image(
              image: AssetImage(
                'assets/illustrations/ironwood_migration_modal_background.png',
              ),
              fit: BoxFit.cover,
            ),
          ),
          const Positioned(
            left: 110,
            top: 23,
            width: _symbolWidth,
            height: _symbolHeight,
            child: Image(
              image: AssetImage(
                'assets/illustrations/ironwood_migration_modal_symbol.png',
              ),
              fit: BoxFit.contain,
            ),
          ),
          Positioned(
            left: AppSpacing.sm,
            top: 168,
            width: _contentWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: SvgPicture.asset(
                    'assets/illustrations/ironwood_wordmark.svg',
                    width: 184,
                    height: 25,
                    colorFilter: ColorFilter.mode(
                      colors.text.accent,
                      BlendMode.srcIn,
                    ),
                  ),
                ),
                const SizedBox(height: 13),
                Text(
                  'Ironwood is the latest Zcash shielded pool.\n'
                  "It's the first formally verified pool with\n"
                  'cutting edge cryptography.',
                  textAlign: TextAlign.center,
                  style: AppTypography.bodyMedium.copyWith(
                    color: colors.text.primary,
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: AppSpacing.sm,
            top: 290,
            width: _contentWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppButton(
                  key: const ValueKey(
                    'ironwood_migration_start_migration_button',
                  ),
                  onPressed: onStartMigration,
                  height: 44,
                  minWidth: _contentWidth,
                  expand: true,
                  constrainContent: true,
                  trailing: const AppIcon(AppIcons.chevronForward, size: 20),
                  child: const Text('Start Migration'),
                ),
                const SizedBox(height: 20),
                AppButton(
                  key: const ValueKey(
                    'ironwood_migration_release_notes_button',
                  ),
                  onPressed: onOpenReleaseNotes,
                  variant: AppButtonVariant.ghost,
                  height: 36,
                  minWidth: _contentWidth,
                  expand: true,
                  constrainContent: true,
                  child: const Text('Official Release Note'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
