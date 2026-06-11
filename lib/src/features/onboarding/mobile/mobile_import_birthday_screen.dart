import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../main.dart' show log;
import '../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/mobile/app_numeric_keypad.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/app_security_provider.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../providers/wallet_mutation_guard.dart';
import '../import/import_birthday_calendar_overlay.dart'
    show ImportBirthdayCalendarPanel;
import '../import/import_birthday_estimator.dart';
import '../shared/onboarding_error_messages.dart';
import '../shared/onboarding_flow_args.dart';
import 'mobile_onboarding_scaffold.dart';

enum _BirthdayEntryMode { date, blockHeight }

/// Mobile wallet-birthday step — Figma `Import — Calendar`
/// (4575:112136): a date / block-height entry toggle, one inline field
/// driven by the shared numeric keypad, the calendar sheet behind the
/// in-field calendar icon, and a circular chevron continue button.
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

  /// Raw digit strings per mode — the date keeps `mmddyyyy` digits so
  /// keypad input and the calendar sheet share one representation.
  var _dateDigits = '';
  var _heightDigits = '';

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

  DateTime? _typedDate() {
    if (_dateDigits.length != 8) return null;
    final month = int.parse(_dateDigits.substring(0, 2));
    final day = int.parse(_dateDigits.substring(2, 4));
    final year = int.parse(_dateDigits.substring(4));
    final date = DateTime(year, month, day);
    // DateTime normalizes overflow (e.g. 02/31 → March 3) — reject it.
    if (date.month != month || date.day != day || date.year != year) {
      return null;
    }
    if (date.isBefore(_firstDate) || date.isAfter(_lastDate)) return null;
    return date;
  }

  int? _typedHeight() =>
      _heightDigits.isEmpty ? null : int.tryParse(_heightDigits);

  bool get _heightPlausible {
    final height = _typedHeight();
    if (height == null) return false;
    if (height < _minHeight) return false;
    final tip = _metadata?.tipHeight;
    if (tip != null && height > tip) return false;
    return true;
  }

  bool get _canContinue => switch (_mode) {
    _BirthdayEntryMode.date => _typedDate() != null,
    _BirthdayEntryMode.blockHeight => _heightPlausible,
  };

  bool get _busy => _submitting || _estimating;

  void _setMode(_BirthdayEntryMode mode) {
    if (_busy || _mode == mode) return;
    setState(() {
      _mode = mode;
      _error = null;
    });
  }

  void _onDigit(int digit) {
    if (_busy) return;
    setState(() {
      _error = null;
      switch (_mode) {
        case _BirthdayEntryMode.date:
          if (_dateDigits.length < 8) _dateDigits += '$digit';
        case _BirthdayEntryMode.blockHeight:
          if (_heightDigits.length < 10) _heightDigits += '$digit';
      }
    });
  }

  void _onBackspace() {
    if (_busy) return;
    setState(() {
      switch (_mode) {
        case _BirthdayEntryMode.date:
          if (_dateDigits.isNotEmpty) {
            _dateDigits = _dateDigits.substring(0, _dateDigits.length - 1);
          }
        case _BirthdayEntryMode.blockHeight:
          if (_heightDigits.isNotEmpty) {
            _heightDigits = _heightDigits.substring(
              0,
              _heightDigits.length - 1,
            );
          }
      }
    });
  }

  void _clearField() {
    if (_busy) return;
    setState(() {
      switch (_mode) {
        case _BirthdayEntryMode.date:
          _dateDigits = '';
        case _BirthdayEntryMode.blockHeight:
          _heightDigits = '';
      }
      _error = null;
    });
  }

  Future<void> _pickDate() async {
    if (_busy) return;
    final initial = _typedDate() ?? _lastDate;
    final candidate = await showAppMobileSheet<DateTime>(
      context: context,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Center(
            child: ImportBirthdayCalendarPanel(
              initialMonth: initial,
              selectedDate: _typedDate(),
              firstDate: _firstDate,
              lastDate: _lastDate,
              onDateSelected: (date) => Navigator.of(sheetContext).pop(date),
            ),
          ),
        ),
      ),
    );
    if (candidate == null || !mounted) return;
    setState(() {
      _dateDigits =
          candidate.month.toString().padLeft(2, '0') +
          candidate.day.toString().padLeft(2, '0') +
          candidate.year.toString();
      _error = null;
    });
  }

  Future<void> _continue() async {
    if (!_canContinue || _busy) return;
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
            selectedDate: _typedDate()!,
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

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDateMode = _mode == _BirthdayEntryMode.date;
    final fieldDigits = isDateMode ? _dateDigits : _heightDigits;

    return MobileOnboardingStepScaffold(
      progress: 0.8,
      onBack: _submitting ? null : () => Navigator.of(context).maybePop(),
      title: 'Around when did you create your wallet?',
      // Two 25 px lines like the Figma subtitle block.
      subtitle: 'An estimate is enough — sync starts\nfrom there.',
      bottomAreaPadding: EdgeInsets.zero,
      bottomArea: AppNumericKeypad(
        onDigit: _onDigit,
        onBackspace: _onBackspace,
        enabled: !_busy,
        keyPrefix: 'mobile_import_birthday_key',
      ),
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
                child: Container(
                  height: 61,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: colors.border.strong,
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(AppRadii.medium),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: isDateMode
                            ? _DateMaskText(digits: _dateDigits)
                            : Text(
                                _heightDigits.isEmpty
                                    ? 'Block height'
                                    : _heightDigits,
                                key: const ValueKey(
                                  'mobile_import_birthday_height',
                                ),
                                maxLines: 1,
                                style: AppTypography.headlineSmall.copyWith(
                                  color: _heightDigits.isEmpty
                                      ? colors.text.muted
                                      : colors.text.accent,
                                ),
                              ),
                      ),
                      if (fieldDigits.isNotEmpty) ...[
                        const SizedBox(width: AppSpacing.xs),
                        _FieldIconButton(
                          key: const ValueKey('mobile_import_birthday_clear'),
                          iconName: AppIcons.cross,
                          semanticLabel: 'Clear input',
                          onTap: _clearField,
                        ),
                      ],
                      if (isDateMode) ...[
                        const SizedBox(width: AppSpacing.xs),
                        _FieldIconButton(
                          key: const ValueKey('mobile_import_birthday_date'),
                          iconName: AppIcons.calendar,
                          semanticLabel: 'Pick a date',
                          onTap: _pickDate,
                        ),
                      ],
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

class _FieldIconButton extends StatelessWidget {
  const _FieldIconButton({
    required this.iconName,
    required this.semanticLabel,
    required this.onTap,
    super.key,
  });

  final String iconName;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 32,
          height: 44,
          child: Center(
            child: AppIcon(
              iconName,
              size: 18,
              color: context.colors.icon.accent,
            ),
          ),
        ),
      ),
    );
  }
}

