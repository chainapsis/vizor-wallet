import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/layout/app_pane_scroll_scaffold.dart';
import '../../../core/profile_pictures.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_pane_modal_overlay.dart';
import '../../../core/widgets/app_profile_picture.dart';
import '../../../providers/account_provider.dart';
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

enum _SettingsModalType { accountName, profilePicture, theme, updates }

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
    final accountState = ref.watch(accountProvider).value;
    final activeAccountName = accountState?.activeAccount?.name ?? 'Wallet 1';
    final activeProfilePictureId =
        accountState?.activeAccount?.profilePictureId ??
        kDefaultProfilePictureId;
    final hasActiveAccount = accountState?.activeAccountUuid != null;
    final activeAccountSupportsSeedPhrase =
        accountState?.activeAccount?.supportsSeedPhraseReveal ?? false;
    final themeMode = ref.watch(themeModeProvider);
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
                  activeProfilePictureId,
                ),
                activeAccountSupportsSeedPhrase:
                    activeAccountSupportsSeedPhrase,
                endpointLabel: endpointLabel,
                themeLabel: _themeLabel(themeMode),
                updateLabel: updateState == null
                    ? null
                    : _updateLabel(updateState),
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
                onTheme: () => _showModal(_SettingsModalType.theme),
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

  static String _themeLabel(ThemeMode mode) {
    return switch (mode) {
      ThemeMode.system => 'System',
      ThemeMode.light => 'Light',
      ThemeMode.dark => 'Dark',
    };
  }

  static String _profilePictureLabel(String profilePictureId) {
    return findProfilePictureOption(profilePictureId)?.label ?? 'Custom';
  }

  static String _updateLabel(WindowsUpdateState state) {
    if (!state.supported) return 'Unavailable';
    return switch (state.status) {
      WindowsUpdateStatus.checking => 'Checking',
      WindowsUpdateStatus.available => 'Available',
      WindowsUpdateStatus.downloading => '${state.downloadProgress}%',
      WindowsUpdateStatus.ready => 'Restart',
      WindowsUpdateStatus.applying => 'Applying',
      WindowsUpdateStatus.failed => 'Failed',
      WindowsUpdateStatus.noUpdate => 'Up to date',
      _ => 'Check',
    };
  }
}

class _SettingsPane extends StatelessWidget {
  const _SettingsPane({
    required this.accountName,
    required this.profilePictureId,
    required this.profilePictureLabel,
    required this.activeAccountSupportsSeedPhrase,
    required this.endpointLabel,
    required this.themeLabel,
    required this.updateLabel,
    required this.onSeedPhrase,
    required this.onChangePassword,
    required this.onEndpoint,
    required this.onAccountName,
    required this.onProfilePicture,
    required this.onAddressBook,
    required this.onTheme,
    required this.onUpdates,
    required this.onAbout,
    required this.onUninstall,
  });

