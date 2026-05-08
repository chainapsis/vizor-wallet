import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_back_link.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_decorative_divider.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_pane_modal_overlay.dart';
import '../../../core/widgets/app_profile_picture.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/sync_provider.dart';
import '../widgets/account_name_modal.dart';
import '../widgets/account_profile_picture_modal.dart';

class AccountsScreen extends ConsumerStatefulWidget {
  const AccountsScreen({super.key});

  @override
  ConsumerState<AccountsScreen> createState() => _AccountsScreenState();
}

enum _AccountModalType { accountName, profilePicture }

class _AccountsScreenState extends ConsumerState<AccountsScreen> {
  String? _modalAccountUuid;
  _AccountModalType? _activeModal;

  void _showAccountNameModal(AccountInfo account) {
    _showModal(_AccountModalType.accountName, account);
  }

  void _showProfilePictureModal(AccountInfo account) {
    _showModal(_AccountModalType.profilePicture, account);
  }

  void _showModal(_AccountModalType modal, AccountInfo account) {
    setState(() {
      _modalAccountUuid = account.uuid;
      _activeModal = modal;
    });
  }

  void _closeModal() {
    setState(() {
      _modalAccountUuid = null;
      _activeModal = null;
    });
  }

  Future<void> _updateAccountName(String uuid, String name) async {
    await ref.read(accountProvider.notifier).renameAccount(uuid, name);
    if (!mounted) return;
    _closeModal();
  }

  Future<void> _updateProfilePicture(
    String uuid,
    String profilePictureId,
  ) async {
    await ref
        .read(accountProvider.notifier)
        .updateProfilePicture(uuid, profilePictureId);
    if (!mounted) return;
    _closeModal();
  }

