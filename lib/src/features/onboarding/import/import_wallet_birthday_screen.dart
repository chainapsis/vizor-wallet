import 'dart:async';

import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../main.dart' show log;
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/app_security_provider.dart';
import '../../../providers/rpc_endpoint_failover_provider.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../providers/router_refresh_provider.dart';
import '../../../providers/wallet_mutation_guard.dart';
import '../../../rust/api/wallet.dart' as rust_wallet;
import '../shared/onboarding_error_messages.dart';
import '../shared/onboarding_flow_args.dart';
import 'import_account_discovery_modal.dart';
import 'import_birthday_estimator.dart';
import 'import_birthday_calendar_overlay.dart';
import 'import_birthday_unknown_height_modal.dart';
import 'import_split_view.dart';

enum ImportBirthdayTab { date, blockHeight }

enum _ImportWalletSubmitPhase {
  idle,
  discoveringAccounts,
  stoppingSync,
  importing,
}

class ImportWalletBirthdayScreen extends ConsumerStatefulWidget {
  const ImportWalletBirthdayScreen({required this.args, super.key});

  final ImportBirthdayArgs args;

  @override
  ConsumerState<ImportWalletBirthdayScreen> createState() =>
      _ImportWalletBirthdayScreenState();
}

class _ImportWalletBirthdayScreenState
    extends ConsumerState<ImportWalletBirthdayScreen> {
  static const _manualHeightErrorText =
      "Doesn't seem like a legit block height";
  static const _titleWidth = 396.0;
  static const _subtitleWidth = 226.0;
  static const _widgetWidth = 304.0;
  static const _fieldWidth = 256.0;
  static const _buttonWidth = 230.0;
  static const _messageHeight = 16.0;

  late final TextEditingController _manualHeightController;
  late final FocusNode _manualHeightFocusNode;

  ImportBirthdayMetadata? _metadata;
  ImportBirthdayTab _activeTab = ImportBirthdayTab.date;
  DateTime? _selectedDate;
  int? _birthdayHeight;
  bool _isEstimating = false;
  bool _isCalendarOpen = false;
  bool _isUnknownBirthdayConfirmOpen = false;
  _ImportWalletSubmitPhase _submitPhase = _ImportWalletSubmitPhase.idle;
  List<rust_wallet.SoftwareWalletDiscoveredAccount>?
  _accountDiscoveryCandidates;
  Completer<List<int>?>? _accountDiscoveryCompleter;
  bool _accountDiscoveryAllowsEmptySelection = true;
  String? _metadataError;
  String? _submitError;
  DateTime? _calendarInitialDate;
  int _estimateSeq = 0;

  bool get _isSubmitting => _submitPhase != _ImportWalletSubmitPhase.idle;

  @override
  void initState() {
    super.initState();
    final initialBirthdayHeight = widget.args.initialBirthdayHeight;
    if (initialBirthdayHeight != null) {
      _activeTab = ImportBirthdayTab.blockHeight;
    }
    _manualHeightController = TextEditingController(
      text: initialBirthdayHeight?.toString() ?? '',
    );
    _manualHeightFocusNode = FocusNode()..addListener(_handleFocusChanged);
    _loadMetadata();
  }

  @override
  void dispose() {
    _completeAccountDiscovery(null);
    _manualHeightFocusNode
      ..removeListener(_handleFocusChanged)
      ..dispose();
    _manualHeightController.dispose();
    super.dispose();
  }

  void _handleFocusChanged() {
    if (mounted) setState(() {});
  }

  int get _minimumBirthdayHeight =>
      ref.read(rpcEndpointProvider).network.saplingActivationHeight;

  Future<void> _loadMetadata() async {
    setState(() {
      _metadataError = null;
    });

    try {
      final metadata = await ref
          .read(rpcEndpointFailoverProvider.notifier)
          .runWithEndpointFallback(
            operation: 'import birthday metadata',
            action: (endpoint) =>
                ImportBirthdayEstimator.loadMetadata(endpoint: endpoint),
          );
      if (!mounted) return;
      setState(() {
        _metadata = metadata;
      });

      if (_selectedDate != null && _birthdayHeight == null) {
        await _estimateSelectedDate(_selectedDate!);
      }
    } catch (e, st) {
      log('ImportWalletBirthdayScreen._loadMetadata: ERROR: $e\n$st');
      if (!mounted) return;
      setState(() {
        _metadataError = 'Could not load wallet birthday metadata.';
      });
    }
  }

  Future<void> _estimateSelectedDate(DateTime date) async {
    final seq = ++_estimateSeq;
    setState(() {
      _selectedDate = date;
      _birthdayHeight = null;
      _isEstimating = true;
      _submitError = null;
    });

    try {
      final estimatedHeight = await ref
          .read(rpcEndpointFailoverProvider.notifier)
          .runWithEndpointFallback(
            operation: 'import birthday estimate',
            action: (endpoint) =>
                ImportBirthdayEstimator.estimateBirthdayHeight(
                  endpoint: endpoint,
                  selectedDate: date,
                ),
          );
      if (!mounted || seq != _estimateSeq) return;
      setState(() {
        _selectedDate = date;
        _birthdayHeight = estimatedHeight;
        _isEstimating = false;
      });
    } catch (e, st) {
      log('ImportWalletBirthdayScreen._estimateSelectedDate: ERROR: $e\n$st');
      if (!mounted || seq != _estimateSeq) return;
      setState(() {
        _isEstimating = false;
        _submitError = 'Could not estimate the wallet birthday height.';
      });
    }
  }

  void _handleTabSelected(ImportBirthdayTab tab) {
    if (tab == ImportBirthdayTab.blockHeight) {
      _estimateSeq++;
      setState(() {
        _activeTab = tab;
        _isEstimating = false;
        _submitError = null;
      });
      return;
    }

    setState(() {
      _activeTab = tab;
      _submitError = null;
    });
    if (tab == ImportBirthdayTab.date &&
        _selectedDate != null &&
        _birthdayHeight == null &&
        !_isEstimating) {
      _estimateSelectedDate(_selectedDate!);
    }
  }

  Future<void> _pickDate() async {
    final firstDate = _calendarFirstDate;
    final lastDate = _calendarLastDate;
    final initialDate = _clampDate(
      _selectedDate ?? lastDate,
      firstDate,
      lastDate,
    );

    setState(() {
      _calendarInitialDate = initialDate;
      _isCalendarOpen = true;
      _submitError = null;
    });
  }

  void _dismissCalendar() {
    if (!_isCalendarOpen) return;
    setState(() {
      _isCalendarOpen = false;
    });
  }

  void _showUnknownBirthdayConfirmation() {
    if (_isSubmitting) return;
    setState(() {
      _isCalendarOpen = false;
      _isUnknownBirthdayConfirmOpen = true;
      _submitError = null;
    });
  }

  void _dismissUnknownBirthdayConfirmation() {
    if (!_isUnknownBirthdayConfirmOpen) return;
    setState(() {
      _isUnknownBirthdayConfirmOpen = false;
    });
  }

  void _confirmAccountDiscovery(List<int> accountIndices) {
    _completeAccountDiscovery(accountIndices, updateState: true);
  }

  void _dismissAccountDiscovery() {
    _completeAccountDiscovery(null, updateState: true);
    setState(() {
      _submitPhase = _ImportWalletSubmitPhase.idle;
    });
  }

  void _completeAccountDiscovery(
    List<int>? accountIndices, {
    bool updateState = false,
  }) {
    final completer = _accountDiscoveryCompleter;
    void clearDiscoveryState() {
      _accountDiscoveryCandidates = null;
      _accountDiscoveryCompleter = null;
      _accountDiscoveryAllowsEmptySelection = true;
    }

    if (updateState && mounted) {
      setState(clearDiscoveryState);
    } else {
      clearDiscoveryState();
    }

    if (completer != null && !completer.isCompleted) {
      completer.complete(accountIndices);
    }
  }

  Future<void> _confirmUnknownBirthday() async {
    if (_isSubmitting) return;
    setState(() {
      _isUnknownBirthdayConfirmOpen = false;
    });
    await _submit(birthdayHeightOverride: _minimumBirthdayHeight);
  }

  Future<void> _handleCalendarDateSelected(DateTime selected) async {
    setState(() {
      _isCalendarOpen = false;
    });
    await _estimateSelectedDate(selected);
  }

  DateTime get _calendarFirstDate {
    final metadataDate = _metadata?.saplingActivationDate;
    if (metadataDate != null) return metadataDate;

    final networkName = ref.read(rpcEndpointProvider).networkName;
    if (networkName == 'regtest') {
      return _dateOnly(DateTime.now().subtract(const Duration(days: 6)));
    }

    // UI-only fallback so the picker can open while endpoint metadata loads.
    // The eventual height estimate still clamps pre-Sapling dates correctly.
    return DateTime(2016, 10, 28);
  }

  DateTime get _calendarLastDate {
    final firstDate = _calendarFirstDate;
    final lastDate = _dateOnly(_metadata?.tipDate ?? DateTime.now());
    if (lastDate.isBefore(firstDate)) return firstDate;
    return lastDate;
  }

  Future<void> _submit({int? birthdayHeightOverride}) async {
    final mnemonic = widget.args.mnemonic;
    final birthdayHeight = birthdayHeightOverride ?? _resolvedBirthdayHeight();
    if (_isSubmitting || birthdayHeight == null) {
      return;
    }

    setState(() {
      _submitPhase = _ImportWalletSubmitPhase.importing;
      _submitError = null;
    });

    try {
      final security = ref.read(appSecurityProvider);
      if (!security.isPasswordConfigured) {
        final selectedAdditionalAccountIndices =
            await _resolveAdditionalAccountIndices(
              mnemonic: mnemonic,
              birthdayHeight: birthdayHeight,
            );
        if (selectedAdditionalAccountIndices == null) return;
        if (!mounted) return;
        context.go(
          '/import/set-password',
          extra: SetPasswordScreenArgs.importWallet(
            mnemonic: mnemonic,
            birthdayHeight: birthdayHeight,
            selectedAdditionalAccountIndices: selectedAdditionalAccountIndices,
          ),
        );
        return;
      }

      final accountNotifier = ref.read(accountProvider.notifier);
      final router = GoRouter.of(context);
      final routerRefresh = ref.read(routerRefreshProvider);
      await routerRefresh.pauseWhile(() async {
        final imported = await runWithSyncPausedForAccountMutation(
          ref,
          () async {
            final selectedAdditionalAccountIndices =
                await _resolveAdditionalAccountIndices(
                  mnemonic: mnemonic,
                  birthdayHeight: birthdayHeight,
                );
            if (selectedAdditionalAccountIndices == null) return false;
            if (!mounted) return false;
            setState(() {
              _submitPhase = _ImportWalletSubmitPhase.importing;
            });
            await accountNotifier.importAccount(
              mnemonic: mnemonic,
              birthdayHeight: birthdayHeight,
              additionalAccountIndices: selectedAdditionalAccountIndices,
            );
            return true;
          },
          onStoppingSync: () {
            if (!mounted) return;
            setState(() {
              _submitPhase = _ImportWalletSubmitPhase.stoppingSync;
            });
          },
          onSyncPaused: () {
            if (!mounted) return;
            setState(() {
              _submitPhase = _ImportWalletSubmitPhase.importing;
            });
          },
        );
        if (!imported || !mounted) return;
        router.go('/home');
      });
    } catch (e, st) {
      log('ImportWalletBirthdayScreen._submit: ERROR: $e\n$st');
      if (!mounted) return;
      setState(() {
        _submitPhase = _ImportWalletSubmitPhase.idle;
        _submitError = onboardingSubmitErrorMessage(e);
      });
      return;
    }
  }

  Future<List<int>?> _resolveAdditionalAccountIndices({
    required String mnemonic,
    required int birthdayHeight,
  }) async {
    setState(() {
      _submitPhase = _ImportWalletSubmitPhase.discoveringAccounts;
    });

    final discovery = await ref
        .read(accountProvider.notifier)
        .discoverAdditionalSoftwareAccounts(
          mnemonic: mnemonic,
          birthdayHeight: birthdayHeight,
        );
    if (!mounted) return null;
    final candidates = discovery.accounts;
    if (candidates.isEmpty) return const [];

    final completer = Completer<List<int>?>();
    setState(() {
      _accountDiscoveryCandidates = candidates;
      _accountDiscoveryCompleter = completer;
      _accountDiscoveryAllowsEmptySelection =
          !discovery.primaryAccountAlreadyExists;
      _submitPhase = _ImportWalletSubmitPhase.idle;
    });
    return completer.future;
  }

  int? _resolvedBirthdayHeight() {
    return switch (_activeTab) {
      ImportBirthdayTab.date => _birthdayHeight,
      ImportBirthdayTab.blockHeight => _validatedManualHeight,
    };
  }

  int? get _validatedManualHeight {
    final value = int.tryParse(_manualHeightController.text.trim());
    if (value == null) return null;
    final minimumHeight = _minimumBirthdayHeight;
    if (value < minimumHeight) {
      return null;
    }
    final maximumHeight = _metadata?.tipHeight;
    if (maximumHeight != null && value > maximumHeight) {
      return null;
    }
    return value;
  }

  String? get _manualHeightError {
    final text = _manualHeightController.text.trim();
    if (text.isEmpty) return null;
    final parsed = int.tryParse(text);
    if (parsed == null) return _manualHeightErrorText;
    if (parsed < _minimumBirthdayHeight) {
      return _manualHeightErrorText;
    }
    final maximumHeight = _metadata?.tipHeight;
    if (maximumHeight != null && parsed > maximumHeight) {
      return _manualHeightErrorText;
    }
    if (_metadataError != null) return _metadataError;
    return null;
  }

  String? get _dateMessage {
    if (_metadataError != null) return _metadataError;
    return null;
  }

  bool get _isSubmitEnabled {
    return switch (_activeTab) {
      ImportBirthdayTab.date =>
        _birthdayHeight != null && !_isSubmitting && !_isEstimating,
      ImportBirthdayTab.blockHeight =>
        _validatedManualHeight != null && !_isSubmitting,
    };
  }

  @override
  Widget build(BuildContext context) {
    final activeTab = _activeTab;
    final calendarFirstDate = _calendarFirstDate;
    final calendarLastDate = _calendarLastDate;
    final buttonLabel = switch (_submitPhase) {
      _ImportWalletSubmitPhase.discoveringAccounts => 'Checking accounts...',
      _ImportWalletSubmitPhase.stoppingSync => 'Stop syncing...',
      _ImportWalletSubmitPhase.importing => 'Importing...',
      _ImportWalletSubmitPhase.idle =>
        activeTab == ImportBirthdayTab.date && _isEstimating
            ? 'Estimating...'
            : 'Continue',
    };

    return ImportOnboardingTrailingPane(
      backTarget: OnboardingBackTarget.callback(
        label: ImportOnboardingStep.secretPassphrase.label,
        onTap: () => context.go(
          '/import',
          extra: ImportSecretPassphraseArgs(mnemonic: widget.args.mnemonic),
        ),
      ),
      overlay: _accountDiscoveryCandidates != null
          ? ImportAccountDiscoveryModal(
              accounts: _accountDiscoveryCandidates!,
              allowEmptySelection: _accountDiscoveryAllowsEmptySelection,
              bip44CoinType: ref.read(rpcEndpointProvider).network.coinType,
              loadTransparentBalance: _loadAccountDiscoveryTransparentBalance,
              onConfirm: _confirmAccountDiscovery,
              onCancel: _dismissAccountDiscovery,
            )
          : _isUnknownBirthdayConfirmOpen
          ? ImportBirthdayUnknownHeightModal(
              onConfirm: _confirmUnknownBirthday,
              onCancel: _dismissUnknownBirthdayConfirmation,
            )
          : _isCalendarOpen
          ? ImportBirthdayCalendarOverlay(
              initialMonth: _calendarInitialDate ?? calendarLastDate,
              selectedDate: _selectedDate,
              firstDate: calendarFirstDate,
              lastDate: calendarLastDate,
              onDismiss: _dismissCalendar,
              onDateSelected: _handleCalendarDateSelected,
            )
          : null,
      child: Column(
        children: [
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.s,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: _titleWidth,
                            child: Text(
                              'Around when did you create your wallet?',
                              style: AppTypography.displayLarge.copyWith(
                                color: context.colors.text.accent,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          SizedBox(
                            width: _subtitleWidth,
                            child: Text(
                              'Zcash (ZEC) built around financial privacy '
                              '& self-custody.',
                              style: AppTypography.bodyMedium.copyWith(
                                color: context.colors.text.primary,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          // Figma On Page Content gap (Spacing/base = 32).
                          const SizedBox(height: AppSpacing.base),
                          SizedBox(
                            width: _widgetWidth,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _BirthdayTabRow(
                                  activeTab: activeTab,
                                  onTabSelected: _handleTabSelected,
                                ),
                                const SizedBox(height: AppSpacing.md),
                                if (activeTab == ImportBirthdayTab.date)
                                  _DatePickerField(
                                    width: _fieldWidth,
                                    valueText: _selectedDate == null
                                        ? null
                                        : _formatDate(_selectedDate!),
                                    enabled: !_isSubmitting,
                                    onTap: _pickDate,
                                  )
                                else
                                  _BlockHeightField(
                                    controller: _manualHeightController,
                                    focusNode: _manualHeightFocusNode,
                                    width: _fieldWidth,
                                    errorText: _manualHeightError,
                                    onChanged: (value) {
                                      setState(() {
                                        _submitError = null;
                                      });
                                    },
                                  ),
                                const SizedBox(height: AppSpacing.xxs),
                                SizedBox(
                                  width: _fieldWidth,
                                  height: _messageHeight,
                                  child: activeTab == ImportBirthdayTab.date
                                      ? _InlineMessage(text: _dateMessage)
                                      : _InlineMessage(
                                          text: _manualHeightError,
                                        ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                SizedBox(
                  width: _widgetWidth,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_submitError != null &&
                          _submitError!.trim().isNotEmpty) ...[
                        _InlineMessage(text: _submitError, centered: true),
                        const SizedBox(height: AppSpacing.s),
                      ],
                      AppButton(
                        key: const ValueKey('import_birthday_submit_button'),
                        onPressed: _isSubmitEnabled ? _submit : null,
                        variant: AppButtonVariant.primary,
                        minWidth: _buttonWidth,
                        trailing: const AppIcon(AppIcons.chevronForward),
                        child: Text(buttonLabel),
                      ),
                      const SizedBox(height: AppSpacing.s),
                      AppButton(
                        key: const ValueKey('import_birthday_skip_button'),
                        onPressed: _isSubmitting
                            ? null
                            : _showUnknownBirthdayConfirmation,
                        variant: AppButtonVariant.ghost,
                        minWidth: _buttonWidth,
                        trailing: const AppIcon(AppIcons.skip),
                        child: const Text('I can’t remember'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<BigInt> _loadAccountDiscoveryTransparentBalance(
    rust_wallet.SoftwareWalletDiscoveredAccount account,
  ) {
    return ref
        .read(accountProvider.notifier)
        .previewSoftwareAccountTransparentBalance(
          mnemonic: widget.args.mnemonic,
          accountIndex: account.zip32AccountIndex,
        );
  }
}

class _BirthdayTabRow extends StatelessWidget {
  const _BirthdayTabRow({required this.activeTab, required this.onTabSelected});

  final ImportBirthdayTab activeTab;
  final ValueChanged<ImportBirthdayTab> onTabSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _TabLabel(
            iconName: AppIcons.calendar,
            label: 'Enter the date',
            active: activeTab == ImportBirthdayTab.date,
            onTap: () => onTabSelected(ImportBirthdayTab.date),
            color: colors.text.accent,
          ),
          const SizedBox(width: AppSpacing.xs),
          _TabLabel(
            iconName: AppIcons.block,
            label: 'Enter the block height',
            active: activeTab == ImportBirthdayTab.blockHeight,
            onTap: () => onTabSelected(ImportBirthdayTab.blockHeight),
            color: colors.text.accent,
          ),
        ],
      ),
    );
  }
}

class _TabLabel extends StatelessWidget {
  const _TabLabel({
    required this.iconName,
    required this.label,
    required this.active,
    required this.onTap,
    required this.color,
  });

  final String iconName;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final style = active
        ? AppTypography.bodyMediumStrong.copyWith(color: color)
        : AppTypography.bodyMedium.copyWith(color: color);
    return Semantics(
      button: true,
      selected: active,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Opacity(
            opacity: active ? 1 : 0.5,
            child: SizedBox(
              height: 25,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xxs,
                  vertical: 2,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppIcon(iconName, size: 16, color: color),
                    const SizedBox(width: AppSpacing.xxs),
                    Text(label, style: style, textAlign: TextAlign.center),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DatePickerField extends StatelessWidget {
  const _DatePickerField({
    required this.width,
    required this.valueText,
    required this.enabled,
    required this.onTap,
  });

  final double width;
  final String? valueText;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final valueColor = valueText == null
        ? colors.text.muted
        : colors.text.accent;
    return Semantics(
      button: true,
      enabled: enabled,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? onTap : null,
          child: Container(
            width: width,
            height: 46,
            padding: const EdgeInsets.only(left: AppSpacing.s, right: 10),
            decoration: BoxDecoration(
              color: colors.surface.input.primary,
              borderRadius: BorderRadius.circular(AppRadii.small),
              border: Border.all(color: const Color(0x00000000), width: 1.5),
              boxShadow: _birthdayFieldSurfaceShadow(colors),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    valueText ?? 'mm/dd/yyyy',
                    style: AppTypography.labelLarge.copyWith(
                      color: valueColor,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
                AppIcon(
                  AppIcons.calendar,
                  size: 20,
                  color: enabled ? colors.icon.accent : colors.icon.disabled,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BlockHeightField extends StatelessWidget {
  const _BlockHeightField({
    required this.controller,
    required this.focusNode,
    required this.width,
    required this.errorText,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final double width;
  final String? errorText;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final hasError = errorText != null;
    final borderColor = hasError
        ? colors.border.utilityDestructive
        : focusNode.hasFocus
        ? colors.background.inverse
        : const Color(0x00000000);

    return Container(
      width: width,
      height: 46,
      decoration: BoxDecoration(
        color: hasError
            ? Color.alphaBlend(
                colors.background.utilityDestructiveAlphaSubtle,
                colors.surface.input.primary,
              )
            : colors.surface.input.primary,
        borderRadius: BorderRadius.circular(AppRadii.small),
        border: Border.all(color: borderColor, width: 1.5),
        boxShadow: hasError
            ? const <BoxShadow>[]
            : _birthdayFieldSurfaceShadow(colors),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: Center(
              child: AppIcon(
                AppIcons.block,
                size: 20,
                color: hasError ? colors.icon.destructive : colors.icon.accent,
              ),
            ),
          ),
          Expanded(
            child: material.TextField(
              controller: controller,
              focusNode: focusNode,
              keyboardType: material.TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: onChanged,
              style: AppTypography.labelLarge.copyWith(
                color: colors.text.accent,
                fontWeight: FontWeight.w500,
              ),
              cursorColor: colors.text.accent,
              decoration: material.InputDecoration.collapsed(
                hintText: 'Block height',
                hintStyle: AppTypography.labelLarge.copyWith(
                  color: colors.text.muted,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ),
          const SizedBox(width: 40),
        ],
      ),
    );
  }
}

class _InlineMessage extends StatelessWidget {
  const _InlineMessage({required this.text, this.centered = false});

  final String? text;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    if (text == null || text!.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    final colors = context.colors;
    final errorColor = colors.border.utilityDestructive;
    final messageText = Text(
      text!,
      textAlign: centered ? TextAlign.center : null,
      style: AppTypography.labelLarge.copyWith(
        color: errorColor,
        fontWeight: FontWeight.w400,
      ),
    );
    return Row(
      mainAxisAlignment: centered
          ? MainAxisAlignment.center
          : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppIcon(AppIcons.warning, size: 16, color: errorColor),
        const SizedBox(width: AppSpacing.xxs),
        if (centered)
          Flexible(child: messageText)
        else
          Expanded(child: messageText),
      ],
    );
  }
}

List<BoxShadow> _birthdayFieldSurfaceShadow(AppColors colors) {
  return [
    BoxShadow(color: colors.shadows.subtle, blurRadius: 1),
    BoxShadow(
      color: colors.shadows.subtle,
      offset: const Offset(0, 2),
      blurRadius: 4,
    ),
    BoxShadow(
      color: colors.shadows.subtle,
      offset: const Offset(0, 1),
      blurRadius: 2,
    ),
    BoxShadow(color: colors.shadows.subtle, blurRadius: 1),
  ];
}

DateTime _clampDate(DateTime value, DateTime min, DateTime max) {
  final date = DateTime(value.year, value.month, value.day);
  final minDate = DateTime(min.year, min.month, min.day);
  final maxDate = DateTime(max.year, max.month, max.day);
  if (date.isBefore(minDate)) return minDate;
  if (date.isAfter(maxDate)) return maxDate;
  return date;
}

DateTime _dateOnly(DateTime value) {
  return DateTime(value.year, value.month, value.day);
}

String _formatDate(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '$month/$day/${date.year}';
}
