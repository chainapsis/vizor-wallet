import 'dart:async';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../../core/layout/mobile/app_mobile_tab_bar.dart';
import '../../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../../core/navigation/mobile_tab_history.dart';
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
import '../../../../../l10n/app_localizations.dart';
import '../../../../providers/locale_provider.dart';

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
    final locale = ref.watch(localeProvider);
    final profilePictureId =
        account?.profilePictureId ?? kDefaultProfilePictureId;
    final profilePictureLabel = _profilePictureDisplayLabel(profilePictureId);
    final biometric =
        ref.watch(biometricUnlockProvider).value ??
        BiometricUnlockState.initial;
    final settingsRowStyle = AppTypography.labelLarge.copyWith(
      fontWeight: FontWeight.w400,
    );
    final settingsValueColor = context.colors.text.accent;
    final settingsChevronColor = context.colors.icon.accent;
    final seedPhraseEnabled = account != null && !account.isHardware;

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          MobileTopNav.back(
            title: AppLocalizations.of(context).settingsTitle,
            onBack: () => context.go(
              resolveMobileBackPath(ref, currentPath: '/settings'),
            ),
          ),
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
                  title: AppLocalizations.of(context).settingsAccountSection,
                  rows: [
                    MobileListRow(
                      key: const ValueKey('mobile_settings_seed_row'),
                      leading: _RowIcon(AppIcons.key),
                      label: AppLocalizations.of(context).settingsSecretPassphraseTitle,
                      minRowHeight: _settingsRowHeight,
                      textStyle: settingsRowStyle,
                      chevronColor: settingsChevronColor,
                      showChevron: true,
                      enabled: seedPhraseEnabled,
                      onTap: seedPhraseEnabled
                          ? () => context.push('/settings/seed-phrase')
                          : null,
                    ),
                    MobileListRow(
                      leading: _RowIcon(AppIcons.lock),
                      label: AppLocalizations.of(context).settingsPassword,
                      minRowHeight: _settingsRowHeight,
                      textStyle: settingsRowStyle,
                      chevronColor: settingsChevronColor,
                      showChevron: true,
                      onTap: () => _openChangePasscode(context),
                    ),
                    MobileListRow(
                      key: const ValueKey('mobile_settings_pfp_row'),
                      leading: _RowIcon(AppIcons.user),
                      label: AppLocalizations.of(context).settingsProfilePictureTitle,
                      minRowHeight: _settingsRowHeight,
                      textStyle: settingsRowStyle,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AppProfilePicture(
                            profilePictureId: profilePictureId,
                            size: AppProfilePictureSize.medium,
                          ),
                          const SizedBox(width: AppSpacing.xxs),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 128),
                            child: Text(
                              profilePictureLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: settingsRowStyle.copyWith(
                                color: account == null
                                    ? context.colors.text.disabled
                                    : settingsValueColor,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xxs),
                          AppIcon(
                            AppIcons.chevronForward,
                            size: AppIconSize.medium,
                            color: account == null
                                ? context.colors.icon.disabled
                                : settingsChevronColor,
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
                      label: AppLocalizations.of(context).settingsAccountNameTitle,
                      value: account?.name ?? '',
                      minRowHeight: _settingsRowHeight,
                      textStyle: settingsRowStyle,
                      valueTextStyle: settingsRowStyle,
                      valueColor: account == null
                          ? context.colors.text.disabled
                          : settingsValueColor,
                      chevronColor: settingsChevronColor,
                      showChevron: true,
                      enabled: account != null,
                      onTap: account == null
                          ? null
                          : () => _editAccount(context, ref, account),
                    ),
                    MobileListRow(
                      key: const ValueKey('mobile_settings_address_book_row'),
                      leading: _RowIcon(AppIcons.users),
                      label: AppLocalizations.of(context).settingsContacts,
                      minRowHeight: _settingsRowHeight,
                      textStyle: settingsRowStyle,
                      chevronColor: settingsChevronColor,
                      showChevron: true,
                      onTap: () => context.push('/settings/address-book'),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                _SettingsGroup(
                  title: AppLocalizations.of(context).settingsSystemSection,
                  rows: [
                    MobileListRow(
                      key: const ValueKey('mobile_settings_endpoint_row'),
                      leading: _RowIcon(AppIcons.endpoint),
                      label: AppLocalizations.of(context).settingsEndpoint,
                      value: endpoint,
                      minRowHeight: _settingsRowHeight,
                      textStyle: settingsRowStyle,
                      valueTextStyle: settingsRowStyle,
                      valueColor: settingsValueColor,
                      chevronColor: settingsChevronColor,
                      showChevron: true,
                      onTap: () => context.push('/settings/endpoint'),
                    ),
                    MobileListRow(
                      key: const ValueKey('mobile_settings_theme_row'),
                      leading: _RowIcon(AppIcons.theme),
                      label: AppLocalizations.of(context).settingsTheme,
                      value: _themeLabel(context, themeMode),
                      minRowHeight: _settingsRowHeight,
                      textStyle: settingsRowStyle,
                      valueTextStyle: settingsRowStyle,
                      valueColor: settingsValueColor,
                      chevronColor: settingsChevronColor,
                      showChevron: true,
                      onTap: () => _showThemeSheet(context, ref, themeMode),
                    ),
                    if (kLanguageFeatureEnabled)
                      MobileListRow(
                        key: const ValueKey('mobile_settings_language_row'),
                        leading: _RowIcon(AppIcons.globe),
                        label: AppLocalizations.of(context).settingsLanguage,
                        value: _languageLabel(context, locale),
                        minRowHeight: _settingsRowHeight,
                        textStyle: settingsRowStyle,
                        valueTextStyle: settingsRowStyle,
                        valueColor: settingsValueColor,
                        chevronColor: settingsChevronColor,
                        showChevron: true,
                        onTap: () => _showLanguageSheet(context, ref, locale),
                      ),
                    // No Figma frame for this row yet — listed in
                    // design_suggestion. Hidden on devices without
                    // biometric hardware.
                    if (biometric.availability.supported)
                      MobileListRow(
                        key: const ValueKey('mobile_settings_biometric_row'),
                        leading: _RowIcon(AppIcons.lock),
                        label: biometric.availability.kind.standaloneLabel(AppLocalizations.of(context)),
                        value: biometric.enabled
                            ? AppLocalizations.of(context).settingsOn
                            : AppLocalizations.of(context).settingsOff,
                        minRowHeight: _settingsRowHeight,
                        textStyle: settingsRowStyle,
                        valueTextStyle: settingsRowStyle,
                        valueColor: settingsValueColor,
                        chevronColor: settingsChevronColor,
                        showChevron: true,
                        onTap: () => unawaited(_toggleBiometric(context, ref)),
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
      showAppToast(context, AppLocalizations.of(context).settingsPasscodeUpdated);
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
        AppLocalizations.of(context).settingsAccountSaveFailed,
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
        AppLocalizations.of(context).settingsAccountSaveFailed,
        iconName: AppIcons.cross,
      );
    }
  }

  static String _themeLabel(BuildContext context, ThemeMode mode) {
    final l10n = AppLocalizations.of(context);
    return switch (mode) {
      ThemeMode.system => l10n.settingsThemeSystem,
      ThemeMode.light => l10n.settingsThemeLight,
      ThemeMode.dark => l10n.settingsThemeDark,
    };
  }

  static String _profilePictureDisplayLabel(String id) {
    final option = resolveProfilePictureOption(id);
    return switch (option.id) {
      'pfp-01' => 'Knight',
      'pfp-02' => 'Viking',
      'pfp-03' => 'Samurai',
      'pfp-11' => 'Wizard',
      _ => option.label,
    };
  }

  Future<void> _toggleBiometric(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(biometricUnlockProvider.notifier);
    final state = await ref.read(biometricUnlockProvider.future);
    if (!context.mounted) return;
    try {
      if (state.enabled) {
        final confirmed = await showAppMobileSheet<bool>(
          context: context,
          builder: (_) => _DisableBiometricSheet(kind: state.availability.kind),
        );
        if (!context.mounted || confirmed != true) return;
        await notifier.disable();
        if (context.mounted) {
          showAppToast(
            context,
            AppLocalizations.of(context).biometricFeatureOff(
              state.availability.kind.unlockFeatureLabel(AppLocalizations.of(context)),
            ),
          );
        }
        return;
      }
      if (!state.availability.usable) {
        showAppToast(
          context,
          AppLocalizations.of(context).biometricSetUpFirst(
            state.availability.kind.inlineLabel(AppLocalizations.of(context)),
          ),
        );
        return;
      }
      final passcode = ref
          .read(appSecurityProvider.notifier)
          .requireSessionPasswordForNativeSecretUse();
      await notifier.enable(passcode);
      if (context.mounted) {
        showAppToast(
          context,
          AppLocalizations.of(context).biometricFeatureOn(
            state.availability.kind.unlockFeatureLabel(AppLocalizations.of(context)),
          ),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      showAppToast(
        context,
        AppLocalizations.of(context).biometricUpdateFailed(
          state.availability.kind.inlineUnlockFeatureLabel(AppLocalizations.of(context)),
        ),
      );
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

  // Language names stay in their own language ("English" / "한국어") so a
  // user stuck in the wrong locale can always find theirs — never localize
  // them. Only the System (Auto) label localizes.
  static String _languageLabel(BuildContext context, Locale? locale) {
    if (locale == null) {
      return AppLocalizations.of(context).settingsThemeSystemAuto;
    }
    return locale.languageCode == 'ko' ? '한국어' : 'English';
  }

  Future<void> _showLanguageSheet(
    BuildContext context,
    WidgetRef ref,
    Locale? current,
  ) async {
    final selected = await showAppMobileSheet<_LanguageSelection>(
      context: context,
      builder: (sheetContext) => _LanguageSheet(current: current),
    );
    if (selected == null) return;
    final notifier = ref.read(localeProvider.notifier);
    if (selected.locale == null) {
      await notifier.clearToSystem();
    } else {
      await notifier.set(selected.locale!);
    }
  }
}

/// Wrapper so the sheet can distinguish "cancelled" (null result) from
/// "picked System (Auto)" (selection with a null locale).
class _LanguageSelection {
  const _LanguageSelection(this.locale);

  final Locale? locale;
}

class _LanguageSheet extends StatefulWidget {
  const _LanguageSheet({required this.current});

  /// Null means System (Auto).
  final Locale? current;

  @override
  State<_LanguageSheet> createState() => _LanguageSheetState();
}

class _LanguageSheetState extends State<_LanguageSheet> {
  late Locale? _selected = widget.current;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final options = <(Locale?, String, String)>[
      (null, AppIcons.monitor, l10n.settingsThemeSystemAuto),
      // Language names stay in their own language — see _languageLabel.
      (kEnglishLocale, AppIcons.globe, 'English'),
      (kKoreanLocale, AppIcons.globe, '한국어'),
    ];
    return MobileModalScaffold(
      title: l10n.settingsLanguage,
      onClose: () => Navigator.of(context).pop(),
      bodyGap: AppSpacing.md,
      bottomPadding: AppSpacing.base,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (locale, iconName, label) in options) ...[
            _ThemeOptionCard(
              key: ValueKey(
                'mobile_language_option_${locale?.languageCode ?? 'system'}',
              ),
              iconName: iconName,
              label: label,
              selected: locale?.languageCode == _selected?.languageCode,
              onTap: () => setState(() => _selected = locale),
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
          const SizedBox(height: AppSpacing.sm),
          AppButton(
            key: const ValueKey('mobile_language_update'),
            expand: true,
            onPressed: () =>
                Navigator.of(context).pop(_LanguageSelection(_selected)),
            child: Text(l10n.commonUpdate),
          ),
          const SizedBox(height: AppSpacing.xs),
          MobileSheetCancel(onTap: () => Navigator.of(context).pop()),
        ],
      ),
    );
  }
}

/// Compact confirmation sheet for disabling biometric unlock. Mirrors the
/// destructive action hierarchy used by the mobile remove-account sheet.
class _DisableBiometricSheet extends StatelessWidget {
  const _DisableBiometricSheet({required this.kind});

  final BiometricKind kind;

  static const _titleStyle = TextStyle(
    fontFamily: 'Geist',
    fontWeight: FontWeight.w600,
    fontSize: 16,
    height: 24 / 16,
    letterSpacing: -0.24,
  );
  static const _bodyStyle = TextStyle(
    fontFamily: 'Geist',
    fontWeight: FontWeight.w400,
    fontSize: 14,
    height: 21 / 14,
    letterSpacing: -0.21,
  );
  static const _buttonLabelStyle = TextStyle(
    fontFamily: 'Geist',
    fontWeight: FontWeight.w500,
    fontSize: 14,
    height: 16 / 14,
    letterSpacing: -0.06,
  );

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return MobileModalScaffold(
      title: AppLocalizations.of(context).biometricTurnOffTitle(
        kind.inlineUnlockFeatureLabel(AppLocalizations.of(context)),
      ),
      onClose: () => Navigator.of(context).pop(false),
      leading: AppIcon(AppIcons.lock, size: 20, color: colors.icon.accent),
      titleStyle: _titleStyle.copyWith(color: colors.text.accent),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            AppLocalizations.of(context).biometricTurnOffBody(
              kind.inlineUnlockFeatureLabel(AppLocalizations.of(context)),
            ),
            style: _bodyStyle.copyWith(color: colors.text.accent),
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton(
            key: const ValueKey('mobile_biometric_disable_confirm'),
            variant: AppButtonVariant.destructive,
            expand: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              AppLocalizations.of(context).settingsTurnOff,
              style: _buttonLabelStyle.copyWith(
                color: colors.button.destructive.label,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s),
          MobileSheetCancel(
            onTap: () => Navigator.of(context).pop(false),
            textStyle: _buttonLabelStyle.copyWith(
              color: colors.button.ghost.label,
            ),
          ),
        ],
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
      cornerRadius: AppRadii.large,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.base,
        AppSpacing.sm,
        AppSpacing.base,
      ),
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
              style: AppTypography.labelLarge.copyWith(
                fontWeight: FontWeight.w400,
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

const _settingsRowHeight = 44.0;

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

  List<(ThemeMode, String, String)> _options(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return [
      (ThemeMode.system, AppIcons.monitor, l10n.settingsThemeSystemAuto),
      (ThemeMode.light, AppIcons.day, l10n.settingsThemeLight),
      (ThemeMode.dark, AppIcons.night, l10n.settingsThemeDark),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return MobileModalScaffold(
      title: AppLocalizations.of(context).settingsTheme,
      onClose: () => Navigator.of(context).pop(),
      bodyGap: AppSpacing.md,
      bottomPadding: AppSpacing.base,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (mode, iconName, label) in _options(context)) ...[
            _ThemeOptionCard(
              key: ValueKey('mobile_theme_option_${mode.name}'),
              iconName: iconName,
              label: label,
              selected: mode == _selected,
              onTap: () => setState(() => _selected = mode),
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
          const SizedBox(height: AppSpacing.sm),
          AppButton(
            key: const ValueKey('mobile_theme_update'),
            expand: true,
            onPressed: () => Navigator.of(context).pop(_selected),
            child: Text(AppLocalizations.of(context).commonUpdate),
          ),
          const SizedBox(height: AppSpacing.xs),
          MobileSheetCancel(onTap: () => Navigator.of(context).pop()),
        ],
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
          height: 64,
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
              Opacity(
                opacity: selected ? 1 : 0.5,
                child: AppIcon(iconName, size: 20, color: colors.icon.accent),
              ),
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
