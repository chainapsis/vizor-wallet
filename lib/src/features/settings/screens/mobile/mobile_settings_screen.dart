import '../../../../core/l10n/l10n.dart';
import '../../../../core/layout/mobile/mobile_navigation_scope.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../payment_links/providers/payment_link_cards_provider.dart';
import '../../../../core/feedback/app_haptics.dart';
import '../../../../core/config/app_version_config.dart';
import '../../../../core/config/zcash_explorer.dart';
import '../../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../../core/layout/mobile/app_mobile_tab_bar.dart';
import '../../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../../core/navigation/route_stack.dart';
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
import '../../../../providers/zcash_explorer_provider.dart';
import '../../../../providers/sync_keep_awake_provider.dart';
import '../../../../core/l10n/app_language.dart';
import '../../../../providers/app_language_provider.dart';
import '../../../../providers/theme_mode_provider.dart';
import '../../../../services/biometric_unlock.dart';
import '../../../accounts/widgets/mobile/account_edit_sheets.dart';
import '../../../onboarding/shared/onboarding_welcome_art.dart'
    show VizorWordmark;
import '../../widgets/mobile/mobile_network_privacy_card.dart';
import '../../widgets/language_picker.dart';
import '../../widgets/settings_new_badge.dart';
import '../../widgets/settings_option_card.dart';
import '../../../donation/donation_config.dart';

