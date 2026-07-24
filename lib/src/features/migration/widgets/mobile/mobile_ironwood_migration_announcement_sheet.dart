import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_icon.dart';

/// Mobile Ironwood announcement content for the shared floating modal shell.
///
/// The 597px content height matches the latest mobile announcement frame when
/// the shared sheet applies its 32px bottom gap.
class MobileIronwoodMigrationAnnouncementSheet extends StatelessWidget {
  const MobileIronwoodMigrationAnnouncementSheet({
    required this.onStartMigration,
    required this.onOpenReleaseNotes,
    super.key,
  });

  static const height = 597.0;

  final VoidCallback onStartMigration;
  final VoidCallback onOpenReleaseNotes;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableHeight =
            constraints.maxHeight.isFinite
                ? constraints.maxHeight.clamp(0.0, height)
                : height;
        return SizedBox(
          key: const ValueKey('mobile_ironwood_announcement_sheet'),
          height: availableHeight,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 204,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      const Image(
                        image: AssetImage(
                          'assets/illustrations/'
                          'ironwood_migration_modal_background.png',
                        ),
                        fit: BoxFit.cover,
                      ),
                      const Positioned(
                        top: 32,
                        left: 0,
                        right: 0,
                        height: 152,
                        child: Center(
                          child: Image(
                            image: AssetImage(
                              'assets/illustrations/'
                              'ironwood_migration_modal_symbol.png',
                            ),
                            width: 140,
                            height: 152,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                      Positioned(
                        top: AppSpacing.sm,
                        right: AppSpacing.sm,
                        child: Semantics(
                          label: 'Close',
                          button: true,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => Navigator.maybePop(context),
                            child: Container(
                              key: const ValueKey(
                                'mobile_ironwood_announcement_close_button',
                              ),
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: colors.button.secondary.bg,
                                shape: BoxShape.circle,
                              ),
                              alignment: Alignment.center,
                              child: AppIcon(
                                AppIcons.cross,
                                size: 20,
                                color: colors.icon.accent,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.s),
                Center(
                  child: SvgPicture.asset(
                    'assets/illustrations/ironwood_wordmark.svg',
                    width: 240,
                    height: 32.3,
                    colorFilter: ColorFilter.mode(
                      colors.text.accent,
                      BlendMode.srcIn,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 180.7),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                    ),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: Text(
                        'Zcash’s latest shielded pool, bringing '
                        'cutting-edge cryptography and formal '
                        'verification.\n\n'
                        'Your shielded balance needs a one-time '
                        'migration to Ironwood.',
                        textAlign: TextAlign.center,
                        style: AppTypography.bodyMediumStrong.copyWith(
                          color: colors.text.accent,
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                  ),
                  child: AppButton(
                    key: const ValueKey(
                      'mobile_ironwood_start_migration_button',
                    ),
                    expand: true,
                    constrainContent: true,
                    height: 50,
                    onPressed: onStartMigration,
                    trailing: const AppIcon(AppIcons.chevronForward, size: 20),
                    child: const Text('Upgrade to Ironwood'),
                  ),
                ),
                const SizedBox(height: 13),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                  ),
                  child: AppButton(
                    key: const ValueKey('mobile_ironwood_release_notes_button'),
                    expand: true,
                    constrainContent: true,
                    height: 50,
                    variant: AppButtonVariant.ghost,
                    onPressed: onOpenReleaseNotes,
                    child: const Text('Official announcement'),
                  ),
                ),
                const SizedBox(height: 31),
              ],
            ),
          ),
        );
      },
    );
  }
}
