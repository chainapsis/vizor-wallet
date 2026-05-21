import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/profile_pictures.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_back_link.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_decorative_divider.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_pane_modal_overlay.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../providers/theme_mode_provider.dart';
import '../../../providers/windows_update_provider.dart';
import '../../accounts/widgets/account_name_modal.dart';
import '../../accounts/widgets/account_profile_picture_modal.dart';

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

  void _showModal(_SettingsModalType modal) {
    setState(() {
      _activeModal = modal;
    });
  }

  void _closeModal() {
    setState(() {
      _activeModal = null;
    });
  }

  Future<void> _updateAccountName(String name) async {
    final accountUuid = ref.read(accountProvider).value?.activeAccountUuid;
    if (accountUuid == null) return;
    await ref.read(accountProvider.notifier).renameAccount(accountUuid, name);
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
    final accountState = ref.watch(accountProvider).value;
    final activeAccountName = accountState?.activeAccount?.name ?? 'Wallet 1';
    final activeProfilePictureId =
        accountState?.activeAccount?.profilePictureId ??
        kDefaultProfilePictureId;
    final hasActiveAccount = accountState?.activeAccountUuid != null;
    final activeAccountIsHardware =
        accountState?.activeAccount?.isHardware ?? false;
    final themeMode = ref.watch(themeModeProvider);
    final endpointLabel = ref.watch(rpcEndpointProvider).hostPort;
    final updateState = Platform.isWindows
        ? ref.watch(windowsUpdateProvider)
        : null;

    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        padding: EdgeInsets.zero,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: _SettingsPane(
                accountName: activeAccountName,
                profilePictureLabel: _profilePictureLabel(
                  activeProfilePictureId,
                ),
                activeAccountIsHardware: activeAccountIsHardware,
                endpointLabel: endpointLabel,
                themeLabel: _themeLabel(themeMode),
                updateLabel: updateState == null
                    ? null
                    : _updateLabel(updateState),
                onSeedPhrase: () => context.push('/settings/secret-passphrase'),
                onChangePassword: () =>
                    context.push('/settings/change-password'),
                onEndpoint: () => context.push('/settings/endpoint'),
                onVoting: activeAccountIsHardware
                    ? null
                    : () => context.push('/voting'),
                onAccountName: hasActiveAccount
                    ? () => _showModal(_SettingsModalType.accountName)
                    : null,
                onProfilePicture: hasActiveAccount
                    ? () => _showModal(_SettingsModalType.profilePicture)
                    : null,
                onTheme: () => _showModal(_SettingsModalType.theme),
                onUpdates: updateState == null
                    ? null
                    : () => _showModal(_SettingsModalType.updates),
              ),
            ),
            if (_activeModal != null)
              AppPaneModalOverlay(
                onDismiss: _closeModal,
                child: switch (_activeModal!) {
                  _SettingsModalType.accountName => AccountNameModal(
                    accountName: activeAccountName,
                    profilePictureId: activeProfilePictureId,
                    onCancel: _closeModal,
                    onUpdate: _updateAccountName,
                  ),
                  _SettingsModalType.profilePicture =>
                    AccountProfilePictureModal(
                      currentProfilePictureId: activeProfilePictureId,
                      onCancel: _closeModal,
                      onUpdate: _updateProfilePicture,
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
    required this.profilePictureLabel,
    required this.activeAccountIsHardware,
    required this.endpointLabel,
    required this.themeLabel,
    required this.updateLabel,
    required this.onSeedPhrase,
    required this.onChangePassword,
    required this.onEndpoint,
    required this.onVoting,
    required this.onAccountName,
    required this.onProfilePicture,
    required this.onTheme,
    required this.onUpdates,
  });

  final String accountName;
  final String profilePictureLabel;
  final bool activeAccountIsHardware;
  final String endpointLabel;
  final String themeLabel;
  final String? updateLabel;
  final VoidCallback onSeedPhrase;
  final VoidCallback onChangePassword;
  final VoidCallback onEndpoint;
  final VoidCallback? onVoting;
  final VoidCallback? onAccountName;
  final VoidCallback? onProfilePicture;
  final VoidCallback onTheme;
  final VoidCallback? onUpdates;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return SizedBox.expand(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(alignment: Alignment.centerLeft, child: AppRouteBackLink()),
          const SizedBox(height: AppSpacing.s),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.s),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 752),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Settings',
                                textAlign: TextAlign.center,
                                style: AppTypography.displaySmall.copyWith(
                                  color: colors.text.accent,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              const AppDecorativeDivider(width: 256),
                              const SizedBox(height: AppSpacing.sm),
                              _SettingsList(
                                accountName: accountName,
                                profilePictureLabel: profilePictureLabel,
                                activeAccountIsHardware:
                                    activeAccountIsHardware,
                                endpointLabel: endpointLabel,
                                themeLabel: themeLabel,
                                updateLabel: updateLabel,
                                onSeedPhrase: onSeedPhrase,
                                onChangePassword: onChangePassword,
                                onEndpoint: onEndpoint,
                                onVoting: onVoting,
                                onAccountName: onAccountName,
                                onProfilePicture: onProfilePicture,
                                onTheme: onTheme,
                                onUpdates: onUpdates,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsList extends StatelessWidget {
  const _SettingsList({
    required this.accountName,
    required this.profilePictureLabel,
    required this.activeAccountIsHardware,
    required this.endpointLabel,
    required this.themeLabel,
    required this.updateLabel,
    required this.onSeedPhrase,
    required this.onChangePassword,
    required this.onEndpoint,
    required this.onVoting,
    required this.onAccountName,
    required this.onProfilePicture,
    required this.onTheme,
    required this.onUpdates,
  });

  final String accountName;
  final String profilePictureLabel;
  final bool activeAccountIsHardware;
  final String endpointLabel;
  final String themeLabel;
  final String? updateLabel;
  final VoidCallback onSeedPhrase;
  final VoidCallback onChangePassword;
  final VoidCallback onEndpoint;
  final VoidCallback? onVoting;
  final VoidCallback? onAccountName;
  final VoidCallback? onProfilePicture;
  final VoidCallback onTheme;
  final VoidCallback? onUpdates;

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
              label: 'Secret Passphrase',
              value: activeAccountIsHardware ? 'Unavailable' : 'View',
              onTap: activeAccountIsHardware ? null : onSeedPhrase,
            ),
            const _SettingsRowDivider(),
            _SettingsRow(
              iconName: AppIcons.lock,
              label: 'Password',
              value: 'Change',
              onTap: onChangePassword,
            ),
            const _SettingsRowDivider(),
            _SettingsRow(
              iconName: AppIcons.users,
              label: 'Profile Picture',
              value: profilePictureLabel,
              onTap: onProfilePicture,
            ),
            const _SettingsRowDivider(),
            _SettingsRow(
              iconName: AppIcons.scroll,
              label: 'Account Name',
              value: accountName,
              onTap: onAccountName,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s),
        _SettingsBlock(
          title: 'Extras',
          rows: [
            _SettingsRow(
              iconName: AppIcons.scroll,
              label: 'Coinholder Polling',
              value: activeAccountIsHardware
                  ? 'Hardware accounts coming soon'
                  : 'Open',
              onTap: onVoting,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s),
        _SettingsBlock(
          title: 'System',
          rows: [
            _SettingsRow(
              iconName: AppIcons.endpoint,
              label: 'Endpoint',
              value: endpointLabel,
              onTap: onEndpoint,
            ),
            const _SettingsRowDivider(),
            _SettingsRow(
              iconName: AppIcons.theme,
              label: 'Theme',
              value: themeLabel,
              onTap: onTheme,
            ),
            if (updateLabel != null && onUpdates != null) ...[
              const _SettingsRowDivider(),
              _SettingsRow(
                iconName: AppIcons.sync,
                label: 'Updates',
                value: updateLabel!,
                onTap: onUpdates,
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _SettingsModalCard extends StatelessWidget {
  const _SettingsModalCard({required this.header, required this.child});

  final Widget header;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 312,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: context.colors.background.ground,
        borderRadius: BorderRadius.circular(AppRadii.large),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          header,
          const SizedBox(height: AppSpacing.md),
          child,
        ],
      ),
    );
  }
}

class _ModalHeader extends StatelessWidget {
  const _ModalHeader({required this.leading, required this.title});

  final Widget leading;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        leading,
        const SizedBox(width: AppSpacing.xs),
        Flexible(
          child: Text(
            title,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodyLarge.copyWith(
              color: context.colors.text.accent,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class _ModalUtilityIcon extends StatelessWidget {
  const _ModalUtilityIcon({required this.iconName});

  final String iconName;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: colors.background.neutralSubtleOpacity,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: AppIcon(
          iconName,
          size: AppIconSize.medium,
          color: colors.icon.accent,
        ),
      ),
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
  static const _buttonWidth = 280.0;

  late ThemeMode _selectedMode = widget.currentMode;
  bool _isSubmitting = false;
  String? _submitError;

  bool get _canUpdate => !_isSubmitting && _selectedMode != widget.currentMode;

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
    return _SettingsModalCard(
      header: const _ModalHeader(
        leading: _ModalUtilityIcon(iconName: AppIcons.theme),
        title: 'Theme',
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Column(
            children: [
              _ThemeOptionCard(
                iconName: AppIcons.monitor,
                label: 'System (Auto)',
                selected: _selectedMode == ThemeMode.system,
                onTap: () => setState(() {
                  _submitError = null;
                  _selectedMode = ThemeMode.system;
                }),
              ),
              const SizedBox(height: AppSpacing.xs),
              _ThemeOptionCard(
                iconName: AppIcons.day,
                label: 'Light Mode',
                selected: _selectedMode == ThemeMode.light,
                onTap: () => setState(() {
                  _submitError = null;
                  _selectedMode = ThemeMode.light;
                }),
              ),
              const SizedBox(height: AppSpacing.xs),
              _ThemeOptionCard(
                iconName: AppIcons.night,
                label: 'Dark Mode',
                selected: _selectedMode == ThemeMode.dark,
                onTap: () => setState(() {
                  _submitError = null;
                  _selectedMode = ThemeMode.dark;
                }),
              ),
            ],
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
          AppButton(
            onPressed: _canUpdate ? _submit : null,
            variant: AppButtonVariant.primary,
            minWidth: _buttonWidth,
            child: Text(_isSubmitting ? 'Updating...' : 'Update'),
          ),
          const SizedBox(height: AppSpacing.s),
          AppButton(
            onPressed: _isSubmitting ? null : widget.onCancel,
            variant: AppButtonVariant.ghost,
            minWidth: _buttonWidth,
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}

class _WindowsUpdateModal extends ConsumerWidget {
  const _WindowsUpdateModal({required this.onCancel});

  static const _buttonWidth = 280.0;

  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(windowsUpdateProvider);
    final primary = _primaryAction(ref, state);

    return _SettingsModalCard(
      header: const _ModalHeader(
        leading: _ModalUtilityIcon(iconName: AppIcons.sync),
        title: 'Updates',
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
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
          AppButton(
            onPressed: primary.onPressed,
            variant: AppButtonVariant.primary,
            minWidth: _buttonWidth,
            child: Text(primary.label),
          ),
          const SizedBox(height: AppSpacing.s),
          AppButton(
            onPressed: state.isBusy ? null : onCancel,
            variant: AppButtonVariant.ghost,
            minWidth: _buttonWidth,
            child: const Text('Cancel'),
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
    return SizedBox(
      width: 280,
      child: Row(
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
      ),
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
      width: 280,
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
          width: 280,
          height: 40,
          padding: const EdgeInsets.only(
            left: AppSpacing.xs,
            right: AppSpacing.s,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.medium),
            border: Border.all(
              color: selected ? colors.border.strong : colors.border.regular,
              width: selected ? 2 : 1.5,
              strokeAlign: BorderSide.strokeAlignInside,
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 32,
                height: 32,
                child: Center(
                  child: AppIcon(iconName, size: 18, color: colors.icon.accent),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.labelLarge.copyWith(
                    color: colors.text.accent,
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 24,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xxs),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                title,
                style: AppTypography.labelMedium.copyWith(
                  color: colors.text.secondary,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows),
      ],
    );
  }
}

class _SettingsRowDivider extends StatelessWidget {
  const _SettingsRowDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: DecoratedBox(
        decoration: BoxDecoration(color: context.colors.border.subtle),
        child: const SizedBox(height: 1),
      ),
    );
  }
}

class _SettingsRow extends StatefulWidget {
  const _SettingsRow({
    required this.iconName,
    required this.label,
    required this.value,
    this.onTap,
  });

  final String iconName;
  final String label;
  final String value;
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
    final row = Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
          decoration: BoxDecoration(
            color: isInteractive && _hovered
                ? _settingsRowHoverBackgroundColor(context)
                : null,
            borderRadius: BorderRadius.circular(AppRadii.xSmall),
          ),
          child: Row(
            children: [
              _SettingsRowIcon(iconName: widget.iconName),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  widget.label,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.labelLarge.copyWith(
                    color: colors.text.accent,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 260),
                child: Text(
                  widget.value,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: AppTypography.labelLarge.copyWith(
                    color: colors.text.accent,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xxs),
              AppIcon(
                AppIcons.chevronForward,
                size: 16,
                color: colors.icon.accent,
              ),
            ],
          ),
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
                  borderRadius: BorderRadius.circular(AppRadii.xSmall),
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

class _SettingsRowIcon extends StatelessWidget {
  const _SettingsRowIcon({required this.iconName});

  final String iconName;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: colors.background.neutralSubtleOpacity,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: AppIcon(iconName, size: 16, color: colors.icon.regular),
    );
  }
}
