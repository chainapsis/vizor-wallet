import 'dart:ui' as ui;

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/profile_pictures.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_decorative_divider.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../providers/theme_mode_provider.dart';

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
    final activeAccountIsHardware =
        accountState?.activeAccount?.isHardware ?? false;
    final themeMode = ref.watch(themeModeProvider);
    final endpointLabel = ref.watch(rpcEndpointProvider).hostPort;

    return AppDesktopShell(
      sidebarWidth: 240,
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
                onBack: () => _handleBack(context),
                onSeedPhrase: () => context.go('/settings/secret-passphrase'),
                onChangePassword: () => context.go('/settings/change-password'),
                onEndpoint: () => context.go('/settings/endpoint'),
                onAccountName: hasActiveAccount
                    ? () => _showModal(_SettingsModalType.accountName)
                    : null,
                onProfilePicture: hasActiveAccount
                    ? () => _showModal(_SettingsModalType.profilePicture)
                    : null,
                onTheme: () => _showModal(_SettingsModalType.theme),
              ),
            ),
            if (_activeModal != null)
              _SettingsModalOverlay(
                onDismiss: _closeModal,
                child: switch (_activeModal!) {
                  _SettingsModalType.accountName => _AccountNameModal(
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

  static void _handleBack(BuildContext context) {
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go('/home');
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
    required this.activeAccountIsHardware,
    required this.endpointLabel,
    required this.themeLabel,
    required this.onBack,
    required this.onSeedPhrase,
    required this.onChangePassword,
    required this.onEndpoint,
    required this.onAccountName,
    required this.onProfilePicture,
    required this.onTheme,
  });

  final String accountName;
  final String profilePictureLabel;
  final bool activeAccountIsHardware;
  final String endpointLabel;
  final String themeLabel;
  final VoidCallback onBack;
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
          Align(
            alignment: Alignment.centerLeft,
            child: _SettingsBackButton(onTap: onBack),
          ),
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
                        activeAccountIsHardware: activeAccountIsHardware,
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

class _SettingsBackButton extends StatelessWidget {
  const _SettingsBackButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          height: 32,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(
                AppIcons.chevronBackward,
                size: 16,
                color: colors.icon.accent,
              ),
              const SizedBox(width: AppSpacing.xxs),
              Text(
                'Back',
                style: AppTypography.labelLarge.copyWith(
                  color: colors.text.accent,
                ),
              ),
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
    required this.profilePictureLabel,
    required this.activeAccountIsHardware,
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
  final bool activeAccountIsHardware;
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

class _SettingsModalOverlay extends StatelessWidget {
  const _SettingsModalOverlay({required this.child, required this.onDismiss});

  final Widget child;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Positioned.fill(
      child: PopScope<void>(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) onDismiss();
        },
        child: Focus(
          autofocus: true,
          onKeyEvent: (_, event) {
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.escape) {
              onDismiss();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: ClipRect(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 15, sigmaY: 15),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onDismiss,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.background.neutralScrim,
                  ),
                  child: Center(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {},
                      child: child,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
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
        children: [
          header,
          SizedBox(height: gap),
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

class _ModalAccountAvatar extends StatelessWidget {
  const _ModalAccountAvatar({required this.profilePictureId});

  final String profilePictureId;

  @override
  Widget build(BuildContext context) {
    final option = resolveProfilePictureOption(profilePictureId);

    return _ProfilePictureImage(assetPath: option.assetPath, size: 32);
  }
}

class _ProfilePictureImage extends StatelessWidget {
  const _ProfilePictureImage({required this.assetPath, required this.size});

  final String assetPath;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: Image.asset(
        assetPath,
        width: size,
        height: size,
        fit: BoxFit.cover,
      ),
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
  static const _optionSize = 32.0;

  late String _selectedId = _initialSelectedId();
  bool _isSubmitting = false;
  String? _submitError;

  bool get _canUpdate =>
      !_isSubmitting &&
      isKnownProfilePictureId(_selectedId) &&
      _selectedId != widget.currentProfilePictureId;

  String _initialSelectedId() {
    return widget.currentProfilePictureId;
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
      header: _ModalHeader(
        leading: _ProfilePictureImage(
          assetPath: previewOption.assetPath,
          size: 56,
        ),
        title: 'Select Profile Picture',
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.s),
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: AppSpacing.s,
              runSpacing: AppSpacing.s,
              children: [
                for (final option in kProfilePictureOptions)
                  _ProfilePictureOptionButton(
                    option: option,
                    size: _optionSize,
                    selected: option.id == _selectedId,
                    onTap: () => _select(option.id),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
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

class _ProfilePictureOptionButton extends StatelessWidget {
  const _ProfilePictureOptionButton({
    required this.option,
    required this.size,
    required this.selected,
    required this.onTap,
  });

  final ProfilePictureOption option;
  final double size;
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
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              _ProfilePictureImage(assetPath: option.assetPath, size: size),
              if (selected)
                Positioned(
                  right: -4,
                  bottom: -2,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: colors.background.inverse,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: AppIcon(
                        AppIcons.check,
                        size: 12,
                        color: colors.background.ground,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountNameModal extends StatefulWidget {
  const _AccountNameModal({
    required this.accountName,
    required this.profilePictureId,
    required this.onCancel,
    required this.onUpdate,
  });

  final String accountName;
  final String profilePictureId;
  final VoidCallback onCancel;
  final Future<void> Function(String name) onUpdate;

  @override
  State<_AccountNameModal> createState() => _AccountNameModalState();
}

class _AccountNameModalState extends State<_AccountNameModal> {
  static const _fieldHeight = 86.0;
  static const _buttonWidth = 280.0;
  static const _minNameLength = 5;
  static const _maxNameLength = 20;

  final _controller = TextEditingController();
  bool _isSubmitting = false;
  String? _submitError;

  String get _trimmedName => _controller.text.trim();

  bool get _isLengthValid =>
      _trimmedName.length >= _minNameLength &&
      _trimmedName.length <= _maxNameLength;

  bool get _canUpdate =>
      !_isSubmitting &&
      _isLengthValid &&
      _trimmedName != widget.accountName.trim();

  String? get _messageText {
    if (_submitError != null) return _submitError;
    if (_controller.text.isEmpty || _isLengthValid) return null;
    return 'Use 5-20 characters.';
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_canUpdate) return;
    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });

    try {
      await widget.onUpdate(_trimmedName);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitError = "Couldn't update account name.";
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  void _handleChanged() {
    setState(() {
      _submitError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return _SettingsModalCard(
      header: _ModalHeader(
        leading: _ModalAccountAvatar(profilePictureId: widget.profilePictureId),
        title: widget.accountName,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: _fieldHeight,
            child: AppTextField(
              label: 'New Account Name',
              hintText: '5-20 Characters',
              controller: _controller,
              autofocus: true,
              enabled: !_isSubmitting,
              trailingSlotWidth: 40,
              inputHorizontalPadding: AppSpacing.s,
              inputFormatters: [
                LengthLimitingTextInputFormatter(_maxNameLength),
              ],
              messageText: _messageText,
              tone: _messageText == null
                  ? AppTextFieldTone.neutral
                  : AppTextFieldTone.destructive,
              onChanged: (_) => _handleChanged(),
              onSubmitted: (_) => _submit(),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
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

class _SettingsRow extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final colors = context.colors;
    final row = Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      child: Row(
        children: [
          _SettingsRowIcon(iconName: iconName),
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
          const SizedBox(width: AppSpacing.xs),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: AppTypography.labelLarge.copyWith(
                color: colors.text.accent,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xxs),
          AppIcon(AppIcons.chevronForward, size: 16, color: colors.icon.accent),
        ],
      ),
    );

    if (onTap == null) return row;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: row,
      ),
    );
  }
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
