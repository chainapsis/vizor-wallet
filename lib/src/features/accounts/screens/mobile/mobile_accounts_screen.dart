import 'dart:async';

import 'package:flutter/material.dart'
    show Material, MaterialType, Scaffold, showGeneralDialog;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../main.dart' show log;
import '../../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../../core/layout/mobile/mobile_bottom_safe_area.dart';
import '../../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/app_profile_picture.dart';
import '../../../../core/widgets/mobile/mobile_account_avatar.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/mobile/mobile_list_row.dart';
import '../../../../core/widgets/mobile/mobile_surface_card.dart';
import '../../../../providers/account_provider.dart';
import '../../../../providers/receive_address_provider.dart';
import '../../../../providers/sync_provider.dart';
import '../../../../providers/wallet_mutation_guard.dart';
import '../../widgets/mobile/account_edit_sheets.dart';

/// Mobile account management — Figma `Accounts` / `Accounts Edits` /
/// `Remove` / `PFP Modal` (4514:53389 / 4514:84873 / 4514:85954 /
/// 4514:85279): current and other accounts with a per-row menu for
/// editing (name + profile picture) and removal.
class MobileAccountsScreen extends ConsumerStatefulWidget {
  const MobileAccountsScreen({super.key});

  @override
  ConsumerState<MobileAccountsScreen> createState() =>
      _MobileAccountsScreenState();
}

class _MobileAccountsScreenState extends ConsumerState<MobileAccountsScreen> {
  var _busy = false;

  /// Mirrors the desktop eligibility rule, except the last remaining
  /// account: on mobile that is a full app reset, which lives behind
  /// the unlock screen's forgot-passcode path instead of this menu.
  bool _canRemove(AccountInfo account, List<AccountInfo> accounts) {
    if (accounts.length <= 1) return false;
    if (!account.isSeedAnchor) return true;
    final seedAnchorCount = accounts.where((a) => a.isSeedAnchor).length;
    return seedAnchorCount > 1;
  }

