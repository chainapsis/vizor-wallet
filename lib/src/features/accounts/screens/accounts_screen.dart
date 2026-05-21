import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart'
    show Scrollbar, ScrollbarTheme, ScrollbarThemeData, WidgetStatePropertyAll;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../main.dart' show log;
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
import '../../../providers/app_security_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../../providers/wallet_mutation_guard.dart';
import '../../../providers/zns_provider.dart';
import '../widgets/account_name_modal.dart';
import '../widgets/account_profile_picture_modal.dart';
import '../widgets/account_remove_modal.dart';

const _accountRowHeight = 44.0;
const _accountsListScrollbarKey = ValueKey('accounts_list_scrollbar');

class AccountsScreen extends ConsumerStatefulWidget {
  const AccountsScreen({super.key});

  @override
  ConsumerState<AccountsScreen> createState() => _AccountsScreenState();
}

enum _AccountModalType { accountName, profilePicture, removeAccount }

class _AccountsScreenState extends ConsumerState<AccountsScreen> {
  String? _modalAccountUuid;
  _AccountModalType? _activeModal;

  void _showAccountNameModal(AccountInfo account) {
    _showModal(_AccountModalType.accountName, account);
  }

  void _showProfilePictureModal(AccountInfo account) {
    _showModal(_AccountModalType.profilePicture, account);
  }

  void _showRemoveAccountModal(AccountInfo account) {
    _showModal(_AccountModalType.removeAccount, account);
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
    unawaited(_checkZnsEasterEgg(uuid, name));
  }