  @override
  Widget build(BuildContext context) {
    final accountState =
        ref.watch(accountProvider).value ?? const AccountState();
    final accounts = [...accountState.accounts]
      ..sort((a, b) => a.order.compareTo(b.order));
    final activeAccount = _activeAccountFor(
      accounts,
      accountState.activeAccountUuid,
    );
    final otherAccounts = [
      for (final account in accounts)
        if (account.uuid != activeAccount?.uuid) account,
    ];
    final modalAccount = _accountForUuid(accounts, _modalAccountUuid);

    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        padding: EdgeInsets.zero,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: _AccountsPane(
                activeAccount: activeAccount,
                otherAccounts: otherAccounts,
                onSelectAccount: _handleAccountSelected,
                onEditAccountName: _showAccountNameModal,
                onChangeProfilePicture: _showProfilePictureModal,
              ),
            ),
            if (modalAccount != null && _activeModal != null)
              AppPaneModalOverlay(
                onDismiss: _closeModal,
                child: switch (_activeModal!) {
                  _AccountModalType.accountName => AccountNameModal(
                    accountName: modalAccount.name,
                    profilePictureId: modalAccount.profilePictureId,
                    onCancel: _closeModal,
                    onUpdate:
                        (name) => _updateAccountName(modalAccount.uuid, name),
                  ),
                  _AccountModalType.profilePicture =>
                    AccountProfilePictureModal(
                      currentProfilePictureId: modalAccount.profilePictureId,
                      onCancel: _closeModal,
                      onUpdate:
                          (profilePictureId) => _updateProfilePicture(
                            modalAccount.uuid,
                            profilePictureId,
                          ),
                    ),
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleAccountSelected(String uuid) async {
    final activeAccountUuid =
        ref.read(accountProvider).value?.activeAccountUuid;
    if (uuid == activeAccountUuid) return;
    await ref.read(accountProvider.notifier).switchAccount(uuid);
    await ref.read(syncProvider.notifier).refreshAfterSend();
  }

  static AccountInfo? _activeAccountFor(
    List<AccountInfo> accounts,
    String? activeAccountUuid,
  ) {
    if (accounts.isEmpty) return null;
    for (final account in accounts) {
      if (account.uuid == activeAccountUuid) return account;
    }
    return accounts.first;
  }

  static AccountInfo? _accountForUuid(
    List<AccountInfo> accounts,
    String? uuid,
  ) {
    if (uuid == null) return null;
    for (final account in accounts) {
      if (account.uuid == uuid) return account;
    }
    return null;
  }
}

class _AccountsPane extends StatelessWidget {
  const _AccountsPane({
    required this.activeAccount,
    required this.otherAccounts,
    required this.onSelectAccount,
    required this.onEditAccountName,
    required this.onChangeProfilePicture,
  });

  final AccountInfo? activeAccount;
  final List<AccountInfo> otherAccounts;
  final Future<void> Function(String uuid) onSelectAccount;
  final ValueChanged<AccountInfo> onEditAccountName;
  final ValueChanged<AccountInfo> onChangeProfilePicture;

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(alignment: Alignment.centerLeft, child: AppRouteBackLink()),
          const SizedBox(height: AppSpacing.s),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.s),
              child: Column(
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          'Accounts',
                          textAlign: TextAlign.center,
                          style: AppTypography.displaySmall.copyWith(
                            color: context.colors.text.accent,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.s),
                        const AppDecorativeDivider(width: 256),
                        const SizedBox(height: AppSpacing.md),
                        Expanded(
                          child: _AccountsList(
                            activeAccount: activeAccount,
                            otherAccounts: otherAccounts,
                            onSelectAccount: onSelectAccount,
                            onEditAccountName: onEditAccountName,
                            onChangeProfilePicture: onChangeProfilePicture,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  AppButton(
                    onPressed: () => context.go('/add-account'),
                    minWidth: 256,
                    trailing: const AppIcon(AppIcons.chevronForward),
                    child: const Text('Add Account'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountsList extends StatelessWidget {
  const _AccountsList({
    required this.activeAccount,
    required this.otherAccounts,
    required this.onSelectAccount,
    required this.onEditAccountName,
    required this.onChangeProfilePicture,
  });

  static const _width = 352.0;

  final AccountInfo? activeAccount;
  final List<AccountInfo> otherAccounts;
  final Future<void> Function(String uuid) onSelectAccount;
  final ValueChanged<AccountInfo> onEditAccountName;
  final ValueChanged<AccountInfo> onChangeProfilePicture;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: SizedBox(
        width: _width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (activeAccount != null)
              _AccountRow(
                key: ValueKey('accounts_active_row_${activeAccount!.uuid}'),
                account: activeAccount!,
                onTap: null,
                onEditName: onEditAccountName,
                onChangePicture: onChangeProfilePicture,
              ),
            const _AccountsSectionLabel(label: 'Other'),
            if (otherAccounts.isNotEmpty)
              Expanded(
                child: ListView.separated(
                  padding: EdgeInsets.zero,
                  itemCount: otherAccounts.length,
                  itemBuilder: (context, index) {
                    final account = otherAccounts[index];
                    return _AccountRow(
                      key: ValueKey('accounts_other_row_${account.uuid}'),
                      account: account,
                      onTap: () {
                        onSelectAccount(account.uuid);
                      },
                      onEditName: onEditAccountName,
                      onChangePicture: onChangeProfilePicture,
                    );
                  },
                  separatorBuilder:
                      (_, _) => const SizedBox(height: AppSpacing.xs),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AccountsSectionLabel extends StatelessWidget {
  const _AccountsSectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xxs),
      child: Text(
        label,
        style: AppTypography.labelMedium.copyWith(
          color: context.colors.text.secondary,
        ),
      ),
    );
  }
}

class _AccountRow extends StatefulWidget {
  const _AccountRow({
    required this.account,
    required this.onTap,
    required this.onEditName,
    required this.onChangePicture,
    super.key,
  });

  final AccountInfo account;
  final VoidCallback? onTap;
  final ValueChanged<AccountInfo> onEditName;
  final ValueChanged<AccountInfo> onChangePicture;

  @override
  State<_AccountRow> createState() => _AccountRowState();
}

class _AccountRowState extends State<_AccountRow> {
  bool _isHovered = false;
  bool _isMenuOpen = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final enabled = widget.onTap != null;
    final isHighlighted = _isHovered || _isMenuOpen;

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        decoration: BoxDecoration(
          color: isHighlighted ? colors.background.base : null,
          borderRadius: BorderRadius.circular(AppRadii.xSmall),
        ),
        child: Row(
          children: [
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onTap,
                child: Row(
                  children: [
                    AppProfilePicture(
                      profilePictureId: widget.account.profilePictureId,
                      size: AppProfilePictureSize.large,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        widget.account.name,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.labelLarge.copyWith(
                          color: colors.text.accent,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _AccountRowMenuButton(
              key: ValueKey('accounts_row_menu_button_${widget.account.uuid}'),
              onOpenChanged: _setMenuOpen,
              onEditName: () => widget.onEditName(widget.account),
              onChangePicture: () => widget.onChangePicture(widget.account),
            ),
          ],
        ),
      ),
    );
  }

  void _setHovered(bool value) {
    if (_isHovered == value) return;
    setState(() {
      _isHovered = value;
    });
  }

  void _setMenuOpen(bool value) {
    if (_isMenuOpen == value) return;
    setState(() {
      _isMenuOpen = value;
    });
  }
}

class _AccountRowMenuButton extends StatefulWidget {
  const _AccountRowMenuButton({
    required this.onOpenChanged,
    required this.onEditName,
    required this.onChangePicture,
    super.key,
  });

  final ValueChanged<bool> onOpenChanged;
  final VoidCallback onEditName;
  final VoidCallback onChangePicture;

  @override
  State<_AccountRowMenuButton> createState() => _AccountRowMenuButtonState();
}

class _AccountRowMenuButtonState extends State<_AccountRowMenuButton> {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _menuEntry;

  @override
  void dispose() {
    _hideMenu(notify: false);
    super.dispose();
  }

  void _toggleMenu() {
    if (_menuEntry == null) {
      _showMenu();
    } else {
      _hideMenu();
    }
  }

  void _showMenu() {
    final overlay = Overlay.of(context, rootOverlay: true);
    _menuEntry = OverlayEntry(
      builder: (overlayContext) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () => _hideMenu(),
              ),
            ),
            CompositedTransformFollower(
              link: _layerLink,
              showWhenUnlinked: false,
              targetAnchor: Alignment.topLeft,
              followerAnchor: Alignment.topLeft,
              offset: const Offset(0, 22),
              child: _AccountContextMenu(
                onEditName: _handleEditName,
                onChangePicture: _handleChangePicture,
                onDismiss: () => _hideMenu(),
              ),
            ),
          ],
        );
      },
    );
    overlay.insert(_menuEntry!);
    widget.onOpenChanged(true);
    setState(() {});
  }

  void _hideMenu({bool notify = true}) {
    final entry = _menuEntry;
    if (entry == null) return;
    _menuEntry = null;
    entry.remove();
    if (notify) widget.onOpenChanged(false);
    if (mounted) setState(() {});
  }

  void _handleEditName() {
    _hideMenu();
    widget.onEditName();
  }

  void _handleChangePicture() {
    _hideMenu();
    widget.onChangePicture();
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggleMenu,
          child: Semantics(
            button: true,
            label: 'Account actions',
            child: SizedBox(
              width: 20,
              height: 20,
              child: Center(
                child: Transform.rotate(
                  angle: -math.pi / 2,
                  child: AppIcon(
                    AppIcons.options,
                    size: AppIconSize.medium,
                    color: context.colors.icon.accent,
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

class _AccountContextMenu extends StatelessWidget {
  const _AccountContextMenu({
    required this.onEditName,
    required this.onChangePicture,
    required this.onDismiss,
  });

  static const _width = 160.0;

  final VoidCallback onEditName;
  final VoidCallback onChangePicture;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final shadowColor =
        AppTheme.of(context) == AppThemeData.light
            ? const Color(0xFFE1E1E1)
            : const Color(0x66000000);

    return DefaultTextStyle.merge(
      style: const TextStyle(decoration: TextDecoration.none),
      child: SizedBox(
        width: _width,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.background.inverse,
            borderRadius: BorderRadius.circular(AppRadii.small),
            border: Border.all(color: colors.border.subtleOpacity),
            boxShadow: [
              BoxShadow(
                color: shadowColor,
                offset: Offset(0, 2),
                blurRadius: 2,
              ),
              BoxShadow(
                color: shadowColor,
                offset: Offset(0, 10),
                blurRadius: 15,
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xxs,
              vertical: AppSpacing.xs,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _AccountContextMenuItem(
                  iconName: AppIcons.scroll,
                  label: 'Edit Name',
                  onTap: onEditName,
                ),
                const SizedBox(height: AppSpacing.xxs),
                _AccountContextMenuItem(
                  iconName: AppIcons.user,
                  label: 'Change Picture',
                  onTap: onChangePicture,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: AppSpacing.xxs / 2,
                  ),
                  child: SizedBox(
                    height: 1,
                    width: double.infinity,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: _contextMenuDividerColor(context),
                      ),
                    ),
                  ),
                ),
                _AccountContextMenuItem(
                  iconName: AppIcons.trash,
                  label: 'Remove Account',
                  destructive: true,
                  onTap: onDismiss,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AccountContextMenuItem extends StatefulWidget {
  const _AccountContextMenuItem({
    required this.iconName,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final String iconName;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  @override
  State<_AccountContextMenuItem> createState() =>
      _AccountContextMenuItemState();
}

class _AccountContextMenuItemState extends State<_AccountContextMenuItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isLight = AppTheme.of(context) == AppThemeData.light;
    final itemColor =
        widget.destructive
            ? (isLight ? const Color(0xFFB67CC0) : colors.text.destructive)
            : colors.text.inverse;
    final iconColor =
        widget.destructive
            ? (isLight ? const Color(0xFFAC6CB7) : colors.icon.destructive)
            : colors.icon.inverse;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          height: 26,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xs,
            vertical: AppSpacing.xxs,
          ),
          decoration: BoxDecoration(
            color: _isHovered ? colors.state.hover : null,
            borderRadius: BorderRadius.circular(AppSpacing.xxs),
          ),
          child: Row(
            children: [
              AppIcon(
                widget.iconName,
                size: AppIconSize.medium,
                color: iconColor,
              ),
              const SizedBox(width: AppSpacing.xxs),
              Expanded(
                child: Text(
                  widget.label,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.labelMedium.copyWith(color: itemColor),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _setHovered(bool value) {
    if (_isHovered == value) return;
    setState(() {
      _isHovered = value;
    });
  }
}

Color _contextMenuDividerColor(BuildContext context) {
  return AppTheme.of(context) == AppThemeData.light
      ? const Color(0x1AFFFFFF)
      : const Color(0x262D3232);
}
