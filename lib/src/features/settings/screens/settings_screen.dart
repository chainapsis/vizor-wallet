import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/layout/app_pane_scroll_scaffold.dart';
import '../../../core/profile_pictures.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_pane_modal_overlay.dart';
import '../../../core/widgets/app_profile_picture.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/locale_provider.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../providers/theme_mode_provider.dart';
import '../../../providers/windows_update_provider.dart';
import '../../accounts/widgets/account_modal_card.dart';
import '../../accounts/widgets/account_edit_modal.dart';
import '../../accounts/widgets/account_profile_picture_modal.dart';
import '../settings_platform.dart';

const _settingsRowActivationShortcuts = <ShortcutActivator, Intent>{
  SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
  SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
};

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

enum _SettingsModalType { accountName, profilePicture, theme, language, updates }

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  _SettingsModalType? _activeModal;

  // Edit-account drafts for the picker round-trip (same model as the
  // accounts screen): the in-progress name and picked picture survive
  // while the picker temporarily replaces the edit modal.
  String? _editDraftName;
  String? _editDraftProfilePictureId;
  bool _pfpPickerFromEdit = false;

  void _showModal(_SettingsModalType modal) {
    setState(() {
      _activeModal = modal;
    });
  }

  void _closeModal() {
    setState(() {
      _activeModal = null;
      _editDraftName = null;
      _editDraftProfilePictureId = null;
      _pfpPickerFromEdit = false;
    });
  }

  void _openEditProfilePicturePicker() {
    setState(() {
      _pfpPickerFromEdit = true;
      _activeModal = _SettingsModalType.profilePicture;
    });
  }

  void _returnToEditAccountModal({String? pickedProfilePictureId}) {
    setState(() {
      if (pickedProfilePictureId != null) {
        _editDraftProfilePictureId = pickedProfilePictureId;
      }
      _pfpPickerFromEdit = false;
      _activeModal = _SettingsModalType.accountName;
    });
  }

  Future<void> _commitEditAccount(String name) async {
    final accountState = ref.read(accountProvider).value;
    final account = accountState?.activeAccount;
    if (account == null) return;
    final notifier = ref.read(accountProvider.notifier);
    if (name.trim() != account.name.trim()) {
      await notifier.renameAccount(account.uuid, name);
    }
    final draftPicture = _editDraftProfilePictureId;
    if (draftPicture != null && draftPicture != account.profilePictureId) {
      await notifier.updateProfilePicture(account.uuid, draftPicture);
    }
    if (!mounted) return;
    _closeModal();
  }

  Future<void> _updateTheme(ThemeMode mode) async {
    await ref.read(themeModeProvider.notifier).set(mode);
    if (!mounted) return;
    _closeModal();
  }

  Future<void> _updateLanguage(Locale? locale) async {
    final notifier = ref.read(localeProvider.notifier);
    if (locale == null) {
      await notifier.clearToSystem();
    } else {
      await notifier.set(locale);
    }
    if (!mounted) return;
    _closeModal();
  }

  Future<void> _updateProfilePicture(String profilePictureId) async {
    final accountUuid = ref.read(accountProvider).value?.activeAccountUuid;
    if (accountUuid == null) return;
    await ref
        .read(accountProvider.notifier)
        .updateProfilePicture(accountUuid, profilePictureId);
    if (!mounted) return;
    _closeModal();
  }

  @override
  Widget build(BuildContext context) {
    // The edit-account modals bind to the ACTIVE account, and the sidebar
    // stays interactive under the pane overlay — switching accounts while a
    // modal is open must drop the previous account's drafts so Update can't
    // commit them to the newly selected account.
    ref.listen(
      accountProvider.select((state) => state.value?.activeAccountUuid),
      (previous, next) {
        if (previous == next) return;
        if (_editDraftName == null && _editDraftProfilePictureId == null) {
          return;
        }
        setState(() {
          _editDraftName = null;
          _editDraftProfilePictureId = null;
        });
      },
    );
    final l10n = AppLocalizations.of(context);
    final accountState = ref.watch(accountProvider).value;
    final activeAccountName = accountState?.activeAccount?.name ?? 'Wallet 1';
    final activeProfilePictureId =
        accountState?.activeAccount?.profilePictureId ??
        kDefaultProfilePictureId;
    final hasActiveAccount = accountState?.activeAccountUuid != null;
    final activeAccountIsHardware =
        accountState?.activeAccount?.isHardware ?? false;
    final themeMode = ref.watch(themeModeProvider);
    // Null preference means System (Auto): the app follows the OS locale.
    final currentLocale = ref.watch(localeProvider);
    final endpointLabel = ref.watch(rpcEndpointProvider).hostPort;
    final updateState = Platform.isWindows
        ? ref.watch(windowsUpdateProvider)
        : null;
    final showUninstall = settingsUninstallSupported();

    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        padding: EdgeInsets.zero,
        child: Stack(
          children: [
            AppPaneScrollScaffold(
              toolbar: const AppPaneToolbar(
                // Design: back chevron sits 16px into the pane on every
                // settings/utility screen. The 16px inset is the
                // AppPaneToolbar default, so no padding override is needed.
                backLinkMinWidth: 60,
              ),
              child: _SettingsPane(
                accountName: activeAccountName,
                profilePictureId: activeProfilePictureId,
                profilePictureLabel: _profilePictureLabel(
                  l10n,
                  activeProfilePictureId,
                ),
                activeAccountIsHardware: activeAccountIsHardware,
                endpointLabel: endpointLabel,
                themeLabel: _themeLabel(l10n, themeMode),
                languageLabel: _languageLabel(
                  AppLocalizations.of(context),
                  currentLocale,
                ),
                updateLabel: updateState == null
                    ? null
                    : _updateLabel(l10n, updateState),
                onSeedPhrase: () => context.push('/settings/secret-passphrase'),
                onChangePassword: () =>
                    context.push('/settings/change-password'),
                onEndpoint: () => context.push('/settings/endpoint'),
                onAccountName: hasActiveAccount
                    ? () => _showModal(_SettingsModalType.accountName)
                    : null,
                onProfilePicture: hasActiveAccount
                    ? () => _showModal(_SettingsModalType.profilePicture)
                    : null,
                onAddressBook: () => context.push('/address-book'),
                onLinkMobile: () => context.push('/settings/link-mobile'),
                onTheme: () => _showModal(_SettingsModalType.theme),
                onLanguage: () => _showModal(_SettingsModalType.language),
                onUpdates: updateState == null
                    ? null
                    : () => _showModal(_SettingsModalType.updates),
                onAbout: () => context.push('/about'),
                onUninstall: showUninstall
                    ? () => context.go('/settings/uninstall')
                    : null,
              ),
            ),
            if (_activeModal != null)
              AppPaneModalOverlay(
                onDismiss: _closeModal,
                child: switch (_activeModal!) {
                  _SettingsModalType.accountName => AccountEditModal(
                    accountUuid: accountState?.activeAccountUuid ?? '',
                    accountName: activeAccountName,
                    initialName: _editDraftName ?? activeAccountName,
                    profilePictureId:
                        _editDraftProfilePictureId ?? activeProfilePictureId,
                    profilePictureChanged:
                        (_editDraftProfilePictureId ??
                            activeProfilePictureId) !=
                        activeProfilePictureId,
                    onEditProfilePicture: _openEditProfilePicturePicker,
                    onNameChanged: (name) => _editDraftName = name,
                    onCancel: _closeModal,
                    onUpdate: _commitEditAccount,
                  ),
                  _SettingsModalType.profilePicture =>
                    AccountProfilePictureModal(
                      currentProfilePictureId: _pfpPickerFromEdit
                          ? (_editDraftProfilePictureId ??
                                activeProfilePictureId)
                          : activeProfilePictureId,
                      onCancel: _pfpPickerFromEdit
                          ? () => _returnToEditAccountModal()
                          : _closeModal,
                      onUpdate: (profilePictureId) async {
                        if (_pfpPickerFromEdit) {
                          _returnToEditAccountModal(
                            pickedProfilePictureId: profilePictureId,
                          );
                          return;
                        }
                        await _updateProfilePicture(profilePictureId);
                      },
                    ),
                  _SettingsModalType.theme => _ThemeModal(
                    currentMode: themeMode,
                    onCancel: _closeModal,
                    onUpdate: _updateTheme,
                  ),
                  _SettingsModalType.language => _LanguageModal(
                    currentLocale: currentLocale,
                    onCancel: _closeModal,
                    onUpdate: _updateLanguage,
                  ),
                  _SettingsModalType.updates => _WindowsUpdateModal(
                    onCancel: _closeModal,
                  ),
                },
              ),
          ],
        ),
      ),
    );
  }

  static String _themeLabel(AppLocalizations l10n, ThemeMode mode) {
    return switch (mode) {
      ThemeMode.system => l10n.settingsThemeSystem,
      ThemeMode.light => l10n.settingsThemeLight,
      ThemeMode.dark => l10n.settingsThemeDark,
    };
  }

  // Language names stay in their own language ("English" / "한국어") so a user
  // stuck in the wrong locale can always find theirs — never localize them.
  // Only the System (Auto) label localizes.
  static String _languageLabel(AppLocalizations l10n, Locale? locale) {
    if (locale == null) return l10n.settingsThemeSystemAuto;
    return locale.languageCode == 'ko' ? '한국어' : 'English';
  }

  static String _profilePictureLabel(
    AppLocalizations l10n,
    String profilePictureId,
  ) {
    return findProfilePictureOption(profilePictureId)?.label ??
        l10n.settingsProfilePictureCustom;
  }

  static String _updateLabel(AppLocalizations l10n, WindowsUpdateState state) {
    if (!state.supported) return l10n.settingsUpdateUnavailable;
    return switch (state.status) {
      WindowsUpdateStatus.checking => l10n.settingsUpdateChecking,
      WindowsUpdateStatus.available => l10n.settingsUpdateAvailable,
      WindowsUpdateStatus.downloading => '${state.downloadProgress}%',
      WindowsUpdateStatus.ready => l10n.settingsUpdateRestart,
      WindowsUpdateStatus.applying => l10n.settingsUpdateApplying,
      WindowsUpdateStatus.failed => l10n.settingsUpdateFailed,
      WindowsUpdateStatus.noUpdate => l10n.settingsUpdateUpToDate,
      _ => l10n.settingsUpdateCheck,
    };
  }
}

