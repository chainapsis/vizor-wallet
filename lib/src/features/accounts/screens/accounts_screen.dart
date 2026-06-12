import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart' show Colors;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../main.dart' show log;
import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_pane_floating_bar.dart';
import '../../../core/layout/app_pane_scroll_scaffold.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_back_link.dart';
import '../../../core/widgets/app_context_menu.dart';
import '../../../core/widgets/app_copy_feedback.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_pane_modal_overlay.dart';
import '../../../core/widgets/app_profile_picture.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/app_security_provider.dart';
import '../../../providers/receive_address_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../../providers/voting/voting_submission_guard_provider.dart';
import '../../../providers/wallet_mutation_guard.dart';
import '../../send/models/send_prefill_args.dart';
import '../../swap/providers/swap_activity_store.dart';
import '../widgets/account_edit_modal.dart';
import '../widgets/account_profile_picture_modal.dart';
import '../widgets/account_remove_modal.dart';

const _accountRowHeight = 44.0;
const _accountsContentWidth = 420.0;
const _accountsSurfaceWidth = 396.0;
const _accountsCurrentSurfaceHeight = 124.0;
const _accountsSurfaceVerticalPadding = AppSpacing.md;
const _accountsSurfaceHorizontalPadding = AppSpacing.sm;
const _accountsSectionLabelHeight = 24.0;
const _accountsRowGap = AppSpacing.xs;
const _accountsContentHorizontalPadding = AppSpacing.s;
const _accountsContentVerticalPadding = AppSpacing.sm;
const _accountsTitleSurfaceGap = AppSpacing.base;

enum AccountsScreenInitialModal { editAccount, profilePicture, removeAccount }

class AccountsScreen extends ConsumerStatefulWidget {
  const AccountsScreen({
    this.initialOpenMenuAccountUuid,
    this.initialModalAccountUuid,
    this.initialModal,
    super.key,
  });

  final String? initialOpenMenuAccountUuid;
  final String? initialModalAccountUuid;
  final AccountsScreenInitialModal? initialModal;

  @override
  ConsumerState<AccountsScreen> createState() => _AccountsScreenState();
}

enum _AccountModalType { editAccount, profilePicture, removeAccount }

_AccountModalType? _modalTypeFromInitial(AccountsScreenInitialModal? modal) {
  return switch (modal) {
    AccountsScreenInitialModal.editAccount => _AccountModalType.editAccount,
    AccountsScreenInitialModal.profilePicture =>
      _AccountModalType.profilePicture,
    AccountsScreenInitialModal.removeAccount => _AccountModalType.removeAccount,
    null => null,
  };
}

class _AccountsScreenState extends ConsumerState<AccountsScreen> {
  late String? _modalAccountUuid;
  late _AccountModalType? _activeModal;
  final Set<String> _copyingAddressUuids = {};
  final Set<String> _sendingZecAddressUuids = {};

  // Edit-account drafts: the picker round-trip unmounts the edit modal, so
  // the in-progress name and picked picture live here until Update commits
  // them (or Cancel discards them).
  String? _editDraftName;
  String? _editDraftProfilePictureId;
  bool _pfpPickerFromEdit = false;

  @override
  void initState() {
    super.initState();
    _modalAccountUuid = widget.initialModalAccountUuid;
    _activeModal = _modalTypeFromInitial(widget.initialModal);
  }

  void _showEditAccountModal(AccountInfo account) {
    _editDraftName = account.name;
    _editDraftProfilePictureId = account.profilePictureId;
    _pfpPickerFromEdit = false;
    _showModal(_AccountModalType.editAccount, account);
  }

