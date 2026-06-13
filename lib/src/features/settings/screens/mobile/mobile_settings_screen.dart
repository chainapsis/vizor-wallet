import 'dart:async';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../../core/layout/mobile/mobile_bottom_safe_area.dart';
import '../../../../core/layout/mobile/app_mobile_tab_bar.dart';
import '../../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../../core/profile_pictures.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/app_profile_picture.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/mobile/mobile_list_row.dart';
import '../../../../core/widgets/mobile/mobile_surface_card.dart';
import '../../../../providers/account_provider.dart';
import '../../../../providers/app_security_provider.dart';
import '../../../../providers/biometric_unlock_provider.dart';
import '../../../../providers/rpc_endpoint_provider.dart';
import '../../../../providers/theme_mode_provider.dart';
import '../../../../services/biometric_unlock.dart';
import '../../../accounts/widgets/mobile/account_edit_sheets.dart';

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
    final biometric =
        ref.watch(biometricUnlockProvider).value ?? BiometricUnlockState.initial;

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
                      key: const ValueKey('mobile_settings_seed_row'),
                      leading: _RowIcon(AppIcons.key),
                      label: 'Secret Passphrase',
                      showChevron: true,
                      onTap: () => context.push('/settings/seed-phrase'),
                    ),
                    MobileListRow(
                      leading: _RowIcon(AppIcons.lock),
                      label: 'Password',
                      showChevron: true,
                      onTap: () => _openChangePasscode(context),
                    ),
                    MobileListRow(
                      key: const ValueKey('mobile_settings_pfp_row'),
                      leading: _RowIcon(AppIcons.user),
                      label: 'Profile Picture',
                      // Just the avatar thumbnail → chevron. The "Profile
                      // picture N" label was redundant with the thumbnail
                      // and only ate horizontal space.
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AppProfilePicture(
                            profilePictureId:
                                account?.profilePictureId ??
                                kDefaultProfilePictureId,
                            size: AppProfilePictureSize.medium,
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          AppIcon(
                            AppIcons.chevronForward,
                            size: AppIconSize.medium,
                            color: context.colors.icon.muted,
                          ),
                        ],
                      ),
                      enabled: account != null,
                      onTap: account == null
                          ? null
                          : () => _updateProfilePicture(context, ref, account),
                    ),
                    MobileListRow(
                      key: const ValueKey('mobile_settings_account_name_row'),
                      leading: _RowIcon(AppIcons.scroll),
                      label: 'Account Name',
                      value: account?.name ?? '',
                      showChevron: true,
                      enabled: account != null,
                      onTap: account == null
                          ? null
                          : () => _editAccount(context, ref, account),
                    ),
                    MobileListRow(
                      key: const ValueKey('mobile_settings_address_book_row'),
                      leading: _RowIcon(AppIcons.users),
                      label: 'Address Book',
                      showChevron: true,
                      onTap: () => context.push('/settings/address-book'),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                _SettingsGroup(
                  title: 'System',
                  rows: [
                    MobileListRow(
                      key: const ValueKey('mobile_settings_endpoint_row'),
                      leading: _RowIcon(AppIcons.endpoint),
                      label: 'Endpoint',
                      value: endpoint,
                      showChevron: true,
                      onTap: () => context.push('/settings/endpoint'),
                    ),
                    MobileListRow(
                      key: const ValueKey('mobile_settings_theme_row'),
                      leading: _RowIcon(AppIcons.theme),
                      label: 'Theme',
                      value: _themeLabel(themeMode),
                      showChevron: true,
                      onTap: () => _showThemeSheet(context, ref, themeMode),
                    ),
                    // No Figma frame for this row yet — listed in
                    // design_suggestion. Hidden on devices without
                    // biometric hardware.
                    if (biometric.availability.supported)
                      MobileListRow(
                        key: const ValueKey('mobile_settings_biometric_row'),
                        leading: _RowIcon(AppIcons.lock),
                        label: biometric.availability.kind ==
                                BiometricKind.face
                            ? 'Face ID'
                            : 'Fingerprint',
                        value: biometric.enabled ? 'On' : 'Off',
                        showChevron: true,
                        onTap: () =>
                            unawaited(_toggleBiometric(context, ref)),
                      ),
                  ],
                ),
                // The About row stays hidden until the legal documents
                // are ready — the /about screen exists but must not be
                // user-reachable (product decision, 2026-06).
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

  Future<void> _editAccount(
    BuildContext context,
    WidgetRef ref,
    AccountInfo account,
  ) async {
    final edits = await showAccountEditSheet(context, account: account);
    if (edits == null || !context.mounted) return;
    final saved = await applyAccountEdits(ref, account, edits);
    if (!saved && context.mounted) {
      showAppToast(
        context,
        "Couldn't save the account changes",
        iconName: AppIcons.cross,
      );
    }
  }

  Future<void> _updateProfilePicture(
    BuildContext context,
    WidgetRef ref,
    AccountInfo account,
  ) async {
    final picked = await showProfilePictureSheet(
      context,
      selectedId: account.profilePictureId,
    );
    if (picked == null ||
        picked == account.profilePictureId ||
        !context.mounted) {
      return;
    }
    final saved = await applyAccountEdits(
      ref,
      account,
      AccountEdits(profilePictureId: picked),
    );
    if (!saved && context.mounted) {
      showAppToast(
        context,
        "Couldn't save the account changes",
        iconName: AppIcons.cross,
      );
    }
  }

  static String _themeLabel(ThemeMode mode) => switch (mode) {
    ThemeMode.system => 'System',
    ThemeMode.light => 'Light',
    ThemeMode.dark => 'Dark',
  };

  Future<void> _toggleBiometric(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(biometricUnlockProvider.notifier);
    final state = await ref.read(biometricUnlockProvider.future);
    if (!context.mounted) return;
    try {
      if (state.enabled) {
        await notifier.disable();
        if (context.mounted) showAppToast(context, 'Biometric unlock off');
        return;
      }
      if (!state.availability.usable) {
        showAppToast(
          context,
          'Set up biometrics in your device settings first.',
        );
        return;
      }
      final passcode = ref
          .read(appSecurityProvider.notifier)
          .requireSessionPasswordForNativeSecretUse();
      await notifier.enable(passcode);
      if (context.mounted) showAppToast(context, 'Biometric unlock on');
    } catch (e) {
      if (!context.mounted) return;
      showAppToast(context, "Couldn't update biometric unlock.");
    }
  }

  Future<void> _showThemeSheet(
    BuildContext context,
    WidgetRef ref,
    ThemeMode current,
  ) async {
    final selected = await showAppMobileSheet<ThemeMode>(
      context: context,
      builder: (sheetContext) => _ThemeSheet(current: current),
    );
    if (selected != null && selected != current) {
      await ref.read(themeModeProvider.notifier).set(selected);
    }
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
    // Muted per the Figma settings rows — the leading glyphs are
    // decorative, not max-contrast.
    return AppIcon(iconName, size: 20, color: context.colors.icon.muted);
  }
}

