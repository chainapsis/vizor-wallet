import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/zcash_explorer.dart';
import '../../../core/config/rpc_endpoint_config.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/layout/app_pane_scroll_scaffold.dart';
import '../../../core/navigation/route_stack.dart';
import '../../../core/profile_pictures.dart';
import '../../../core/storage/linux_keyring_coordinator.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_pane_modal_overlay.dart';
import '../../../core/widgets/app_profile_picture.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/untranslated_details.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/enhance_pir_provider.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../core/l10n/app_language.dart';
import '../../../providers/app_language_provider.dart';
import '../../../providers/theme_mode_provider.dart';
import '../../../providers/zcash_explorer_provider.dart';
import '../../../providers/windows_update_provider.dart';
import '../../accounts/widgets/account_modal_card.dart';
import '../../accounts/widgets/account_edit_modal.dart';
import '../../accounts/widgets/account_profile_picture_modal.dart';
import '../../payment_links/providers/payment_link_cards_provider.dart';
import '../../donation/donation_config.dart';
import '../settings_platform.dart';
import '../widgets/near_swap_privacy_info.dart';
import '../widgets/network_privacy_control.dart';
import '../widgets/enhance_pir_privacy_control.dart';
import '../widgets/private_queries_turn_off.dart';
import '../widgets/language_picker.dart';
import '../widgets/settings_new_badge.dart';
import '../widgets/settings_sub_option.dart';
import '../widgets/settings_option_card.dart';
import '../widgets/windows_update_download_flow.dart';

const _settingsRowActivationShortcuts = <ShortcutActivator, Intent>{
  SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
  SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
};

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({this.scrollController, super.key});

  final ScrollController? scrollController;

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

enum _SettingsModalType {
  accountName,
  profilePicture,
  theme,
  language,
  updates,
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  _SettingsModalType? _activeModal;

  // Edit-account drafts for the picker round-trip (same model as the
  // accounts screen): the in-progress name and picked picture survive
  // while the picker temporarily replaces the edit modal.
  String? _editDraftName;
  String? _editDraftProfilePictureId;
  bool _pfpPickerFromEdit = false;
  bool _isOpeningGiftCards = false;

  // The pane modals are state, not routes, so a slow Gift Cards load has no
  // route change to notice; every modal open bumps this instead.
  int _modalGeneration = 0;

  void _showModal(_SettingsModalType modal) {
    setState(() {
      _modalGeneration++;
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
      _modalGeneration++;
      _pfpPickerFromEdit = true;
      _activeModal = _SettingsModalType.profilePicture;
    });
  }

