import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart' show Material, MaterialType, Scaffold;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../main.dart' show log;
import '../../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../../core/layout/mobile/app_mobile_tab_bar.dart';
import '../../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_context_menu.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/app_profile_picture.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/mobile/mobile_account_avatar.dart';
import '../../../../core/widgets/mobile/mobile_list_row.dart';
import '../../../../core/widgets/mobile/mobile_surface_card.dart';
import '../../../../providers/account_provider.dart';
import '../../../../providers/biometric_unlock_provider.dart';
import '../../../../providers/receive_address_provider.dart';
import '../../../../providers/sync_provider.dart';
import '../../../../providers/wallet_mutation_guard.dart';
import '../../widgets/mobile/account_edit_sheets.dart';

/// Mobile account management — Figma `Accounts` / `Accounts Edits` /
/// `Remove` / `PFP Modal` (4514:53389 / 4514:84873 / 4514:85954 /
/// 4514:85279): current and other accounts with a per-row menu for
/// editing (name + profile picture) and removal.
class MobileAccountsScreen extends ConsumerStatefulWidget {
  const MobileAccountsScreen({
    this.initialSheetAccountUuid,
    this.initialSheet,
    super.key,
  });

  final String? initialSheetAccountUuid;
  final MobileAccountsInitialSheet? initialSheet;

  @override
  ConsumerState<MobileAccountsScreen> createState() =>
      _MobileAccountsScreenState();
}

enum MobileAccountsInitialSheet { editAccount, removeAccount }

class _MobileAccountsScreenState extends ConsumerState<MobileAccountsScreen> {
  var _busy = false;
  OverlayEntry? _rowMenuEntry;
  String? _openRowMenuAccountUuid;