class _SettingsPane extends StatelessWidget {
  const _SettingsPane({
    required this.accountName,
    required this.profilePictureId,
    required this.profilePictureLabel,
    required this.activeAccountIsHardware,
    required this.endpointLabel,
    required this.themeLabel,
    required this.languageLabel,
    required this.updateLabel,
    required this.onSeedPhrase,
    required this.onChangePassword,
    required this.onEndpoint,
    required this.onAccountName,
    required this.onProfilePicture,
    required this.onAddressBook,
    required this.onLinkMobile,
    required this.onTheme,
    required this.onLanguage,
    required this.onUpdates,
    required this.onAbout,
    required this.onUninstall,
  });

  final String accountName;
  final String profilePictureId;
  final String profilePictureLabel;
  final bool activeAccountIsHardware;
  final String endpointLabel;
  final String themeLabel;
  final String languageLabel;
  final String? updateLabel;
  final VoidCallback onSeedPhrase;
  final VoidCallback onChangePassword;
  final VoidCallback onEndpoint;
  final VoidCallback? onAccountName;
  final VoidCallback? onProfilePicture;
  final VoidCallback onAddressBook;
  final VoidCallback onLinkMobile;
  final VoidCallback onTheme;
  final VoidCallback onLanguage;
  final VoidCallback? onUpdates;
  final VoidCallback onAbout;
  final VoidCallback? onUninstall;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: AppSpacing.sm),
              Text(
                AppLocalizations.of(context).settingsTitle,
                textAlign: TextAlign.center,
                style: AppTypography.headlineLarge.copyWith(
                  color: colors.text.accent,
                ),
              ),
              const SizedBox(height: AppSpacing.base),
              _SettingsList(
                accountName: accountName,
                profilePictureId: profilePictureId,
                profilePictureLabel: profilePictureLabel,
                activeAccountIsHardware: activeAccountIsHardware,
                endpointLabel: endpointLabel,
                themeLabel: themeLabel,
                languageLabel: languageLabel,
                updateLabel: updateLabel,
                onSeedPhrase: onSeedPhrase,
                onChangePassword: onChangePassword,
                onEndpoint: onEndpoint,
                onAccountName: onAccountName,
                onProfilePicture: onProfilePicture,
                onAddressBook: onAddressBook,
                onLinkMobile: onLinkMobile,
                onTheme: onTheme,
                onLanguage: onLanguage,
                onUpdates: onUpdates,
                onAbout: onAbout,
                onUninstall: onUninstall,
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsList extends StatelessWidget {
  const _SettingsList({
    required this.accountName,
    required this.profilePictureId,
    required this.profilePictureLabel,
    required this.activeAccountIsHardware,
    required this.endpointLabel,
    required this.themeLabel,
    required this.languageLabel,
    required this.updateLabel,
    required this.onSeedPhrase,
    required this.onChangePassword,
    required this.onEndpoint,
    required this.onAccountName,
    required this.onProfilePicture,
    required this.onAddressBook,
    required this.onLinkMobile,
    required this.onTheme,
    required this.onLanguage,
    required this.onUpdates,
    required this.onAbout,
    required this.onUninstall,
  });

  final String accountName;
  final String profilePictureId;
  final String profilePictureLabel;
  final bool activeAccountIsHardware;
  final String endpointLabel;
  final String themeLabel;
  final String languageLabel;
  final String? updateLabel;
  final VoidCallback onSeedPhrase;
  final VoidCallback onChangePassword;
  final VoidCallback onEndpoint;
  final VoidCallback? onAccountName;
  final VoidCallback? onProfilePicture;
  final VoidCallback onAddressBook;
  final VoidCallback onLinkMobile;
  final VoidCallback onTheme;
  final VoidCallback onLanguage;
  final VoidCallback? onUpdates;
  final VoidCallback onAbout;
  final VoidCallback? onUninstall;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SettingsBlock(
          title: l10n.settingsSectionAccount,
          rows: [
            _SettingsRow(
              iconName: AppIcons.key,
              label: l10n.settingsSecretPassphrase,
              onTap: activeAccountIsHardware ? null : onSeedPhrase,
            ),
            _SettingsRow(
              iconName: AppIcons.lock,
              label: l10n.settingsPassword,
              onTap: onChangePassword,
            ),
            _SettingsRow(
              iconName: AppIcons.user,
              label: l10n.settingsProfilePicture,
              value: profilePictureLabel,
              valueLeading: AppProfilePicture(
                profilePictureId: profilePictureId,
                size: AppProfilePictureSize.medium,
              ),
              onTap: onProfilePicture,
            ),
            _SettingsRow(
              iconName: AppIcons.scroll,
              label: l10n.settingsAccountName,
              value: accountName,
              onTap: onAccountName,
            ),
            _SettingsRow(
              iconName: AppIcons.users,
              label: l10n.settingsContacts,
              onTap: onAddressBook,
            ),
            _SettingsRow(
              iconName: AppIcons.link,
              label: 'Link mobile',
              onTap: onLinkMobile,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        _SettingsBlock(
          title: l10n.settingsSectionSystem,
          rows: [
            _SettingsRow(
              iconName: AppIcons.endpoint,
              label: l10n.settingsEndpoint,
              value: endpointLabel,
              onTap: onEndpoint,
            ),
            _SettingsRow(
              iconName: AppIcons.theme,
              label: l10n.settingsTheme,
              value: themeLabel,
              onTap: onTheme,
            ),
            if (kLanguageFeatureEnabled)
              _SettingsRow(
                iconName: AppIcons.globe,
                label: l10n.settingsLanguage,
                value: languageLabel,
                onTap: onLanguage,
              ),
            if (updateLabel != null && onUpdates != null)
              _SettingsRow(
                iconName: AppIcons.sync,
                label: l10n.settingsUpdates,
                value: updateLabel,
                onTap: onUpdates,
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        _SettingsBlock(
          title: l10n.settingsSectionMisc,
          rows: [
            _SettingsRow(
              iconName: AppIcons.vizor,
              label: l10n.settingsAboutVizor,
              onTap: onAbout,
            ),
          ],
        ),
        if (onUninstall != null) ...[
          const SizedBox(height: AppSpacing.md),
          _SettingsBlock(
            title: l10n.settingsSectionDangerZone,
            rows: [
              _SettingsRow(
                iconName: AppIcons.trash,
                label: l10n.settingsUninstallVizor,
                destructive: true,
                onTap: onUninstall!,
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _ThemeModal extends StatefulWidget {
  const _ThemeModal({
    required this.currentMode,
    required this.onCancel,
    required this.onUpdate,
  });

  final ThemeMode currentMode;
  final VoidCallback onCancel;
  final Future<void> Function(ThemeMode mode) onUpdate;

  @override
  State<_ThemeModal> createState() => _ThemeModalState();
}

class _ThemeModalState extends State<_ThemeModal> {
  late ThemeMode _selectedMode = widget.currentMode;
  bool _isSubmitting = false;
  String? _submitError;

  bool get _canUpdate => !_isSubmitting && _selectedMode != widget.currentMode;

  void _select(ThemeMode mode) {
    setState(() {
      _submitError = null;
      _selectedMode = mode;
    });
  }

  Future<void> _submit() async {
    if (!_canUpdate) return;
    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });
    try {
      await widget.onUpdate(_selectedMode);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitError = AppLocalizations.of(context).settingsThemeUpdateError;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return AccountModalCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.settingsTheme,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodyLarge.copyWith(
              color: context.colors.text.accent,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _ThemeOptionCard(
            iconName: AppIcons.monitor,
            label: l10n.settingsThemeSystemAuto,
            selected: _selectedMode == ThemeMode.system,
            onTap: () => _select(ThemeMode.system),
          ),
          const SizedBox(height: AppSpacing.xs),
          _ThemeOptionCard(
            iconName: AppIcons.day,
            label: l10n.settingsThemeLight,
            selected: _selectedMode == ThemeMode.light,
            onTap: () => _select(ThemeMode.light),
          ),
          const SizedBox(height: AppSpacing.xs),
          _ThemeOptionCard(
            iconName: AppIcons.night,
            label: l10n.settingsThemeDark,
            selected: _selectedMode == ThemeMode.dark,
            onTap: () => _select(ThemeMode.dark),
          ),
          const SizedBox(height: AppSpacing.md),
          if (_submitError != null) ...[
            Text(
              _submitError!,
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(
                color: context.colors.text.destructive,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
          AccountModalActions(
            onCancel: _isSubmitting ? null : widget.onCancel,
            cancelLabel: l10n.commonCancel,
            actionLabel: _isSubmitting ? l10n.commonUpdating : l10n.commonUpdate,
            onAction: _canUpdate ? _submit : null,
          ),
        ],
      ),
    );
  }
}

class _LanguageModal extends StatefulWidget {
  const _LanguageModal({
    required this.currentLocale,
    required this.onCancel,
    required this.onUpdate,
  });

  /// Null means System (Auto).
  final Locale? currentLocale;
  final VoidCallback onCancel;
  final Future<void> Function(Locale? locale) onUpdate;

  @override
  State<_LanguageModal> createState() => _LanguageModalState();
}

class _LanguageModalState extends State<_LanguageModal> {
  late Locale? _selectedLocale = widget.currentLocale;
  bool _isSubmitting = false;
  String? _submitError;

  bool get _canUpdate =>
      !_isSubmitting &&
      _selectedLocale?.languageCode != widget.currentLocale?.languageCode;

  void _select(Locale? locale) {
    setState(() {
      _submitError = null;
      _selectedLocale = locale;
    });
  }

  Future<void> _submit() async {
    if (!_canUpdate) return;
    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });
    try {
      await widget.onUpdate(_selectedLocale);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitError = AppLocalizations.of(context).settingsLanguageUpdateError;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return AccountModalCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.settingsLanguage,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodyLarge.copyWith(
              color: context.colors.text.accent,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          // Option labels stay in their own language — see _languageLabel.
          _ThemeOptionCard(
            iconName: AppIcons.monitor,
            label: l10n.settingsThemeSystemAuto,
            selected: _selectedLocale == null,
            onTap: () => _select(null),
          ),
          const SizedBox(height: AppSpacing.xs),
          _ThemeOptionCard(
            iconName: AppIcons.globe,
            label: 'English',
            selected: _selectedLocale?.languageCode == 'en',
            onTap: () => _select(kEnglishLocale),
          ),
          const SizedBox(height: AppSpacing.xs),
          _ThemeOptionCard(
            iconName: AppIcons.globe,
            label: '한국어',
            selected: _selectedLocale?.languageCode == 'ko',
            onTap: () => _select(kKoreanLocale),
          ),
          const SizedBox(height: AppSpacing.md),
          if (_submitError != null) ...[
            Text(
              _submitError!,
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(
                color: context.colors.text.destructive,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
          AccountModalActions(
            onCancel: _isSubmitting ? null : widget.onCancel,
            cancelLabel: l10n.commonCancel,
            actionLabel: _isSubmitting ? l10n.commonUpdating : l10n.commonUpdate,
            onAction: _canUpdate ? _submit : null,
          ),
        ],
      ),
    );
  }
}

class _WindowsUpdateModal extends ConsumerWidget {
  const _WindowsUpdateModal({required this.onCancel});

  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(windowsUpdateProvider);
    final primary = _primaryAction(l10n, ref, state);

    return AccountModalCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.settingsUpdates,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodyLarge.copyWith(
              color: context.colors.text.accent,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _UpdateInfoRow(
            label: l10n.settingsUpdateCurrent,
            value: state.currentVersion,
          ),
          if (state.availableVersion.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xxs),
            _UpdateInfoRow(
              label: l10n.settingsUpdateAvailable,
              value: state.availableVersion,
            ),
          ],
          const SizedBox(height: AppSpacing.s),
          Text(
            _statusText(l10n, state),
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodyMedium.copyWith(
              color: state.status == WindowsUpdateStatus.failed
                  ? context.colors.text.destructive
                  : context.colors.text.secondary,
            ),
          ),
          if (state.status == WindowsUpdateStatus.downloading) ...[
            const SizedBox(height: AppSpacing.s),
            _UpdateProgressBar(progress: state.downloadProgress),
          ],
          const SizedBox(height: AppSpacing.md),
          AccountModalActions(
            onCancel: state.isBusy ? null : onCancel,
            cancelLabel: l10n.commonCancel,
            actionLabel: primary.label,
            onAction: primary.onPressed,
          ),
        ],
      ),
    );
  }

  static _UpdatePrimaryAction _primaryAction(
    AppLocalizations l10n,
    WidgetRef ref,
    WindowsUpdateState state,
  ) {
    if (!state.supported) {
      return _UpdatePrimaryAction(label: l10n.settingsUpdateActionCheck);
    }
    return switch (state.status) {
      WindowsUpdateStatus.checking => _UpdatePrimaryAction(
        label: l10n.settingsUpdateActionChecking,
      ),
      WindowsUpdateStatus.downloading => _UpdatePrimaryAction(
        label: l10n.settingsUpdateActionDownloading,
      ),
      WindowsUpdateStatus.applying => _UpdatePrimaryAction(
        label: l10n.settingsUpdateActionRestarting,
      ),
      WindowsUpdateStatus.available => _UpdatePrimaryAction(
        label: l10n.settingsUpdateActionDownload,
        onPressed: () {
          unawaited(ref.read(windowsUpdateProvider.notifier).downloadUpdate());
        },
      ),
      WindowsUpdateStatus.ready => _UpdatePrimaryAction(
        label: l10n.settingsUpdateActionRestartToUpdate,
        onPressed: () {
          unawaited(
            ref.read(windowsUpdateProvider.notifier).applyUpdateAndRestart(),
          );
        },
      ),
      WindowsUpdateStatus.failed => _UpdatePrimaryAction(
        label: l10n.settingsUpdateActionTryAgain,
        onPressed: () {
          unawaited(ref.read(windowsUpdateProvider.notifier).checkForUpdates());
        },
      ),
      _ => _UpdatePrimaryAction(
        label: l10n.settingsUpdateActionCheck,
        onPressed: () {
          unawaited(ref.read(windowsUpdateProvider.notifier).checkForUpdates());
        },
      ),
    };
  }

  static String _statusText(AppLocalizations l10n, WindowsUpdateState state) {
    if (!state.supported) {
      return l10n.settingsUpdateStatusWindowsOnly;
    }
    return switch (state.status) {
      WindowsUpdateStatus.checking => l10n.settingsUpdateStatusChecking,
      WindowsUpdateStatus.noUpdate => l10n.settingsUpdateStatusUpToDate,
      WindowsUpdateStatus.available => l10n.settingsUpdateStatusAvailable(
        state.availableVersion,
      ),
      WindowsUpdateStatus.downloading => l10n.settingsUpdateStatusDownloading(
        state.downloadProgress,
      ),
      WindowsUpdateStatus.ready => l10n.settingsUpdateStatusReady(
        state.availableVersion,
      ),
      WindowsUpdateStatus.applying => l10n.settingsUpdateStatusApplying,
      WindowsUpdateStatus.failed => state.message.isEmpty
          ? l10n.settingsUpdateStatusCheckFailed
          : state.message,
      _ => l10n.settingsUpdateStatusIdle,
    };
  }
}

class _UpdatePrimaryAction {
  const _UpdatePrimaryAction({required this.label, this.onPressed});

  final String label;
  final VoidCallback? onPressed;
}

class _UpdateInfoRow extends StatelessWidget {
  const _UpdateInfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 72,
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.labelMedium.copyWith(
              color: context.colors.text.secondary,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            value.isEmpty ? '-' : value,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: AppTypography.labelLarge.copyWith(
              color: context.colors.text.accent,
            ),
          ),
        ),
      ],
    );
  }
}

class _UpdateProgressBar extends StatelessWidget {
  const _UpdateProgressBar({required this.progress});

  final int progress;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final factor = progress.clamp(0, 100) / 100;

    return Container(
      height: 4,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.background.neutralSubtleOpacity,
        borderRadius: BorderRadius.circular(AppRadii.full),
      ),
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: factor,
        heightFactor: 1,
        child: DecoratedBox(
          decoration: BoxDecoration(color: colors.background.inverse),
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
  });

  final String iconName;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 40,
          padding: const EdgeInsets.only(
            left: AppSpacing.xs,
            right: AppSpacing.s,
          ),
          decoration: BoxDecoration(
            color: colors.background.ground,
            borderRadius: BorderRadius.circular(AppRadii.medium),
            boxShadow: _settingsSurfaceShadow(colors),
          ),
          foregroundDecoration: selected
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadii.medium),
                  border: Border.all(
                    color: colors.border.strong,
                    width: 2,
                    strokeAlign: BorderSide.strokeAlignInside,
                  ),
                )
              : null,
          child: Row(
            children: [
              SizedBox(
                width: 32,
                height: 32,
                child: Center(
                  child: AppIcon(
                    iconName,
                    size: 18,
                    color: selected
                        ? colors.icon.accent
                        : colors.icon.accent.withValues(alpha: 0.5),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.labelMedium.copyWith(
                    color: colors.text.accent,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
              _ThemeOptionIndicator(selected: selected),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThemeOptionIndicator extends StatelessWidget {
  const _ThemeOptionIndicator({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: selected
            ? colors.background.inverse
            : colors.background.neutralSubtleOpacity,
        shape: BoxShape.circle,
      ),
      child: selected
          ? Center(
              child: AppIcon(
                AppIcons.check,
                size: 12,
                color: colors.background.ground,
              ),
            )
          : null,
    );
  }
}

class _SettingsBlock extends StatelessWidget {
  const _SettingsBlock({required this.title, required this.rows});

  final String title;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: colors.background.ground,
        borderRadius: BorderRadius.circular(AppRadii.large),
        boxShadow: _settingsSurfaceShadow(colors),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.xxs),
            child: Text(
              title,
              style: AppTypography.labelMedium.copyWith(
                fontWeight: FontWeight.w400,
                color: colors.text.secondary,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.xs),
            rows[i],
          ],
        ],
      ),
    );
  }
}

class _SettingsRow extends StatefulWidget {
  const _SettingsRow({
    required this.iconName,
    required this.label,
    this.value,
    this.valueLeading,
    this.destructive = false,
    this.onTap,
  });

  final String iconName;
  final String label;
  final String? value;
  final Widget? valueLeading;
  final bool destructive;
  final VoidCallback? onTap;

  @override
  State<_SettingsRow> createState() => _SettingsRowState();
}

class _SettingsRowState extends State<_SettingsRow> {
  bool _hovered = false;
  bool _focused = false;

  @override
  void didUpdateWidget(covariant _SettingsRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.iconName != widget.iconName ||
        oldWidget.label != widget.label ||
        oldWidget.value != widget.value ||
        (oldWidget.onTap == null) != (widget.onTap == null)) {
      _hovered = false;
      _focused = false;
    }
  }

  void _handleHoverChanged(bool value) {
    if (_hovered == value) return;
    setState(() => _hovered = value);
  }

  void _handleFocusChanged(bool value) {
    if (_focused == value) return;
    setState(() => _focused = value);
  }

  void _activate() {
    _handleHoverChanged(false);
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isInteractive = widget.onTap != null;
    final contentColor = widget.destructive
        ? colors.text.destructive
        : colors.text.accent;
    final iconColor = widget.destructive
        ? colors.text.destructive
        : colors.icon.muted;
    final chevronColor = widget.destructive
        ? colors.text.destructive
        : colors.icon.accent;

    Widget content = Row(
      children: [
        AppIcon(widget.iconName, size: 20, color: iconColor),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            widget.label,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.labelMedium.copyWith(color: contentColor),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        if (widget.valueLeading != null) ...[
          widget.valueLeading!,
          const SizedBox(width: AppSpacing.xxs),
        ],
        if (widget.value != null) ...[
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: Text(
              widget.value!,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: AppTypography.labelMedium.copyWith(color: contentColor),
            ),
          ),
          const SizedBox(width: AppSpacing.xxs),
        ],
        AppIcon(AppIcons.chevronForward, size: 16, color: chevronColor),
      ],
    );
    if (!isInteractive) {
      content = Opacity(opacity: 0.5, child: content);
    }

    final row = Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
          decoration: BoxDecoration(
            color: isInteractive && _hovered
                ? _settingsRowHoverBackgroundColor(context)
                : null,
            borderRadius: BorderRadius.circular(AppRadii.small),
          ),
          child: content,
        ),
        if (isInteractive && _focused)
          Positioned(
            left: -1,
            top: -1,
            right: -1,
            bottom: -1,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: colors.state.focusRing, width: 2),
                  borderRadius: BorderRadius.circular(AppRadii.small),
                ),
              ),
            ),
          ),
      ],
    );

    if (!isInteractive) return row;
    return Semantics(
      button: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => _handleHoverChanged(true),
        onExit: (_) => _handleHoverChanged(false),
        child: FocusableActionDetector(
          mouseCursor: SystemMouseCursors.click,
          onShowFocusHighlight: _handleFocusChanged,
          shortcuts: _settingsRowActivationShortcuts,
          actions: <Type, Action<Intent>>{
            ActivateIntent: CallbackAction<Intent>(
              onInvoke: (_) {
                _activate();
                return null;
              },
            ),
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _activate,
            child: row,
          ),
        ),
      ),
    );
  }
}

Color _settingsRowHoverBackgroundColor(BuildContext context) {
  final colors = context.colors;
  final isDark = AppTheme.of(context) == AppThemeData.dark;
  return isDark ? colors.background.raised : colors.background.base;
}

List<BoxShadow> _settingsSurfaceShadow(AppColors colors) =>
    appSurfaceShadow(colors);
