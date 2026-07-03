import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../core/formatting/zec_amount.dart';
import '../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../rust/api/wallet.dart' as rust_wallet;
import '../../../../l10n/app_localizations.dart';

typedef MobileImportAccountTransparentBalanceLoader =
    Future<BigInt> Function(
      rust_wallet.SoftwareWalletDiscoveredAccount account,
    );

Future<List<int>?> showMobileImportAccountDiscoverySheet({
  required BuildContext context,
  required List<rust_wallet.SoftwareWalletDiscoveredAccount> accounts,
  required bool allowEmptySelection,
  required int bip44CoinType,
  required MobileImportAccountTransparentBalanceLoader loadTransparentBalance,
}) {
  return showAppMobileSheet<List<int>?>(
    context: context,
    builder: (sheetContext) => MobileImportAccountDiscoverySheet(
      accounts: accounts,
      allowEmptySelection: allowEmptySelection,
      bip44CoinType: bip44CoinType,
      loadTransparentBalance: loadTransparentBalance,
      onConfirm: (indices) => Navigator.of(sheetContext).pop(indices),
      onCancel: () => Navigator.of(sheetContext).pop(),
    ),
  );
}

class MobileImportAccountDiscoverySheet extends StatefulWidget {
  const MobileImportAccountDiscoverySheet({
    required this.accounts,
    required this.allowEmptySelection,
    required this.bip44CoinType,
    required this.loadTransparentBalance,
    required this.onConfirm,
    required this.onCancel,
    super.key,
  });

  final List<rust_wallet.SoftwareWalletDiscoveredAccount> accounts;
  final bool allowEmptySelection;
  final int bip44CoinType;
  final MobileImportAccountTransparentBalanceLoader loadTransparentBalance;
  final ValueChanged<List<int>> onConfirm;
  final VoidCallback onCancel;

  @override
  State<MobileImportAccountDiscoverySheet> createState() =>
      _MobileImportAccountDiscoverySheetState();
}