  Future<void> _checkZnsEasterEgg(String uuid, String name) async {
    final owned = await ref.read(znsResolverProvider).isOwnedByAccount(name, uuid);
    if (!mounted || !owned) return;
    final account = ref.read(accountProvider).value?.accounts
        .where((a) => a.uuid == uuid)
        .firstOrNull;
    if (account == null) return;
    final currentId = account.profilePictureId;
    if (currentId.startsWith('zns-')) return;
    await ref.read(accountProvider.notifier).updateProfilePicture(uuid, 'zns-$currentId');
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

  Future<void> _removeAccount(
    String uuid, {
    required bool isLastAccount,
    AccountRemoveProgressCallback? onProgress,
  }) async {
    if (isLastAccount) {
      await _resetWalletFromAccountRemoval(onProgress);
      return;
    }

    final accountNotifier = ref.read(accountProvider.notifier);
    onProgress?.call(AccountRemoveProgress.stoppingSync);
    final flowWatch = Stopwatch()..start();
    final pauseWatch = Stopwatch()..start();
    var didLogPause = false;
    void logPauseComplete() {
      if (didLogPause) return;
      didLogPause = true;
      pauseWatch.stop();
      onProgress?.call(AccountRemoveProgress.removingAccount);
      log(
        'removeAccountFlow: sync pause complete in '
        '${pauseWatch.elapsedMilliseconds}ms uuid=$uuid',
      );
    }

    await runWithSyncPausedForAccountMutation(ref, () async {
      logPauseComplete();
      final mutationWatch = Stopwatch()..start();
      await accountNotifier.removeAccount(uuid);
      log(
        'removeAccountFlow: account mutation complete in '
        '${mutationWatch.elapsedMilliseconds}ms uuid=$uuid',
      );
    }, onSyncPaused: logPauseComplete);
    if (!mounted) return;
    _closeModal();
    final refreshWatch = Stopwatch()..start();
    await ref.read(syncProvider.notifier).refreshAfterSend();
    log(
      'removeAccountFlow: refreshAfterSend complete in '
      '${refreshWatch.elapsedMilliseconds}ms uuid=$uuid '
      'total=${flowWatch.elapsedMilliseconds}ms',
    );
  }

  Future<void> _resetWalletFromAccountRemoval(
    AccountRemoveProgressCallback? onProgress,
  ) async {
    final syncNotifier = ref.read(syncProvider.notifier);
    final accountNotifier = ref.read(accountProvider.notifier);

    onProgress?.call(AccountRemoveProgress.stoppingSync);
    await runWithSyncPausedForAccountMutation(ref, () async {
      onProgress?.call(AccountRemoveProgress.removingAccount);
      await accountNotifier.resetWallet();
      syncNotifier.clearCachedWalletDbPath();
    }, resumeAfterMutation: false);
    if (!mounted) return;
    _closeModal();
    context.go('/welcome');
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
    final isLastModalAccount =
        modalAccount != null &&
        accounts.length == 1 &&
        accounts.first.uuid == modalAccount.uuid;

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
                onRemoveAccount: _showRemoveAccountModal,
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
                    onUpdate: (name) =>
                        _updateAccountName(modalAccount.uuid, name),
                  ),
                  _AccountModalType.profilePicture =>
                    AccountProfilePictureModal(
                      currentProfilePictureId: modalAccount.profilePictureId,
                      onCancel: _closeModal,
                      onUpdate: (profilePictureId) => _updateProfilePicture(
                        modalAccount.uuid,
                        profilePictureId,
                      ),
                    ),
                  _AccountModalType.removeAccount => AccountRemoveModal(
                    accountName: modalAccount.name,
                    profilePictureId: modalAccount.profilePictureId,
                    isLastAccount: isLastModalAccount,
                    onCancel: _closeModal,
                    onConfirmPassword: (password) => ref
                        .read(appSecurityProvider.notifier)
                        .confirmPassword(password),
                    onRemove: (onProgress) => _removeAccount(
                      modalAccount.uuid,
                      isLastAccount: isLastModalAccount,
                      onProgress: onProgress,
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
    final activeAccountUuid = ref
        .read(accountProvider)
        .value
        ?.activeAccountUuid;
    if (uuid == activeAccountUuid) return;
    final accountNotifier = ref.read(accountProvider.notifier);
    final syncNotifier = ref.read(syncProvider.notifier);

    await accountNotifier.switchAccount(uuid);
    if (mounted) {
      context.go('/home');
    }
    unawaited(_refreshAfterAccountSwitch(syncNotifier));
  }

  Future<void> _refreshAfterAccountSwitch(SyncNotifier syncNotifier) async {
    try {
      await syncNotifier.refreshAfterSend();
    } catch (e) {
      log('switchAccount: refreshAfterSend failed: $e');
    }
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
    required this.onRemoveAccount,
  });

  final AccountInfo? activeAccount;
  final List<AccountInfo> otherAccounts;
  final Future<void> Function(String uuid) onSelectAccount;
  final ValueChanged<AccountInfo> onEditAccountName;
  final ValueChanged<AccountInfo> onChangeProfilePicture;
  final ValueChanged<AccountInfo> onRemoveAccount;

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
                            onRemoveAccount: onRemoveAccount,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  AppButton(
                    key: const ValueKey('accounts_add_account_button'),
                    onPressed: () => context.go('/add-account'),
                    variant: AppButtonVariant.secondary,
                    minWidth: 256,
                    leading: const AppIcon(AppIcons.addNew),
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

class _AccountsList extends StatefulWidget {
  const _AccountsList({
    required this.activeAccount,
    required this.otherAccounts,
    required this.onSelectAccount,
    required this.onEditAccountName,
    required this.onChangeProfilePicture,
    required this.onRemoveAccount,
  });

  static const _width = 352.0;

  final AccountInfo? activeAccount;
  final List<AccountInfo> otherAccounts;
  final Future<void> Function(String uuid) onSelectAccount;
  final ValueChanged<AccountInfo> onEditAccountName;
  final ValueChanged<AccountInfo> onChangeProfilePicture;
  final ValueChanged<AccountInfo> onRemoveAccount;

  @override
  State<_AccountsList> createState() => _AccountsListState();
}

class _AccountsListState extends State<_AccountsList> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accountCount =
        widget.otherAccounts.length + (widget.activeAccount == null ? 0 : 1);
    final seedAnchorCount =
        widget.otherAccounts.where((account) => account.isSeedAnchor).length +
        (widget.activeAccount?.isSeedAnchor == true ? 1 : 0);

    return Align(
      alignment: Alignment.topCenter,
      child: SizedBox(
        width: _AccountsList._width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.activeAccount != null) ...[
              const _AccountsSectionLabel(label: 'Current'),
              const SizedBox(height: AppSpacing.xs),
              _AccountRow(
                key: ValueKey(
                  'accounts_active_row_${widget.activeAccount!.uuid}',
                ),
                account: widget.activeAccount!,
                onTap: null,
                onEditName: widget.onEditAccountName,
                onChangePicture: widget.onChangeProfilePicture,
                onRemove: widget.onRemoveAccount,
                canRemove: _canRemoveAccount(
                  widget.activeAccount!,
                  accountCount,
                  seedAnchorCount,
                ),
              ),
            ],
            if (widget.otherAccounts.isNotEmpty) ...[
              if (widget.activeAccount != null)
                const SizedBox(height: AppSpacing.md),
              const _AccountsSectionLabel(label: 'Other'),
              const SizedBox(height: AppSpacing.xs),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final canScroll =
                        _otherAccountsContentHeight(
                          widget.otherAccounts.length,
                        ) >
                        constraints.maxHeight;
                    final listView = ScrollConfiguration(
                      behavior: ScrollConfiguration.of(
                        context,
                      ).copyWith(scrollbars: false),
                      child: ListView.separated(
                        controller: _scrollController,
                        padding: EdgeInsets.zero,
                        itemCount: widget.otherAccounts.length,
                        itemBuilder: (context, index) {
                          final account = widget.otherAccounts[index];
                          return _AccountRow(
                            key: ValueKey('accounts_other_row_${account.uuid}'),
                            account: account,
                            onTap: () {
                              widget.onSelectAccount(account.uuid);
                            },
                            onEditName: widget.onEditAccountName,
                            onChangePicture: widget.onChangeProfilePicture,
                            onRemove: widget.onRemoveAccount,
                            canRemove: _canRemoveAccount(
                              account,
                              accountCount,
                              seedAnchorCount,
                            ),
                          );
                        },
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: AppSpacing.xs),
                      ),
                    );

                    if (!canScroll) return listView;

                    return _AccountsListScrollbar(
                      controller: _scrollController,
                      child: listView,
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static bool _canRemoveAccount(
    AccountInfo account,
    int accountCount,
    int seedAnchorCount,
  ) {
    if (accountCount == 1) return true;
    if (!account.isSeedAnchor) return true;
    return seedAnchorCount > 1;
  }

  static double _otherAccountsContentHeight(int count) {
    if (count <= 0) return 0;
    return count * _accountRowHeight + (count - 1) * AppSpacing.xs;
  }
}

class _AccountsListScrollbar extends StatelessWidget {
  const _AccountsListScrollbar({required this.controller, required this.child});

  static const _scrollbarGutter = 18.0;

  final ScrollController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return OverflowBox(
      alignment: Alignment.topLeft,
      minWidth: _AccountsList._width + _scrollbarGutter,
      maxWidth: _AccountsList._width + _scrollbarGutter,
      child: SizedBox(
        width: _AccountsList._width + _scrollbarGutter,
        child: ScrollbarTheme(
          data: ScrollbarThemeData(
            thumbColor: WidgetStatePropertyAll(
              context.colors.background.overlay,
            ),
            thickness: const WidgetStatePropertyAll(6),
            radius: const Radius.circular(AppRadii.full),
            thumbVisibility: const WidgetStatePropertyAll(true),
            trackVisibility: const WidgetStatePropertyAll(false),
            crossAxisMargin: 3,
            mainAxisMargin: 3,
          ),
          child: Scrollbar(
            key: _accountsListScrollbarKey,
            controller: controller,
            child: Row(
              children: [
                SizedBox(width: _AccountsList._width, child: child),
                const SizedBox(width: _scrollbarGutter),
              ],
            ),
          ),
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
    required this.onRemove,
    required this.canRemove,
    super.key,
  });

  final AccountInfo account;
  final VoidCallback? onTap;
  final ValueChanged<AccountInfo> onEditName;
  final ValueChanged<AccountInfo> onChangePicture;
  final ValueChanged<AccountInfo> onRemove;
  final bool canRemove;

  @override
  State<_AccountRow> createState() => _AccountRowState();
}

class _AccountRowState extends State<_AccountRow> {
  bool _isHovered = false;

  void _setHovered(bool isHovered) {
    if (_isHovered == isHovered) return;
    setState(() {
      _isHovered = isHovered;
    });
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final isHighlighted = enabled && _isHovered;

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: enabled ? (_) => _setHovered(true) : null,
      onExit: enabled ? (_) => _setHovered(false) : null,
      child: AnimatedContainer(
        key: ValueKey('accounts_row_background_${widget.account.uuid}'),
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        height: _accountRowHeight,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        decoration: BoxDecoration(
          color: isHighlighted ? context.colors.background.base : null,
          borderRadius: BorderRadius.circular(AppRadii.xSmall),
        ),
        child: Row(
          children: [
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onTap,
                child: SizedBox(
                  height: _accountRowHeight,
                  child: Row(
                    children: [
                      AppProfilePicture(
                        profilePictureId: widget.account.profilePictureId,
                        size: AppProfilePictureSize.large,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: _AccountRowContent(account: widget.account),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            _AccountRowMenuButton(
              key: ValueKey('accounts_row_menu_button_${widget.account.uuid}'),
              onEditName: () => widget.onEditName(widget.account),
              onChangePicture: () => widget.onChangePicture(widget.account),
              onRemove: () => widget.onRemove(widget.account),
              canRemove: widget.canRemove,
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountRowContent extends StatelessWidget {
  const _AccountRowContent({required this.account});

  final AccountInfo account;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    if (!account.isHardware) {
      return Text(
        account.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.labelLarge.copyWith(color: colors.text.accent),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          account.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.labelLarge.copyWith(color: colors.text.accent),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(
              AppIcons.keystone,
              size: AppIconSize.medium,
              color: colors.icon.accent,
            ),
            const SizedBox(width: AppSpacing.xxs),
            Flexible(
              child: Text(
                'Keystone',
                overflow: TextOverflow.ellipsis,
                style: AppTypography.labelMedium.copyWith(
                  color: colors.text.secondary,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _AccountRowMenuButton extends StatefulWidget {
  const _AccountRowMenuButton({
    required this.onEditName,
    required this.onChangePicture,
    required this.onRemove,
    required this.canRemove,
    super.key,
  });

  final VoidCallback onEditName;
  final VoidCallback onChangePicture;
  final VoidCallback onRemove;
  final bool canRemove;

  @override
  State<_AccountRowMenuButton> createState() => _AccountRowMenuButtonState();
}

class _AccountRowMenuButtonState extends State<_AccountRowMenuButton> {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _menuEntry;
  bool _isHovered = false;

  @override
  void dispose() {
    _hideMenu(rebuild: false);
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
    final overlay = Overlay.of(context);
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
                onRemove: _handleRemove,
                canRemove: widget.canRemove,
                onDismiss: () => _hideMenu(),
              ),
            ),
          ],
        );
      },
    );
    overlay.insert(_menuEntry!);
    setState(() {});
  }

  void _hideMenu({bool rebuild = true}) {
    final entry = _menuEntry;
    if (entry == null) return;
    _menuEntry = null;
    entry.remove();
    if (rebuild && mounted) setState(() {});
  }

  void _handleEditName() {
    _hideMenu();
    widget.onEditName();
  }

  void _handleChangePicture() {
    _hideMenu();
    widget.onChangePicture();
  }

  void _handleRemove() {
    _hideMenu();
    widget.onRemove();
  }

  @override
  Widget build(BuildContext context) {
    final isHighlighted = _isHovered || _menuEntry != null;

    return CompositedTransformTarget(
      link: _layerLink,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => _setHovered(true),
        onExit: (_) => _setHovered(false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggleMenu,
          child: Semantics(
            button: true,
            label: 'Account actions',
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOut,
              width: 20,
              height: 20,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: isHighlighted ? context.colors.background.base : null,
                borderRadius: BorderRadius.circular(AppRadii.xSmall),
              ),
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

  void _setHovered(bool value) {
    if (_isHovered == value) return;
    setState(() {
      _isHovered = value;
    });
  }
}

class _AccountContextMenu extends StatelessWidget {
  const _AccountContextMenu({
    required this.onEditName,
    required this.onChangePicture,
    required this.onRemove,
    required this.canRemove,
    required this.onDismiss,
  });

  static const _width = 160.0;

  final VoidCallback onEditName;
  final VoidCallback onChangePicture;
  final VoidCallback onRemove;
  final bool canRemove;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final shadowColor = AppTheme.of(context) == AppThemeData.light
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
                if (canRemove) ...[
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
                    onTap: onRemove,
                  ),
                ],
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
    final itemColor = widget.destructive
        ? (isLight ? const Color(0xFFB67CC0) : colors.text.destructive)
        : colors.text.inverse;
    final iconColor = widget.destructive
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
