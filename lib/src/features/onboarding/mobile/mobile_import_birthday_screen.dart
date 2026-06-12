import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart' show TextField;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../main.dart' show log;
import '../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../core/layout/mobile/mobile_bottom_safe_area.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/app_security_provider.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../providers/wallet_mutation_guard.dart';
import '../../../services/native_date_picker.dart';
import '../import/import_birthday_calendar_overlay.dart'
    show ImportBirthdayCalendarPanel;
import '../import/import_birthday_estimator.dart';
import '../shared/onboarding_error_messages.dart';
import '../shared/onboarding_flow_args.dart';
import 'mobile_onboarding_scaffold.dart';

enum _BirthdayEntryMode { date, blockHeight }

/// Mobile wallet-birthday step — Figma `Import — Calendar`
/// (4575:112136): a date / block-height entry toggle and a circular
/// chevron continue button. The date "field" is not typeable — tapping
/// it opens the calendar sheet, which is the only way to pick a date.
/// The block height is a real text field on the system numeric
/// keyboard.
class MobileImportBirthdayScreen extends ConsumerStatefulWidget {
  const MobileImportBirthdayScreen({
    required this.args,
    this.onHeightConfirmed,
    this.loadChainMetadata = true,
    super.key,
  });

  final ImportBirthdayArgs args;

  /// When set, confirming a height delegates to this callback instead
  /// of the software-mnemonic import path — the Keystone flow shares
  /// this screen but imports a hardware UFVK. Thrown errors surface
  /// through the screen's standard error line.
  final Future<void> Function(int height)? onHeightConfirmed;

  /// Test seam — widget tests disable the lightwalletd metadata fetch.
  @visibleForTesting
  final bool loadChainMetadata;

  @override
  ConsumerState<MobileImportBirthdayScreen> createState() =>
      _MobileImportBirthdayScreenState();
}

