import '../../../../core/l10n/l10n.dart';
import '../../../../core/navigation/mobile_sidebar_exit.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart' show Material, MaterialType, Scaffold;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../main.dart' show log;
import '../../../../core/feedback/app_haptics.dart';
import '../../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../../core/layout/mobile/mobile_sticky_bottom_action.dart';
import '../../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_context_menu.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/app_profile_picture.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/mobile/mobile_account_avatar.dart';
import '../../../../core/widgets/mobile/mobile_list_row.dart';
import '../../../../core/widgets/mobile/mobile_section.dart';
import '../../../../providers/account_provider.dart';
import '../../../../providers/biometric_unlock_provider.dart';
import '../../../../providers/mobile_account_visibility_provider.dart';
import '../../../../providers/receive_address_provider.dart';
import '../../../../providers/sync_provider.dart';
import '../../../../providers/wallet_mutation_guard.dart';
import '../../../migration/models/ironwood_migration_phases.dart';
import '../../../migration/providers/ironwood_migration_coordinator_provider.dart';
import '../../../payment_links/services/payment_link_received_store.dart';
import '../../../payment_links/services/payment_link_recovery_reconciler.dart';
import '../../../payment_links/services/payment_link_recovery_store.dart';
import '../../widgets/mobile/account_edit_sheets.dart';

/// Mobile account management — Figma `Accounts` / `Accounts Edits` /
/// `Remove` / `PFP Modal` (4514:53389 / 4514:84873 / 4514:85954 /
/// 4514:85279): current and other accounts with a per-row menu for
/// editing (name + profile picture) and removal.
class MobileAccountsScreen extends ConsumerStatefulWidget {
  const MobileAccountsScreen({
    this.initialSheetAccountUuid,
    this.initialSheet,
    this.initialOpenMenuAccountUuid,
    super.key,
  });

  final String? initialSheetAccountUuid;
  final MobileAccountsInitialSheet? initialSheet;
  final String? initialOpenMenuAccountUuid;

  @override
  ConsumerState<MobileAccountsScreen> createState() =>
      _MobileAccountsScreenState();
}

enum MobileAccountsInitialSheet { editAccount, removeAccount }

class _MobileAccountsScreenState extends ConsumerState<MobileAccountsScreen> {
  var _busy = false;
  OverlayEntry? _rowMenuEntry;
  String? _openRowMenuAccountUuid;
  var _didOpenInitialRowMenu = false;

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
    final accounts = ref.read(visibleAccountsProvider);
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

  // With one ordinary account, offer the same explicit wallet reset whether
  // or not other accounts exist. A private view must retain at least one
  // linked account until the user removes that passcode.
  bool _canRemoveOrReset(AccountInfo account, List<AccountInfo> accounts) =>
      accounts.any((candidate) => candidate.uuid == account.uuid) &&
      (accounts.length > 1 || ref.read(mobileAccountScopeProvider) == null);

