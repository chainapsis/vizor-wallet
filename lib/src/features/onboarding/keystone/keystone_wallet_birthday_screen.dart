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
import '../import/import_birthday_unknown_height_modal.dart';
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
  static const _manualHeightErrorText =
      "That doesn't look like a valid block height.";
  static const _titleWidth = 396.0;
  static const _subtitleWidth = 226.0;
  static const _widgetWidth = 304.0;
  static const _fieldWidth = 256.0;
  static const _buttonWidth = 230.0;
  static const _messageHeight = 16.0;

  late final TextEditingController _manualHeightController;
  late final FocusNode _manualHeightFocusNode;

  ImportBirthdayMetadata? _metadata;
  KeystoneBirthdayTab _activeTab = KeystoneBirthdayTab.date;
  DateTime? _selectedDate;
  int? _birthdayHeight;
  bool _isEstimating = false;
  bool _isCalendarOpen = false;
  bool _isUnknownBirthdayConfirmOpen = false;
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
      });

      if (_selectedDate != null && _birthdayHeight == null) {
        await _estimateSelectedDate(_selectedDate!);
      }
    } catch (e, st) {
      log('KeystoneWalletBirthdayScreen._loadMetadata: ERROR: $e\n$st');
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
      KeystoneBirthdayTab.date =>
        _birthdayHeight != null && !_isSubmitting && !_isEstimating,
      KeystoneBirthdayTab.blockHeight =>
        _validatedManualHeight != null && !_isSubmitting,
    };
  }

  @override
  Widget build(BuildContext context) {
    final activeTab = _activeTab;
    final calendarFirstDate = _calendarFirstDate;
    final calendarLastDate = _calendarLastDate;
    final buttonLabel = switch (_submitPhase) {
      _KeystoneBirthdaySubmitPhase.stoppingSync => 'Stop syncing...',
      _KeystoneBirthdaySubmitPhase.importing => 'Importing...',
      _KeystoneBirthdaySubmitPhase.idle =>
        activeTab == KeystoneBirthdayTab.date && _isEstimating
            ? 'Estimating...'
            : 'Continue',
    };

    return KeystoneOnboardingTrailingPane(
      backTarget: OnboardingBackTarget.route(
        label: KeystoneOnboardingStep.selectAccount.label,
        routePath: KeystoneOnboardingStep.selectAccount.routePath,
      ),
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
                                fontFamily: 'Young Serif',
                                fontWeight: FontWeight.w400,
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
                                color: context.colors.text.primary,
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
                        key: const ValueKey('keystone_birthday_submit_button'),
                        onPressed: _isSubmitEnabled ? _submit : null,
                        variant: AppButtonVariant.primary,
                        minWidth: _buttonWidth,
                        trailing: const AppIcon(AppIcons.chevronForward),
                        child: Text(buttonLabel),
                      ),
                      const SizedBox(height: AppSpacing.s),
                      AppButton(
                        key: const ValueKey('keystone_birthday_skip_button'),
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

class _BirthdayTabRow extends StatelessWidget {
  const _BirthdayTabRow({required this.activeTab, required this.onTabSelected});

  final KeystoneBirthdayTab activeTab;
  final ValueChanged<KeystoneBirthdayTab> onTabSelected;

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
            active: activeTab == KeystoneBirthdayTab.date,
            onTap: () => onTabSelected(KeystoneBirthdayTab.date),
            color: colors.text.accent,
          ),
          const SizedBox(width: AppSpacing.xs),
          _TabLabel(
            iconName: AppIcons.block,
            label: 'Enter the block height',
            active: activeTab == KeystoneBirthdayTab.blockHeight,
            onTap: () => onTabSelected(KeystoneBirthdayTab.blockHeight),
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
              color: colors.surface.input,
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
                colors.surface.input,
              )
            : colors.surface.input,
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
