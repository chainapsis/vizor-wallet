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

const _accountsSheetLabelMStyle = TextStyle(
  fontFamily: 'Geist',
  fontWeight: FontWeight.w500,
  fontSize: 14,
  height: 16 / 14,
  letterSpacing: -0.06,
);

const _accountsSheetCurrentNameStyle = TextStyle(
  fontFamily: 'Geist',
  fontWeight: FontWeight.w500,
  fontSize: 16,
  height: 20 / 16,
  letterSpacing: 0,
);

const _accountsSheetListMaxHeight = 216.0;
const _accountsSheetRowHeight = 48.0;
const _accountsSheetRowGap = 8.0;
const _accountsSheetScrollbarGutter = 18.0;
const _accountsSheetScrollbarThickness = 6.0;
const _accountsSheetCurrentToTitleGap = AppSpacing.md; // 24
const _accountsSheetTitleToListGap = AppSpacing.s + AppSpacing.xs; // 20

double _accountsSheetListHeight(int rowCount) {
  if (rowCount <= 0) return 0;
  final visibleRows = rowCount > 4 ? 4 : rowCount;
  final height = _accountsSheetContentHeight(visibleRows);
  return height > _accountsSheetListMaxHeight
      ? _accountsSheetListMaxHeight
      : height;
}

double _accountsSheetContentHeight(int rowCount) {
  if (rowCount <= 0) return 0;
  return rowCount * _accountsSheetRowHeight +
      (rowCount - 1) * _accountsSheetRowGap;
}

class _MobileAccountsSheetState extends ConsumerState<MobileAccountsSheet> {
  bool _isCopyingAddress = false;
  late final ScrollController _accountsScrollController = ScrollController();

  @override
  void dispose() {
    _accountsScrollController.dispose();
    super.dispose();
  }

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
    final accountsListHeight = _accountsSheetListHeight(others.length);
    final showAccountsScrollbar = others.length > 4;

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
            style: _accountsSheetCurrentNameStyle.copyWith(
              color: colors.text.accent,
            ),
          ),
          const SizedBox(height: _accountsSheetCurrentToTitleGap),
          if (others.isNotEmpty) ...[
            Text(
              'Other accounts',
              style: _accountsSheetLabelMStyle.copyWith(
                color: colors.text.accent,
              ),
            ),
            const SizedBox(height: _accountsSheetTitleToListGap),
            SizedBox(
              key: const ValueKey('mobile_accounts_sheet_list'),
              height: accountsListHeight,
              child: RawScrollbar(
                key: const ValueKey('mobile_accounts_sheet_scrollbar'),
                controller: _accountsScrollController,
                thumbVisibility: showAccountsScrollbar,
                interactive: true,
                radius: const Radius.circular(AppRadii.full),
                thickness: _accountsSheetScrollbarThickness,
                mainAxisMargin: 0,
                padding: EdgeInsets.zero,
                crossAxisMargin:
                    (_accountsSheetScrollbarGutter -
                        _accountsSheetScrollbarThickness) /
                    2,
                thumbColor: colors.background.overlay,
                child: Padding(
                  key: const ValueKey('mobile_accounts_sheet_list_gutter'),
                  padding: const EdgeInsets.only(
                    right: _accountsSheetScrollbarGutter,
                  ),
                  child: ScrollConfiguration(
                    behavior: ScrollConfiguration.of(
                      context,
                    ).copyWith(scrollbars: false),
                    child: ListView.separated(
                      controller: _accountsScrollController,
                      physics: const ClampingScrollPhysics(),
                      padding: EdgeInsets.zero,
                      itemCount: others.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: _accountsSheetRowGap),
                      itemBuilder: (context, index) {
                        final account = others[index];
                        return MobileListRow(
                          key: ValueKey('account_row_${account.uuid}'),
                          minRowHeight: _accountsSheetRowHeight,
                          textStyle: _accountsSheetLabelMStyle,
                          leading: MobileAccountAvatar(
                            profilePictureId: account.profilePictureId,
                            size: AppProfilePictureSize.navLarge,
                            isHardware: account.isHardware,
                          ),
                          label: account.name,
                          trailing: _CopyAddressButton(
                            onTap: () =>
                                unawaited(_copyShieldedAddress(account)),
                          ),
                          onTap: () => unawaited(_switchAccount(account.uuid)),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.s),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  key: const ValueKey('mobile_accounts_manage'),
                  variant: AppButtonVariant.secondary,
                  expand: true,
                  constrainContent: true,
                  onPressed: () {
                    Navigator.of(context).pop();
                    context.push('/accounts');
                  },
                  height: AppButtonSizing.largeHeight,
                  child: const Text(
                    'Manage accounts',
                    style: _accountsSheetLabelMStyle,
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