/// Mobile settings tab — Figma `SETTINGS` root frame (4494:65997).
///
/// Rows share the grouped-list pattern; each row owns its navigation or
/// toggle behavior as the corresponding mobile flow ships.
class MobileSettingsScreen extends ConsumerWidget {
  const MobileSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(accountProvider).value?.activeAccount;
    final endpointConfig = ref.watch(rpcEndpointProvider);
    final endpoint = endpointConfig.hostPort;
    final explorer = explorerSettingsLabel(
      ref.watch(zcashExplorerProvider),
      networkName: endpointConfig.networkName,
    );
    final themeMode = ref.watch(themeModeProvider);
    final appLanguage = ref.watch(appLanguageProvider);
    final languages = ref.watch(availableAppLanguagesProvider);
    final profilePictureId =
        account?.profilePictureId ?? kDefaultProfilePictureId;
    final profilePictureLabel = _profilePictureDisplayLabel(
      context.l10n,
      profilePictureId,
    );
    final biometric =
        ref.watch(biometricUnlockProvider).value ??
        BiometricUnlockState.initial;
    final syncKeepAwake = ref.watch(syncKeepAwakeProvider);
    const settingsRowStyle = AppTypography.labelLarge;
    final settingsValueColor = context.colors.text.accent;
    final settingsChevronColor = context.colors.icon.accent;
    final seedPhraseEnabled = account != null && !account.isHardware;
    final viewingKeyEnabled = account != null;

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          MobileTopNav.back(title: context.l10n.navSettings),
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.sm,
                AppSpacing.s,
                AppSpacing.sm,
                // The shell exposes the floating tab bar's full occupied
                // height, including Android's navigation-bar inset.
                math.max(
                  MobileNavigationScope.bottomClearanceOf(
                    context,
                    kMobileTabBarHeight + AppSpacing.lg,
                  ),
                  MediaQuery.paddingOf(context).bottom + AppSpacing.md,
                ),
              ),
              children: [
                _SettingsGroup(
                  title: context.l10n.settingsSectionPersonal,
                  rows: [
                    MobileListRow(
                      key: const ValueKey(
                        'mobile_settings_coinholder_voting_row',
                      ),
                      leading: _RowIcon(AppIcons.vote),
                      label: context.l10n.commonCoinholderVoting,
                      minRowHeight: _settingsRowHeight,
                      textStyle: settingsRowStyle,
                      chevronColor: settingsChevronColor,
                      showChevron: true,
                      onTap: () => context.push('/voting'),
                    ),
                    _GiftCardsRow(
                      textStyle: settingsRowStyle,
                      chevronColor: settingsChevronColor,
                    ),
                    MobileListRow(
                      key: const ValueKey('mobile_settings_address_book_row'),
                      leading: _RowIcon(AppIcons.users),
                      label: context.l10n.settingsRowAddressBook,
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
                  title: context.l10n.settingsSectionAccount,
                  rows: [
                    MobileListRow(
                      key: const ValueKey('mobile_settings_seed_row'),
                      leading: _RowIcon(AppIcons.key),
                      label: context.l10n.secretPassphraseTitle,
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
                      key: const ValueKey('mobile_settings_viewing_key_row'),
                      leading: _RowIcon(AppIcons.eye),
                      label: context.l10n.settingsRowViewingKeyMobile,
                      minRowHeight: _settingsRowHeight,
                      textStyle: settingsRowStyle,
                      chevronColor: settingsChevronColor,
                      showChevron: true,
                      enabled: viewingKeyEnabled,
                      onTap: viewingKeyEnabled
                          ? () => context.push('/settings/viewing-key')
                          : null,
                    ),
                    MobileListRow(
                      leading: _RowIcon(AppIcons.lock),
                      label: context.l10n.settingsRowChangePasscode,
                      minRowHeight: _settingsRowHeight,
                      textStyle: settingsRowStyle,
                      chevronColor: settingsChevronColor,
                      showChevron: true,
                      onTap: () => _openChangePasscode(context),
                    ),
                    MobileListRow(
                      key: const ValueKey('mobile_settings_pfp_row'),
                      leading: _RowIcon(AppIcons.user),
                      label: context.l10n.settingsRowProfilePictureMobile,
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
                      label: context.l10n.settingsRowAccountNameMobile,
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
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                _SyncKeepAwakeSettingsCard(
                  enabled: syncKeepAwake.enabled,
                  onToggle: () => unawaited(
                    _toggleSyncKeepAwake(
                      context,
                      ref,
                      enabled: syncKeepAwake.enabled,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                _SettingsGroup(
                  title: context.l10n.settingsSectionSystem,
                  rows: [
                    MobileListRow(
                      key: const ValueKey('mobile_settings_endpoint_row'),
                      leading: _RowIcon(AppIcons.endpoint),
                      label: context.l10n.settingsEndpointTitle,
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
                      key: const ValueKey('mobile_settings_explorer_row'),
                      leading: _RowIcon(AppIcons.globe),
                      label: context.l10n.settingsExplorerTitle,
                      value: explorer,
                      minRowHeight: _settingsRowHeight,
                      textStyle: settingsRowStyle,
                      valueTextStyle: settingsRowStyle,
                      valueColor: settingsValueColor,
                      chevronColor: settingsChevronColor,
                      showChevron: true,
                      onTap: () => context.push('/settings/explorer'),
                    ),
                    MobileListRow(
                      key: const ValueKey('mobile_settings_theme_row'),
                      leading: _RowIcon(AppIcons.theme),
                      label: context.l10n.settingsThemeTitle,
                      value: _themeLabel(context.l10n, themeMode),
                      minRowHeight: _settingsRowHeight,
                      textStyle: settingsRowStyle,
                      valueTextStyle: settingsRowStyle,
                      valueColor: settingsValueColor,
                      chevronColor: settingsChevronColor,
                      showChevron: true,
                      onTap: () => _showThemeSheet(context, ref, themeMode),
                    ),
                    // With English alone there is nothing to choose.
                    if (languages.length > 1)
                      MobileListRow(
                        key: const ValueKey('mobile_settings_language_row'),
                        leading: _RowIcon(AppIcons.language),
                        label: context.l10n.settingsLanguageLabel,
                        value: appLanguageLabel(
                          context,
                          appLanguage,
                          languages,
                        ),
                        minRowHeight: _settingsRowHeight,
                        textStyle: settingsRowStyle,
                        valueTextStyle: settingsRowStyle,
                        valueColor: settingsValueColor,
                        chevronColor: settingsChevronColor,
                        showChevron: true,
                        onTap: () => unawaited(
                          _showLanguageSheet(
                            context,
                            ref,
                            appLanguage,
                            languages,
                          ),
                        ),
                      ),
                    // No Figma frame for this row yet — listed in
                    // design_suggestion. Hidden on devices without
                    // biometric hardware.
                    if (biometric.availability.supported)
                      MobileListRow(
                        key: const ValueKey('mobile_settings_biometric_row'),
                        leading: _RowIcon(AppIcons.lock),
                        label: biometric.availability.kind.standaloneLabel,
                        value: biometric.enabled
                            ? context.l10n.settingsStatusOn
                            : context.l10n.settingsStatusOff,
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
                const SizedBox(height: AppSpacing.md),
                const MobileNetworkPrivacyCard(),
                if (donationFeatureEnabledForNetwork(
                  endpointConfig.networkName,
                )) ...[
                  const SizedBox(height: AppSpacing.md),
                  _SettingsGroup(
                    title: context.l10n.settingsSectionMisc,
                    rows: [
                      MobileListRow(
                        key: const ValueKey('mobile_settings_donation_row'),
                        leading: _RowIcon(AppIcons.donation, glyphSize: 16.5),
                        label: context.l10n.settingsRowSupportVizor,
                        minRowHeight: _settingsRowHeight,
                        textStyle: settingsRowStyle,
                        chevronColor: settingsChevronColor,
                        showChevron: true,
                        onTap: () => context.push('/donation'),
                      ),
                    ],
                  ),
                ],
                // The About row stays hidden until the legal documents
                // are ready — the /about screen exists but must not be
                // user-reachable (product decision, 2026-06).
                const SizedBox(height: AppSpacing.base),
                const _SettingsVersionFooter(
                  key: ValueKey('mobile_settings_version'),
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
      showAppToast(context, context.l10n.settingsPasscodeUpdatedToast);
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
        context.l10n.accountsSaveFailed,
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
        context.l10n.accountsSaveFailed,
        iconName: AppIcons.cross,
      );
    }
  }

  static String _themeLabel(AppLocalizations l10n, ThemeMode mode) =>
      switch (mode) {
        ThemeMode.system => l10n.settingsThemeSystem,
        ThemeMode.light => l10n.settingsThemeLight,
        ThemeMode.dark => l10n.settingsThemeDark,
      };

  static String _profilePictureDisplayLabel(AppLocalizations l10n, String id) {
    final option = resolveProfilePictureOption(id);
    return switch (option.id) {
      'pfp-01' => l10n.settingsPfpKnight,
      'pfp-02' => l10n.settingsPfpViking,
      'pfp-03' => l10n.settingsPfpSamurai,
      'pfp-11' => l10n.settingsPfpWizard,
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
        unawaited(AppHaptics.selection());
        if (context.mounted) {
          showAppToast(
            context,
            context.l10n.settingsBiometricOffToast(
              state.availability.kind.unlockFeatureLabel,
            ),
          );
        }
        return;
      }
      if (!state.availability.usable) {
        showAppToast(
          context,
          context.l10n.settingsBiometricSetupFirst(
            state.availability.kind.inlineLabel,
          ),
        );
        return;
      }
      final passcode = ref
          .read(appSecurityProvider.notifier)
          .requireSessionPasswordForNativeSecretUse();
      await notifier.enable(passcode);
      unawaited(AppHaptics.selection());
      if (context.mounted) {
        showAppToast(
          context,
          context.l10n.settingsBiometricOnToast(
            state.availability.kind.unlockFeatureLabel,
          ),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      showAppToast(
        context,
        context.l10n.settingsBiometricUpdateFailed(
          state.availability.kind.inlineUnlockFeatureLabel,
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

  Future<void> _showLanguageSheet(
    BuildContext context,
    WidgetRef ref,
    AppLanguage? current,
    List<AppLanguage> languages,
  ) async {
    final choice = await showMobileLanguageSheet(
      context,
      current: current,
      available: languages,
    );
    if (choice == null || choice.language == current) return;
    try {
      await ref.read(appLanguageProvider.notifier).set(choice.language);
    } catch (_) {
      if (context.mounted) {
        showAppToast(context, context.l10n.settingsLanguageUpdateFailed);
      }
    }
  }

  Future<void> _toggleSyncKeepAwake(
    BuildContext context,
    WidgetRef ref, {
    required bool enabled,
  }) async {
    try {
      await ref.read(syncKeepAwakeProvider.notifier).setEnabled(!enabled);
      if (context.mounted &&
          ref.read(syncKeepAwakeProvider).enabled != enabled) {
        unawaited(AppHaptics.selection());
      }
    } catch (_) {
      if (!context.mounted) return;
      showAppToast(context, context.l10n.settingsKeepAwakeUpdateFailed);
    }
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

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return MobileModalScaffold(
      title: context.l10n.settingsBiometricTurnOffTitle(
        kind.inlineUnlockFeatureLabel,
      ),
      onClose: () => Navigator.of(context).pop(false),
      leading: AppIcon(AppIcons.lock, size: 20, color: colors.icon.accent),
      titleStyle: _titleStyle.copyWith(color: colors.text.accent),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.l10n.settingsBiometricTurnOffBody(
              kind.inlineUnlockFeatureLabel,
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
              context.l10n.settingsTurnOffConfirm,
              style: AppTypography.labelLarge.copyWith(
                color: colors.button.destructive.label,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s),
          MobileSheetCancel(
            onTap: () => Navigator.of(context).pop(false),
            textStyle: AppTypography.labelLarge.copyWith(
              color: colors.button.ghost.label,
            ),
          ),
        ],
      ),
    );
  }
}

/// A quiet app signature, separate from the actionable settings cards.
/// Keep the full release identifier, including rc/internal suffixes.
class _SettingsVersionFooter extends StatelessWidget {
  const _SettingsVersionFooter({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: context.l10n.settingsVersionFooterLabel(kVizorReleaseVersion),
      excludeSemantics: true,
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            VizorWordmark(
              width: 64,
              height: 24,
              color: context.colors.text.secondary,
            ),
            const SizedBox(width: AppSpacing.s),
            SizedBox(
              width: 1,
              height: AppSpacing.sm,
              child: ColoredBox(color: context.colors.border.regular),
            ),
            const SizedBox(width: AppSpacing.s),
            Flexible(
              child: Text(
                'v$kVizorReleaseVersion',
                style: AppTypography.codeSmall.copyWith(
                  color: context.colors.text.secondary,
                ),
              ),
            ),
          ],
        ),
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

class _SyncKeepAwakeSettingsCard extends StatelessWidget {
  const _SyncKeepAwakeSettingsCard({
    required this.enabled,
    required this.onToggle,
  });

  final bool enabled;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
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
            padding: const EdgeInsets.all(AppSpacing.xxs),
            child: Text(
              context.l10n.settingsSectionSyncing,
              style: AppTypography.labelLarge.copyWith(
                color: colors.text.secondary,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s),
          Semantics(
            button: true,
            toggled: enabled,
            label: context.l10n.commonKeepScreenAwake,
            excludeSemantics: true,
            child: GestureDetector(
              key: const ValueKey('mobile_settings_sync_keep_awake_row'),
              behavior: HitTestBehavior.opaque,
              onTap: onToggle,
              child: SizedBox(
                height: _settingsRowHeight,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xxs,
                  ),
                  child: Row(
                    children: [
                      const SizedBox.square(
                        dimension: 32,
                        child: Center(child: _RowIcon(AppIcons.day)),
                      ),
                      const SizedBox(width: AppSpacing.s),
                      Expanded(
                        child: Text(
                          context.l10n.commonKeepScreenAwake,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.labelLarge.copyWith(
                            color: colors.text.accent,
                          ),
                        ),
                      ),
                      _SyncKeepAwakeToggle(
                        key: const ValueKey(
                          'mobile_settings_sync_keep_awake_toggle',
                        ),
                        enabled: enabled,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            context.l10n.settingsKeepAwakeDescription,
            style: AppTypography.bodyMedium.copyWith(
              color: colors.text.secondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _SyncKeepAwakeToggle extends StatelessWidget {
  const _SyncKeepAwakeToggle({required this.enabled, super.key});

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final trackColor = enabled
        ? colors.background.brandCrimsonStrong
        : colors.background.raised;
    final borderColor = enabled
        ? colors.border.brandCrimsonStrong
        : colors.border.regular;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      width: 64,
      height: 28,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: trackColor,
        borderRadius: BorderRadius.circular(AppRadii.full),
        border: Border.all(color: borderColor),
      ),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        alignment: enabled ? Alignment.centerRight : Alignment.centerLeft,
        child: DecoratedBox(
          key: const ValueKey('mobile_settings_sync_keep_awake_toggle_thumb'),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFFFF),
            borderRadius: BorderRadius.circular(AppRadii.full),
          ),
          child: const SizedBox(width: 40, height: 24),
        ),
      ),
    );
  }
}

const _settingsRowHeight = 44.0;

class _RowIcon extends StatelessWidget {
  const _RowIcon(this.iconName, {this.glyphSize = 20});

  final String iconName;
  final double glyphSize;

  @override
  Widget build(BuildContext context) {
    // Muted per the Figma settings rows — the leading glyphs are
    // decorative, not max-contrast.
    final icon = AppIcon(iconName, size: 20, color: context.colors.icon.muted);
    return glyphSize == 20
        ? icon
        : Transform.scale(scale: glyphSize / 20, child: icon);
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

  @override
  Widget build(BuildContext context) {
    final options = [
      (
        ThemeMode.system,
        AppIcons.monitor,
        context.l10n.settingsThemeSystemAuto,
      ),
      (ThemeMode.light, AppIcons.day, context.l10n.settingsThemeLight),
      (ThemeMode.dark, AppIcons.night, context.l10n.settingsThemeDark),
    ];
    return MobileModalScaffold(
      title: context.l10n.settingsThemeTitle,
      onClose: () => Navigator.of(context).pop(),
      bodyGap: AppSpacing.md,
      bottomPadding: AppSpacing.base,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (mode, iconName, label) in options) ...[
            MobileSettingsOptionCard(
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
            child: Text(context.l10n.commonUpdate),
          ),
          const SizedBox(height: AppSpacing.xs),
          MobileSheetCancel(onTap: () => Navigator.of(context).pop()),
        ],
      ),
    );
  }
}

/// The Gift Cards entry. Like the desktop settings entry, it loads the
/// created and received cards before pushing the screen, so the screen opens
/// straight on the cards list (or the create/redeem landing) instead of
/// flashing the landing while it loads. A load failure still opens the
/// screen, which then loads its own cards.
class _GiftCardsRow extends ConsumerStatefulWidget {
  const _GiftCardsRow({required this.textStyle, required this.chevronColor});

  final TextStyle textStyle;
  final Color chevronColor;

  @override
  ConsumerState<_GiftCardsRow> createState() => _GiftCardsRowState();
}

class _GiftCardsRowState extends ConsumerState<_GiftCardsRow> {
  bool _isOpening = false;

  @override
  Widget build(BuildContext context) {
    return MobileListRow(
      key: const ValueKey('mobile_settings_gift_cards_row'),
      leading: _RowIcon(AppIcons.giftCard),
      label: context.l10n.settingsRowMyGiftCards,
      labelBadge: const SettingsNewBadge(),
      minRowHeight: _settingsRowHeight,
      textStyle: widget.textStyle,
      chevronColor: widget.chevronColor,
      showChevron: true,
      onTap: _isOpening ? null : () => unawaited(_open()),
    );
  }

  Future<void> _open() async {
    if (_isOpening) return;
    setState(() => _isOpening = true);
    final router = GoRouter.of(context);
    final entryPath = router.routerDelegate.currentConfiguration.uri.path;
    PaymentLinkCardsSnapshot? cards;
    try {
      cards = await ref.read(paymentLinkCardsLoaderProvider)();
    } catch (_) {
      cards = null;
    }
    if (!mounted) return;
    setState(() => _isOpening = false);
    // Drop the open once the user has moved on: the tab shell's sheets sit
    // on the root navigator, so the path alone does not show them.
    if (router.routerDelegate.currentConfiguration.uri.path != entryPath ||
        !isRouteTopmost(context)) {
      return;
    }
    unawaited(router.push('/payment-links', extra: cards));
  }
}