  void _showRemoveAccountModal(AccountInfo account) {
    if (_blockDestructiveWalletChangeIfVotingSubmissionInProgress()) return;
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
      _editDraftName = null;
      _editDraftProfilePictureId = null;
      _pfpPickerFromEdit = false;
    });
  }

  void _openEditProfilePicturePicker() {
    setState(() {
      _pfpPickerFromEdit = true;
      _activeModal = _AccountModalType.profilePicture;
    });
  }

  void _returnToEditAccountModal({String? pickedProfilePictureId}) {
    setState(() {
      if (pickedProfilePictureId != null) {
        _editDraftProfilePictureId = pickedProfilePictureId;
      }
      _pfpPickerFromEdit = false;
      _activeModal = _AccountModalType.editAccount;
    });
  }

  Future<void> _commitEditAccount(AccountInfo account, String name) async {
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
    if (_blockDestructiveWalletChangeIfVotingSubmissionInProgress()) return;
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
    if (_blockDestructiveWalletChangeIfVotingSubmissionInProgress()) return;
    final accountNotifier = ref.read(accountProvider.notifier);

    onProgress?.call(AccountRemoveProgress.stoppingSync);
    await runWithSyncPausedForWalletReset(
      ref,
      accountNotifier.resetWallet,
      onResetting: () {
        onProgress?.call(AccountRemoveProgress.removingAccount);
      },
    );
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
    final modalPendingSwapCount =
        modalAccount != null && _activeModal == _AccountModalType.removeAccount
        ? ref.watch(swapPendingIntentCountProvider(modalAccount.uuid))
        : const AsyncValue<int>.data(0);

    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        padding: EdgeInsets.zero,
        backgroundColor: Colors.transparent,
        child: Stack(
          children: [
            AppPaneFloatingBar(
              bar: _AccountsAddAccountButton(
                key: const ValueKey('accounts_add_account_button'),
                onPressed: () => context.go('/add-account'),
              ),
              builder: (context, bottomReserve) => AppPaneScrollScaffold(
                toolbar: const AppPaneToolbar(
                  key: ValueKey('accounts_pane_toolbar'),
                  leading: AppRouteBackLink(
                    key: ValueKey('accounts_pane_back_button'),
                    minWidth: 60,
                  ),
                ),
                padding: EdgeInsets.only(bottom: bottomReserve),
                child: _AccountsPane(
                  activeAccount: activeAccount,
                  otherAccounts: otherAccounts,
                  onSelectAccount: _handleAccountSelected,
                  onCopyAddress: _copyAddress,
                  onSendZec: _sendZec,
                  onEditAccount: _showEditAccountModal,
                  onRemoveAccount: _showRemoveAccountModal,
                  initialOpenMenuAccountUuid: widget.initialOpenMenuAccountUuid,
                ),
              ),
            ),
            if (modalAccount != null && _activeModal != null)
              AppPaneModalOverlay(
                borderRadius: const BorderRadius.all(Radius.circular(20)),
                onDismiss: _closeModal,
                child: switch (_activeModal!) {
                  _AccountModalType.editAccount => AccountEditModal(
                    accountName: modalAccount.name,
                    initialName: _editDraftName ?? modalAccount.name,
                    profilePictureId:
                        _editDraftProfilePictureId ??
                        modalAccount.profilePictureId,
                    profilePictureChanged:
                        (_editDraftProfilePictureId ??
                            modalAccount.profilePictureId) !=
                        modalAccount.profilePictureId,
                    onEditProfilePicture: _openEditProfilePicturePicker,
                    onNameChanged: (name) => _editDraftName = name,
                    onCancel: _closeModal,
                    onUpdate: (name) => _commitEditAccount(modalAccount, name),
                  ),
                  _AccountModalType.profilePicture =>
                    AccountProfilePictureModal(
                      currentProfilePictureId: _pfpPickerFromEdit
                          ? (_editDraftProfilePictureId ??
                                modalAccount.profilePictureId)
                          : modalAccount.profilePictureId,
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
                        await _updateProfilePicture(
                          modalAccount.uuid,
                          profilePictureId,
                        );
                      },
                    ),
                  _AccountModalType.removeAccount => AccountRemoveModal(
                    accountName: modalAccount.name,
                    profilePictureId: modalAccount.profilePictureId,
                    isLastAccount: isLastModalAccount,
                    pendingSwapCount: modalPendingSwapCount.value ?? 0,
                    checkingPendingSwaps: modalPendingSwapCount.isLoading,
                    pendingSwapCheckFailed: modalPendingSwapCount.hasError,
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

  Future<void> _copyAddress(AccountInfo account) async {
    if (_copyingAddressUuids.contains(account.uuid)) return;

    setState(() {
      _copyingAddressUuids.add(account.uuid);
    });

    try {
      final address = await _loadShieldedAddressForAccount(account);
      if (!mounted) return;
      if (address.trim().isEmpty) {
        showAppToast(context, "Address couldn't be copied");
        return;
      }

      if (!mounted) return;
      copyTextWithToast(context, text: address, toastMessage: 'Address copied');
    } catch (e) {
      log('AccountsScreen: ERROR copying shielded address: $e');
      if (!mounted) return;
      showAppToast(context, "Address couldn't be copied");
    } finally {
      if (mounted) {
        setState(() {
          _copyingAddressUuids.remove(account.uuid);
        });
      }
    }
  }

  Future<void> _sendZec(AccountInfo account) async {
    if (_sendingZecAddressUuids.contains(account.uuid)) return;

    setState(() {
      _sendingZecAddressUuids.add(account.uuid);
    });

    try {
      final address = (await _loadShieldedAddressForAccount(account)).trim();
      if (!mounted) return;
      if (address.isEmpty) {
        showAppToast(context, "Send couldn't be started");
        return;
      }

      context.go(
        '/send',
        extra: SendPrefillArgs(
          id: 'account-address:${account.uuid}:$address',
          source: 'Accounts',
          address: address,
          label: account.name,
        ),
      );
    } catch (e) {
      log('AccountsScreen: ERROR opening send flow for account address: $e');
      if (!mounted) return;
      showAppToast(context, "Send couldn't be started");
    } finally {
      if (mounted) {
        setState(() {
          _sendingZecAddressUuids.remove(account.uuid);
        });
      }
    }
  }

  Future<String> _loadShieldedAddressForAccount(AccountInfo account) {
    final accountState = ref.read(accountProvider).value;
    final currentShieldedAddress =
        accountState?.activeAccountUuid == account.uuid
        ? accountState?.activeAddress
        : null;
    return ref
        .read(receiveAddressServiceProvider)
        .loadShieldedAddress(
          accountUuid: account.uuid,
          currentShieldedAddress: currentShieldedAddress,
        );
  }

  Future<void> _refreshAfterAccountSwitch(SyncNotifier syncNotifier) async {
    try {
      await syncNotifier.refreshAfterSend();
    } catch (e) {
      log('switchAccount: refreshAfterSend failed: $e');
    }
  }

  /// Blocks wallet mutations that would delete account state during submission.
  ///
  /// Account switching and address copy/send prefill remain allowed while a
  /// vote submission is guarded. This UI guard only covers destructive account
  /// removal and wallet reset flows; `AccountNotifier` repeats the invariant
  /// before mutating state.
  bool _blockDestructiveWalletChangeIfVotingSubmissionInProgress() {
    final guards = ref.read(votingSubmissionGuardProvider);
    if (guards.isEmpty) return false;
    showAppToast(context, guards.first.message);
    return true;
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
    required this.onCopyAddress,
    required this.onSendZec,
    required this.onEditAccount,
    required this.onRemoveAccount,
    required this.initialOpenMenuAccountUuid,
  });

  final AccountInfo? activeAccount;
  final List<AccountInfo> otherAccounts;
  final Future<void> Function(String uuid) onSelectAccount;
  final ValueChanged<AccountInfo> onCopyAddress;
  final ValueChanged<AccountInfo> onSendZec;
  final ValueChanged<AccountInfo> onEditAccount;
  final ValueChanged<AccountInfo> onRemoveAccount;
  final String? initialOpenMenuAccountUuid;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _accountsContentWidth),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: _accountsContentHorizontalPadding,
            vertical: _accountsContentVerticalPadding,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Accounts',
                textAlign: TextAlign.center,
                style: AppTypography.headlineLarge.copyWith(
                  color: context.colors.text.accent,
                ),
              ),
              const SizedBox(height: _accountsTitleSurfaceGap),
              _AccountsList(
                activeAccount: activeAccount,
                otherAccounts: otherAccounts,
                onSelectAccount: onSelectAccount,
                onCopyAddress: onCopyAddress,
                onSendZec: onSendZec,
                onEditAccount: onEditAccount,
                onRemoveAccount: onRemoveAccount,
                initialOpenMenuAccountUuid: initialOpenMenuAccountUuid,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountsAddAccountButton extends StatefulWidget {
  const _AccountsAddAccountButton({required this.onPressed, super.key});

  final VoidCallback onPressed;

  @override
  State<_AccountsAddAccountButton> createState() =>
      _AccountsAddAccountButtonState();
}

class _AccountsAddAccountButtonState extends State<_AccountsAddAccountButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  void _setHovered(bool value) {
    if (_isHovered == value) return;
    setState(() {
      _isHovered = value;
    });
  }

  void _setPressed(bool value) {
    if (_isPressed == value) return;
    setState(() {
      _isPressed = value;
    });
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey != LogicalKeyboardKey.enter &&
        event.logicalKey != LogicalKeyboardKey.numpadEnter &&
        event.logicalKey != LogicalKeyboardKey.space) {
      return KeyEventResult.ignored;
    }
    widget.onPressed();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final backgroundColor = _isPressed
        ? colors.button.secondary.bgPressed
        : _isHovered
        ? colors.button.secondary.bgHover
        : colors.button.secondary.bg;
    final labelColor = colors.button.secondary.label;

    return Focus(
      onKeyEvent: _handleKeyEvent,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => _setHovered(true),
        onExit: (_) {
          _setHovered(false);
          _setPressed(false);
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => _setPressed(true),
          onTapUp: (_) {
            _setPressed(false);
            widget.onPressed();
          },
          onTapCancel: () => _setPressed(false),
          child: Semantics(
            button: true,
            label: 'Add account',
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 96),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                curve: Curves.easeOut,
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s),
                decoration: ShapeDecoration(
                  color: backgroundColor,
                  shape: const StadiumBorder(),
                ),
                child: IconTheme.merge(
                  data: IconThemeData(color: labelColor, size: 16),
                  child: DefaultTextStyle.merge(
                    style: AppTypography.labelLarge.copyWith(color: labelColor),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AppIcon(AppIcons.addNew),
                        SizedBox(width: AppSpacing.xxs),
                        Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: AppSpacing.xxs,
                          ),
                          child: Text('Add account'),
                        ),
                      ],
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

class _AccountsList extends StatelessWidget {
  const _AccountsList({
    required this.activeAccount,
    required this.otherAccounts,
    required this.onSelectAccount,
    required this.onCopyAddress,
    required this.onSendZec,
    required this.onEditAccount,
    required this.onRemoveAccount,
    required this.initialOpenMenuAccountUuid,
  });

  static const _width = _accountsSurfaceWidth;

  final AccountInfo? activeAccount;
  final List<AccountInfo> otherAccounts;
  final Future<void> Function(String uuid) onSelectAccount;
  final ValueChanged<AccountInfo> onCopyAddress;
  final ValueChanged<AccountInfo> onSendZec;
  final ValueChanged<AccountInfo> onEditAccount;
  final ValueChanged<AccountInfo> onRemoveAccount;
  final String? initialOpenMenuAccountUuid;

  @override
  Widget build(BuildContext context) {
    final accountCount = otherAccounts.length + (activeAccount == null ? 0 : 1);
    final seedAnchorCount =
        otherAccounts.where((account) => account.isSeedAnchor).length +
        (activeAccount?.isSeedAnchor == true ? 1 : 0);
    return Align(
      alignment: Alignment.topCenter,
      child: SizedBox(
        width: _width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (activeAccount != null) ...[
              _AccountsSurface(
                key: const ValueKey('accounts_current_surface'),
                height: _accountsCurrentSurfaceHeight,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _AccountsSectionLabel(label: 'Current'),
                    const SizedBox(height: _accountsRowGap),
                    _AccountRow(
                      key: ValueKey(
                        'accounts_active_row_${activeAccount!.uuid}',
                      ),
                      account: activeAccount!,
                      onTap: null,
                      showSendZec: false,
                      onCopyAddress: onCopyAddress,
                      onSendZec: onSendZec,
                      onEditAccount: onEditAccount,
                      onRemove: onRemoveAccount,
                      showRemove: _AccountsList._canRemoveAccount(
                        activeAccount!,
                        accountCount,
                        seedAnchorCount,
                      ),
                      initiallyOpenMenu:
                          initialOpenMenuAccountUuid == activeAccount!.uuid,
                    ),
                  ],
                ),
              ),
            ],
            if (otherAccounts.isNotEmpty) ...[
              if (activeAccount != null) const SizedBox(height: AppSpacing.sm),
              _AccountsSurface(
                key: const ValueKey('accounts_other_surface'),
                height: _otherAccountsSurfaceHeight(otherAccounts.length),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _AccountsSectionLabel(label: 'Other'),
                    const SizedBox(height: _accountsRowGap),
                    _OtherAccountsRows(
                      accounts: otherAccounts,
                      accountCount: accountCount,
                      seedAnchorCount: seedAnchorCount,
                      onSelectAccount: onSelectAccount,
                      onCopyAddress: onCopyAddress,
                      onSendZec: onSendZec,
                      onEditAccount: onEditAccount,
                      onRemoveAccount: onRemoveAccount,
                      initialOpenMenuAccountUuid: initialOpenMenuAccountUuid,
                    ),
                  ],
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

  static double _accountsRowsHeight(int count) {
    if (count <= 0) return 0;
    return count * _accountRowHeight + (count - 1) * _accountsRowGap;
  }

  static double _otherAccountsSurfaceHeight(int count) {
    return _accountsSurfaceVerticalPadding * 2 +
        _accountsSectionLabelHeight +
        _accountsRowGap +
        _accountsRowsHeight(count);
  }
}

class _AccountsSurface extends StatelessWidget {
  const _AccountsSurface({
    required this.height,
    required this.child,
    super.key,
  });

  final double height;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(
        horizontal: _accountsSurfaceHorizontalPadding,
        vertical: _accountsSurfaceVerticalPadding,
      ),
      decoration: BoxDecoration(
        color: _accountsSurfaceColor(context),
        borderRadius: BorderRadius.circular(AppRadii.large),
        boxShadow: appSurfaceShadow(context.colors),
      ),
      child: child,
    );
  }
}

class _OtherAccountsRows extends StatelessWidget {
  const _OtherAccountsRows({
    required this.accounts,
    required this.accountCount,
    required this.seedAnchorCount,
    required this.onSelectAccount,
    required this.onCopyAddress,
    required this.onSendZec,
    required this.onEditAccount,
    required this.onRemoveAccount,
    required this.initialOpenMenuAccountUuid,
  });

  final List<AccountInfo> accounts;
  final int accountCount;
  final int seedAnchorCount;
  final Future<void> Function(String uuid) onSelectAccount;
  final ValueChanged<AccountInfo> onCopyAddress;
  final ValueChanged<AccountInfo> onSendZec;
  final ValueChanged<AccountInfo> onEditAccount;
  final ValueChanged<AccountInfo> onRemoveAccount;
  final String? initialOpenMenuAccountUuid;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: _buildRows(),
    );
  }

  List<Widget> _buildRows() {
    final rows = <Widget>[];
    for (var index = 0; index < accounts.length; index += 1) {
      if (index > 0) {
        rows.add(const SizedBox(height: _accountsRowGap));
      }
      final account = accounts[index];
      rows.add(
        _AccountRow(
          key: ValueKey('accounts_other_row_${account.uuid}'),
          account: account,
          onTap: () {
            onSelectAccount(account.uuid);
          },
          showSendZec: true,
          onCopyAddress: onCopyAddress,
          onSendZec: onSendZec,
          onEditAccount: onEditAccount,
          onRemove: onRemoveAccount,
          showRemove: _AccountsList._canRemoveAccount(
            account,
            accountCount,
            seedAnchorCount,
          ),
          initiallyOpenMenu: initialOpenMenuAccountUuid == account.uuid,
        ),
      );
    }
    return rows;
  }
}

class _AccountsSectionLabel extends StatelessWidget {
  const _AccountsSectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _accountsSectionLabelHeight,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxs),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            label,
            style: AppTypography.labelMedium.copyWith(
              color: context.colors.text.secondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _AccountRow extends StatefulWidget {
  const _AccountRow({
    required this.account,
    required this.onTap,
    required this.showSendZec,
    required this.onCopyAddress,
    required this.onSendZec,
    required this.onEditAccount,
    required this.onRemove,
    required this.showRemove,
    required this.initiallyOpenMenu,
    super.key,
  });

  final AccountInfo account;
  final VoidCallback? onTap;
  final bool showSendZec;
  final ValueChanged<AccountInfo> onCopyAddress;
  final ValueChanged<AccountInfo> onSendZec;
  final ValueChanged<AccountInfo> onEditAccount;
  final ValueChanged<AccountInfo> onRemove;
  final bool showRemove;
  final bool initiallyOpenMenu;

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
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
        decoration: BoxDecoration(
          color: isHighlighted ? _accountsHoverColor(context) : null,
          borderRadius: BorderRadius.circular(AppRadii.small),
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
                      _AccountRowAvatar(account: widget.account),
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
              showSendZec: widget.showSendZec,
              onCopyAddress: () => widget.onCopyAddress(widget.account),
              onSendZec: () => widget.onSendZec(widget.account),
              onEditAccount: () => widget.onEditAccount(widget.account),
              onRemove: () => widget.onRemove(widget.account),
              showRemove: widget.showRemove,
              initiallyOpen: widget.initiallyOpenMenu,
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

    return Text(
      account.name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppTypography.labelLarge.copyWith(color: colors.text.accent),
    );
  }
}

class _AccountRowAvatar extends StatelessWidget {
  const _AccountRowAvatar({required this.account});

  final AccountInfo account;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return SizedBox(
      width: 32,
      height: 32,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AppProfilePicture(
            profilePictureId: account.profilePictureId,
            size: AppProfilePictureSize.large,
          ),
          if (account.isHardware)
            Positioned(
              right: -5,
              bottom: 0,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.background.inverse,
                  // The ring sits OUTSIDE the 16px badge like the Figma
                  // stroke, leaving the full box to the 14px logo.
                  border: Border.all(
                    color: _accountsSurfaceColor(context),
                    width: 2,
                    strokeAlign: BorderSide.strokeAlignOutside,
                  ),
                  borderRadius: BorderRadius.circular(AppSpacing.xxs),
                ),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: Center(
                    child: AppIcon(
                      AppIcons.keystone,
                      size: 14,
                      color: colors.icon.inverse,
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

class _AccountRowMenuButton extends StatefulWidget {
  const _AccountRowMenuButton({
    required this.showSendZec,
    required this.onCopyAddress,
    required this.onSendZec,
    required this.onEditAccount,
    required this.onRemove,
    required this.showRemove,
    required this.initiallyOpen,
    super.key,
  });

  final bool showSendZec;
  final VoidCallback onCopyAddress;
  final VoidCallback onSendZec;
  final VoidCallback onEditAccount;
  final VoidCallback onRemove;
  final bool showRemove;
  final bool initiallyOpen;

  @override
  State<_AccountRowMenuButton> createState() => _AccountRowMenuButtonState();
}

class _AccountRowMenuButtonState extends State<_AccountRowMenuButton> {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _menuEntry;
  bool _isHovered = false;
  bool _openedInitialMenu = false;

  @override
  void initState() {
    super.initState();
    if (widget.initiallyOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _openedInitialMenu || !widget.initiallyOpen) return;
        _openedInitialMenu = true;
        _showMenu();
      });
    }
  }

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
    final appTheme = AppTheme.of(context);
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
              targetAnchor: Alignment.topRight,
              followerAnchor: Alignment.topRight,
              offset: const Offset(0, 22),
              child: AppTheme(
                data: appTheme,
                child: _AccountContextMenu(
                  showSendZec: widget.showSendZec,
                  onCopyAddress: _handleCopyAddress,
                  onSendZec: _handleSendZec,
                  onEditAccount: _handleEditAccount,
                  onRemove: _handleRemove,
                  showRemove: widget.showRemove,
                  onDismiss: () => _hideMenu(),
                ),
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

  void _handleEditAccount() {
    _hideMenu();
    widget.onEditAccount();
  }

  void _handleCopyAddress() {
    _hideMenu();
    widget.onCopyAddress();
  }

  void _handleSendZec() {
    _hideMenu();
    widget.onSendZec();
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
                color: isHighlighted ? _accountsHoverColor(context) : null,
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
    required this.showSendZec,
    required this.onCopyAddress,
    required this.onSendZec,
    required this.onEditAccount,
    required this.onRemove,
    required this.showRemove,
    required this.onDismiss,
  });

  static const _width = 160.0;

  final bool showSendZec;
  final VoidCallback onCopyAddress;
  final VoidCallback onSendZec;
  final VoidCallback onEditAccount;
  final VoidCallback onRemove;
  final bool showRemove;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    // Figma: the current account's menu is Edit account / Copy address;
    // other accounts get Copy address / Send ZEC / Edit account. Remove
    // stays gated by the account-invariant rules rather than the mock,
    // since it is the only path to remove (or reset via) an account.
    return AppContextMenu(
      width: _width,
      children: [
        if (!showSendZec) ...[
          AppContextMenuItem(
            iconName: AppIcons.edit,
            label: 'Edit account',
            onTap: onEditAccount,
          ),
          const SizedBox(height: AppSpacing.xxs),
          AppContextMenuItem(
            iconName: AppIcons.copy,
            label: 'Copy address',
            onTap: onCopyAddress,
          ),
        ] else ...[
          AppContextMenuItem(
            iconName: AppIcons.copy,
            label: 'Copy address',
            onTap: onCopyAddress,
          ),
          const SizedBox(height: AppSpacing.xxs),
          AppContextMenuItem(
            iconName: AppIcons.plane,
            label: 'Send ZEC',
            onTap: onSendZec,
          ),
          const SizedBox(height: AppSpacing.xxs),
          AppContextMenuItem(
            iconName: AppIcons.edit,
            label: 'Edit account',
            onTap: onEditAccount,
          ),
        ],
        if (showRemove) ...[
          const AppContextMenuDivider(),
          AppContextMenuItem(
            iconName: AppIcons.trash,
            label: 'Remove account',
            destructive: true,
            onTap: onRemove,
          ),
        ],
      ],
    );
  }
}

Color _accountsSurfaceColor(BuildContext context) {
  final colors = context.colors;
  return AppTheme.of(context) == AppThemeData.light
      ? colors.background.ground
      : colors.background.base;
}

Color _accountsHoverColor(BuildContext context) {
  final colors = context.colors;
  return AppTheme.of(context) == AppThemeData.light
      ? colors.background.base
      : colors.background.raised;
}