/// `mm/dd/yyyy` mask — typed digits render dark, the rest of the mask
/// stays as a muted placeholder, slashes appear as sections fill.
class _DateMaskText extends StatelessWidget {
  const _DateMaskText({required this.digits});

  final String digits;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    const mask = ['mm', 'dd', 'yyyy'];
    final parts = [
      digits.length >= 2 ? digits.substring(0, 2) : digits,
      digits.length >= 4
          ? digits.substring(2, 4)
          : digits.length > 2
          ? digits.substring(2)
          : '',
      digits.length > 4 ? digits.substring(4) : '',
    ];

    final spans = <TextSpan>[];
    for (var i = 0; i < 3; i++) {
      if (i > 0) {
        spans.add(
          TextSpan(
            text: '/',
            style: TextStyle(
              color: parts[i - 1].length == mask[i - 1].length
                  ? colors.text.accent
                  : colors.text.muted,
            ),
          ),
        );
      }
      if (parts[i].isNotEmpty) {
        spans.add(
          TextSpan(
            text: parts[i],
            style: TextStyle(color: colors.text.accent),
          ),
        );
      }
      if (parts[i].length < mask[i].length) {
        spans.add(
          TextSpan(
            text: mask[i].substring(parts[i].length),
            style: TextStyle(color: colors.text.muted),
          ),
        );
      }
    }

    return Text.rich(
      TextSpan(style: AppTypography.headlineSmall, children: spans),
      key: const ValueKey('mobile_import_birthday_date_text'),
      maxLines: 1,
    );
  }
}
