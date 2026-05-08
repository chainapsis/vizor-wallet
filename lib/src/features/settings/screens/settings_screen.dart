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
import '../../../core/widgets/app_profile_picture.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../providers/theme_mode_provider.dart';
import '../../accounts/widgets/account_name_modal.dart';

const _settingsRowActivationShortcuts = <ShortcutActivator, Intent>{
  SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
  SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
};

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

enum _SettingsModalType { accountName, profilePicture, theme }

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
    final themeMode = ref.watch(themeModeProvider);
    final endpointLabel = ref.watch(rpcEndpointProvider).hostPort;

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
                endpointLabel: endpointLabel,
                themeLabel: _themeLabel(themeMode),
                onSeedPhrase: () => context.push('/settings/secret-passphrase'),
                onChangePassword:
                    () => context.push('/settings/change-password'),
                onEndpoint: () => context.push('/settings/endpoint'),
                onAccountName:
                    hasActiveAccount
                        ? () => _showModal(_SettingsModalType.accountName)
                        : null,
                onProfilePicture:
                    hasActiveAccount
                        ? () => _showModal(_SettingsModalType.profilePicture)
                        : null,
                onTheme: () => _showModal(_SettingsModalType.theme),
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
                  _SettingsModalType.profilePicture => _ProfilePictureModal(
                    currentProfilePictureId: activeProfilePictureId,
                    onCancel: _closeModal,
                    onUpdate: _updateProfilePicture,
                  ),
                  _SettingsModalType.theme => _ThemeModal(
                    currentMode: themeMode,
                    onCancel: _closeModal,
                    onUpdate: _updateTheme,
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
}

class _SettingsPane extends StatelessWidget {
  const _SettingsPane({
    required this.accountName,
    required this.profilePictureLabel,
    required this.endpointLabel,
    required this.themeLabel,
    required this.onSeedPhrase,
    required this.onChangePassword,
    required this.onEndpoint,
    required this.onAccountName,
    required this.onProfilePicture,
    required this.onTheme,
  });

  final String accountName;
  final String profilePictureLabel;
  final String endpointLabel;
  final String themeLabel;
  final VoidCallback onSeedPhrase;
  final VoidCallback onChangePassword;
  final VoidCallback onEndpoint;
  final VoidCallback? onAccountName;
  final VoidCallback? onProfilePicture;
  final VoidCallback onTheme;

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
                        endpointLabel: endpointLabel,
                        themeLabel: themeLabel,
                        onSeedPhrase: onSeedPhrase,
                        onChangePassword: onChangePassword,
                        onEndpoint: onEndpoint,
                        onAccountName: onAccountName,
                        onProfilePicture: onProfilePicture,
                        onTheme: onTheme,
                      ),
                    ],
                  ),
                ),
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
    required this.endpointLabel,
    required this.themeLabel,
    required this.onSeedPhrase,
    required this.onChangePassword,
    required this.onEndpoint,
    required this.onAccountName,
    required this.onProfilePicture,
    required this.onTheme,
  });

  final String accountName;
  final String profilePictureLabel;
  final String endpointLabel;
  final String themeLabel;
  final VoidCallback onSeedPhrase;
  final VoidCallback onChangePassword;
  final VoidCallback onEndpoint;
  final VoidCallback? onAccountName;
  final VoidCallback? onProfilePicture;
  final VoidCallback onTheme;

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
              value: 'View',
              onTap: onSeedPhrase,
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
          ],
        ),
      ],
    );
  }
}

class _SettingsModalCard extends StatelessWidget {
  const _SettingsModalCard({
    required this.header,
    required this.child,
    this.gap = AppSpacing.md,
  });

  final Widget header;
  final Widget child;
  final double gap;

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
        children: [header, SizedBox(height: gap), child],
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

class _ProfilePictureModal extends StatefulWidget {
  const _ProfilePictureModal({
    required this.currentProfilePictureId,
    required this.onCancel,
    required this.onUpdate,
  });

  final String currentProfilePictureId;
  final VoidCallback onCancel;
  final Future<void> Function(String profilePictureId) onUpdate;

  @override
  State<_ProfilePictureModal> createState() => _ProfilePictureModalState();
}

class _ProfilePictureModalState extends State<_ProfilePictureModal> {
  static const _buttonWidth = 280.0;
  static const _optionSize = AppProfilePictureSize.large;
  static const _gridWidth = 184.0;

  late String _selectedId = _initialSelectedId();
  bool _isSubmitting = false;
  String? _submitError;

  bool get _canUpdate =>
      !_isSubmitting &&
      isKnownProfilePictureId(_selectedId) &&
      _selectedId != _currentResolvedId;

  String get _currentResolvedId {
    return resolveProfilePictureOption(widget.currentProfilePictureId).id;
  }

  String _initialSelectedId() {
    return _currentResolvedId;
  }