  /// Anchored dark popup at the row's ⋯ button — Figma `Accounts` row
  /// menu: secret passphrase (software only) / viewing key / copy address /
  /// send ZEC / edit, with removal separated below a divider when the
  /// eligibility rule allows it.
  void _showRowMenu(AccountInfo account, BuildContext anchorContext) {
    if (_rowMenuEntry != null) {
      final wasOpenForAccount = _openRowMenuAccountUuid == account.uuid;
      _hideRowMenu();
      if (wasOpenForAccount) return;
    }

    final accountState = ref.read(accountProvider).value;
    final accounts = ref.read(visibleAccountsProvider);
    final isCurrentAccount = accountState?.activeAccountUuid == account.uuid;
    final canRemove = _canRemoveOrReset(account, accounts);

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
    const menuWidth = 208.0;
    const menuPadding = EdgeInsets.symmetric(
      horizontal: AppSpacing.xxs,
      vertical: AppSpacing.sm,
    );
    final baseMenuHeight = switch ((isCurrentAccount, canRemove)) {
      (true, true) => 139.0,
      (true, false) => 92.0,
      (false, true) => 173.0,
      (false, false) => 126.0,
    };
    // The viewing-key row is always shown (unlike the secret-passphrase
    // row, a UFVK never grants spend authority, so hardware accounts get
    // it too); each extra row costs the same fixed 34 (26 item + 8 gap).
    final menuHeight = baseMenuHeight + 34 + (account.isHardware ? 0 : 34);
    // The screen covers the tab bar, so the menu only clears the home
    // indicator.
    final bottomClearance =
        MediaQuery.paddingOf(context).bottom + AppSpacing.lg;
    final colors = context.colors;
    final appTheme = AppTheme.of(context);
    final menuMaxTop = math.max(
      AppSpacing.sm,
      overlaySize.height - bottomClearance - menuHeight,
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
          case _AccountAction.viewSecretPassphrase:
            context.push('/settings/seed-phrase', extra: account.uuid);
          case _AccountAction.viewViewingKey:
            context.push('/settings/viewing-key', extra: account.uuid);
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
                    softWrap: false,
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
      if (!account.isHardware)
        item(
          key: const ValueKey('mobile_account_menu_secret_passphrase'),
          iconName: AppIcons.key,
          label: context.l10n.accountsViewSecretPhrase,
          action: _AccountAction.viewSecretPassphrase,
        ),
      item(
        key: const ValueKey('mobile_account_menu_viewing_key'),
        iconName: AppIcons.eye,
        label: context.l10n.accountsViewViewingKey,
        action: _AccountAction.viewViewingKey,
      ),
      item(
        key: const ValueKey('mobile_account_menu_copy'),
        iconName: AppIcons.copy,
        label: context.l10n.commonCopyAddress,
        action: _AccountAction.copy,
      ),
      if (!isCurrentAccount)
        item(
          key: const ValueKey('mobile_account_menu_send'),
          iconName: AppIcons.plane,
          label: context.l10n.commonSendZec,
          action: _AccountAction.send,
        ),
      item(
        key: const ValueKey('mobile_account_menu_edit'),
        iconName: AppIcons.edit,
        label: context.l10n.accountsEdit,
        action: _AccountAction.edit,
      ),
      if (canRemove) ...[
        const AppContextMenuDivider(),
        item(
          key: const ValueKey('mobile_account_menu_remove'),
          iconName: AppIcons.trash,
          label: accounts.length == 1
              ? context.l10n.commonResetVizor
              : context.l10n.accountsRemove,
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
            child: AppTheme(
              data: appTheme,
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

  void _openInitialRowMenuIfNeeded(
    AccountInfo account,
    BuildContext anchorContext,
  ) {
    if (_didOpenInitialRowMenu ||
        widget.initialOpenMenuAccountUuid != account.uuid) {
      return;
    }
    _didOpenInitialRowMenu = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showRowMenu(account, anchorContext);
    });
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
        context.l10n.sidebarAddressCopyFailed,
        iconName: AppIcons.cross,
      );
      return;
    }
    await Clipboard.setData(ClipboardData(text: address));
    unawaited(AppHaptics.copy());
    if (mounted) {
      showAppToast(context, context.l10n.sidebarShieldedAddressCopied);
    }
  }

  Future<void> _sendToAccount(AccountInfo account) async {
    final address = await _loadShieldedAddress(account);
    if (!mounted) return;
    if (address == null) {
      showAppToast(
        context,
        context.l10n.accountsAddressLoadFailed,
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
          context.l10n.accountsSaveFailed,
          iconName: AppIcons.cross,
        );
      }
      setState(() => _busy = false);
    }
  }