  void _returnToEditAccountModal({String? pickedProfilePictureId}) {
    setState(() {
      _modalGeneration++;
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
    try {
      if (name.trim() != account.name.trim()) {
        await notifier.renameAccount(account.uuid, name);
      }
      final draftPicture = _editDraftProfilePictureId;
      if (draftPicture != null && draftPicture != account.profilePictureId) {
        await notifier.updateProfilePicture(account.uuid, draftPicture);
      }
    } on WalletMutationBusyException {
      // Another wallet mutation, such as the private queries toggle, holds
      // the wallet. The modal stays open with its drafts for a retry.
      if (mounted) showAppToast(context, context.l10n.walletMutationBusy);
      return;
    }
    if (!mounted) return;
    _closeModal();
  }

  Future<void> _updateTheme(ThemeMode mode) async {
    await ref.read(themeModeProvider.notifier).set(mode);
    if (!mounted) return;
    _closeModal();
  }

  Future<void> _updateLanguage(AppLanguage language) async {
    await ref.read(appLanguageProvider.notifier).set(language);
    if (!mounted) return;
    _closeModal();
  }

  Future<void> _updateProfilePicture(String profilePictureId) async {
    final accountUuid = ref.read(accountProvider).value?.activeAccountUuid;
    if (accountUuid == null) return;
    try {
      await ref
          .read(accountProvider.notifier)
          .updateProfilePicture(accountUuid, profilePictureId);
    } on WalletMutationBusyException {
      if (mounted) showAppToast(context, context.l10n.walletMutationBusy);
      return;
    }
    if (!mounted) return;
    _closeModal();
  }

  Future<void> _openGiftCards() async {
    if (_isOpeningGiftCards) return;
    final router = GoRouter.of(context);
    final entryPath = router.routerDelegate.currentConfiguration.uri.path;
    final entryModalGeneration = _modalGeneration;
    setState(() => _isOpeningGiftCards = true);
    PaymentLinkCardsSnapshot? cards;
    try {
      cards = await ref.read(paymentLinkCardsLoaderProvider)();
    } catch (_) {
      // Open anyway, like mobile: the screen loads and reports each store on
      // its own, so one unreadable store must not lock Gift Cards away.
      cards = null;
    }
    if (!mounted) return;
    setState(() => _isOpeningGiftCards = false);
    // Drop the open once the user has moved on: another route, a dialog, or
    // a pane modal would all be replaced by this late navigation.
    if (router.routerDelegate.currentConfiguration.uri.path != entryPath ||
        _modalGeneration != entryModalGeneration ||
        !isRouteTopmost(context)) {
      return;
    }
    router.go('/payment-links', extra: cards);
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
    final accountState = ref.watch(accountProvider).value;
    final activeAccountName =
        accountState?.activeAccount?.name ??
        'Wallet 1'; // l10n-ignore: default account name is data
    final activeProfilePictureId =
        accountState?.activeAccount?.profilePictureId ??
        kDefaultProfilePictureId;
    final hasActiveAccount = accountState?.activeAccountUuid != null;
    final activeAccountIsHardware =
        accountState?.activeAccount?.isHardware ?? false;
    final themeMode = ref.watch(themeModeProvider);
    final appLanguage = ref.watch(appLanguageProvider);
    final languages = ref.watch(availableAppLanguagesProvider);
    // With English alone there is nothing to choose.
    final showLanguage = languages.length > 1;
    final endpoint = ref.watch(rpcEndpointProvider);
    final endpointLabel = isAutomaticRpcEndpointConfig(endpoint)
        ? context.l10n.endpointAutomatic
        : endpoint.hostPort;
    final explorerLabel = explorerSettingsLabel(
      context.l10n,
      ref.watch(zcashExplorerProvider),
      networkName: endpoint.networkName,
    );
    final updateState = defaultTargetPlatform == TargetPlatform.windows
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
              controller: widget.scrollController,
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
                  context.l10n,
                  activeProfilePictureId,
                ),
                activeAccountIsHardware: activeAccountIsHardware,
                endpointLabel: endpointLabel,
                explorerLabel: explorerLabel,
                themeLabel: _themeLabel(context.l10n, themeMode),
                languageLabel: showLanguage ? appLanguage.nativeName : null,
                updateLabel: updateState == null
                    ? null
                    : _updateLabel(context.l10n, updateState),
                onSeedPhrase: () => context.push('/settings/secret-passphrase'),
                onViewingKey: () => context.push('/settings/viewing-key'),
                onChangePassword: () =>
                    context.push('/settings/change-password'),
                onEndpoint: () => context.push('/settings/endpoint'),
                onExplorer: () => context.push('/settings/explorer'),
                onAccountName: hasActiveAccount
                    ? () => _showModal(_SettingsModalType.accountName)
                    : null,
                onProfilePicture: hasActiveAccount
                    ? () => _showModal(_SettingsModalType.profilePicture)
                    : null,
                onAddressBook: () => context.push('/address-book'),
                onGiftCards: _isOpeningGiftCards
                    ? null
                    : () => unawaited(_openGiftCards()),
                onLinkMobile: () => context.push('/settings/link-mobile'),
                onTheme: () => _showModal(_SettingsModalType.theme),
                onLanguage: showLanguage
                    ? () => _showModal(_SettingsModalType.language)
                    : null,
                onUpdates: updateState == null
                    ? null
                    : () => _showModal(_SettingsModalType.updates),
                onAbout: () => context.push('/about'),
                onDonation:
                    donationFeatureEnabledForNetwork(endpoint.networkName)
                    ? () => context.push('/donation')
                    : null,
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
                  _SettingsModalType.language => DesktopLanguageModal(
                    current: appLanguage,
                    available: languages,
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

  static String _profilePictureLabel(
    AppLocalizations l10n,
    String profilePictureId,
  ) {
    return findProfilePictureOption(profilePictureId)?.label(l10n) ??
        l10n.settingsProfilePictureCustom;
  }

  static String _updateLabel(AppLocalizations l10n, WindowsUpdateState state) {
    if (!state.supported) return l10n.settingsUpdateUnavailable;
    return switch (state.status) {
      WindowsUpdateStatus.checking => l10n.settingsUpdateChecking,
      WindowsUpdateStatus.available => l10n.settingsUpdateAvailable,
      WindowsUpdateStatus.downloading => '${state.downloadProgress}%',
      WindowsUpdateStatus.ready => l10n.updateRestart,
      WindowsUpdateStatus.applying => l10n.settingsUpdateApplying,
      WindowsUpdateStatus.failed => l10n.commonFailed,
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
    required this.explorerLabel,
    required this.themeLabel,
    required this.languageLabel,
    required this.updateLabel,
    required this.onSeedPhrase,
    required this.onViewingKey,
    required this.onChangePassword,
    required this.onEndpoint,
    required this.onExplorer,
    required this.onAccountName,
    required this.onProfilePicture,
    required this.onAddressBook,
    required this.onGiftCards,
    required this.onLinkMobile,
    required this.onTheme,
    required this.onLanguage,
    required this.onUpdates,
    required this.onAbout,
    required this.onDonation,
    required this.onUninstall,
  });

  final String accountName;
  final String profilePictureId;
  final String profilePictureLabel;
  final bool activeAccountIsHardware;
  final String endpointLabel;
  final String explorerLabel;
  final String themeLabel;

  /// `null` hides the Language row.
  final String? languageLabel;
  final String? updateLabel;
  final VoidCallback onSeedPhrase;
  final VoidCallback onViewingKey;
  final VoidCallback onChangePassword;
  final VoidCallback onEndpoint;
  final VoidCallback onExplorer;
  final VoidCallback? onAccountName;
  final VoidCallback? onProfilePicture;
  final VoidCallback onAddressBook;
  final VoidCallback? onGiftCards;
  final VoidCallback onLinkMobile;
  final VoidCallback onTheme;
  final VoidCallback? onLanguage;
  final VoidCallback? onUpdates;
  final VoidCallback onAbout;
  final VoidCallback? onDonation;
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
                context.l10n.navSettings,
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
                explorerLabel: explorerLabel,
                themeLabel: themeLabel,
                languageLabel: languageLabel,
                updateLabel: updateLabel,
                onSeedPhrase: onSeedPhrase,
                onViewingKey: onViewingKey,
                onChangePassword: onChangePassword,
                onEndpoint: onEndpoint,
                onExplorer: onExplorer,
                onAccountName: onAccountName,
                onProfilePicture: onProfilePicture,
                onAddressBook: onAddressBook,
                onGiftCards: onGiftCards,
                onLinkMobile: onLinkMobile,
                onTheme: onTheme,
                onLanguage: onLanguage,
                onUpdates: onUpdates,
                onAbout: onAbout,
                onDonation: onDonation,
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

class _SettingsList extends ConsumerWidget {
  const _SettingsList({
    required this.accountName,
    required this.profilePictureId,
    required this.profilePictureLabel,
    required this.activeAccountIsHardware,
    required this.endpointLabel,
    required this.explorerLabel,
    required this.themeLabel,
    required this.languageLabel,
    required this.updateLabel,
    required this.onSeedPhrase,
    required this.onViewingKey,
    required this.onChangePassword,
    required this.onEndpoint,
    required this.onExplorer,
    required this.onAccountName,
    required this.onProfilePicture,
    required this.onAddressBook,
    required this.onGiftCards,
    required this.onLinkMobile,
    required this.onTheme,
    required this.onLanguage,
    required this.onUpdates,
    required this.onAbout,
    required this.onDonation,
    required this.onUninstall,
  });

  final String accountName;
  final String profilePictureId;
  final String profilePictureLabel;
  final bool activeAccountIsHardware;
  final String endpointLabel;
  final String explorerLabel;
  final String themeLabel;

  /// `null` hides the Language row.
  final String? languageLabel;
  final String? updateLabel;
  final VoidCallback onSeedPhrase;
  final VoidCallback onViewingKey;
  final VoidCallback onChangePassword;
  final VoidCallback onEndpoint;
  final VoidCallback onExplorer;
  final VoidCallback? onAccountName;
  final VoidCallback? onProfilePicture;
  final VoidCallback onAddressBook;
  final VoidCallback? onGiftCards;
  final VoidCallback onLinkMobile;
  final VoidCallback onTheme;
  final VoidCallback? onLanguage;
  final VoidCallback? onUpdates;
  final VoidCallback onAbout;
  final VoidCallback? onDonation;
  final VoidCallback? onUninstall;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enhancePirEnabled = ref.watch(privateQueriesControlEnabledProvider);
    final enhancePirAvailable =
        ref.watch(enhancePirAvailableProvider) || enhancePirEnabled;
    final nearSwapPrivacy = ref.watch(nearSwapPrivacySettingProvider);
    final recoveryTransition = ref.watch(enhancePirTransitionProvider);
    final changingRecovery =
        recoveryTransition == EnhancePirTransition.changing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SettingsBlock(
          title: context.l10n.settingsSectionPersonal,
          rows: [
            _SettingsRow(
              key: const ValueKey('settings_gift_cards_row'),
              iconName: AppIcons.giftCardOutline,
              label: context.l10n.settingsRowMyGiftCards,
              labelBadge: const SettingsNewBadge(),
              onTap: onGiftCards,
            ),
            _SettingsRow(
              iconName: AppIcons.users,
              label: context.l10n.settingsRowAddressBook,
              onTap: onAddressBook,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        _SettingsBlock(
          title: context.l10n.settingsSectionAccount,
          rows: [
            _SettingsRow(
              iconName: AppIcons.key,
              label: context.l10n.settingsRowSecretPassphrase,
              onTap: activeAccountIsHardware ? null : onSeedPhrase,
            ),
            _SettingsRow(
              iconName: AppIcons.eye,
              label: context.l10n.settingsViewingKeyTitle,
              onTap: onViewingKey,
            ),
            _SettingsRow(
              iconName: AppIcons.lock,
              label: context.l10n.settingsRowChangePassword,
              onTap: onChangePassword,
            ),
            _SettingsRow(
              iconName: AppIcons.user,
              label: context.l10n.settingsRowProfilePicture,
              value: profilePictureLabel,
              valueLeading: AppProfilePicture(
                profilePictureId: profilePictureId,
                size: AppProfilePictureSize.medium,
              ),
              onTap: onProfilePicture,
            ),
            _SettingsRow(
              iconName: AppIcons.scroll,
              label: context.l10n.accountNameLabel,
              value: accountName,
              onTap: onAccountName,
            ),
            _SettingsRow(
              iconName: AppIcons.link,
              label: context.l10n.settingsRowLinkMobile,
              onTap: onLinkMobile,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        _SettingsBlock(
          title: context.l10n.settingsSectionSystem,
          rows: [
            _SettingsRow(
              iconName: AppIcons.endpoint,
              label: context.l10n.settingsEndpointTitle,
              value: endpointLabel,
              onTap: onEndpoint,
            ),
            _SettingsRow(
              iconName: AppIcons.globe,
              label: context.l10n.settingsExplorerTitle,
              value: explorerLabel,
              onTap: onExplorer,
            ),
            _SettingsRow(
              iconName: AppIcons.theme,
              label: context.l10n.settingsThemeTitle,
              value: themeLabel,
              onTap: onTheme,
            ),
            if (languageLabel case final languageLabel?)
              _SettingsRow(
                key: const ValueKey('settings_language_row'),
                iconName: AppIcons.language,
                label: context.l10n.settingsLanguageLabel,
                value: languageLabel,
                onTap: onLanguage,
              ),
            if (updateLabel != null && onUpdates != null)
              _SettingsRow(
                iconName: AppIcons.sync,
                label: context.l10n.settingsRowUpdates,
                value: updateLabel,
                onTap: onUpdates,
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        _SettingsBlock(
          title: context.l10n.settingsPrivacyTitle,
          rows: [
            const NetworkPrivacyControl(
              key: ValueKey('settings_tor_control'),
              showSurface: false,
            ),
            if (enhancePirAvailable) ...[
              const SizedBox(height: AppSpacing.sm),
              EnhancePirPrivacyControl(
                enabled: enhancePirEnabled,
                transition: recoveryTransition,
                onToggle: changingRecovery
                    ? null
                    : () => unawaited(togglePrivateQueries(context, ref)),
              ),
            ],
            if (nearSwapPrivacy != null) ...[
              const SizedBox(height: AppSpacing.sm),
              // An option of Private queries: its icon sits under the label
              // above, and the hook starts under that row's icon.
              SettingsSubOption(
                key: const ValueKey('settings_near_swap_privacy_sub_option'),
                indent: AppSpacing.xs + 20,
                lineX: AppSpacing.xxs + 10,
                rowCenter: 22,
                child: EnhancePirPrivacyControl(
                  label: context.l10n.settingsNearSwapPrivacyLabel,
                  keyPrefix: 'settings_near_swap_privacy',
                  serverSettings: false,
                  iconName: AppIcons.linkOff,
                  description: nearSwapPrivacy.description.text(context.l10n),
                  unavailableLabel: nearSwapPrivacy.available
                      ? null
                      : context.l10n.settingsNearSwapPrivacyUnavailable,
                  footer: [
                    if (nearSwapPrivacy.checkingPastSwaps)
                      const Padding(
                        padding: EdgeInsetsDirectional.only(
                          start: AppSpacing.xxs,
                        ),
                        child: NearSwapPrivacyCheckingPastSwaps(),
                      ),
                    const NearSwapPrivacyLearnMore(),
                  ],
                  enabled: nearSwapPrivacy.enabled,
                  transition: nearSwapPrivacy.transition,
                  onToggle: nearSwapPrivacy.available
                      ? () => unawaited(
                          ref.read(nearSwapPrivacyProvider.notifier).toggle(),
                        )
                      : null,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        _SettingsBlock(
          title: context.l10n.settingsSectionMisc,
          rows: [
            _SettingsRow(
              iconName: AppIcons.vizor,
              iconGlyphSize: 16.5,
              label: context.l10n.settingsRowAboutVizor,
              onTap: onAbout,
            ),
            if (onDonation != null)
              _SettingsRow(
                iconName: AppIcons.donation,
                iconGlyphSize: 16.5,
                label: context.l10n.commonSupportVizor,
                onTap: onDonation!,
              ),
          ],
        ),
        if (onUninstall != null) ...[
          const SizedBox(height: AppSpacing.md),
          _SettingsBlock(
            title: context.l10n.settingsSectionDangerZone,
            rows: [
              _SettingsRow(
                iconName: AppIcons.trash,
                label: context.l10n.settingsUninstallTitle,
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
        _submitError = context.l10n.settingsThemeUpdateFailed;
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
    return AccountModalCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.l10n.settingsThemeTitle,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodyLarge.copyWith(
              color: context.colors.text.accent,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          SettingsOptionCard(
            iconName: AppIcons.monitor,
            label: context.l10n.settingsThemeSystemAuto,
            selected: _selectedMode == ThemeMode.system,
            onTap: () => _select(ThemeMode.system),
          ),
          const SizedBox(height: AppSpacing.xs),
          SettingsOptionCard(
            iconName: AppIcons.day,
            label: context.l10n.settingsThemeLight,
            selected: _selectedMode == ThemeMode.light,
            onTap: () => _select(ThemeMode.light),
          ),
          const SizedBox(height: AppSpacing.xs),
          SettingsOptionCard(
            iconName: AppIcons.night,
            label: context.l10n.settingsThemeDark,
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
            actionLabel: _isSubmitting
                ? context.l10n.commonUpdating
                : context.l10n.commonUpdate,
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
    final state = ref.watch(windowsUpdateProvider);
    final primary = _primaryAction(context, ref, state);

    return AccountModalCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.l10n.settingsRowUpdates,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodyLarge.copyWith(
              color: context.colors.text.accent,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _UpdateInfoRow(
            label: context.l10n.settingsUpdateCurrentLabel,
            value: state.currentVersion,
          ),
          if (state.availableVersion.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xxs),
            _UpdateInfoRow(
              label: context.l10n.settingsUpdateAvailable,
              value: state.availableVersion,
            ),
          ],
          const SizedBox(height: AppSpacing.s),
          Text(
            _statusText(context.l10n, state),
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodyMedium.copyWith(
              color: state.status == WindowsUpdateStatus.failed
                  ? context.colors.text.destructive
                  : context.colors.text.secondary,
            ),
          ),
          if (state.status == WindowsUpdateStatus.failed)
            ...untranslatedDetailsButton(state.failureDetails),
          if (state.status == WindowsUpdateStatus.downloading) ...[
            const SizedBox(height: AppSpacing.s),
            _UpdateProgressBar(progress: state.downloadProgress),
          ],
          const SizedBox(height: AppSpacing.md),
          AccountModalActions(
            onCancel: state.isBusy ? null : onCancel,
            actionLabel: primary.label,
            onAction: primary.onPressed,
          ),
        ],
      ),
    );
  }

  static _UpdatePrimaryAction _primaryAction(
    BuildContext context,
    WidgetRef ref,
    WindowsUpdateState state,
  ) {
    if (!state.supported) {
      return _UpdatePrimaryAction(
        label: context.l10n.settingsUpdateCheckForUpdates,
      );
    }
    return switch (state.status) {
      WindowsUpdateStatus.checking => _UpdatePrimaryAction(
        label: context.l10n.commonCheckingEllipsis,
      ),
      WindowsUpdateStatus.downloading => _UpdatePrimaryAction(
        label: context.l10n.settingsUpdateDownloadingButton,
      ),
      WindowsUpdateStatus.applying => _UpdatePrimaryAction(
        label: context.l10n.settingsUpdateRestartingButton,
      ),
      WindowsUpdateStatus.available => _UpdatePrimaryAction(
        label: context.l10n.settingsUpdateDownloadButton,
        onPressed: () {
          unawaited(startWindowsUpdateDownload(context: context, ref: ref));
        },
      ),
      WindowsUpdateStatus.ready => _UpdatePrimaryAction(
        label: context.l10n.settingsUpdateRestartButton,
        onPressed: () {
          unawaited(
            ref.read(windowsUpdateProvider.notifier).applyUpdateAndRestart(),
          );
        },
      ),
      WindowsUpdateStatus.failed => _UpdatePrimaryAction(
        label: context.l10n.commonTryAgain,
        onPressed: () {
          unawaited(ref.read(windowsUpdateProvider.notifier).checkForUpdates());
        },
      ),
      _ => _UpdatePrimaryAction(
        label: context.l10n.settingsUpdateCheckForUpdates,
        onPressed: () {
          unawaited(ref.read(windowsUpdateProvider.notifier).checkForUpdates());
        },
      ),
    };
  }

  static String _statusText(AppLocalizations l10n, WindowsUpdateState state) {
    if (!state.supported) {
      return l10n.settingsUpdateStatusUnsupported;
    }
    return switch (state.status) {
      WindowsUpdateStatus.checking => l10n.settingsUpdateStatusChecking,
      WindowsUpdateStatus.noUpdate => l10n.settingsUpdateStatusUpToDate,
      WindowsUpdateStatus.available => l10n.settingsUpdateStatusAvailable(
        state.availableVersion,
      ),
      WindowsUpdateStatus.downloading => l10n.settingsUpdateStatusDownloading(
        state.downloadProgress.toString(),
      ),
      WindowsUpdateStatus.ready => l10n.settingsUpdateStatusReady(
        state.availableVersion,
      ),
      WindowsUpdateStatus.applying => l10n.settingsUpdateStatusRestarting,
      WindowsUpdateStatus.failed => state.failureMessage(l10n),
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
              style: AppTypography.labelLarge.copyWith(
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
    super.key,
    required this.iconName,
    required this.label,
    this.iconGlyphSize = 20,
    this.value,
    this.valueLeading,
    this.labelBadge,
    this.destructive = false,
    this.onTap,
  });

  final String iconName;
  final String label;
  final double iconGlyphSize;
  final String? value;
  final Widget? valueLeading;
  final Widget? labelBadge;
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
        SizedBox.square(
          dimension: 20,
          child: Center(
            child: AppIcon(
              widget.iconName,
              size: widget.iconGlyphSize,
              color: iconColor,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Row(
            children: [
              Flexible(
                child: Text(
                  widget.label,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.labelMedium.copyWith(
                    color: contentColor,
                  ),
                ),
              ),
              if (widget.labelBadge != null) ...[
                const SizedBox(width: AppSpacing.xxs),
                widget.labelBadge!,
              ],
            ],
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