  Future<void> _submit() async {
    if (!_canUpdate) return;
    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });
    try {
      await widget.onUpdate(_selectedId);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitError = "Couldn't update profile picture.";
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  void _select(String id) {
    if (_isSubmitting) return;
    setState(() {
      _selectedId = id;
      _submitError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final previewOption = resolveProfilePictureOption(_selectedId);

    return _SettingsModalCard(
      gap: AppSpacing.sm,
      header: _ProfilePictureModalHeader(profilePictureId: previewOption.id),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: _gridWidth,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.s),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  for (final option in kProfilePictureOptions)
                    _ProfilePictureOptionButton(
                      option: option,
                      size: _optionSize,
                      selected: option.id == _selectedId,
                      enabled: !_isSubmitting,
                      onTap: () => _select(option.id),
                    ),
                ],
              ),
            ),
          ),
          if (_submitError != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              _submitError!,
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(
                color: context.colors.text.destructive,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
          const SizedBox(height: AppSpacing.sm),
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

class _ProfilePictureModalHeader extends StatelessWidget {
  const _ProfilePictureModalHeader({required this.profilePictureId});

  final String profilePictureId;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppProfilePicture(
          profilePictureId: profilePictureId,
          size: AppProfilePictureSize.xLarge,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Select Profile Picture',
          overflow: TextOverflow.ellipsis,
          style: AppTypography.bodyLarge.copyWith(
            color: context.colors.text.accent,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _ProfilePictureOptionButton extends StatefulWidget {
  const _ProfilePictureOptionButton({
    required this.option,
    required this.size,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final ProfilePictureOption option;
  final AppProfilePictureSize size;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  State<_ProfilePictureOptionButton> createState() =>
      _ProfilePictureOptionButtonState();
}

class _ProfilePictureOptionButtonState
    extends State<_ProfilePictureOptionButton> {
  static const _outerPadding = 4.0;
  static const _focusRingWidth = 2.0;
  static const _checkGapSize = 22.0;
  static const _checkBadgeSize = 16.0;
  static const _checkIconSize = 12.0;
  static const _checkRight = -3.0;
  static const _checkBottom = -1.0;

  bool _isHovered = false;
  bool _isFocused = false;

  void _setHovered(bool value) {
    if (_isHovered == value) return;
    setState(() {
      _isHovered = value;
    });
  }

  void _setFocused(bool value) {
    if (_isFocused == value) return;
    setState(() {
      _isFocused = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final showFocusRing = widget.enabled && (_isHovered || _isFocused);
    final outerDimension = widget.size.dimension + _outerPadding * 2;

    return FocusableActionDetector(
      enabled: widget.enabled,
      mouseCursor:
          widget.enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onShowFocusHighlight: _setFocused,
      child: MouseRegion(
        onEnter: (_) => _setHovered(true),
        onExit: (_) => _setHovered(false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.enabled ? widget.onTap : null,
          child: SizedBox(
            width: outerDimension,
            height: outerDimension,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                if (showFocusRing)
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: colors.state.focusRing,
                          width: _focusRingWidth,
                        ),
                        borderRadius: BorderRadius.circular(widget.size.radius),
                      ),
                    ),
                  ),
                AppProfilePicture(
                  profilePictureId: widget.option.id,
                  size: widget.size,
                ),
                if (widget.selected)
                  Positioned(
                    right: _checkRight,
                    bottom: _checkBottom,
                    child: Container(
                      width: _checkGapSize,
                      height: _checkGapSize,
                      decoration: BoxDecoration(
                        color: colors.background.ground,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Container(
                          width: _checkBadgeSize,
                          height: _checkBadgeSize,
                          decoration: BoxDecoration(
                            color: colors.background.inverse,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: AppIcon(
                              AppIcons.check,
                              size: _checkIconSize,
                              color: colors.background.ground,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
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
                onTap:
                    () => setState(() {
                      _submitError = null;
                      _selectedMode = ThemeMode.system;
                    }),
              ),
              const SizedBox(height: AppSpacing.xs),
              _ThemeOptionCard(
                iconName: AppIcons.day,
                label: 'Light Mode',
                selected: _selectedMode == ThemeMode.light,
                onTap:
                    () => setState(() {
                      _submitError = null;
                      _selectedMode = ThemeMode.light;
                    }),
              ),
              const SizedBox(height: AppSpacing.xs),
              _ThemeOptionCard(
                iconName: AppIcons.night,
                label: 'Dark Mode',
                selected: _selectedMode == ThemeMode.dark,
                onTap:
                    () => setState(() {
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
        color:
            selected
                ? colors.background.inverse
                : colors.background.neutralSubtleOpacity,
        shape: BoxShape.circle,
      ),
      child:
          selected
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
            color:
                isInteractive && _hovered
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
