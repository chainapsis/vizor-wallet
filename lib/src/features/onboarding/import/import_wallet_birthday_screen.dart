import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../main.dart' show log;
import '../../../core/config/rpc_endpoint_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/app_security_provider.dart';
import '../../../providers/rpc_endpoint_failover_provider.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../providers/wallet_mutation_guard.dart';
import '../shared/onboarding_error_messages.dart';
import '../shared/onboarding_flow_args.dart';
import 'import_birthday_estimator.dart';
import 'import_birthday_calendar_overlay.dart';
import 'import_birthday_unknown_height_modal.dart';
import 'import_split_view.dart';

enum ImportBirthdayTab { date, blockHeight }

enum _ImportWalletSubmitPhase { idle, stoppingSync, importing }

class ImportWalletBirthdayScreen extends ConsumerStatefulWidget {
  const ImportWalletBirthdayScreen({required this.args, super.key});

  final ImportBirthdayArgs args;

  @override
  ConsumerState<ImportWalletBirthdayScreen> createState() =>
      _ImportWalletBirthdayScreenState();
}

class _ImportWalletBirthdayScreenState
    extends ConsumerState<ImportWalletBirthdayScreen> {
  static const _titleWidth = 574.0;
  static const _subtitleWidth = 270.0;
  static const _widgetWidth = 304.0;
  static const _buttonWidth = 256.0;
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
    _manualHeightFocusNode
      ..removeListener(_handleFocusChanged)
      ..dispose();
    _manualHeightController.dispose();
    super.dispose();
  }

  void _handleFocusChanged() {
    if (mounted) setState(() {});
  }

  int get _minimumBirthdayHeight {
    final endpoint = ref.read(rpcEndpointProvider);
    if (isLocalIronwoodTestnetEndpoint(endpoint)) return 1;
    return _metadata?.saplingActivationHeight ??
        endpoint.network.saplingActivationHeight;
  }

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
        if (!mounted) return;
        context.go(
          '/import/set-password',
          extra: SetPasswordScreenArgs.importWallet(
            mnemonic: mnemonic,
            birthdayHeight: birthdayHeight,
          ),
        );
        return;
      }

      final accountNotifier = ref.read(accountProvider.notifier);
      final router = GoRouter.of(context);
      await runWithSyncPausedForAccountMutation(
        ref,
        () => accountNotifier.importAccount(
          mnemonic: mnemonic,
          birthdayHeight: birthdayHeight,
        ),
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
      router.go('/home');
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

  int? _resolvedBirthdayHeight() {
    return switch (_activeTab) {
      ImportBirthdayTab.date => _birthdayHeight,
      ImportBirthdayTab.blockHeight => _validatedManualHeight,
    };
  }

  int? get _validatedManualHeight {
    final value = _parseManualHeight(_manualHeightController.text);
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
    final parsed = _parseManualHeight(text);
    if (parsed == null) return "That doesn't look like a valid block height.";
    if (parsed < _minimumBirthdayHeight) {
      return "That doesn't look like a valid block height.";
    }
    final maximumHeight = _metadata?.tipHeight;
    if (maximumHeight != null && parsed > maximumHeight) {
      return "That doesn't look like a valid block height.";
    }
    if (_metadataError != null) return _metadataError;
    return null;
  }

  int? _parseManualHeight(String text) {
    final trimmed = text.trim();
    return int.tryParse(
      trimmed.endsWith('.')
          ? trimmed.substring(0, trimmed.length - 1)
          : trimmed,
    );
  }

  String? get _dateMessage {
    if (_submitError != null && _submitError!.isNotEmpty) return _submitError;
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
      _ImportWalletSubmitPhase.stoppingSync => 'Stop syncing...',
      _ImportWalletSubmitPhase.importing => 'Importing...',
      _ImportWalletSubmitPhase.idle =>
        activeTab == ImportBirthdayTab.date && _isEstimating
            ? 'Estimating...'
            : 'Continue',
    };

    return ImportOnboardingTrailingPane(
      overlay: _isUnknownBirthdayConfirmOpen
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
          _BackRow(
            onTap: () => context.go(
              '/import',
              extra: ImportSecretPassphraseArgs(mnemonic: widget.args.mnemonic),
            ),
          ),
          const SizedBox(height: AppSpacing.s),
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
                              'Around when did you\ncreate your wallet?',
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
                              'It helps us import your wallet faster.',
                              style: AppTypography.bodyMedium.copyWith(
                                color: context.colors.text.accent,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.lg),
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
                                    width: _widgetWidth,
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
                                    width: _widgetWidth,
                                    errorText: _manualHeightError,
                                    onChanged: (value) {
                                      setState(() {
                                        _submitError = null;
                                      });
                                    },
                                  ),
                                const SizedBox(height: AppSpacing.xxs),
                                SizedBox(
                                  width: _widgetWidth,
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
                  width: _buttonWidth,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppButton(
                        key: const ValueKey('import_birthday_submit_button'),
                        onPressed: _isSubmitEnabled ? _submit : null,
                        variant: AppButtonVariant.primary,
                        minWidth: _buttonWidth,
                        trailing: const AppIcon(AppIcons.chevronForward),
                        child: Text(buttonLabel),
                      ),
                      const SizedBox(height: AppSpacing.xs),
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
}

class _BackRow extends StatelessWidget {
  const _BackRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      height: 32,
      child: Align(
        alignment: Alignment.centerLeft,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIcon(
                  AppIcons.chevronBackward,
                  size: AppIconSize.medium,
                  color: colors.text.accent,
                ),
                const SizedBox(width: AppSpacing.xxs),
                Text(
                  'Back',
                  style: AppTypography.labelLarge.copyWith(
                    color: colors.text.accent,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _TabLabel(
          label: 'Enter the Date',
          active: activeTab == ImportBirthdayTab.date,
          onTap: () => onTabSelected(ImportBirthdayTab.date),
          activeColor: colors.text.accent,
          inactiveColor: colors.text.muted,
        ),
        const SizedBox(width: 10),
        _TabLabel(
          label: 'Enter the Block Height',
          active: activeTab == ImportBirthdayTab.blockHeight,
          onTap: () => onTabSelected(ImportBirthdayTab.blockHeight),
          activeColor: colors.text.accent,
          inactiveColor: colors.text.muted,
        ),
      ],
    );
  }
}

class _TabLabel extends StatelessWidget {
  const _TabLabel({
    required this.label,
    required this.active,
    required this.onTap,
    required this.activeColor,
    required this.inactiveColor,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final Color activeColor;
  final Color inactiveColor;

  @override
  Widget build(BuildContext context) {
    final style = active
        ? AppTypography.bodyMediumStrong.copyWith(color: activeColor)
        : AppTypography.bodyMedium.copyWith(color: inactiveColor);
    return Semantics(
      button: true,
      selected: active,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Text(label, style: style),
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
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s),
            decoration: BoxDecoration(
              color: colors.background.base,
              borderRadius: BorderRadius.circular(AppRadii.small),
              border: Border.all(color: colors.border.medium, width: 1.5),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    valueText ?? 'mm/dd/yyyy',
                    style: AppTypography.labelLarge.copyWith(color: valueColor),
                  ),
                ),
                AppIcon(
                  AppIcons.calendar,
                  size: 20,
                  color: enabled ? colors.icon.accent : colors.icon.regular,
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
        ? colors.border.medium
        : colors.border.subtle;

    return Container(
      width: width,
      height: 46,
      decoration: BoxDecoration(
        color: colors.background.base,
        borderRadius: BorderRadius.circular(AppRadii.small),
        border: Border.all(color: borderColor, width: 1.5),
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
              ),
              cursorColor: colors.text.accent,
              decoration: material.InputDecoration.collapsed(
                hintText: 'Block Height',
                hintStyle: AppTypography.labelLarge.copyWith(
                  color: colors.text.muted,
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
  const _InlineMessage({required this.text});

  final String? text;

  @override
  Widget build(BuildContext context) {
    if (text == null || text!.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    final colors = context.colors;
    return Row(
      children: [
        AppIcon(AppIcons.warning, size: 16, color: colors.text.destructive),
        const SizedBox(width: AppSpacing.xxs),
        Expanded(
          child: Text(
            text!,
            style: AppTypography.labelMedium.copyWith(
              color: colors.text.destructive,
            ),
          ),
        ),
      ],
    );
  }
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
