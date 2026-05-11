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
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../providers/wallet_mutation_guard.dart';
import '../import/import_birthday_calendar_overlay.dart';
import '../import/import_birthday_estimator.dart';
import '../shared/onboarding_error_messages.dart';
import '../shared/onboarding_flow_args.dart';
import 'keystone_onboarding_flow.dart';

enum KeystoneBirthdayTab { date, blockHeight }

enum _KeystoneBirthdaySubmitPhase { idle, stoppingSync, importing }

class KeystoneWalletBirthdayScreen extends ConsumerStatefulWidget {
  const KeystoneWalletBirthdayScreen({super.key});

  @override
  ConsumerState<KeystoneWalletBirthdayScreen> createState() =>
      _KeystoneWalletBirthdayScreenState();
}

class _KeystoneWalletBirthdayScreenState
    extends ConsumerState<KeystoneWalletBirthdayScreen> {
  static const _titleWidth = 574.0;
  static const _subtitleWidth = 270.0;
  static const _widgetWidth = 304.0;
  static const _buttonWidth = 256.0;
  static const _messageHeight = 16.0;

  late final TextEditingController _manualHeightController;
  late final FocusNode _manualHeightFocusNode;

  ImportBirthdayMetadata? _metadata;
  KeystoneBirthdayTab _activeTab = KeystoneBirthdayTab.date;
  DateTime? _selectedDate;
  int? _birthdayHeight;
  bool _isLoadingMetadata = true;
  bool _isEstimating = false;
  bool _isCalendarOpen = false;
  _KeystoneBirthdaySubmitPhase _submitPhase = _KeystoneBirthdaySubmitPhase.idle;
  String? _metadataError;
  String? _submitError;
  DateTime? _calendarInitialDate;
  int _estimateSeq = 0;

  bool get _isSubmitting => _submitPhase != _KeystoneBirthdaySubmitPhase.idle;

  @override
  void initState() {
    super.initState();
    _manualHeightController = TextEditingController();
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

  int get _minimumBirthdayHeight =>
      ref.read(rpcEndpointProvider).network.saplingActivationHeight;

  Future<void> _loadMetadata() async {
    setState(() {
      _isLoadingMetadata = true;
      _metadataError = null;
    });

    try {
      final endpoint = ref.read(rpcEndpointProvider);
      final metadata = await ImportBirthdayEstimator.loadMetadata(
        endpoint: endpoint,
      );
      if (!mounted) return;
      setState(() {
        _metadata = metadata;
        _isLoadingMetadata = false;
      });

      if (_selectedDate != null && _birthdayHeight == null) {
        await _estimateSelectedDate(_selectedDate!);
      }
    } catch (e, st) {
      log('KeystoneWalletBirthdayScreen._loadMetadata: ERROR: $e\n$st');
      if (!mounted) return;
      setState(() {
        _isLoadingMetadata = false;
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
      final endpoint = ref.read(rpcEndpointProvider);
      final estimatedHeight =
          await ImportBirthdayEstimator.estimateBirthdayHeight(
            endpoint: endpoint,
            selectedDate: date,
          );
      if (!mounted || seq != _estimateSeq) return;
      setState(() {
        _selectedDate = date;
        _birthdayHeight = estimatedHeight;
        _isEstimating = false;
      });
    } catch (e, st) {
      log('KeystoneWalletBirthdayScreen._estimateSelectedDate: ERROR: $e\n$st');
      if (!mounted || seq != _estimateSeq) return;
      setState(() {
        _isEstimating = false;
        _submitError = 'Could not estimate the wallet birthday height.';
      });
    }
  }

  void _handleTabSelected(KeystoneBirthdayTab tab) {
    if (tab == KeystoneBirthdayTab.blockHeight) {
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
    if (tab == KeystoneBirthdayTab.date &&
        _selectedDate != null &&
        _birthdayHeight == null &&
        !_isEstimating) {
      _estimateSelectedDate(_selectedDate!);
    }
  }

  Future<void> _pickDate() async {
    final metadata = _metadata;
    if (metadata == null) return;
    final initialDate = _clampDate(
      _selectedDate ?? metadata.tipDate,
      metadata.saplingActivationDate,
      metadata.tipDate,
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

  Future<void> _handleCalendarDateSelected(DateTime selected) async {
    setState(() {
      _isCalendarOpen = false;
    });
    await _estimateSelectedDate(selected);
  }

  Future<void> _submit({int? birthdayHeightOverride}) async {
    final birthdayHeight = birthdayHeightOverride ?? _resolvedBirthdayHeight();
    if (_isSubmitting || birthdayHeight == null) {
      return;
    }

    final account = ref.read(keystoneOnboardingProvider).selectedAccount;
    if (account == null) {
      context.go(KeystoneOnboardingStep.selectAccount.routePath);
      return;
    }

    setState(() {
      _submitPhase = _KeystoneBirthdaySubmitPhase.importing;
      _submitError = null;
    });

    try {
      final security = ref.read(appSecurityProvider);
      if (!security.isPasswordConfigured) {
        if (!mounted) return;
        context.go(
          KeystoneOnboardingStep.setPassword.routePath,
          extra: SetPasswordScreenArgs.importKeystone(
            name: account.name,
            ufvk: account.ufvk,
            seedFingerprint: account.seedFingerprint.toList(),
            zip32Index: account.index,
            birthdayHeight: birthdayHeight,
          ),
        );
        return;
      }

      final accountNotifier = ref.read(accountProvider.notifier);
      final router = GoRouter.of(context);
      await runWithSyncPausedForAccountMutation(
        ref,
        () => accountNotifier.importKeystoneAccount(
          name: account.name,
          ufvk: account.ufvk,
          seedFingerprint: account.seedFingerprint.toList(),
          zip32Index: account.index,
          birthdayHeight: birthdayHeight,
        ),
        onStoppingSync: () {
          if (!mounted) return;
          setState(() {
            _submitPhase = _KeystoneBirthdaySubmitPhase.stoppingSync;
          });
        },
        onSyncPaused: () {
          if (!mounted) return;
          setState(() {
            _submitPhase = _KeystoneBirthdaySubmitPhase.importing;
          });
        },
      );

      ref.read(keystoneOnboardingProvider.notifier).resetScan();
      router.go('/home');
    } catch (e, st) {
      log('KeystoneWalletBirthdayScreen._submit: ERROR: $e\n$st');
      if (!mounted) return;
      setState(() {
        _submitPhase = _KeystoneBirthdaySubmitPhase.idle;
        _submitError = onboardingSubmitErrorMessage(e);
      });
      return;
    }
  }

  int? _resolvedBirthdayHeight() {
    return switch (_activeTab) {
      KeystoneBirthdayTab.date => _birthdayHeight,
      KeystoneBirthdayTab.blockHeight => _validatedManualHeight,
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
    if (parsed == null) return 'Doesn’t seem like a legit block height';
    if (parsed < _minimumBirthdayHeight) {
      return 'Doesn’t seem like a legit block height';
    }
    final maximumHeight = _metadata?.tipHeight;
    if (maximumHeight != null && parsed > maximumHeight) {
      return 'Doesn’t seem like a legit block height';
    }
    if (_metadataError != null) return _metadataError;
    return null;
  }

  String? get _dateMessage {
    if (_submitError != null && _submitError!.isNotEmpty) return _submitError;
    if (_metadataError != null) return _metadataError;
    return null;
  }

  bool get _isSubmitEnabled {
    return switch (_activeTab) {
      KeystoneBirthdayTab.date =>
        _birthdayHeight != null && !_isSubmitting && !_isEstimating,
      KeystoneBirthdayTab.blockHeight =>
        _validatedManualHeight != null && !_isSubmitting,
    };
  }

  @override
  Widget build(BuildContext context) {
    final activeTab = _activeTab;
    final buttonLabel = switch (_submitPhase) {
      _KeystoneBirthdaySubmitPhase.stoppingSync => 'Stop syncing...',
      _KeystoneBirthdaySubmitPhase.importing => 'Importing...',
      _KeystoneBirthdaySubmitPhase.idle =>
        activeTab == KeystoneBirthdayTab.date && _isEstimating
            ? 'Estimating...'
            : 'Continue',
    };

    return KeystoneOnboardingTrailingPane(
      overlay: _isCalendarOpen && _metadata != null
          ? ImportBirthdayCalendarOverlay(
              initialMonth: _calendarInitialDate ?? _metadata!.tipDate,
              selectedDate: _selectedDate,
              firstDate: _metadata!.saplingActivationDate,
              lastDate: _metadata!.tipDate,
              onDismiss: _dismissCalendar,
              onDateSelected: _handleCalendarDateSelected,
            )
          : null,
      child: Column(
        children: [
          KeystoneBackRow(
            routePath: KeystoneOnboardingStep.selectAccount.routePath,
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
                              'This will help to import your wallet faster.',
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
                                if (activeTab == KeystoneBirthdayTab.date)
                                  _DatePickerField(
                                    width: _widgetWidth,
                                    valueText: _selectedDate == null
                                        ? null
                                        : _formatDate(_selectedDate!),
                                    enabled:
                                        !_isLoadingMetadata &&
                                        _metadata != null,
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
                                  child: activeTab == KeystoneBirthdayTab.date
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
                        key: const ValueKey('keystone_birthday_submit_button'),
                        onPressed: _isSubmitEnabled ? _submit : null,
                        variant: AppButtonVariant.primary,
                        minWidth: _buttonWidth,
                        trailing: const AppIcon(AppIcons.chevronForward),
                        child: Text(buttonLabel),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      AppButton(
                        key: const ValueKey('keystone_birthday_skip_button'),
                        onPressed: _isSubmitting
                            ? null
                            : () => _submit(
                                birthdayHeightOverride: _minimumBirthdayHeight,
                              ),
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

class _BirthdayTabRow extends StatelessWidget {
  const _BirthdayTabRow({required this.activeTab, required this.onTabSelected});

  final KeystoneBirthdayTab activeTab;
  final ValueChanged<KeystoneBirthdayTab> onTabSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _TabLabel(
          label: 'Enter the Date',
          active: activeTab == KeystoneBirthdayTab.date,
          onTap: () => onTabSelected(KeystoneBirthdayTab.date),
          activeColor: colors.text.accent,
          inactiveColor: colors.text.muted,
        ),
        const SizedBox(width: 10),
        _TabLabel(
          label: 'Enter the Block Height',
          active: activeTab == KeystoneBirthdayTab.blockHeight,
          onTap: () => onTabSelected(KeystoneBirthdayTab.blockHeight),
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
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Text(label, style: style),
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
    return GestureDetector(
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

String _formatDate(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '$month/$day/${date.year}';
}
