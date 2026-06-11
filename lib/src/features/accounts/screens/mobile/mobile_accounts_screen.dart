import 'dart:async';

import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../main.dart' show log;
import '../../../../core/account_name_policy.dart';
import '../../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../../core/profile_pictures.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/app_profile_picture.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/mobile/mobile_list_row.dart';
import '../../../../core/widgets/mobile/mobile_surface_card.dart';
import '../../../../providers/account_provider.dart';
import '../../../../providers/sync_provider.dart';
import '../../../../providers/wallet_mutation_guard.dart';

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

  Future<void> _showRowMenu(AccountInfo account) async {
    final accounts = ref.read(accountProvider).value?.accounts ?? const [];
    final canRemove = _canRemove(account, accounts);
    final action = await showAppMobileSheet<_AccountAction>(
      context: context,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              MobileListRow(
                key: const ValueKey('mobile_account_menu_edit'),
                leading: AppIcon(
                  AppIcons.edit,
                  size: 20,
                  color: sheetContext.colors.icon.accent,
                ),
                label: 'Edit account',
                onTap: () =>
                    Navigator.of(sheetContext).pop(_AccountAction.edit),
              ),
              if (canRemove)
                MobileListRow(
                  key: const ValueKey('mobile_account_menu_remove'),
                  leading: AppIcon(
                    AppIcons.trash,
                    size: 20,
                    color: sheetContext.colors.text.destructive,
                  ),
                  label: 'Remove account',
                  labelColor: sheetContext.colors.text.destructive,
                  onTap: () =>
                      Navigator.of(sheetContext).pop(_AccountAction.remove),
                ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case _AccountAction.edit:
        await _showEditSheet(account);
      case _AccountAction.remove:
        await _showRemoveSheet(account);
      case null:
        break;
    }
  }

  Future<void> _showEditSheet(AccountInfo account) async {
    final result = await showAppMobileSheet<_AccountEdits>(
      context: context,
      builder: (_) => _EditAccountSheet(account: account),
    );
    if (result == null || !mounted) return;

    setState(() => _busy = true);
    final accountNotifier = ref.read(accountProvider.notifier);
    try {
      if (result.name != null) {
        await accountNotifier.renameAccount(account.uuid, result.name!);
      }
      if (result.profilePictureId != null) {
        await accountNotifier.updateProfilePicture(
          account.uuid,
          result.profilePictureId!,
        );
      }
    } catch (e, st) {
      log('MobileAccounts: edit failed: $e\n$st');
      if (mounted) {
        showAppToast(
          context,
          "Couldn't save the account changes",
          iconName: AppIcons.cross,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
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
      leading: AppProfilePicture(
        profilePictureId: account.profilePictureId,
        size: AppProfilePictureSize.large,
      ),
      label: account.name,
      trailing: Semantics(
        button: true,
        label: 'Account options for ${account.name}',
        excludeSemantics: true,
        child: GestureDetector(
          key: ValueKey('mobile_accounts_menu_${account.uuid}'),
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? () => unawaited(_showRowMenu(account)) : null,
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
    );
  }
}

enum _AccountAction { edit, remove }

class _AccountEdits {
  const _AccountEdits({this.name, this.profilePictureId});

  final String? name;
  final String? profilePictureId;
}

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
class _EditAccountSheet extends StatefulWidget {
  const _EditAccountSheet({required this.account});

  final AccountInfo account;

  @override
  State<_EditAccountSheet> createState() => _EditAccountSheetState();
}

class _EditAccountSheetState extends State<_EditAccountSheet> {
  late final TextEditingController _nameController = TextEditingController(
    text: widget.account.name,
  );
  final _nameFocusNode = FocusNode();
  late String _profilePictureId = widget.account.profilePictureId;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _nameFocusNode.dispose();
    super.dispose();
  }

  Future<void> _pickPicture() async {
    final picked = await showAppMobileSheet<String>(
      context: context,
      builder: (_) => _ProfilePictureSheet(selectedId: _profilePictureId),
    );
    if (picked != null && mounted) {
      setState(() => _profilePictureId = picked);
    }
  }

  void _save() {
    final name = normalizeAccountName(_nameController.text);
    try {
      validateAccountName(name);
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      return;
    }
    Navigator.of(context).pop(
      _AccountEdits(
        name: name == widget.account.name ? null : name,
        profilePictureId: _profilePictureId == widget.account.profilePictureId
            ? null
            : _profilePictureId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.md + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Semantics(
                button: true,
                label: 'Change profile picture',
                excludeSemantics: true,
                child: GestureDetector(
                  key: const ValueKey('mobile_account_edit_avatar'),
                  behavior: HitTestBehavior.opaque,
                  onTap: _pickPicture,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      AppProfilePicture(
                        profilePictureId: _profilePictureId,
                        size: AppProfilePictureSize.xLarge,
                      ),
                      Positioned(
                        right: -4,
                        bottom: -4,
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: colors.background.homeCard,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: AppIcon(
                              AppIcons.edit,
                              size: AppIconSize.medium,
                              color: colors.text.homeCard,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Account name',
              style: AppTypography.labelMedium.copyWith(
                color: colors.text.secondary,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.s,
              ),
              decoration: BoxDecoration(
                color: colors.background.ground,
                borderRadius: BorderRadius.circular(AppRadii.medium),
                border: Border.all(color: colors.border.subtle),
              ),
              child: EditableText(
                key: const ValueKey('mobile_account_edit_name'),
                controller: _nameController,
                focusNode: _nameFocusNode,
                style: AppTypography.bodyMedium.copyWith(
                  color: colors.text.accent,
                ),
                cursorColor: colors.text.accent,
                backgroundCursorColor: colors.background.overlay,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                _error!,
                style: AppTypography.bodySmall.copyWith(
                  color: colors.text.destructive,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            AppButton(
              key: const ValueKey('mobile_account_edit_save'),
              onPressed: _save,
              child: const Text('Save edits'),
            ),
            const SizedBox(height: AppSpacing.s),
            _SheetCancel(onTap: () => Navigator.of(context).pop()),
          ],
        ),
      ),
    );
  }
}

/// Figma `PFP Modal` (4514:85279): the avatar grid with the selection
/// check and the update action.
class _ProfilePictureSheet extends StatefulWidget {
  const _ProfilePictureSheet({required this.selectedId});

  final String selectedId;

  @override
  State<_ProfilePictureSheet> createState() => _ProfilePictureSheetState();
}

class _ProfilePictureSheetState extends State<_ProfilePictureSheet> {
  late String _selected = widget.selectedId;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: AppProfilePicture(
                profilePictureId: _selected,
                size: AppProfilePictureSize.xLarge,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Select profile picture',
              textAlign: TextAlign.center,
              style: AppTypography.headlineSmall.copyWith(
                color: colors.text.accent,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: AppSpacing.s,
              runSpacing: AppSpacing.s,
              children: [
                for (final option in kProfilePictureOptions)
                  Semantics(
                    button: true,
                    label: option.label,
                    selected: option.id == _selected,
                    excludeSemantics: true,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(() => _selected = option.id),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          AppProfilePicture(
                            profilePictureId: option.id,
                            size: AppProfilePictureSize.large,
                          ),
                          if (option.id == _selected)
                            Positioned(
                              left: -2,
                              bottom: -2,
                              child: Container(
                                width: 18,
                                height: 18,
                                decoration: BoxDecoration(
                                  color: colors.background.homeCard,
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: AppIcon(
                                    AppIcons.check,
                                    size: 12,
                                    color: colors.text.homeCard,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            AppButton(
              key: const ValueKey('mobile_account_pfp_update'),
              onPressed: () => Navigator.of(context).pop(_selected),
              child: const Text('Update picture'),
            ),
            const SizedBox(height: AppSpacing.s),
            _SheetCancel(onTap: () => Navigator.of(context).pop()),
          ],
        ),
      ),
    );
  }
}

/// Figma `Remove` (4514:85954): destructive confirmation.
class _RemoveAccountSheet extends StatelessWidget {
  const _RemoveAccountSheet({required this.account});

  final AccountInfo account;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                AppProfilePicture(
                  profilePictureId: account.profilePictureId,
                  size: AppProfilePictureSize.large,
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
              onPressed: () => Navigator.of(context).pop(true),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppIcon(
                    AppIcons.trash,
                    size: 20,
                    color: DefaultTextStyle.of(context).style.color,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  const Text('Remove'),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.s),
            _SheetCancel(onTap: () => Navigator.of(context).pop(false)),
          ],
        ),
      ),
    );
  }
}

class _SheetCancel extends StatelessWidget {
  const _SheetCancel({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          height: 44,
          child: Center(
            child: Text(
              'Cancel',
              style: AppTypography.labelLarge.copyWith(
                color: context.colors.text.primary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