  @override
  void initState() {
    super.initState();
    if (widget.initialSheetAccountUuid != null && widget.initialSheet != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showInitialSheet());
    }
  }

  @override
  void dispose() {
    _hideRowMenu(updateState: false);
    super.dispose();
  }

  void _showInitialSheet() {
    if (!mounted) return;
    final accounts = ref.read(accountProvider).value?.accounts ?? const [];
    AccountInfo? account;
    for (final candidate in accounts) {
      if (candidate.uuid == widget.initialSheetAccountUuid) {
        account = candidate;
        break;
      }
    }
    if (account == null) return;
    switch (widget.initialSheet!) {
      case MobileAccountsInitialSheet.editAccount:
        unawaited(_showEditSheet(account));
      case MobileAccountsInitialSheet.removeAccount:
        unawaited(_showRemoveSheet(account));
    }
  }

  /// Mirrors the desktop eligibility rule: the last remaining account
  /// is removable because removal becomes a full app reset.
  bool _canRemove(AccountInfo account, List<AccountInfo> accounts) {
    if (accounts.length == 1) return true;
    if (!account.isSeedAnchor) return true;
    final seedAnchorCount = accounts.where((a) => a.isSeedAnchor).length;
    return seedAnchorCount > 1;
  }

  /// Anchored dark popup at the row's ⋯ button — Figma `Accounts` row
  /// menu: copy address / send ZEC / edit, with removal separated below
  /// a divider when the eligibility rule allows it.
  void _showRowMenu(AccountInfo account, BuildContext anchorContext) {
    if (_rowMenuEntry != null) {
      final wasOpenForAccount = _openRowMenuAccountUuid == account.uuid;
      _hideRowMenu();
      if (wasOpenForAccount) return;
    }

    final accounts = ref.read(accountProvider).value?.accounts ?? const [];
    final canRemove = _canRemove(account, accounts);

    final overlay = Overlay.of(context, rootOverlay: true);
    final overlayRenderObject = overlay.context.findRenderObject();
    final anchorRenderObject = anchorContext.findRenderObject();
    if (overlayRenderObject is! RenderBox || anchorRenderObject is! RenderBox) {
      return;
    }

    final anchorTopLeft = anchorRenderObject.localToGlobal(
      Offset.zero,
      ancestor: overlayRenderObject,
    );
    final anchorRect = anchorTopLeft & anchorRenderObject.size;
    final overlaySize = overlayRenderObject.size;
    const menuWidth = 173.0;
    const menuPadding = EdgeInsets.symmetric(
      horizontal: AppSpacing.xxs,
      vertical: AppSpacing.sm,
    );
    final menuHeight = canRemove ? 173.0 : 126.0;
    const bottomNavClearance = kMobileTabBarHeight + AppSpacing.lg;
    final colors = context.colors;
    final menuMaxTop = math.max(
      AppSpacing.sm,
      overlaySize.height - bottomNavClearance - menuHeight,
    );
    final menuTop = (anchorRect.top + 34).clamp(AppSpacing.sm, menuMaxTop);
    final menuRight =
        (overlaySize.width - anchorRect.right).clamp(
              AppSpacing.sm,
              math.max(
                AppSpacing.sm,
                overlaySize.width - menuWidth - AppSpacing.sm,
              ),
            )
            as double;

    void select(_AccountAction action) {
      _hideRowMenu();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        switch (action) {
          case _AccountAction.copy:
            unawaited(_copyAddress(account));
          case _AccountAction.send:
            unawaited(_sendToAccount(account));
          case _AccountAction.edit:
            unawaited(_showEditSheet(account));
          case _AccountAction.remove:
            unawaited(_showRemoveSheet(account));
        }
      });
    }

    Widget item({
      required Key key,
      required String iconName,
      required String label,
      required _AccountAction action,
      Color? textColor,
      Color? iconColor,
    }) {
      final itemTextColor = textColor ?? colors.text.inverse;
      final itemIconColor = iconColor ?? colors.icon.inverse;
      return Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: GestureDetector(
          key: key,
          behavior: HitTestBehavior.opaque,
          onTap: () => select(action),
          child: Container(
            height: 26,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xs,
              vertical: AppSpacing.xxs,
            ),
            child: Row(
              children: [
                AppIcon(
                  iconName,
                  size: AppIconSize.medium,
                  color: itemIconColor,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.labelLarge.copyWith(
                      color: itemTextColor,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final menuItems = [
      item(
        key: const ValueKey('mobile_account_menu_copy'),
        iconName: AppIcons.copy,
        label: 'Copy address',
        action: _AccountAction.copy,
      ),
      item(
        key: const ValueKey('mobile_account_menu_send'),
        iconName: AppIcons.plane,
        label: 'Send ZEC',
        action: _AccountAction.send,
      ),
      item(
        key: const ValueKey('mobile_account_menu_edit'),
        iconName: AppIcons.edit,
        label: 'Edit account',
        action: _AccountAction.edit,
      ),
      if (canRemove) ...[
        const AppContextMenuDivider(),
        item(
          key: const ValueKey('mobile_account_menu_remove'),
          iconName: AppIcons.trash,
          label: 'Remove account',
          action: _AccountAction.remove,
          textColor: colors.text.destructiveLight,
          iconColor: colors.icon.destructiveLight,
        ),
      ],
    ];

    final entry = OverlayEntry(
      builder: (_) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _hideRowMenu,
              child: const SizedBox.expand(),
            ),
          ),
          Positioned(
            top: menuTop,
            right: menuRight,
            // Material ancestor: root overlays have none, and Text
            // would otherwise fall back to the debug underline style.
            child: Material(
              type: MaterialType.transparency,
              child: DefaultTextStyle.merge(
                style: const TextStyle(decoration: TextDecoration.none),
                child: SizedBox(
                  key: const ValueKey('mobile_account_menu_card'),
                  width: menuWidth,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.background.inverse,
                      borderRadius: BorderRadius.circular(AppRadii.medium),
                      border: Border.all(color: colors.border.inverseOpacity),
                      boxShadow: appContextMenuShadow,
                    ),
                    child: Padding(
                      padding: menuPadding,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var i = 0; i < menuItems.length; i++) ...[
                            if (i > 0) const SizedBox(height: AppSpacing.xs),
                            menuItems[i],
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    _rowMenuEntry = entry;
    setState(() => _openRowMenuAccountUuid = account.uuid);
    overlay.insert(entry);
  }

  void _hideRowMenu({bool updateState = true}) {
    final entry = _rowMenuEntry;
    if (entry == null) return;
    _rowMenuEntry = null;
    if (updateState && mounted) {
      setState(() => _openRowMenuAccountUuid = null);
    } else {
      _openRowMenuAccountUuid = null;
    }
    entry.remove();
  }

  Future<String?> _loadShieldedAddress(AccountInfo account) async {
    final accountState = ref.read(accountProvider).value;
    final currentShieldedAddress =
        accountState?.activeAccountUuid == account.uuid
        ? accountState?.activeAddress
        : null;
    try {
      final address = await ref
          .read(receiveAddressServiceProvider)
          .loadShieldedAddress(
            accountUuid: account.uuid,
            currentShieldedAddress: currentShieldedAddress,
          );
      return address.trim().isEmpty ? null : address;
    } catch (e) {
      log('MobileAccounts: shielded address load failed: $e');
      return null;
    }
  }

  Future<void> _copyAddress(AccountInfo account) async {
    final address = await _loadShieldedAddress(account);
    if (!mounted) return;
    if (address == null) {
      showAppToast(
        context,
        "Address couldn't be copied",
        iconName: AppIcons.cross,
      );
      return;
    }
    await Clipboard.setData(ClipboardData(text: address));
    if (mounted) showAppToast(context, 'Shielded address copied');
  }

  Future<void> _sendToAccount(AccountInfo account) async {
    final address = await _loadShieldedAddress(account);
    if (!mounted) return;
    if (address == null) {
      showAppToast(
        context,
        "Couldn't load the account address",
        iconName: AppIcons.cross,
      );
      return;
    }
    context.push('/send', extra: address);
  }

  Future<void> _showEditSheet(AccountInfo account) async {
    final result = await showAccountEditSheet(context, account: account);
    if (result == null || !mounted) return;

    setState(() => _busy = true);
    final saved = await applyAccountEdits(ref, account, result);
    if (mounted) {
      if (!saved) {
        showAppToast(
          context,
          "Couldn't save the account changes",
          iconName: AppIcons.cross,
        );
      }
      setState(() => _busy = false);
    }
  }

  Future<void> _showRemoveSheet(AccountInfo account) async {
    final accounts = ref.read(accountProvider).value?.accounts ?? const [];
    final isLastAccount = accounts.length == 1;
    final confirmed = await showAppMobileSheet<bool>(
      context: context,
      builder: (_) =>
          _RemoveAccountSheet(account: account, isLastAccount: isLastAccount),
    );
    if (confirmed != true || !mounted) return;

    final router = GoRouter.of(context);
    setState(() => _busy = true);
    final accountNotifier = ref.read(accountProvider.notifier);
    final syncNotifier = ref.read(syncProvider.notifier);
    try {
      if (isLastAccount) {
        await runWithSyncPausedForAccountMutation(ref, () async {
          await accountNotifier.resetWallet();
          syncNotifier.clearCachedWalletDbPath();
          try {
            await ref.read(biometricUnlockProvider.notifier).disable();
          } catch (e, st) {
            log(
              'MobileAccounts: biometric cleanup after reset failed: $e\n$st',
            );
          }
        }, resumeAfterMutation: false);
        if (!mounted) return;
        router.go('/welcome');
      } else {
        await runWithSyncPausedForAccountMutation(
          ref,
          () => accountNotifier.removeAccount(account.uuid),
        );
        await syncNotifier.refreshAfterSend();
      }
    } catch (e, st) {
      log('MobileAccounts: remove failed: $e\n$st');
      if (mounted) {
        showAppToast(
          context,
          isLastAccount
              ? "Couldn't reset Vizor"
              : "Couldn't remove the account",
          iconName: AppIcons.cross,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final state = ref.watch(accountProvider).value;
    final accounts = state?.accounts ?? const <AccountInfo>[];
    final active = state?.activeAccount;
    final others = [
      for (final account in accounts)
        if (account.uuid != active?.uuid) account,
    ];

    return Scaffold(
      backgroundColor: colors.background.window,
      body: AppToastHost(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              MobileTopNav.back(
                title: 'Accounts',
                titleStyle: AppTypography.headlineLarge,
                onBack: _busy ? null : () => context.pop(),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.sm,
                    AppSpacing.s,
                    AppSpacing.sm,
                    kMobileTabBarHeight + AppSpacing.lg,
                  ),
                  children: [
                    if (active != null)
                      _AccountsGroupCard(
                        title: 'Current',
                        titleGap: AppSpacing.s,
                        children: [_accountRow(active, enabled: !_busy)],
                      ),
                    if (others.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.sm),
                      _AccountsGroupCard(
                        title: 'Other',
                        titleGap: AppSpacing.xs,
                        children: [
                          for (final account in others)
                            _accountRow(account, enabled: !_busy),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _accountRow(AccountInfo account, {required bool enabled}) {
    final colors = context.colors;
    final menuOpen = _openRowMenuAccountUuid == account.uuid;
    return MobileListRow(
      key: ValueKey('mobile_accounts_row_${account.uuid}'),
      leading: MobileAccountAvatar(
        profilePictureId: account.profilePictureId,
        size: AppProfilePictureSize.navLarge,
        isHardware: account.isHardware,
        badgeRingColor: colors.background.ground,
        badgeBorderWidth: 3,
        badgeRight: -5,
        badgeBottom: 0,
      ),
      label: account.name,
      minRowHeight: 44,
      textStyle: AppTypography.labelLarge,
      trailing: Builder(
        builder: (anchorContext) => Semantics(
          button: true,
          label: 'Account options for ${account.name}',
          excludeSemantics: true,
          child: GestureDetector(
            key: ValueKey('mobile_accounts_menu_${account.uuid}'),
            behavior: HitTestBehavior.opaque,
            onTap: enabled ? () => _showRowMenu(account, anchorContext) : null,
            child: SizedBox(
              width: 44,
              height: 44,
              child: Center(
                child: DecoratedBox(
                  key: ValueKey('mobile_accounts_menu_button_${account.uuid}'),
                  decoration: BoxDecoration(
                    color: menuOpen
                        ? colors.state.hover
                        : const Color(0x00000000),
                    borderRadius: BorderRadius.circular(AppRadii.xSmall),
                  ),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: Center(
                      child: Transform.rotate(
                        angle: -math.pi / 2,
                        child: AppIcon(
                          AppIcons.options,
                          size: AppIconSize.medium,
                          color: colors.icon.accent,
                        ),
                      ),
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

enum _AccountAction { copy, send, edit, remove }

class _AccountsGroupCard extends StatelessWidget {
  const _AccountsGroupCard({
    required this.title,
    required this.titleGap,
    required this.children,
  });

  final String title;
  final double titleGap;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return MobileSurfaceCard(
      cornerRadius: AppRadii.large,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.base,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.xxs),
            child: Text(
              title,
              style: AppTypography.labelLarge.copyWith(
                color: context.colors.text.secondary,
              ),
            ),
          ),
          SizedBox(height: titleGap),
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.s),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// Figma `Remove` (4514:85954): compact destructive confirmation sheet.
class _RemoveAccountSheet extends StatelessWidget {
  const _RemoveAccountSheet({
    required this.account,
    required this.isLastAccount,
  });

  final AccountInfo account;
  final bool isLastAccount;

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
  static const _buttonLabelStyle = TextStyle(
    fontFamily: 'Geist',
    fontWeight: FontWeight.w500,
    fontSize: 14,
    height: 16 / 14,
    letterSpacing: -0.06,
  );

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return MobileModalScaffold(
      title: 'Remove account',
      onClose: () => Navigator.of(context).pop(false),
      leading: MobileAccountAvatar(
        profilePictureId: account.profilePictureId,
        size: AppProfilePictureSize.large,
        isHardware: account.isHardware,
      ),
      titleStyle: _titleStyle.copyWith(color: colors.text.accent),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            isLastAccount
                ? 'Removing this account will completely reset the Vizor app. '
                      'This means deleting all accounts and requiring you to '
                      'import accounts again.\n'
                      'This cannot be undone.'
                : "Are you sure you want to remove this account? This action "
                      "can't be reverted.\n"
                      'You will have to re-import your account.',
            style: _bodyStyle.copyWith(color: colors.text.accent),
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton(
            key: const ValueKey('mobile_account_remove_confirm'),
            variant: AppButtonVariant.destructive,
            expand: true,
            onPressed: () => Navigator.of(context).pop(true),
            leading: isLastAccount ? null : const AppIcon(AppIcons.trash),
            child: Text(
              isLastAccount ? 'Reset Vizor' : 'Remove',
              style: _buttonLabelStyle.copyWith(
                color: colors.button.destructive.label,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s),
          MobileSheetCancel(
            onTap: () => Navigator.of(context).pop(false),
            textStyle: _buttonLabelStyle.copyWith(
              color: colors.button.ghost.label,
            ),
          ),
        ],
      ),
    );
  }
}
