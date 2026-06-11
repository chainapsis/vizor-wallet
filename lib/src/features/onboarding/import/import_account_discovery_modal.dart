import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_pane_modal_overlay.dart';
import '../../../rust/api/wallet.dart' as rust_wallet;

class ImportAccountDiscoveryModal extends StatefulWidget {
  const ImportAccountDiscoveryModal({
    required this.accounts,
    required this.onConfirm,
    required this.onCancel,
    super.key,
  });

  final List<rust_wallet.SoftwareWalletDiscoveredAccount> accounts;
  final ValueChanged<List<int>> onConfirm;
  final VoidCallback onCancel;

  @override
  State<ImportAccountDiscoveryModal> createState() =>
      _ImportAccountDiscoveryModalState();
}

class _ImportAccountDiscoveryModalState
    extends State<ImportAccountDiscoveryModal> {
  static const _modalWidth = 420.0;
  static const _maxListHeight = 280.0;

  late Set<int> _selectedAccountIndices;
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _selectedAccountIndices = {
      for (final account in widget.accounts) account.zip32AccountIndex,
    };
  }

  @override
  void didUpdateWidget(covariant ImportAccountDiscoveryModal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.accounts == widget.accounts) return;
    _selectedAccountIndices = {
      for (final account in widget.accounts) account.zip32AccountIndex,
    };
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _toggle(int accountIndex) {
    setState(() {
      if (!_selectedAccountIndices.add(accountIndex)) {
        _selectedAccountIndices.remove(accountIndex);
      }
    });
  }

  void _confirm() {
    final selected = [
      for (final account in widget.accounts)
        if (_selectedAccountIndices.contains(account.zip32AccountIndex))
          account.zip32AccountIndex,
    ];
    widget.onConfirm(selected);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final selectedCount = _selectedAccountIndices.length;
    final primaryLabel = selectedCount == 0 ? 'Continue' : 'Import';

    return AppPaneModalOverlay(
      onDismiss: widget.onCancel,
      child: Container(
        width: _modalWidth,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: colors.background.ground,
          borderRadius: BorderRadius.circular(AppRadii.large),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: colors.background.neutralSubtleOpacity,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: AppIcon(
                      AppIcons.users,
                      size: AppIconSize.medium,
                      color: colors.icon.regular,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    'Additional accounts found',
                    style: AppTypography.bodyLarge.copyWith(
                      color: colors.text.accent,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
              child: Text(
                'Choose the additional accounts to import.',
                style: AppTypography.bodyMedium.copyWith(
                  color: colors.text.secondary,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: _maxListHeight),
              child: RawScrollbar(
                controller: _scrollController,
                thumbVisibility: widget.accounts.length > 3,
                child: ListView.separated(
                  controller: _scrollController,
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: widget.accounts.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AppSpacing.xs),
                  itemBuilder: (context, index) {
                    final account = widget.accounts[index];
                    final selected = _selectedAccountIndices.contains(
                      account.zip32AccountIndex,
                    );
                    return _DiscoveredAccountRow(
                      account: account,
                      selected: selected,
                      onTap: () => _toggle(account.zip32AccountIndex),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                AppButton(
                  key: const ValueKey('import_account_discovery_cancel_button'),
                  onPressed: widget.onCancel,
                  variant: AppButtonVariant.ghost,
                  minWidth: 96,
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: AppButton(
                    key: const ValueKey(
                      'import_account_discovery_confirm_button',
                    ),
                    onPressed: _confirm,
                    variant: AppButtonVariant.primary,
                    minWidth: 120,
                    trailing: const AppIcon(AppIcons.chevronForward),
                    child: Text(primaryLabel),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DiscoveredAccountRow extends StatelessWidget {
  const _DiscoveredAccountRow({
    required this.account,
    required this.selected,
    required this.onTap,
  });

  final rust_wallet.SoftwareWalletDiscoveredAccount account;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final borderColor = selected ? colors.border.strong : colors.border.regular;

    return Semantics(
      button: true,
      selected: selected,
      label: 'Account ${account.zip32AccountIndex}',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          key: ValueKey(
            'import_account_discovery_row_${account.zip32AccountIndex}',
          ),
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            height: 68,
            padding: const EdgeInsets.only(
              left: AppSpacing.xs,
              right: AppSpacing.s,
              top: AppSpacing.xxs,
              bottom: AppSpacing.xxs,
            ),
            decoration: BoxDecoration(
              border: Border.all(color: borderColor, width: selected ? 2 : 1.5),
              borderRadius: BorderRadius.circular(AppRadii.medium),
            ),
            child: Row(
              children: [
                AppIcon(
                  AppIcons.transparentBalance,
                  size: 18,
                  color: colors.icon.accent,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Account ${account.zip32AccountIndex}',
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.labelLarge.copyWith(
                          color: colors.text.accent,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _shortAddress(account.firstTransparentAddress),
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.codeSmall.copyWith(
                          color: colors.text.secondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                _AccountToggle(
                  selected: selected,
                  accountIndex: account.zip32AccountIndex,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _shortAddress(String address) {
    if (address.length <= 28) return address;
    return '${address.substring(0, 12)} ... ${address.substring(address.length - 12)}';
  }
}

class _AccountToggle extends StatelessWidget {
  const _AccountToggle({required this.selected, required this.accountIndex});

  final bool selected;
  final int accountIndex;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final trackColor = selected
        ? colors.background.inverse
        : colors.background.neutralSubtleOpacity;
    final knobColor = selected ? colors.icon.inverse : colors.icon.regular;

    return AnimatedContainer(
      key: ValueKey('import_account_discovery_toggle_$accountIndex'),
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      width: 36,
      height: 20,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: trackColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Align(
        alignment: selected ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(color: knobColor, shape: BoxShape.circle),
        ),
      ),
    );
  }
}