  /// Anchored dark popup at the row's ⋯ button — Figma `Accounts` row
  /// menu: copy address / send ZEC / edit, with removal separated below
  /// a divider when the eligibility rule allows it.
  Future<void> _showRowMenu(
    AccountInfo account,
    BuildContext anchorContext,
  ) async {
    final accounts = ref.read(accountProvider).value?.accounts ?? const [];
    final canRemove = _canRemove(account, accounts);

    final anchorBox = anchorContext.findRenderObject()! as RenderBox;
    final anchorRect = anchorBox.localToGlobal(Offset.zero) & anchorBox.size;
    final screen = MediaQuery.sizeOf(context);

    final action = await showGeneralDialog<_AccountAction>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: true,
      barrierLabel: 'Dismiss menu',
      barrierColor: const Color(0x00000000),
      transitionDuration: const Duration(milliseconds: 120),
      transitionBuilder: (_, animation, _, child) =>
          Opacity(opacity: animation.value, child: child),
      pageBuilder: (dialogContext, _, _) {
        final colors = dialogContext.colors;
        final menuTop = anchorRect.bottom + AppSpacing.xxs;

        Widget item({
          required Key key,
          required String iconName,
          required String label,
          required _AccountAction action,
          Color? color,
        }) {
          final tint = color ?? colors.text.homeCard;
          return Semantics(
            button: true,
            label: label,
            excludeSemantics: true,
            child: GestureDetector(
              key: key,
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(dialogContext).pop(action),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.s,
                ),
                child: Row(
                  children: [
                    AppIcon(iconName, size: AppIconSize.medium, color: tint),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.labelMedium.copyWith(color: tint),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return Stack(
          children: [
            Positioned(
              top: menuTop.clamp(0.0, screen.height - 240),
              right: (screen.width - anchorRect.right).clamp(
                AppSpacing.sm,
                screen.width,
              ),
              // Material ancestor: bare dialog routes have none, and
              // Text would fall back to the debug underline style.
              child: Material(
                type: MaterialType.transparency,
                child: Container(
                  width: 220,
                  decoration: BoxDecoration(
                    color: colors.background.homeCard,
                    borderRadius: BorderRadius.circular(AppRadii.large),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
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
                        Container(
                          height: 1,
                          margin: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm,
                          ),
                          color: colors.text.homeCard.withValues(alpha: 0.15),
                        ),
                        item(
                          key: const ValueKey('mobile_account_menu_remove'),
                          iconName: AppIcons.trash,
                          label: 'Remove account',
                          action: _AccountAction.remove,
                          color: colors.text.destructive,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
    if (!mounted) return;
    switch (action) {
      case _AccountAction.copy:
        await _copyAddress(account);
      case _AccountAction.send:
        await _sendToAccount(account);
      case _AccountAction.edit:
        await _showEditSheet(account);
      case _AccountAction.remove:
        await _showRemoveSheet(account);
      case null:
        break;
    }
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
    final confirmed = await showAppMobileSheet<bool>(
      context: context,
      builder: (_) => _RemoveAccountSheet(account: account),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    final accountNotifier = ref.read(accountProvider.notifier);
    final syncNotifier = ref.read(syncProvider.notifier);
    try {
      await runWithSyncPausedForAccountMutation(
        ref,
        () => accountNotifier.removeAccount(account.uuid),
      );
      await syncNotifier.refreshAfterSend();
    } catch (e, st) {
      log('MobileAccounts: remove failed: $e\n$st');
      if (mounted) {
        showAppToast(
          context,
          "Couldn't remove the account",
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
          child: Column(
            children: [
              MobileTopNav.back(
                title: 'Accounts',
                onBack: _busy ? null : () => context.pop(),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.sm,
                    AppSpacing.s,
                    AppSpacing.sm,
                    AppSpacing.lg,
                  ),
                  children: [
                    if (active != null)
                      _AccountsGroupCard(
                        title: 'Current',
                        children: [_accountRow(active, enabled: !_busy)],
                      ),
                    if (others.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.sm),
                      _AccountsGroupCard(
                        title: 'Other',
                        children: [
                          for (final account in others)
                            _accountRow(account, enabled: !_busy),
                        ],
                      ),
                    ],
                    // VZR-73: the page-level add affordance, mirroring
                    // the accounts sheet and the desktop accounts page.
                    const SizedBox(height: AppSpacing.sm),
                    AppButton(
                      key: const ValueKey('mobile_accounts_add_account'),
                      variant: AppButtonVariant.secondary,
                      expand: true,
                      onPressed: _busy
                          ? null
                          : () => context.push('/add-account'),
                      leading: const AppIcon(AppIcons.addNew),
                      child: const Text('Add account'),
                    ),
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
    return MobileListRow(
      key: ValueKey('mobile_accounts_row_${account.uuid}'),
      leading: MobileAccountAvatar(
        profilePictureId: account.profilePictureId,
        size: AppProfilePictureSize.large,
        isHardware: account.isHardware,
      ),
      label: account.name,
      trailing: Builder(
        builder: (anchorContext) => Semantics(
          button: true,
          label: 'Account options for ${account.name}',
          excludeSemantics: true,
          child: GestureDetector(
            key: ValueKey('mobile_accounts_menu_${account.uuid}'),
            behavior: HitTestBehavior.opaque,
            onTap: enabled
                ? () => unawaited(_showRowMenu(account, anchorContext))
                : null,
            child: SizedBox(
              width: 44,
              height: 44,
              child: Center(
                child: Text(
                  '⋯',
                  style: AppTypography.headlineSmall.copyWith(
                    color: context.colors.text.secondary,
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
  const _AccountsGroupCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return MobileSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(
              left: AppSpacing.xxs,
              bottom: AppSpacing.xs,
            ),
            child: Text(
              title,
              style: AppTypography.labelMedium.copyWith(
                color: context.colors.text.secondary,
              ),
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

/// Figma `Accounts Edits` (4514:84873): avatar with the pencil overlay
/// opening the picture picker, the name field, and Save Edits.
class _RemoveAccountSheet extends StatelessWidget {
  const _RemoveAccountSheet({required this.account});

  final AccountInfo account;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return MobileBottomSafeArea(
      bottomPadding: AppSpacing.md,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                MobileAccountAvatar(
                  profilePictureId: account.profilePictureId,
                  size: AppProfilePictureSize.large,
                  isHardware: account.isHardware,
                ),
                const SizedBox(width: AppSpacing.s),
                Expanded(
                  child: Text(
                    'Remove account',
                    style: AppTypography.headlineSmall.copyWith(
                      color: colors.text.accent,
                    ),
                  ),
                ),
                MobileSheetClose(onTap: () => Navigator.of(context).pop(false)),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              "Are you sure you want to remove this account? This action "
              "can't be reverted. You will have to re-import your account.",
              style: AppTypography.bodyMedium.copyWith(
                color: colors.text.primary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            AppButton(
              key: const ValueKey('mobile_account_remove_confirm'),
              variant: AppButtonVariant.destructive,
              expand: true,
              onPressed: () => Navigator.of(context).pop(true),
              leading: const AppIcon(AppIcons.trash),
              child: const Text('Remove'),
            ),
            const SizedBox(height: AppSpacing.s),
            MobileSheetCancel(onTap: () => Navigator.of(context).pop(false)),
          ],
        ),
      ),
    );
  }
}

/// Circled X dismiss control in the sheet's top-right corner.