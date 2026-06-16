import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../main.dart' show log;
import '../../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../../core/profile_pictures.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/app_profile_picture.dart';
import '../../../../core/widgets/mobile/mobile_account_avatar.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/mobile/mobile_list_row.dart';
import '../../../../providers/account_provider.dart';
import '../../../../providers/receive_address_provider.dart';
import '../../../../providers/sync_provider.dart';

/// Opens the account-switcher bottom sheet — Figma `Accounts Modal`
/// (4411:91628).
Future<void> showMobileAccountsSheet(BuildContext context) {
  return showAppMobileSheet<void>(
    context: context,
    builder: (_) => const MobileAccountsSheet(),
  );
}

class MobileAccountsSheet extends ConsumerStatefulWidget {
  const MobileAccountsSheet({super.key});

  @override
  ConsumerState<MobileAccountsSheet> createState() =>
      _MobileAccountsSheetState();
}

class _MobileAccountsSheetState extends ConsumerState<MobileAccountsSheet> {
  bool _isCopyingAddress = false;

  Future<void> _switchAccount(String uuid) async {
    final activeAccountUuid = ref
        .read(accountProvider)
        .value
        ?.activeAccountUuid;
    Navigator.of(context).pop();
    if (uuid == activeAccountUuid) return;

    final accountNotifier = ref.read(accountProvider.notifier);
    final syncNotifier = ref.read(syncProvider.notifier);
    await accountNotifier.switchAccount(uuid);
    unawaited(_refreshAfterAccountSwitch(syncNotifier));
  }

  Future<void> _refreshAfterAccountSwitch(SyncNotifier syncNotifier) async {
    try {
      await syncNotifier.refreshAfterSend();
    } catch (e) {
      log('MobileAccountsSheet: refresh after account switch failed: $e');
    }
  }

  Future<void> _copyShieldedAddress(AccountInfo account) async {
    if (_isCopyingAddress) return;
    setState(() => _isCopyingAddress = true);

    try {
      final accountState = ref.read(accountProvider).value;
      final currentShieldedAddress =
          accountState?.activeAccountUuid == account.uuid
          ? accountState?.activeAddress
          : null;
      final address = await ref
          .read(receiveAddressServiceProvider)
          .loadShieldedAddress(
            accountUuid: account.uuid,
            currentShieldedAddress: currentShieldedAddress,
          );
      if (!mounted) return;
      if (address.trim().isEmpty) {
        showAppToast(context, "Address couldn't be copied");
        return;
      }

      await Clipboard.setData(ClipboardData(text: address));
      if (!mounted) return;
      showAppToast(context, 'Address copied');
    } catch (e) {
      log('MobileAccountsSheet: ERROR copying shielded address: $e');
      if (!mounted) return;
      showAppToast(context, "Address couldn't be copied");
    } finally {
      if (mounted) {
        setState(() => _isCopyingAddress = false);
      }
    }
  }

  void _addAccount() {
    Navigator.of(context).pop();
    context.push('/add-account');
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final accountState = ref.watch(accountProvider).value;
    final accounts = accountState?.accounts ?? const <AccountInfo>[];
    final active = accountState?.activeAccount;
    final others = [
      for (final account in accounts)
        if (account.uuid != active?.uuid) account,
    ];

    return MobileModalScaffold(
      title: '',
      showTitle: false,
      bottomPadding: AppSpacing.base,
      onClose: () => Navigator.of(context).pop(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSpacing.s),
          // Centered so the stretch column can't blow the circle up
          // to full width; 56 px per the Figma accounts modal.
          Center(
            child: MobileAccountAvatar(
              profilePictureId:
                  active?.profilePictureId ?? kDefaultProfilePictureId,
              size: AppProfilePictureSize.xLarge,
              isHardware: active?.isHardware ?? false,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            active?.name ?? '',
            textAlign: TextAlign.center,
            style: AppTypography.bodyLarge.copyWith(color: colors.text.accent),
          ),
          const SizedBox(height: AppSpacing.s),
          if (others.isNotEmpty) ...[
            Text(
              'Other accounts',
              style: AppTypography.labelLarge.copyWith(
                fontWeight: FontWeight.w500,
                color: colors.text.accent,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 216),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final account in others)
                    MobileListRow(
                      key: ValueKey('account_row_${account.uuid}'),
                      minRowHeight: 48,
                      leading: MobileAccountAvatar(
                        profilePictureId: account.profilePictureId,
                        size: AppProfilePictureSize.navLarge,
                        isHardware: account.isHardware,
                      ),
                      label: account.name,
                      trailing: _CopyAddressButton(
                        onTap: () => unawaited(_copyShieldedAddress(account)),
                      ),
                      onTap: () => unawaited(_switchAccount(account.uuid)),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.s),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  variant: AppButtonVariant.secondary,
                  expand: true,
                  constrainContent: true,
                  onPressed: () {
                    Navigator.of(context).pop();
                    context.push('/accounts');
                  },
                  child: const Text(
                    'Manage accounts',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              _AddAccountButton(onTap: _addAccount),
            ],
          ),
        ],
      ),
    );
  }
}

class _AccountSheetButtonShell extends StatefulWidget {
  const _AccountSheetButtonShell({
    required this.onTap,
    required this.child,
    required this.label,
  });

  final VoidCallback onTap;
  final Widget child;
  final String label;

  @override
  State<_AccountSheetButtonShell> createState() =>
      _AccountSheetButtonShellState();
}

class _AccountSheetButtonShellState extends State<_AccountSheetButtonShell> {
  var _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.label,
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _pressed ? 0.96 : 1,
          duration: const Duration(milliseconds: 90),
          curve: Curves.easeOut,
          child: widget.child,
        ),
      ),
    );
  }
}

class _CopyAddressButton extends StatelessWidget {
  const _CopyAddressButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _AccountSheetButtonShell(
      label: 'Copy shielded address',
      onTap: onTap,
      child: SizedBox(
        width: 40,
        height: 40,
        child: Center(
          child: AppIcon(
            AppIcons.copy,
            size: 20,
            color: context.colors.icon.muted,
          ),
        ),
      ),
    );
  }
}

class _AddAccountButton extends StatelessWidget {
  const _AddAccountButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return _AccountSheetButtonShell(
      label: 'Add account',
      onTap: onTap,
      child: Container(
        key: const ValueKey('mobile_accounts_add'),
        width: 80,
        height: AppButtonSizing.largeHeight,
        decoration: BoxDecoration(
          color: colors.button.primary.bg,
          borderRadius: BorderRadius.circular(AppRadii.full),
          border: Border.all(color: colors.button.primary.border, width: 1.5),
        ),
        child: Center(
          child: AppIcon(
            AppIcons.addNew,
            size: 20,
            color: colors.button.primary.label,
          ),
        ),
      ),
    );
  }
}