class _MobileImportAccountDiscoverySheetState
    extends State<MobileImportAccountDiscoverySheet> {
  static const _maxConcurrentBalanceLoads = 2;
  static const _maxListHeight = 316.0;
  static const _rowHeight = 76.0;
  static const _rowGap = AppSpacing.xs;
  static const _scrollbarGutter = 16.0;
  static const _scrollbarThickness = 6.0;

  late Set<int> _selectedAccountIndices;
  late Map<int, _TransparentBalanceState> _transparentBalanceStates;
  final _scrollController = ScrollController();
  var _balanceLoadGeneration = 0;
  var _nextBalanceLoadIndex = 0;

  @override
  void initState() {
    super.initState();
    _resetSelectedAccounts();
    _resetTransparentBalanceStates();
    _scheduleTransparentBalanceLoads();
  }

  @override
  void didUpdateWidget(covariant MobileImportAccountDiscoverySheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.accounts == widget.accounts) return;
    _resetSelectedAccounts();
    _resetTransparentBalanceStates();
    _scheduleTransparentBalanceLoads();
  }

  @override
  void dispose() {
    _balanceLoadGeneration++;
    _scrollController.dispose();
    super.dispose();
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

  double _listHeight() {
    if (widget.accounts.isEmpty) return 0;
    final visibleRows = widget.accounts.length > 4 ? 4 : widget.accounts.length;
    final height = visibleRows * _rowHeight + (visibleRows - 1) * _rowGap;
    return height > _maxListHeight ? _maxListHeight : height;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final selectedCount = _selectedAccountIndices.length;
    final canConfirm = selectedCount > 0 || widget.allowEmptySelection;
    final showScrollbar = widget.accounts.length > 4;

    return MobileModalScaffold(
      key: const ValueKey('mobile_import_account_discovery_sheet'),
      title: AppLocalizations.of(context).onbAdditionalAccountsFound,
      onClose: widget.onCancel,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            AppLocalizations.of(context).onbChooseAdditionalAccounts,
            style: AppTypography.bodyMedium.copyWith(
              color: colors.text.secondary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            key: const ValueKey('mobile_import_account_discovery_list'),
            height: _listHeight(),
            child: RawScrollbar(
              key: const ValueKey('mobile_import_account_discovery_scrollbar'),
              controller: _scrollController,
              thumbVisibility: showScrollbar,
              interactive: true,
              radius: const Radius.circular(AppRadii.full),
              thickness: _scrollbarThickness,
              mainAxisMargin: 0,
              padding: EdgeInsets.zero,
              crossAxisMargin: (_scrollbarGutter - _scrollbarThickness) / 2,
              thumbColor: colors.background.overlay,
              child: Padding(
                padding: EdgeInsets.only(
                  right: showScrollbar ? _scrollbarGutter : 0,
                ),
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(
                    context,
                  ).copyWith(scrollbars: false),
                  child: ListView.separated(
                    controller: _scrollController,
                    physics: const ClampingScrollPhysics(),
                    padding: EdgeInsets.zero,
                    itemCount: widget.accounts.length,
                    separatorBuilder: (_, _) => const SizedBox(height: _rowGap),
                    itemBuilder: (context, index) {
                      final account = widget.accounts[index];
                      return _MobileDiscoveredAccountRow(
                        account: account,
                        selected: _selectedAccountIndices.contains(
                          account.zip32AccountIndex,
                        ),
                        bip44CoinType: widget.bip44CoinType,
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
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton(
            key: const ValueKey('mobile_import_account_discovery_confirm'),
            expand: true,
            onPressed: canConfirm ? _confirm : null,
            child: Text(AppLocalizations.of(context).onbImportAction),
          ),
          const SizedBox(height: AppSpacing.xs),
          AppButton(
            key: const ValueKey('mobile_import_account_discovery_cancel'),
            variant: AppButtonVariant.ghost,
            expand: true,
            onPressed: widget.onCancel,
            child: Text(AppLocalizations.of(context).commonCancel),
          ),
        ],
      ),
    );
  }
}

class _MobileDiscoveredAccountRow extends StatelessWidget {
  const _MobileDiscoveredAccountRow({
    required this.account,
    required this.selected,
    required this.bip44CoinType,
    required this.transparentBalanceState,
    required this.onTap,
  });

  final rust_wallet.SoftwareWalletDiscoveredAccount account;
  final bool selected;
  final int bip44CoinType;
  final _TransparentBalanceState transparentBalanceState;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final accountPath =
        "m/44'/$bip44CoinType'/${account.zip32AccountIndex}'/...";
    final rowColor = selected
        ? colors.background.neutralSubtleOpacity
        : colors.background.base;
    final borderColor = selected ? colors.border.strong : colors.border.regular;

    return Semantics(
      button: true,
      selected: selected,
      label: accountPath,
      child: GestureDetector(
        key: ValueKey(
          'mobile_import_account_discovery_row_${account.zip32AccountIndex}',
        ),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          height: _MobileImportAccountDiscoverySheetState._rowHeight,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xs,
            vertical: AppSpacing.xxs,
          ),
          decoration: BoxDecoration(
            color: rowColor,
            border: Border.all(color: borderColor, width: selected ? 2 : 1.5),
            borderRadius: BorderRadius.circular(AppRadii.small),
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
                      accountPath,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.labelLarge.copyWith(
                        color: colors.text.accent,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _shortAddress(account.firstTransparentAddress),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.codeSmall.copyWith(
                        color: colors.text.secondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    _TransparentBalancePreviewLabel(
                      state: transparentBalanceState,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              _AccountCheckbox(
                selected: selected,
                accountIndex: account.zip32AccountIndex,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _shortAddress(String address) {
    if (address.length <= 24) return address;
    return '${address.substring(0, 10)} ... ${address.substring(address.length - 10)}';
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
      _TransparentBalanceStatus.loading => AppLocalizations.of(context).onbBalanceLoading,
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

    return Row(
      key: const ValueKey('mobile_import_account_discovery_balance_label'),
      children: [
        Text(
          AppLocalizations.of(context).onbTransparentLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.labelMedium.copyWith(
            color: colors.text.secondary,
          ),
        ),
        const SizedBox(width: AppSpacing.xxs),
        Expanded(
          child: Text(
            balanceText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.labelMedium.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

class _AccountCheckbox extends StatelessWidget {
  const _AccountCheckbox({required this.selected, required this.accountIndex});

  final bool selected;
  final int accountIndex;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AnimatedContainer(
      key: ValueKey('mobile_import_account_discovery_toggle_$accountIndex'),
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected ? colors.background.inverse : null,
        border: Border.all(
          color: selected ? colors.border.strong : colors.border.regular,
          width: 1.5,
        ),
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      child: selected
          ? AppIcon(AppIcons.check, size: 13, color: colors.icon.inverse)
          : null,
    );
  }
}
