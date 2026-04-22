import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../main.dart' show log;
import '../../../app_bootstrap.dart';
import '../../../core/config/network_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_decorative_divider.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/app_security_provider.dart';
import '../shared/set_password_screen.dart';
import 'import_birthday_estimator.dart';
import 'import_draft_provider.dart';
import 'import_split_view.dart';

class ImportWalletBirthdayScreen extends ConsumerStatefulWidget {
  const ImportWalletBirthdayScreen({super.key});

  @override
  ConsumerState<ImportWalletBirthdayScreen> createState() =>
      _ImportWalletBirthdayScreenState();
}

class _ImportWalletBirthdayScreenState
    extends ConsumerState<ImportWalletBirthdayScreen> {
  static const _titleWidth = 378.0;
  static const _subtitleWidth = 270.0;
  static const _contentWidth = 256.0;
  static const _buttonWidth = 256.0;
  static const _messageHeight = 16.0;

  late final TextEditingController _manualHeightController;
  late final FocusNode _manualHeightFocusNode;

  ImportBirthdayMetadata? _metadata;
  bool _isLoadingMetadata = true;
  bool _isEstimating = false;
  bool _isSubmitting = false;
  String? _metadataError;
  String? _submitError;
  bool _redirectScheduled = false;
  int _estimateSeq = 0;

  @override
  void initState() {
    super.initState();
    final draft = ref.read(importDraftProvider);
    _manualHeightController = TextEditingController(
      text: draft.manualBirthdayHeightText,
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

  ZcashNetwork get _network {
    final network = ref.read(appBootstrapProvider).network;
    return network == 'main' ? ZcashNetwork.mainnet : ZcashNetwork.testnet;
  }

  void _handleFocusChanged() {
    if (mounted) setState(() {});
  }

  void _scheduleReturnToImport() {
    if (_redirectScheduled) return;
    _redirectScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.go('/import');
    });
  }

  Future<void> _loadMetadata() async {
    setState(() {
      _isLoadingMetadata = true;
      _metadataError = null;
    });

    try {
      final metadata = await ImportBirthdayEstimator.loadMetadata(
        network: _network,
      );
      if (!mounted) return;
      setState(() {
        _metadata = metadata;
        _isLoadingMetadata = false;
      });

      final draft = ref.read(importDraftProvider);
      if (draft.selectedDate != null && draft.estimatedBirthdayHeight == null) {
        await _estimateSelectedDate(draft.selectedDate!);
      }
    } catch (e, st) {
      log('ImportWalletBirthdayScreen._loadMetadata: ERROR: $e\n$st');
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
      _isEstimating = true;
      _submitError = null;
    });
    ref.read(importDraftProvider.notifier).setSelectedDate(date);

    try {
      final estimatedHeight =
          await ImportBirthdayEstimator.estimateBirthdayHeight(
            network: _network,
            selectedDate: date,
          );
      if (!mounted || seq != _estimateSeq) return;
      ref
          .read(importDraftProvider.notifier)
          .setSelectedDate(date, estimatedBirthdayHeight: estimatedHeight);
      setState(() {
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
      if (_isEstimating) {
        setState(() {
          _isEstimating = false;
        });
      }
    }
    ref.read(importDraftProvider.notifier).setTab(tab);
  }

  Future<void> _pickDate() async {
    final metadata = _metadata;
    if (metadata == null) return;
    final draft = ref.read(importDraftProvider);
    final initialDate = _clampDate(
      draft.selectedDate ?? metadata.tipDate,
      metadata.saplingActivationDate,
      metadata.tipDate,
    );

    final selected = await material.showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: metadata.saplingActivationDate,
      lastDate: metadata.tipDate,
      helpText: '',
      builder: (context, child) {
        final colors = context.colors;
        final baseTheme = material.Theme.of(context);
        final theme = baseTheme.copyWith(
          colorScheme: baseTheme.colorScheme.copyWith(
            primary: colors.border.brandPurpleStrong,
            onPrimary: colors.text.inverse,
            surface: colors.background.ground,
            onSurface: colors.text.accent,
          ),
          dialogTheme: material.DialogThemeData(
            backgroundColor: colors.background.ground,
          ),
          datePickerTheme: material.DatePickerThemeData(
            backgroundColor: colors.background.ground,
            surfaceTintColor: const Color(0x00000000),
            shadowColor: const Color(0x33000000),
            dividerColor: colors.border.subtle.withValues(alpha: 0.2),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.large),
            ),
            headerForegroundColor: colors.text.accent,
            headerBackgroundColor: colors.background.ground,
            weekdayStyle: AppTypography.labelLarge.copyWith(
              color: colors.text.muted,
            ),
            dayStyle: AppTypography.labelLarge.copyWith(
              color: colors.text.accent,
            ),
            yearStyle: AppTypography.labelLarge.copyWith(
              color: colors.text.accent,
            ),
            dayForegroundColor: material.WidgetStateProperty.resolveWith((
              states,
            ) {
              if (states.contains(material.WidgetState.disabled)) {
                return colors.text.muted;
              }
              if (states.contains(material.WidgetState.selected)) {
                return colors.text.inverse;
              }
              return colors.text.accent;
            }),
            dayBackgroundColor: material.WidgetStateProperty.resolveWith((
              states,
            ) {
              if (states.contains(material.WidgetState.selected)) {
                return colors.border.brandPurpleStrong;
              }
              return null;
            }),
            yearForegroundColor: material.WidgetStateProperty.resolveWith((
              states,
            ) {
              if (states.contains(material.WidgetState.selected)) {
                return colors.text.inverse;
              }
              return colors.text.accent;
            }),
            yearBackgroundColor: material.WidgetStateProperty.resolveWith((
              states,
            ) {
              if (states.contains(material.WidgetState.selected)) {
                return colors.border.brandPurpleStrong;
              }
              return null;
            }),
            todayForegroundColor: material.WidgetStatePropertyAll(
              colors.text.accent,
            ),
            todayBackgroundColor: const material.WidgetStatePropertyAll<Color?>(
              null,
            ),
            todayBorder: BorderSide(color: colors.border.regular),
          ),
        );
        return material.Theme(data: theme, child: child!);
      },
    );

    if (selected == null || !mounted) return;
    await _estimateSelectedDate(selected);
  }

  Future<void> _submit() async {
    final draft = ref.read(importDraftProvider);
    final mnemonic = draft.mnemonic;
    final birthdayHeight = _resolvedBirthdayHeight(draft);
    if (_isSubmitting || mnemonic == null || birthdayHeight == null) {
      return;
    }

    setState(() {
      _isSubmitting = true;
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

      await ref
          .read(accountProvider.notifier)
          .importAccount(mnemonic: mnemonic, birthdayHeight: birthdayHeight);
      ref.read(importDraftProvider.notifier).clear();
    } catch (e, st) {
      log('ImportWalletBirthdayScreen._submit: ERROR: $e\n$st');
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _submitError = e.toString();
      });
      return;
    }

    if (!mounted) return;
    context.go('/home');
  }

  int? _resolvedBirthdayHeight(ImportDraftState draft) {
    return switch (draft.selectedTab) {
      ImportBirthdayTab.date => draft.estimatedBirthdayHeight,
      ImportBirthdayTab.blockHeight => _validatedManualHeight,
    };
  }

  int? get _validatedManualHeight {
    final value = int.tryParse(_manualHeightController.text.trim());
    if (value == null) return null;
    final minimumHeight = _network.saplingActivationHeight;
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
    if (parsed < _network.saplingActivationHeight) {
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

  bool _isSubmitEnabled(ImportDraftState draft) {
    return switch (draft.selectedTab) {
      ImportBirthdayTab.date =>
        draft.estimatedBirthdayHeight != null &&
            !_isSubmitting &&
            !_isEstimating,
      ImportBirthdayTab.blockHeight =>
        _validatedManualHeight != null && !_isSubmitting,
    };
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(importDraftProvider);
    final security = ref.watch(appSecurityProvider);
    if (!draft.hasMnemonic) {
      _scheduleReturnToImport();
    }

    final activeTab = draft.selectedTab;
    final buttonLabel = _isSubmitting
        ? 'Importing...'
        : activeTab == ImportBirthdayTab.date && _isEstimating
        ? 'Estimating...'
        : 'Import';

    return ImportOnboardingShell(
      activeStep: ImportOnboardingStep.walletBirthdayHeight,
      showPasswordStep: !security.isPasswordConfigured,
      child: ImportOnboardingTrailingPane(
        child: Column(
          children: [
            _BackRow(onTap: () => context.go('/import')),
            const SizedBox(height: AppSpacing.xxs),
            Expanded(
              child: Column(
                children: [
                  Expanded(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.s,
                        ),
                        child: SizedBox(
                          width: 636,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: _titleWidth,
                                child: Text(
                                  'Around when did you create your wallet?',
                                  style: AppTypography.displaySmall.copyWith(
                                    color: context.colors.text.accent,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.s),
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
                              const SizedBox(height: AppSpacing.s),
                              const AppDecorativeDivider(width: _contentWidth),
                              const SizedBox(height: AppSpacing.md),
                              _BirthdayTabRow(
                                activeTab: activeTab,
                                onTabSelected: _handleTabSelected,
                              ),
                              const SizedBox(height: AppSpacing.md),
                              if (activeTab == ImportBirthdayTab.date)
                                _DatePickerField(
                                  width: _contentWidth,
                                  valueText: draft.selectedDate == null
                                      ? null
                                      : _formatDate(draft.selectedDate!),
                                  enabled:
                                      !_isLoadingMetadata && _metadata != null,
                                  onTap: _pickDate,
                                )
                              else
                                _BlockHeightField(
                                  controller: _manualHeightController,
                                  focusNode: _manualHeightFocusNode,
                                  width: _contentWidth,
                                  errorText: _manualHeightError,
                                  onChanged: (value) {
                                    ref
                                        .read(importDraftProvider.notifier)
                                        .setManualBirthdayHeightText(value);
                                    setState(() {
                                      _submitError = null;
                                    });
                                  },
                                ),
                              const SizedBox(height: AppSpacing.xxs),
                              SizedBox(
                                width: _contentWidth,
                                height: _messageHeight,
                                child: activeTab == ImportBirthdayTab.date
                                    ? _InlineMessage(text: _dateMessage)
                                    : _InlineMessage(text: _manualHeightError),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: _buttonWidth,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AppButton(
                          onPressed: _isSubmitEnabled(draft) ? _submit : null,
                          variant: AppButtonVariant.primary,
                          minWidth: _buttonWidth,
                          trailing: const AppIcon(AppIcons.chevronForward),
                          child: Text(buttonLabel),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        AppButton(
                          onPressed: activeTab == ImportBirthdayTab.date
                              ? () => _handleTabSelected(
                                    ImportBirthdayTab.blockHeight,
                                  )
                              : () {},
                          variant: AppButtonVariant.ghost,
                          minWidth: _buttonWidth,
                          trailing: const AppIcon(AppIcons.skip),
                          child: Text(
                            activeTab == ImportBirthdayTab.date
                                ? 'I can’t Remember the Date'
                                : 'I can’t remember the Block height',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
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
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
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
          borderRadius: BorderRadius.circular(AppRadii.medium),
          border: Border.all(color: colors.border.subtle, width: 1.5),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                valueText ?? 'mm/dd/yyyy',
                style: AppTypography.labelLarge.copyWith(color: valueColor),
              ),
            ),
            material.Icon(
              material.Icons.calendar_month_outlined,
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
        ? colors.border.strong
        : colors.border.subtle;

    return Container(
      width: width,
      height: 46,
      decoration: BoxDecoration(
        color: colors.background.base,
        borderRadius: BorderRadius.circular(AppRadii.medium),
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
                color: hasError ? colors.text.warning : colors.icon.accent,
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
        AppIcon(AppIcons.warning, size: 16, color: colors.text.warning),
        const SizedBox(width: AppSpacing.xxs),
        Expanded(
          child: Text(
            text!,
            style: AppTypography.labelMedium.copyWith(
              color: colors.text.warning,
            ),
          ),
        ),
      ],
    );
  }
}

DateTime _clampDate(DateTime value, DateTime min, DateTime max) {
  if (value.isBefore(min)) return min;
  if (value.isAfter(max)) return max;
  return value;
}

String _formatDate(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '$month/$day/${date.year}';
}