  /// [recheckFailed] reopens the sheet after a failed post-drain recheck: it
  /// shows the "couldn't check" warning and the next attempt skips the recheck.
  Future<void> _showRemoveSheet(
    AccountInfo account, {
    bool recheckFailed = false,
  }) async {
    final accounts = ref.read(visibleAccountsProvider);
    if (!_canRemoveOrReset(account, accounts)) return;
    final isLastAccount = accounts.length == 1;
    final migrationStatus = ref
        .read(ironwoodMigrationCoordinatorProvider)
        .statuses[account.uuid];
    final hasActiveMigration =
        migrationStatus != null &&
        (migrationStatus.activeRunId != null ||
            isIronwoodMigrationInProgressPhase(migrationStatus.phase));
    int? unsharedGiftCardCount;
    if (!recheckFailed) {
      try {
        unsharedGiftCardCount = await ref.read(
          paymentLinkUnsharedFundedCountProvider(account.uuid).future,
        );
      } catch (e, st) {
        log('MobileAccounts: unshared gift card count failed: $e\n$st');
      }
    }
    if (!mounted) return;
    final confirmed = await showAppMobileSheet<bool>(
      context: context,
      builder: (_) => MobileAccountRemovalSheet(
        account: account,
        isLastAccount: isLastAccount,
        hasActiveMigration: hasActiveMigration,
        unsharedGiftCardCount: unsharedGiftCardCount,
      ),
    );
    if (confirmed != true || !mounted) return;
    final authenticated = await context.push<bool>(
      '/accounts/confirm-removal',
      extra: isLastAccount,
    );
    if (authenticated != true || !mounted) return;
    final visible = ref.read(visibleAccountsProvider);
    if (!_canRemoveOrReset(account, visible) ||
        (visible.length == 1) != isLastAccount) {
      return;
    }

    final router = GoRouter.of(context);
    setState(() => _busy = true);
    final accountNotifier = ref.read(accountProvider.notifier);
    final syncNotifier = ref.read(syncProvider.notifier);
    final activeAccountBeforeRemoval = ref
        .read(accountProvider)
        .value
        ?.activeAccountUuid;
    UnsharedGiftCardsChangedException? reconfirm;
    try {
      if (isLastAccount) {
        // runWithSyncPausedForWalletReset clears the cached DB path in its
        // finally (so a reset that throws after deleting the DB can't strand a
        // stale path) and applies the WalletResetException.dbDeleted resume
        // guard. The escrow drop stays on the success path.
        await runWithSyncPausedForWalletReset(ref, () async {
          await accountNotifier.resetWallet(
            confirmedUnsharedGiftCardCount: unsharedGiftCardCount,
          );
          try {
            await ref.read(biometricUnlockProvider.notifier).disable();
          } catch (e, st) {
            log(
              'MobileAccounts: biometric cleanup after reset failed: $e\n$st',
            );
          }
        });
        if (!mounted) return;
        router.go('/welcome');
      } else {
        await runWithSyncPausedForAccountMutation(
          ref,
          () => accountNotifier.removeAccount(
            account.uuid,
            confirmedUnsharedGiftCardCount: unsharedGiftCardCount,
          ),
          quiesceVotingWork: true,
        );
        final activeAccountAfterRemoval = ref
            .read(accountProvider)
            .value
            ?.activeAccountUuid;
        if (activeAccountBeforeRemoval != activeAccountAfterRemoval) {
          await syncNotifier.refreshAfterAccountSwitch();
        } else {
          await syncNotifier.refreshAfterSend();
        }
      }
    } on UnsharedGiftCardsChangedException catch (e) {
      log('MobileAccounts: remove needs reconfirmation: ${e.count}');
      reconfirm = e;
    } catch (e, st) {
      log('MobileAccounts: remove failed: $e\n$st');
      if (mounted) {
        showAppToast(context, switch (e) {
          PaymentLinkInFlightClaimsException() =>
            context.l10n.accountsRemoveWaitForGiftCards,
          WalletResetInFlightGiftCardClaimsException() =>
            context.l10n.walletResetGiftCardInFlight,
          _ when isLastAccount => context.l10n.accountsResetFailedToast,
          _ => context.l10n.accountsRemoveFailedToast,
        }, iconName: AppIcons.cross);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (reconfirm != null && mounted) {
      // Show the confirmation again with the fresh count.
      ref.invalidate(paymentLinkUnsharedFundedCountProvider(account.uuid));
      await _showRemoveSheet(account, recheckFailed: reconfirm.count == null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final state = ref.watch(accountProvider).value;
    final accounts = ref.watch(visibleAccountsProvider);
    final active = accounts
        .where((account) => account.uuid == state?.activeAccountUuid)
        .firstOrNull;
    final others = [
      for (final account in accounts)
        if (account.uuid != active?.uuid) account,
    ];

    return MobileSidebarExitScope(
      canNavigate: !_busy,
      canSwitchAccount: !_busy,
      child: Scaffold(
        backgroundColor: colors.background.window,
        body: AppToastHost(
          child: SafeArea(
            bottom: false,
            child: Column(
              children: [
                MobileTopNav.back(
                  title: context.l10n.accountsTitle,
                  // Reached with go() when a viewing-key target account is
                  // gone; then there is no page underneath to return to.
                  onBack: _busy
                      ? null
                      : () {
                          if (context.canPop()) {
                            context.pop();
                          } else {
                            context.go('/home');
                          }
                        },
                ),
                Expanded(
                  // Add account stays in reach however long the list grows,
                  // floating over it like the tab bar.
                  child: MobileStickyBottomAction(
                    action: AppButton(
                      key: const ValueKey('mobile_accounts_add_account'),
                      expand: true,
                      constrainContent: true,
                      onPressed:
                          _busy || ref.watch(mobileAccountScopeProvider) != null
                          ? null
                          : () => context.push('/add-account'),
                      leading: const AppIcon(AppIcons.addNew),
                      child: Text(context.l10n.commonAddAccount),
                    ),
                    child: ListView(
                      padding: EdgeInsets.fromLTRB(
                        kMobilePageMargin,
                        AppSpacing.s,
                        kMobilePageMargin,
                        MobileStickyBottomAction.contentInset(context),
                      ),
                      children: [
                        // Titled lists in the Settings style: the label above
                        // its card, rows split by hairlines.
                        if (active != null)
                          MobileSection(
                            title: context.l10n.accountsCurrent,
                            child: MobileSectionRows(
                              rows: [_accountRow(active, enabled: !_busy)],
                            ),
                          ),
                        if (others.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.md),
                          MobileSection(
                            title: context.l10n.accountsOther,
                            child: MobileSectionRows(
                              rows: [
                                for (final account in others)
                                  _accountRow(account, enabled: !_busy),
                              ],
                            ),
                          ),
                        ],
                      ],
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

  Widget _accountRow(AccountInfo account, {required bool enabled}) {
    final colors = context.colors;
    final menuOpen = _openRowMenuAccountUuid == account.uuid;
    return MobileListRow(
      key: ValueKey('mobile_accounts_row_${account.uuid}'),
      leading: MobileAccountAvatar(
        profilePictureId: account.profilePictureId,
        size: AppProfilePictureSize.navLarge,
        hardwareSignerKind: account.hardwareSignerKind,
        badgeRingColor: colors.background.ground,
        badgeBorderWidth: 3,
        badgeRight: -5,
        badgeBottom: 0,
      ),
      label: account.name,
      minRowHeight: _accountRowHeight,
      textStyle: AppTypography.labelLarge,
      trailing: Builder(
        builder: (anchorContext) {
          _openInitialRowMenuIfNeeded(account, anchorContext);
          return Semantics(
            button: true,
            label: context.l10n.accountsOptionsFor(account.name),
            excludeSemantics: true,
            child: GestureDetector(
              key: ValueKey('mobile_accounts_menu_${account.uuid}'),
              behavior: HitTestBehavior.opaque,
              onTap: enabled
                  ? () => _showRowMenu(account, anchorContext)
                  : null,
              child: SizedBox(
                width: 44,
                height: 44,
                child: Center(
                  child: DecoratedBox(
                    key: ValueKey(
                      'mobile_accounts_menu_button_${account.uuid}',
                    ),
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
          );
        },
      ),
    );
  }
}

enum _AccountAction {
  viewSecretPassphrase,
  viewViewingKey,
  copy,
  send,
  edit,
  remove,
}

/// Account rows match the Settings list rows.
const _accountRowHeight = 60.0;

/// Figma `Remove` (4514:85954): compact destructive confirmation sheet.
class MobileAccountRemovalSheet extends StatelessWidget {
  const MobileAccountRemovalSheet({
    required this.account,
    required this.isLastAccount,
    required this.hasActiveMigration,
    required this.unsharedGiftCardCount,
    super.key,
  });

  final AccountInfo account;
  final bool isLastAccount;
  final bool hasActiveMigration;

  /// Null when the unshared gift card check failed.
  final int? unsharedGiftCardCount;

  // The shared mobile sheet title and body, as on every other sheet.
  static final _titleStyle = AppTypography.bodyLarge.copyWith(
    fontWeight: FontWeight.w600,
  );
  static const _bodyStyle = AppTypography.bodyMedium;

  String _description(BuildContext context) {
    final l10n = context.l10n;
    if (hasActiveMigration) {
      return isLastAccount
          ? l10n.accountsResetMigrationBody
          : l10n.accountsRemoveMigrationBody;
    }
    return isLastAccount ? l10n.accountsResetBody : l10n.accountsRemoveBody;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final unsharedGiftCardWarning = unsharedGiftCardRemovalWarning(
      context.l10n,
      unsharedGiftCardCount,
      walletReset: isLastAccount,
    );
    return MobileModalScaffold(
      title: isLastAccount
          ? context.l10n.commonResetVizor
          : context.l10n.accountsRemove,
      onClose: () => Navigator.of(context).pop(false),
      leading: MobileAccountAvatar(
        profilePictureId: account.profilePictureId,
        size: AppProfilePictureSize.large,
        hardwareSignerKind: account.hardwareSignerKind,
      ),
      titleStyle: _titleStyle.copyWith(color: colors.text.accent),
      constrainBody: true,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _description(context),
              style: _bodyStyle.copyWith(color: colors.text.accent),
            ),
            if (account.setupPending && !account.isHardware) ...[
              const SizedBox(height: AppSpacing.s),
              Text(
                context.l10n.accountsRemoveBackupWarning,
                key: const ValueKey('mobile_account_remove_backup_warning'),
                style: _bodyStyle.copyWith(color: colors.text.destructive),
              ),
            ],
            if (unsharedGiftCardWarning != null) ...[
              const SizedBox(height: AppSpacing.s),
              Text(
                unsharedGiftCardWarning,
                key: const ValueKey(
                  'mobile_account_remove_unshared_gift_cards',
                ),
                style: _bodyStyle.copyWith(color: colors.text.warning),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            AppButton(
              key: const ValueKey('mobile_account_remove_confirm'),
              variant: AppButtonVariant.destructive,
              expand: true,
              onPressed: () => Navigator.of(context).pop(true),
              leading: isLastAccount ? null : const AppIcon(AppIcons.trash),
              child: Text(
                isLastAccount
                    ? context.l10n.commonResetVizor
                    : context.l10n.commonRemove,
                style: AppTypography.labelLarge.copyWith(
                  color: colors.button.destructive.label,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.s),
            MobileSheetCancel(
              onTap: () => Navigator.of(context).pop(false),
              textStyle: AppTypography.labelLarge.copyWith(
                color: colors.button.ghost.label,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
