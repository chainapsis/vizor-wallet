import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../core/formatting/zec_amount.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_pane_modal_overlay.dart';
import '../../../rust/api/wallet.dart' as rust_wallet;

typedef ImportAccountTransparentBalanceLoader =
    Future<BigInt> Function(
      rust_wallet.SoftwareWalletDiscoveredAccount account,
    );

class ImportAccountDiscoveryModal extends StatefulWidget {
  const ImportAccountDiscoveryModal({
    required this.accounts,
    required this.allowEmptySelection,
    required this.loadTransparentBalance,
    required this.onConfirm,
    required this.onCancel,
    super.key,
  });

  final List<rust_wallet.SoftwareWalletDiscoveredAccount> accounts;
  final bool allowEmptySelection;
  final ImportAccountTransparentBalanceLoader loadTransparentBalance;
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
  static const _maxConcurrentBalanceLoads = 2;

  late Set<int> _selectedAccountIndices;
  late Map<int, _TransparentBalanceState> _transparentBalanceStates;
  final _scrollController = ScrollController();
  int _balanceLoadGeneration = 0;
  int _nextBalanceLoadIndex = 0;

  @override
  void initState() {
    super.initState();
    _resetSelectedAccounts();
    _resetTransparentBalanceStates();
    _scheduleTransparentBalanceLoads();
  }

  @override
  void didUpdateWidget(covariant ImportAccountDiscoveryModal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.accounts == widget.accounts) return;
    _resetSelectedAccounts();
    _resetTransparentBalanceStates();
    _scheduleTransparentBalanceLoads();
  }

  void _resetSelectedAccounts() {
    _selectedAccountIndices = {
      for (final account in widget.accounts) account.zip32AccountIndex,
    };
  }

  void _resetTransparentBalanceStates() {
    _transparentBalanceStates = {
      for (final account in widget.accounts)
        account.zip32AccountIndex: const _TransparentBalanceState.loading(),
    };
  }

  void _scheduleTransparentBalanceLoads() {
    final generation = ++_balanceLoadGeneration;
    _nextBalanceLoadIndex = 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _balanceLoadGeneration) return;
      _startTransparentBalanceLoads(generation);
    });
  }

  void _startTransparentBalanceLoads(int generation) {
    final workerCount = widget.accounts.length < _maxConcurrentBalanceLoads
        ? widget.accounts.length
        : _maxConcurrentBalanceLoads;
    for (var i = 0; i < workerCount; i++) {
      unawaited(_loadTransparentBalances(generation));
    }
  }

  Future<void> _loadTransparentBalances(int generation) async {
    while (mounted && generation == _balanceLoadGeneration) {
      final account = _takeNextBalanceLoadAccount(generation);
      if (account == null) return;

      final accountIndex = account.zip32AccountIndex;
      try {
        final balance = await widget.loadTransparentBalance(account);
        if (!mounted || generation != _balanceLoadGeneration) return;
        setState(() {
          _transparentBalanceStates[accountIndex] =
              _TransparentBalanceState.loaded(balance);
        });
      } catch (_) {
        if (!mounted || generation != _balanceLoadGeneration) return;
        setState(() {
          _transparentBalanceStates[accountIndex] =
              const _TransparentBalanceState.failed();
        });
      }
    }
  }

  rust_wallet.SoftwareWalletDiscoveredAccount? _takeNextBalanceLoadAccount(
    int generation,
  ) {
    if (generation != _balanceLoadGeneration) return null;
    if (_nextBalanceLoadIndex >= widget.accounts.length) return null;
    return widget.accounts[_nextBalanceLoadIndex++];
  }

  @override
  void dispose() {
    _balanceLoadGeneration++;
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
    if (_selectedAccountIndices.isEmpty && !widget.allowEmptySelection) {
      return;
    }
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
    final canConfirm = selectedCount > 0 || widget.allowEmptySelection;

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
                      transparentBalanceState:
                          _transparentBalanceStates[account
                              .zip32AccountIndex] ??
                          const _TransparentBalanceState.loading(),
                      onTap: () => _toggle(account.zip32AccountIndex),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            LayoutBuilder(
              builder: (context, constraints) {
                final buttonWidth = (constraints.maxWidth - AppSpacing.xs) / 2;
                return Row(
                  children: [
                    AppButton(
                      key: const ValueKey(
                        'import_account_discovery_cancel_button',
                      ),
                      onPressed: widget.onCancel,
                      variant: AppButtonVariant.ghost,
                      minWidth: buttonWidth,
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    AppButton(
                      key: const ValueKey(
                        'import_account_discovery_confirm_button',
                      ),
                      onPressed: canConfirm ? _confirm : null,
                      variant: AppButtonVariant.primary,
                      minWidth: buttonWidth,
                      trailing: const AppIcon(AppIcons.chevronForward),
                      child: const Text('Import'),
                    ),
                  ],
                );
              },
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
    required this.transparentBalanceState,
    required this.onTap,
  });

  final rust_wallet.SoftwareWalletDiscoveredAccount account;
  final bool selected;
  final _TransparentBalanceState transparentBalanceState;
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
                SizedBox(
                  width: 112,
                  child: _TransparentBalancePreviewLabel(
                    state: transparentBalanceState,
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

enum _TransparentBalanceStatus { loading, loaded, failed }

class _TransparentBalanceState {
  const _TransparentBalanceState.loading()
    : status = _TransparentBalanceStatus.loading,
      zatoshi = null;

  const _TransparentBalanceState.loaded(this.zatoshi)
    : status = _TransparentBalanceStatus.loaded;

  const _TransparentBalanceState.failed()
    : status = _TransparentBalanceStatus.failed,
      zatoshi = null;

  final _TransparentBalanceStatus status;
  final BigInt? zatoshi;
}

class _TransparentBalancePreviewLabel extends StatelessWidget {
  const _TransparentBalancePreviewLabel({required this.state});

  final _TransparentBalanceState state;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final balanceText = switch (state.status) {
      _TransparentBalanceStatus.loading => 'Loading',
      _TransparentBalanceStatus.failed => '-',
      _TransparentBalanceStatus.loaded => ZecAmount.fromZatoshi(
        state.zatoshi ?? BigInt.zero,
      ).activity.toString(),
    };
    final color = switch (state.status) {
      _TransparentBalanceStatus.loading => colors.text.secondary,
      _TransparentBalanceStatus.failed => colors.text.secondary,
      _TransparentBalanceStatus.loaded => colors.text.accent,
    };

    return Column(
      key: const ValueKey('import_account_discovery_balance_label'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          'Transparent',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.end,
          style: AppTypography.labelMedium.copyWith(
            color: colors.text.secondary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          balanceText,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.end,
          style: AppTypography.labelMedium.copyWith(color: color),
        ),
      ],
    );
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
