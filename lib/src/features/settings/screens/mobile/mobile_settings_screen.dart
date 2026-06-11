import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../../core/layout/mobile/app_mobile_tab_bar.dart';
import '../../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../../core/profile_pictures.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/app_profile_picture.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/mobile/mobile_list_row.dart';
import '../../../../core/widgets/mobile/mobile_surface_card.dart';
import '../../../../providers/account_provider.dart';
import '../../../../providers/rpc_endpoint_provider.dart';
import '../../../../providers/theme_mode_provider.dart';

/// Mobile settings tab — Figma `SETTINGS` root frame (4494:65997).
///
/// Phase 1 scope: the grouped list renders with live values, but only
/// the theme row is interactive; the remaining rows enable as their
/// mobile flows ship (secret passphrase needs the FaceID/screenshot
/// guards, password/endpoint/address book need their own screens).
class MobileSettingsScreen extends ConsumerWidget {
  const MobileSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(accountProvider).value?.activeAccount;
    final endpoint = ref.watch(rpcEndpointProvider).hostPort;
    final themeMode = ref.watch(themeModeProvider);

    final profileLabel = resolveProfilePictureOption(
      account?.profilePictureId ?? kDefaultProfilePictureId,
    ).label;

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          const MobileTopNav.back(title: 'Settings'),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.sm,
                AppSpacing.s,
                AppSpacing.sm,
                kMobileTabBarHeight + AppSpacing.lg,
              ),
              children: [
                _SettingsGroup(
                  title: 'Account',
                  rows: [
                    MobileListRow(
                      leading: _RowIcon(AppIcons.key),
                      label: 'Secret Passphrase',
                      showChevron: true,
                      enabled: false,
                    ),
                    MobileListRow(
                      leading: _RowIcon(AppIcons.lock),
                      label: 'Password',
                      showChevron: true,
                      onTap: () => _openChangePasscode(context),
                    ),
                    MobileListRow(
                      leading: _RowIcon(AppIcons.users),
                      label: 'Profile Picture',
                      value: profileLabel,
                      trailing: AppProfilePicture(
                        profilePictureId:
                            account?.profilePictureId ??
                            kDefaultProfilePictureId,
                        size: AppProfilePictureSize.medium,
                      ),
                      enabled: false,
                    ),
                    MobileListRow(
                      leading: _RowIcon(AppIcons.scroll),
                      label: 'Account Name',
                      value: account?.name ?? '',
                      showChevron: true,
                      enabled: false,
                    ),
                    MobileListRow(
                      leading: _RowIcon(AppIcons.users),
                      label: 'Address Book',
                      showChevron: true,
                      enabled: false,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                _SettingsGroup(
                  title: 'System',
                  rows: [
                    MobileListRow(
                      leading: _RowIcon(AppIcons.endpoint),
                      label: 'Endpoint',
                      value: endpoint,
                      showChevron: true,
                      enabled: false,
                    ),
                    MobileListRow(
                      leading: _RowIcon(AppIcons.theme),
                      label: 'Theme',
                      value: _themeLabel(themeMode),
                      showChevron: true,
                      onTap: () => _showThemeSheet(context, ref, themeMode),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                MobileSurfaceCard(
                  child: MobileListRow(
                    leading: _RowIcon(AppIcons.shieldKeyhole),
                    label: 'About Vizor',
                    showChevron: true,
                    enabled: false,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openChangePasscode(BuildContext context) async {
    final changed = await context.push<bool>('/settings/change-password');
    if (changed == true && context.mounted) {
      showAppToast(context, 'Passcode updated');
    }
  }

  static String _themeLabel(ThemeMode mode) => switch (mode) {
    ThemeMode.system => 'System',
    ThemeMode.light => 'Light',
    ThemeMode.dark => 'Dark',
  };

  Future<void> _showThemeSheet(
    BuildContext context,
    WidgetRef ref,
    ThemeMode current,
  ) {
    return showAppMobileSheet<void>(
      context: context,
      builder: (sheetContext) => _ThemeSheet(
        current: current,
        onSelect: (mode) async {
          Navigator.of(sheetContext).pop();
          await ref.read(themeModeProvider.notifier).set(mode);
        },
      ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.title, required this.rows});

  final String title;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    return MobileSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(
              left: AppSpacing.xxs,
              bottom: AppSpacing.xs,
            ),
            child: Text(
              title,
              style: AppTypography.labelMedium.copyWith(
                color: context.colors.text.secondary,
              ),
            ),
          ),
          ...rows,
        ],
      ),
    );
  }
}

class _RowIcon extends StatelessWidget {
  const _RowIcon(this.iconName);

  final String iconName;

  @override
  Widget build(BuildContext context) {
    return AppIcon(iconName, size: 20, color: context.colors.icon.accent);
  }
}

/// Theme picker sheet — Figma `Theme Modal` (4494:92272). Selecting an
/// option applies it immediately.
class _ThemeSheet extends StatelessWidget {
  const _ThemeSheet({required this.current, required this.onSelect});

  final ThemeMode current;
  final ValueChanged<ThemeMode> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    const options = [
      (ThemeMode.system, 'System (Auto)'),
      (ThemeMode.light, 'Light Mode'),
      (ThemeMode.dark, 'Dark Mode'),
    ];

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Theme',
              style: AppTypography.headlineSmall.copyWith(
                color: colors.text.accent,
              ),
            ),
            const SizedBox(height: AppSpacing.s),
            for (final (mode, label) in options)
              MobileListRow(
                label: label,
                trailing: mode == current
                    ? AppIcon(
                        AppIcons.check,
                        size: AppIconSize.medium,
                        color: colors.icon.accent,
                      )
                    : const SizedBox(width: AppIconSize.medium),
                onTap: () => onSelect(mode),
              ),
          ],
        ),
      ),
    );
  }
}