/// Theme picker sheet — Figma `Theme Modal` (4494:92272): white option
/// cards with leading mode icons and radio selection, committed via the
/// Update action. Pops the chosen [ThemeMode] (null = cancelled).
class _ThemeSheet extends StatefulWidget {
  const _ThemeSheet({required this.current});

  final ThemeMode current;

  @override
  State<_ThemeSheet> createState() => _ThemeSheetState();
}

class _ThemeSheetState extends State<_ThemeSheet> {
  late ThemeMode _selected = widget.current;

  static const _options = [
    (ThemeMode.system, AppIcons.monitor, 'System (Auto)'),
    (ThemeMode.light, AppIcons.day, 'Light'),
    (ThemeMode.dark, AppIcons.night, 'Dark'),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return MobileBottomSafeArea(
      bottomPadding: AppSpacing.sm,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Theme',
                    style: AppTypography.headlineSmall.copyWith(
                      color: colors.text.accent,
                    ),
                  ),
                ),
                Semantics(
                  label: 'Close',
                  button: true,
                  excludeSemantics: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: colors.background.raised,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: AppIcon(
                          AppIcons.cross,
                          size: AppIconSize.medium,
                          color: colors.icon.accent,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            for (final (mode, iconName, label) in _options) ...[
              _ThemeOptionCard(
                key: ValueKey('mobile_theme_option_${mode.name}'),
                iconName: iconName,
                label: label,
                selected: mode == _selected,
                onTap: () => setState(() => _selected = mode),
              ),
              const SizedBox(height: AppSpacing.xs),
            ],
            const SizedBox(height: AppSpacing.xs),
            AppButton(
              key: const ValueKey('mobile_theme_update'),
              expand: true,
              onPressed: () => Navigator.of(context).pop(_selected),
              child: const Text('Update'),
            ),
            const SizedBox(height: AppSpacing.xs),
            Semantics(
              button: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).pop(),
                child: SizedBox(
                  height: 44,
                  child: Center(
                    child: Text(
                      'Cancel',
                      style: AppTypography.labelLarge.copyWith(
                        color: colors.text.primary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemeOptionCard extends StatelessWidget {
  const _ThemeOptionCard({
    required this.iconName,
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String iconName;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          decoration: BoxDecoration(
            color: colors.background.ground,
            borderRadius: BorderRadius.circular(AppRadii.medium),
            border: Border.all(
              color: selected ? colors.border.strong : colors.border.subtle,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              AppIcon(iconName, size: 20, color: colors.icon.accent),
              const SizedBox(width: AppSpacing.s),
              Expanded(
                child: Text(
                  label,
                  style: AppTypography.bodyMediumStrong.copyWith(
                    color: colors.text.accent,
                  ),
                ),
              ),
              if (selected)
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: colors.background.inverse,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: AppIcon(
                      AppIcons.check,
                      size: 14,
                      color: colors.text.inverse,
                    ),
                  ),
                )
              else
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colors.background.raised,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
