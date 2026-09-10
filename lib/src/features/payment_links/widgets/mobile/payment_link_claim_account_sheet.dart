import 'package:flutter/widgets.dart';

import '../../../../core/formatting/zec_amount.dart';
import '../../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/app_profile_picture.dart';
import '../../../../core/widgets/mobile/mobile_account_avatar.dart';
import '../../../../core/widgets/mobile/mobile_list_row.dart';
import '../../../../providers/account_provider.dart';

Future<bool> showPaymentLinkClaimAccountSheet({
  required BuildContext context,
  required BigInt amountZatoshi,
  required List<AccountInfo> accounts,
  required String activeAccountUuid,
  required Future<void> Function(String accountUuid) onConfirm,
}) async {
  final confirmed = await showAppMobileSheet<bool>(
    context: context,
    // Back, the scrim and Close remain available before confirmation. A drag
    // cannot dismiss the sheet halfway through switching/preparing a claim.
    enableDrag: false,
    builder: (sheetContext) => PaymentLinkClaimAccountSheet(
      amountZatoshi: amountZatoshi,
      accounts: accounts,
      activeAccountUuid: activeAccountUuid,
      onConfirm: onConfirm,
      onConfirmed: () => Navigator.of(sheetContext).pop(true),
      onClose: () => Navigator.of(sheetContext).pop(false),
    ),
  );
  return confirmed == true;
}

class PaymentLinkClaimAccountSheet extends StatefulWidget {
  const PaymentLinkClaimAccountSheet({
    required this.amountZatoshi,
    required this.accounts,
    required this.activeAccountUuid,
    required this.onConfirm,
    required this.onConfirmed,
    required this.onClose,
    super.key,
  });

  final BigInt amountZatoshi;
  final List<AccountInfo> accounts;
  final String activeAccountUuid;
  final Future<void> Function(String accountUuid) onConfirm;
  final VoidCallback onConfirmed;
  final VoidCallback onClose;

  @override
  State<PaymentLinkClaimAccountSheet> createState() =>
      _PaymentLinkClaimAccountSheetState();
}

class _PaymentLinkClaimAccountSheetState
    extends State<PaymentLinkClaimAccountSheet> {
  static const _rowHeight = 48.0;
  static const _rowGap = AppSpacing.xs;
  static const _listMaxHeight = 4 * _rowHeight + 3 * _rowGap;

  final _scrollController = ScrollController();
  late String _selectedAccountUuid = widget.activeAccountUuid;
  bool _preparing = false;
  bool _failed = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_preparing) return;
    setState(() {
      _preparing = true;
      _failed = false;
    });
    try {
      await widget.onConfirm(_selectedAccountUuid);
      if (mounted) widget.onConfirmed();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _preparing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final accounts = [
      for (final account in widget.accounts)
        if (account.uuid == widget.activeAccountUuid) account,
      for (final account in widget.accounts)
        if (account.uuid != widget.activeAccountUuid) account,
    ];
    final contentHeight =
        accounts.length * _rowHeight + (accounts.length - 1) * _rowGap;

    return PopScope(
      canPop: !_preparing,
      child: MobileModalScaffold(
        key: const ValueKey('payment_link_claim_account_sheet'),
        title: 'Choose receiving account',
        constrainBody: true,
        showClose: !_preparing,
        onClose: widget.onClose,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Gift amount',
              style: AppTypography.bodySmall.copyWith(
                color: colors.text.secondary,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              '${formatZecAmount(widget.amountZatoshi)} ZEC',
              style: appSerifDisplayStyle(color: colors.text.accent),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Receive to',
              style: AppTypography.bodyMedium.copyWith(
                color: colors.text.secondary,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: _listMaxHeight),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final scrolls = contentHeight > constraints.maxHeight;
                    return RawScrollbar(
                      controller: _scrollController,
                      thumbVisibility: scrolls,
                      thickness: 6,
                      radius: const Radius.circular(AppRadii.full),
                      thumbColor: colors.background.overlay,
                      child: ListView.separated(
                        key: const ValueKey('payment_link_claim_accounts'),
                        controller: _scrollController,
                        shrinkWrap: true,
                        physics: const ClampingScrollPhysics(),
                        padding: EdgeInsets.only(right: scrolls ? 18 : 0),
                        itemCount: accounts.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: _rowGap),
                        itemBuilder: (context, index) {
                          final account = accounts[index];
                          final selected = account.uuid == _selectedAccountUuid;
                          return Semantics(
                            button: true,
                            selected: selected,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.s,
                              ),
                              decoration: BoxDecoration(
                                color: selected
                                    ? colors.background.neutralSubtleOpacity
                                    : null,
                                borderRadius: BorderRadius.circular(
                                  AppRadii.small,
                                ),
                              ),
                              child: MobileListRow(
                                key: ValueKey(
                                  'payment_link_claim_account_${account.uuid}',
                                ),
                                label: account.name,
                                minRowHeight: _rowHeight,
                                textStyle: AppTypography.labelMedium.copyWith(
                                  fontWeight: FontWeight.w500,
                                ),
                                leading: MobileAccountAvatar(
                                  profilePictureId: account.profilePictureId,
                                  size: AppProfilePictureSize.navLarge,
                                  hardwareSignerKind:
                                      account.hardwareSignerKind,
                                ),
                                trailing: selected
                                    ? AppIcon(
                                        AppIcons.check,
                                        size: AppIconSize.medium,
                                        color: colors.icon.accent,
                                      )
                                    : null,
                                onTap: _preparing
                                    ? null
                                    : () => setState(() {
                                        _selectedAccountUuid = account.uuid;
                                        _failed = false;
                                      }),
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            if (_failed) ...[
              Semantics(
                liveRegion: true,
                child: Text(
                  'Couldn’t prepare this gift. Try again or choose another account.',
                  style: AppTypography.bodySmall.copyWith(
                    color: colors.text.destructive,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            AppButton(
              key: const ValueKey('payment_link_claim_account_confirm'),
              expand: true,
              onPressed: _preparing || accounts.isEmpty ? null : _confirm,
              child: Text(
                _preparing
                    ? 'Preparing...'
                    : _failed
                    ? 'Try again'
                    : 'Claim gift',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