class _MobileImportBirthdayScreenState
    extends ConsumerState<MobileImportBirthdayScreen> {
  var _mode = _BirthdayEntryMode.date;

  DateTime? _selectedDate;
  final _heightController = TextEditingController();
  final _heightFocus = FocusNode();

  ImportBirthdayMetadata? _metadata;
  bool _estimating = false;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.loadChainMetadata) {
      unawaited(_loadMetadata());
    }
  }

  @override
  void dispose() {
    _heightController.dispose();
    _heightFocus.dispose();
    super.dispose();
  }

  Future<void> _loadMetadata() async {
    try {
      final endpoint = ref.read(rpcEndpointProvider);
      final metadata = await ImportBirthdayEstimator.loadMetadata(
        endpoint: endpoint,
      );
      if (mounted) setState(() => _metadata = metadata);
    } catch (e) {
      log('MobileImportBirthday: metadata load failed: $e');
    }
  }

  int get _minHeight =>
      _metadata?.saplingActivationHeight ??
      ref.read(rpcEndpointProvider).network.saplingActivationHeight;

  DateTime get _firstDate =>
      // Mainnet Sapling activation predates every wallet; a fallback only
      // matters while the chain metadata is still loading.
      _metadata?.saplingActivationDate ?? DateTime(2018, 10, 28);

  DateTime get _lastDate => _metadata?.tipDate ?? DateTime.now();

  int? _typedHeight() {
    final text = _heightController.text.trim();
    return text.isEmpty ? null : int.tryParse(text);
  }

  bool get _heightPlausible {
    final height = _typedHeight();
    if (height == null) return false;
    if (height < _minHeight) return false;
    final tip = _metadata?.tipHeight;
    if (tip != null && height > tip) return false;
    return true;
  }

  bool get _canContinue => switch (_mode) {
    _BirthdayEntryMode.date => _selectedDate != null,
    _BirthdayEntryMode.blockHeight => _heightPlausible,
  };

  bool get _busy => _submitting || _estimating;

  void _setMode(_BirthdayEntryMode mode) {
    if (_busy || _mode == mode) return;
    setState(() {
      _mode = mode;
      _error = null;
    });
    // The height field owns the system keyboard; the date "field" only
    // opens the calendar sheet.
    if (mode == _BirthdayEntryMode.blockHeight) {
      _heightFocus.requestFocus();
    } else {
      _heightFocus.unfocus();
    }
  }

  Future<void> _pickDate() async {
    if (_busy) return;
    _heightFocus.unfocus();
    final initial = _selectedDate ?? _lastDate;

    DateTime? candidate;
    var picked = false;
    if (Platform.isIOS) {
      // iOS gets the OS-native calendar sheet; the Flutter sheet below
      // stays as the fallback (handler requires iOS 16+).
      try {
        candidate = await NativeDatePicker.pickDate(
          initialDate: _selectedDate,
          firstDate: _firstDate,
          lastDate: _lastDate,
          isDarkTheme: AppTheme.of(context) == AppThemeData.dark,
          accentColor: context.colors.text.accent,
        );
        picked = true;
      } catch (e) {
        log('MobileImportBirthday: native date picker failed: $e');
      }
      if (!mounted) return;
    }
    if (!picked) {
      candidate = await showAppMobileSheet<DateTime>(
        context: context,
        // The calendar panel is its own card; drop the sheet surface so
        // only the scrim and the calendar show.
        transparentBackground: true,
        builder: (sheetContext) => MobileBottomSafeArea(
          bottomPadding: AppSpacing.sm,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            // mainAxisSize.min so the sheet hugs the calendar instead of
            // claiming the scroll-controlled full height.
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ImportBirthdayCalendarPanel(
                  initialMonth: initial,
                  selectedDate: _selectedDate,
                  firstDate: _firstDate,
                  lastDate: _lastDate,
                  onDateSelected: (date) =>
                      Navigator.of(sheetContext).pop(date),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (candidate == null || !mounted) return;
    setState(() {
      _selectedDate = candidate;
      _error = null;
    });
  }

  Future<void> _continue() async {
    if (!_canContinue || _busy) return;
    _heightFocus.unfocus();
    switch (_mode) {
      case _BirthdayEntryMode.blockHeight:
        await _submit(_typedHeight()!);
      case _BirthdayEntryMode.date:
        setState(() {
          _estimating = true;
          _error = null;
        });
        try {
          final endpoint = ref.read(rpcEndpointProvider);
          final height = await ImportBirthdayEstimator.estimateBirthdayHeight(
            endpoint: endpoint,
            selectedDate: _selectedDate!,
          );
          if (!mounted) return;
          setState(() => _estimating = false);
          await _submit(height);
        } catch (e) {
          log('MobileImportBirthday: estimate failed: $e');
          if (!mounted) return;
          setState(() {
            _estimating = false;
            _error =
                "Couldn't estimate a height for that date. Enter a block "
                'height instead.';
          });
        }
    }
  }

  Future<void> _submit(int height) async {
    final onHeightConfirmed = widget.onHeightConfirmed;
    if (onHeightConfirmed != null) {
      setState(() {
        _submitting = true;
        _error = null;
      });
      try {
        await onHeightConfirmed(height);
      } catch (e, st) {
        log('MobileImportBirthday: height confirm failed: $e\n$st');
        if (!mounted) return;
        setState(() {
          _submitting = false;
          _error = onboardingSubmitErrorMessage(e);
        });
      }
      return;
    }

    final security = ref.read(appSecurityProvider);
    if (!security.isPasswordConfigured) {
      context.push(
        '/onboarding/set-passcode',
        extra: SetPasswordScreenArgs.importWallet(
          mnemonic: widget.args.mnemonic,
          birthdayHeight: height,
        ),
      );
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    final router = GoRouter.of(context);
    final accountNotifier = ref.read(accountProvider.notifier);
    try {
      await runWithSyncPausedForAccountMutation(
        ref,
        () => accountNotifier.importAccount(
          mnemonic: widget.args.mnemonic,
          birthdayHeight: height,
        ),
      );
    } catch (e, st) {
      log('MobileImportBirthday: import failed: $e\n$st');
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = onboardingSubmitErrorMessage(e);
      });
      return;
    }
    router.go('/home');
  }

  String _formattedDate(DateTime date) =>
      '${date.month.toString().padLeft(2, '0')}/'
      '${date.day.toString().padLeft(2, '0')}/'
      '${date.year}';

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDateMode = _mode == _BirthdayEntryMode.date;

    return MobileOnboardingStepScaffold(
      progress: 0.8,
      onBack: _submitting ? null : () => Navigator.of(context).maybePop(),
      title: 'Around when did you create your wallet?',
      // Two 25 px lines like the Figma subtitle block.
      subtitle: 'An estimate is enough — sync starts\nfrom there.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: _ModeTab(
                  key: const ValueKey('mobile_import_birthday_mode_date'),
                  iconName: AppIcons.calendar,
                  label: 'Enter the date',
                  selected: isDateMode,
                  onTap: () => _setMode(_BirthdayEntryMode.date),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Flexible(
                child: _ModeTab(
                  key: const ValueKey('mobile_import_birthday_mode_height'),
                  iconName: AppIcons.block,
                  label: 'Enter the block height',
                  selected: !isDateMode,
                  onTap: () => _setMode(_BirthdayEntryMode.blockHeight),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                // 61-high 2 px-bordered field per the Figma entry row.
                child: isDateMode
                    ? _DateFieldButton(
                        date: _selectedDate,
                        formatted: _selectedDate == null
                            ? null
                            : _formattedDate(_selectedDate!),
                        enabled: !_busy,
                        onTap: () => unawaited(_pickDate()),
                      )
                    : _FieldShell(
                        child: Row(
                          children: [
                            Expanded(
                              child: Stack(
                                alignment: Alignment.centerLeft,
                                children: [
                                  if (_heightController.text.isEmpty)
                                    IgnorePointer(
                                      child: Text(
                                        'Block height',
                                        maxLines: 1,
                                        style: AppTypography.headlineSmall
                                            .copyWith(color: colors.text.muted),
                                      ),
                                    ),
                                  // A real TextField (bare, no
                                  // decoration) rather than raw
                                  // EditableText so long-press selection
                                  // and the paste menu work; the shell
                                  // owns all visible chrome.
                                  TextField(
                                    key: const ValueKey(
                                      'mobile_import_birthday_height',
                                    ),
                                    controller: _heightController,
                                    focusNode: _heightFocus,
                                    autofocus: true,
                                    readOnly: _busy,
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                      LengthLimitingTextInputFormatter(10),
                                    ],
                                    onChanged: (_) =>
                                        setState(() => _error = null),
                                    maxLines: 1,
                                    style: AppTypography.headlineSmall
                                        .copyWith(color: colors.text.accent),
                                    cursorColor: colors.text.accent,
                                    decoration: null,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
              const SizedBox(width: AppSpacing.s),
              AppButton(
                key: const ValueKey('mobile_import_birthday_continue'),
                onPressed: !_canContinue || _busy ? null : _continue,
                // 78×60 chevron pill per the Figma entry row.
                height: 60,
                minWidth: 78,
                child: const AppIcon(AppIcons.chevronForward, size: 24),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s),
          if (_error != null)
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: AppTypography.bodySmall.copyWith(
                color: colors.text.destructive,
              ),
            )
          else if (_submitting || _estimating)
            Text(
              _submitting ? 'Importing wallet...' : 'Estimating height...',
              textAlign: TextAlign.center,
              style: AppTypography.bodySmall.copyWith(
                color: colors.text.secondary,
              ),
            )
          else if (!isDateMode)
            Text(
              _metadata == null
                  ? 'At least $_minHeight.'
                  : 'Between $_minHeight and ${_metadata!.tipHeight}.',
              textAlign: TextAlign.center,
              style: AppTypography.bodySmall.copyWith(
                color: colors.text.muted,
              ),
            ),
        ],
      ),
    );
  }
}

/// One side of the date / block-height entry toggle.
class _ModeTab extends StatelessWidget {
  const _ModeTab({
    required this.iconName,
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String iconName;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = selected ? colors.text.accent : colors.text.muted;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          height: 44,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(iconName, size: AppIconSize.medium, color: color),
              const SizedBox(width: AppSpacing.xxs),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.labelMedium.copyWith(color: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The Figma entry-row field chrome shared by both modes.
class _FieldShell extends StatelessWidget {
  const _FieldShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      height: 61,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s),
      decoration: BoxDecoration(
        border: Border.all(color: colors.border.strong, width: 2),
        borderRadius: BorderRadius.circular(AppRadii.medium),
      ),
      child: child,
    );
  }
}

/// The date "field" — looks like the entry field but is not typeable;
/// the calendar sheet is the only input. Tapping anywhere on it opens
/// the sheet.
class _DateFieldButton extends StatelessWidget {
  const _DateFieldButton({
    required this.date,
    required this.formatted,
    required this.enabled,
    required this.onTap,
  });

  final DateTime? date;
  final String? formatted;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      label: 'Pick a date',
      child: GestureDetector(
        key: const ValueKey('mobile_import_birthday_date'),
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
        child: _FieldShell(
          child: Row(
            children: [
              Expanded(
                child: Text(
                  formatted ?? 'mm/dd/yyyy',
                  key: const ValueKey('mobile_import_birthday_date_text'),
                  maxLines: 1,
                  style: AppTypography.headlineSmall.copyWith(
                    color: formatted == null
                        ? colors.text.muted
                        : colors.text.accent,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              AppIcon(AppIcons.calendar, size: 18, color: colors.icon.accent),
            ],
          ),
        ),
      ),
    );
  }
}