  final String accountName;
  final String profilePictureId;
  final String profilePictureLabel;
  final bool activeAccountSupportsSeedPhrase;
  final String endpointLabel;
  final String themeLabel;
  final String? updateLabel;
  final VoidCallback onSeedPhrase;
  final VoidCallback onChangePassword;
  final VoidCallback onEndpoint;
  final VoidCallback? onAccountName;
  final VoidCallback? onProfilePicture;
  final VoidCallback onAddressBook;
  final VoidCallback onTheme;
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
                'Settings',
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
                activeAccountSupportsSeedPhrase:
                    activeAccountSupportsSeedPhrase,
                endpointLabel: endpointLabel,
                themeLabel: themeLabel,
                updateLabel: updateLabel,
                onSeedPhrase: onSeedPhrase,
                onChangePassword: onChangePassword,
                onEndpoint: onEndpoint,
                onAccountName: onAccountName,
                onProfilePicture: onProfilePicture,
                onAddressBook: onAddressBook,
                onTheme: onTheme,
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
    required this.activeAccountSupportsSeedPhrase,
    required this.endpointLabel,
    required this.themeLabel,
    required this.updateLabel,
    required this.onSeedPhrase,
    required this.onChangePassword,
    required this.onEndpoint,
    required this.onAccountName,
    required this.onProfilePicture,
    required this.onAddressBook,
    required this.onTheme,
    required this.onUpdates,
    required this.onAbout,
    required this.onUninstall,
  });

  final String accountName;
  final String profilePictureId;
  final String profilePictureLabel;
  final bool activeAccountSupportsSeedPhrase;
  final String endpointLabel;
  final String themeLabel;
  final String? updateLabel;
  final VoidCallback onSeedPhrase;
  final VoidCallback onChangePassword;
  final VoidCallback onEndpoint;
  final VoidCallback? onAccountName;
  final VoidCallback? onProfilePicture;
  final VoidCallback onAddressBook;
  final VoidCallback onTheme;
  final VoidCallback? onUpdates;
  final VoidCallback onAbout;
  final VoidCallback? onUninstall;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SettingsBlock(
          title: 'Account',
          rows: [
            _SettingsRow(
              iconName: AppIcons.key,
              label: 'Secret passphrase',
              onTap: activeAccountSupportsSeedPhrase ? onSeedPhrase : null,
            ),
            _SettingsRow(
              iconName: AppIcons.lock,
              label: 'Password',
              onTap: onChangePassword,
            ),
            _SettingsRow(
              iconName: AppIcons.user,
              label: 'Profile picture',
              value: profilePictureLabel,
              valueLeading: AppProfilePicture(
                profilePictureId: profilePictureId,
                size: AppProfilePictureSize.medium,
              ),
              onTap: onProfilePicture,
            ),
            _SettingsRow(
              iconName: AppIcons.scroll,
              label: 'Account name',
              value: accountName,
              onTap: onAccountName,
            ),
            _SettingsRow(
              iconName: AppIcons.users,
              label: 'Contacts',
              onTap: onAddressBook,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        _SettingsBlock(
          title: 'System',
          rows: [
            _SettingsRow(
              iconName: AppIcons.endpoint,
              label: 'Endpoint',
              value: endpointLabel,
              onTap: onEndpoint,
            ),
            _SettingsRow(
              iconName: AppIcons.theme,
              label: 'Theme',
              value: themeLabel,
              onTap: onTheme,
            ),
            if (updateLabel != null && onUpdates != null)
              _SettingsRow(
                iconName: AppIcons.sync,
                label: 'Updates',
                value: updateLabel,
                onTap: onUpdates,
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        _SettingsBlock(
          title: 'Misc',
          rows: [
            _SettingsRow(
              iconName: AppIcons.vizor,
              label: 'About Vizor',
              onTap: onAbout,
            ),
          ],
        ),
        if (onUninstall != null) ...[
          const SizedBox(height: AppSpacing.md),
          _SettingsBlock(
            title: 'Danger zone',
            rows: [
              _SettingsRow(
                iconName: AppIcons.trash,
                label: 'Uninstall Vizor',
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
        _submitError = "Couldn't update theme.";
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
            'Theme',
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodyLarge.copyWith(
              color: context.colors.text.accent,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _ThemeOptionCard(
            iconName: AppIcons.monitor,
            label: 'System (Auto)',
            selected: _selectedMode == ThemeMode.system,
            onTap: () => _select(ThemeMode.system),
          ),
          const SizedBox(height: AppSpacing.xs),
          _ThemeOptionCard(
            iconName: AppIcons.day,
            label: 'Light',
            selected: _selectedMode == ThemeMode.light,
            onTap: () => _select(ThemeMode.light),
          ),
          const SizedBox(height: AppSpacing.xs),
          _ThemeOptionCard(
            iconName: AppIcons.night,
            label: 'Dark',
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
            actionLabel: _isSubmitting ? 'Updating...' : 'Update',
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
    final primary = _primaryAction(ref, state);

    return AccountModalCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Updates',
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodyLarge.copyWith(
              color: context.colors.text.accent,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _UpdateInfoRow(label: 'Current', value: state.currentVersion),
          if (state.availableVersion.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xxs),
            _UpdateInfoRow(label: 'Available', value: state.availableVersion),
          ],
          const SizedBox(height: AppSpacing.s),
          Text(
            _statusText(state),
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
            actionLabel: primary.label,
            onAction: primary.onPressed,
          ),
        ],
      ),
    );
  }

  static _UpdatePrimaryAction _primaryAction(
    WidgetRef ref,
    WindowsUpdateState state,
  ) {
    if (!state.supported) {
      return const _UpdatePrimaryAction(label: 'Check for updates');
    }
    return switch (state.status) {
      WindowsUpdateStatus.checking => const _UpdatePrimaryAction(
        label: 'Checking...',
      ),
      WindowsUpdateStatus.downloading => const _UpdatePrimaryAction(
        label: 'Downloading...',
      ),
      WindowsUpdateStatus.applying => const _UpdatePrimaryAction(
        label: 'Restarting...',
      ),
      WindowsUpdateStatus.available => _UpdatePrimaryAction(
        label: 'Download update',
        onPressed: () {
          unawaited(ref.read(windowsUpdateProvider.notifier).downloadUpdate());
        },
      ),
      WindowsUpdateStatus.ready => _UpdatePrimaryAction(
        label: 'Restart to update',
        onPressed: () {
          unawaited(
            ref.read(windowsUpdateProvider.notifier).applyUpdateAndRestart(),
          );
        },
      ),
      WindowsUpdateStatus.failed => _UpdatePrimaryAction(
        label: 'Try again',
        onPressed: () {
          unawaited(ref.read(windowsUpdateProvider.notifier).checkForUpdates());
        },
      ),
      _ => _UpdatePrimaryAction(
        label: 'Check for updates',
        onPressed: () {
          unawaited(ref.read(windowsUpdateProvider.notifier).checkForUpdates());
        },
      ),
    };
  }

  static String _statusText(WindowsUpdateState state) {
    if (!state.supported) {
      return 'Updates are available in the installed Windows app.';
    }
    return switch (state.status) {
      WindowsUpdateStatus.checking => 'Checking for updates.',
      WindowsUpdateStatus.noUpdate => 'Vizor is up to date.',
      WindowsUpdateStatus.available =>
        'Version ${state.availableVersion} is available.',
      WindowsUpdateStatus.downloading =>
        'Downloading ${state.downloadProgress}%.',
      WindowsUpdateStatus.ready =>
        'Version ${state.availableVersion} is ready.',
      WindowsUpdateStatus.applying => 'Restarting Vizor.',
      WindowsUpdateStatus.failed =>
        state.message.isEmpty ? "Couldn't check for updates." : state.message,
      _ => 'Ready to check for updates.',
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
