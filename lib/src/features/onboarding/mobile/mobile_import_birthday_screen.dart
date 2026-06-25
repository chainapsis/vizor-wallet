import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart' show TextField;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../main.dart' show log;
import '../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/app_security_provider.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../providers/wallet_mutation_guard.dart';
import '../../../rust/api/wallet.dart' as rust_wallet;
import '../../../services/native_date_picker.dart';
import '../import/import_birthday_calendar_overlay.dart'
    show ImportBirthdayCalendarPanel;
import '../import/import_birthday_estimator.dart';
import '../shared/onboarding_error_messages.dart';
import '../shared/onboarding_flow_args.dart';
import 'mobile_import_account_discovery_sheet.dart';
import 'mobile_import_birthday_unknown_height_sheet.dart';
import 'mobile_onboarding_scaffold.dart';

enum _BirthdayEntryMode { date, blockHeight }

enum _MobileImportSubmitPhase {
  idle,
  estimating,
  discoveringAccounts,
  stoppingSync,
  importing,
}

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
  _MobileImportSubmitPhase _submitPhase = _MobileImportSubmitPhase.idle;
  String? _error;

  bool get _isSubmitting =>
      _submitPhase != _MobileImportSubmitPhase.idle &&
      _submitPhase != _MobileImportSubmitPhase.estimating;

  @override
  void initState() {
    super.initState();
    // Repaint the height field's focus ring when it gains/loses the keyboard.
    _heightFocus.addListener(_onHeightFocusChanged);
    if (widget.loadChainMetadata) {
      unawaited(_loadMetadata());
    }
  }

  @override
  void dispose() {
    _heightFocus.removeListener(_onHeightFocusChanged);
    _heightController.dispose();
    _heightFocus.dispose();
    super.dispose();
  }

  void _onHeightFocusChanged() {
    if (mounted) setState(() {});
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

  bool get _busy => _submitPhase != _MobileImportSubmitPhase.idle;

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
      // iOS gets an OS-native month/year picker. The Flutter calendar sheet
      // below stays as the fallback for Android and channel failures.
      try {
        candidate = await NativeDatePicker.pickMonthYear(
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
        builder: (sheetContext) => Padding(
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
                onDateSelected: (date) => Navigator.of(sheetContext).pop(date),
              ),
            ],
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
          _submitPhase = _MobileImportSubmitPhase.estimating;
          _error = null;
        });
        try {
          final endpoint = ref.read(rpcEndpointProvider);
          final height = await ImportBirthdayEstimator.estimateBirthdayHeight(
            endpoint: endpoint,
            selectedDate: _selectedDate!,
          );
          if (!mounted) return;
          await _submit(height);
        } catch (e) {
          log('MobileImportBirthday: estimate failed: $e');
          if (!mounted) return;
          setState(() {
            _submitPhase = _MobileImportSubmitPhase.idle;
            _error =
                "Couldn't estimate a height for that date. Enter a block "
                'height instead.';
          });
        }
    }
  }

  /// "I can't remember" — like the desktop skip, import from the Sapling
  /// activation height so the wallet scans the whole chain rather than
  /// guessing a birthday.
  Future<void> _skipBirthday() async {
    if (_busy) return;
    _heightFocus.unfocus();
    final confirmed = await showMobileImportBirthdayUnknownHeightSheet(context);
    if (!mounted || !confirmed) return;
    await _submit(_minHeight);
  }

  Future<void> _submit(int height) async {
    final onHeightConfirmed = widget.onHeightConfirmed;
    if (onHeightConfirmed != null) {
      setState(() {
        _submitPhase = _MobileImportSubmitPhase.importing;
        _error = null;
      });
      try {
        await onHeightConfirmed(height);
      } catch (e, st) {
        log('MobileImportBirthday: height confirm failed: $e\n$st');
        if (!mounted) return;
        setState(() {
          _submitPhase = _MobileImportSubmitPhase.idle;
          _error = onboardingSubmitErrorMessage(e);
        });
      }
      return;
    }

    final security = ref.read(appSecurityProvider);
    if (!security.isPasswordConfigured) {
      try {
        final selectedAdditionalAccountIndices =
            await _resolveAdditionalAccountIndices(
              mnemonic: widget.args.mnemonic,
              birthdayHeight: height,
            );
        if (selectedAdditionalAccountIndices == null) {
          if (mounted) {
            setState(() {
              _submitPhase = _MobileImportSubmitPhase.idle;
            });
          }
          return;
        }
        if (!mounted) return;
        setState(() {
          _submitPhase = _MobileImportSubmitPhase.idle;
        });
        context.push(
          '/onboarding/set-passcode',
          extra: SetPasswordScreenArgs.importWallet(
            mnemonic: widget.args.mnemonic,
            birthdayHeight: height,
            selectedAdditionalAccountIndices: selectedAdditionalAccountIndices,
          ),
        );
      } catch (e, st) {
        log('MobileImportBirthday: account discovery failed: $e\n$st');
        if (!mounted) return;
        setState(() {
          _submitPhase = _MobileImportSubmitPhase.idle;
          _error = onboardingSubmitErrorMessage(e);
        });
      }
      return;
    }

    setState(() {
      _submitPhase = _MobileImportSubmitPhase.importing;
      _error = null;
    });
    final router = GoRouter.of(context);
    final accountNotifier = ref.read(accountProvider.notifier);
    try {
      final imported = await runWithSyncPausedForAccountMutation(
        ref,
        () async {
          final selectedAdditionalAccountIndices =
              await _resolveAdditionalAccountIndices(
                mnemonic: widget.args.mnemonic,
                birthdayHeight: height,
              );
          if (selectedAdditionalAccountIndices == null) return false;
          if (!mounted) return false;
          setState(() {
            _submitPhase = _MobileImportSubmitPhase.importing;
          });
          await accountNotifier.importAccount(
            mnemonic: widget.args.mnemonic,
            birthdayHeight: height,
            additionalAccountIndices: selectedAdditionalAccountIndices,
          );
          return true;
        },
        onStoppingSync: () {
          if (!mounted) return;
          setState(() {
            _submitPhase = _MobileImportSubmitPhase.stoppingSync;
          });
        },
        onSyncPaused: () {
          if (!mounted) return;
          setState(() {
            _submitPhase = _MobileImportSubmitPhase.importing;
          });
        },
      );
      if (!imported) {
        if (mounted) {
          setState(() {
            _submitPhase = _MobileImportSubmitPhase.idle;
          });
        }
        return;
      }
    } catch (e, st) {
      log('MobileImportBirthday: import failed: $e\n$st');
      if (!mounted) return;
      setState(() {
        _submitPhase = _MobileImportSubmitPhase.idle;
        _error = onboardingSubmitErrorMessage(e);
      });
      return;
    }
    router.go('/home');
  }

  Future<List<int>?> _resolveAdditionalAccountIndices({
    required String mnemonic,
    required int birthdayHeight,
  }) async {
    setState(() {
      _submitPhase = _MobileImportSubmitPhase.discoveringAccounts;
      _error = null;
    });

    final discovery = await ref
        .read(accountProvider.notifier)
        .discoverAdditionalSoftwareAccounts(
          mnemonic: mnemonic,
          birthdayHeight: birthdayHeight,
        );
    if (!mounted) return null;
    final candidates = discovery.accounts;
    if (candidates.isEmpty) {
      setState(() {
        _submitPhase = _MobileImportSubmitPhase.idle;
      });
      return const [];
    }

    setState(() {
      _submitPhase = _MobileImportSubmitPhase.idle;
    });
    return showMobileImportAccountDiscoverySheet(
      context: context,
      accounts: candidates,
      allowEmptySelection: !discovery.primaryAccountAlreadyExists,
      bip44CoinType: ref.read(rpcEndpointProvider).network.coinType,
      loadTransparentBalance: _loadAccountDiscoveryTransparentBalance,
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

  String? get _statusMessage => switch (_submitPhase) {
    _MobileImportSubmitPhase.idle => null,
    _MobileImportSubmitPhase.estimating => 'Estimating height...',
    _MobileImportSubmitPhase.discoveringAccounts => 'Checking accounts...',
    _MobileImportSubmitPhase.stoppingSync => 'Pausing sync...',
    _MobileImportSubmitPhase.importing => 'Importing wallet...',
  };

  String _formattedDate(DateTime date) => Platform.isIOS
      ? '${date.month.toString().padLeft(2, '0')}/${date.year}'
      : '${date.month.toString().padLeft(2, '0')}/'
            '${date.day.toString().padLeft(2, '0')}/'
            '${date.year}';

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDateMode = _mode == _BirthdayEntryMode.date;

    return MobileOnboardingStepScaffold(
      progress: 0.8,
      onBack: _isSubmitting ? null : () => Navigator.of(context).maybePop(),
      title: 'Around when did you create your wallet?',
      // Two 25 px lines like the Figma subtitle block.
      subtitle: 'An estimate is enough — sync starts\nfrom there.',
      // Figma `Buttons Stack` (4752:26672): a full-width skip below the
      // entry row that imports from the Sapling activation height.
      bottomArea: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppButton(
            key: const ValueKey('mobile_import_birthday_skip'),
            variant: AppButtonVariant.secondary,
            expand: true,
            onPressed: _busy ? null : () => unawaited(_skipBirthday()),
            trailing: const AppIcon(AppIcons.skip),
            child: const Text('I can’t remember'),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Tabs size to their content and only scale down on very narrow
          // screens — a 50/50 Flexible split clipped the longer label.
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ModeTab(
                  key: const ValueKey('mobile_import_birthday_mode_date'),
                  iconName: AppIcons.calendar,
                  label: Platform.isIOS ? 'Enter the month' : 'Enter the date',
                  selected: isDateMode,
                  onTap: () => _setMode(_BirthdayEntryMode.date),
                ),
                const SizedBox(width: AppSpacing.sm),
                _ModeTab(
                  key: const ValueKey('mobile_import_birthday_mode_height'),
                  iconName: AppIcons.block,
                  label: 'Enter the block height',
                  selected: !isDateMode,
                  onTap: () => _setMode(_BirthdayEntryMode.blockHeight),
                ),
              ],
            ),
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
                        focused: _heightFocus.hasFocus,
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
                                    style: AppTypography.headlineSmall.copyWith(
                                      color: colors.text.accent,
                                    ),
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
              const SizedBox(width: AppSpacing.xs),
              AppButton(
                key: const ValueKey('mobile_import_birthday_continue'),
                onPressed: !_canContinue || _busy ? null : _continue,
                // 70×60 chevron pill with a 20 px glyph per the Figma row.
                height: 60,
                minWidth: 70,
                child: const AppIcon(AppIcons.chevronForward, size: 20),
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
          else if (_statusMessage != null)
            // Figma `Import — Estimating` (4752:27008): a spinner + Label M
            // SemiBold in text.accent, centered, sitting ~24px (spacing/md)
            // below the field rather than tight against it.
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.s),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AppIcon(AppIcons.loader, size: 20, color: colors.icon.accent),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    _statusMessage!,
                    textAlign: TextAlign.center,
                    style: AppTypography.labelLarge.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colors.text.accent,
                    ),
                  ),
                ],
              ),
            )
          else if (!isDateMode)
            Text(
              _metadata == null
                  ? 'At least $_minHeight.'
                  : 'Between $_minHeight and ${_metadata!.tipHeight}.',
              textAlign: TextAlign.center,
              style: AppTypography.bodySmall.copyWith(color: colors.text.muted),
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
    // Figma `Simple Tabs`: both tabs use Body M on text.accent; the
    // inactive one is the same content at 50% opacity, and the active one
    // is the medium weight.
    final tab = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppIcon(iconName, size: AppIconSize.medium, color: colors.icon.accent),
        const SizedBox(width: AppSpacing.xxs),
        Text(
          label,
          maxLines: 1,
          style:
              (selected
                      ? AppTypography.bodyMediumStrong
                      : AppTypography.bodyMedium)
                  .copyWith(color: colors.text.accent),
        ),
      ],
    );
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          height: 44,
          child: Opacity(opacity: selected ? 1 : 0.5, child: tab),
        ),
      ),
    );
  }
}

/// The Figma entry-row field chrome shared by both modes.
class _FieldShell extends StatelessWidget {
  const _FieldShell({required this.child, this.focused = false});

  final Widget child;

  /// Shows the inverse focus ring while the field owns the keyboard. The
  /// resting state has no visible border — the previous always-on 2px
  /// border read as a permanent focus state.
  final bool focused;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // Raised white card (surface.input fill, radius 16, layered subtle
    // shadow) with a focus-only inverse outline — mirrors MobileTextField.
    return Container(
      height: AppInputSizing.height,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s),
      decoration: BoxDecoration(
        color: colors.surface.input,
        borderRadius: BorderRadius.circular(AppInputSizing.radius),
        border: Border.all(
          color: focused ? colors.background.inverse : const Color(0x00000000),
          width: 1.5,
          strokeAlign: BorderSide.strokeAlignInside,
        ),
        boxShadow: [
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
        ],
      ),
      child: child,
    );
  }
}

/// The date "field" — looks like the entry field but is not typeable;
/// tapping anywhere on it opens the native picker or fallback calendar.
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
      label: Platform.isIOS ? 'Pick a month' : 'Pick a date',
      child: GestureDetector(
        key: const ValueKey('mobile_import_birthday_date'),
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
        child: _FieldShell(
          child: Row(
            children: [
              Expanded(
                child: Text(
                  formatted ?? (Platform.isIOS ? 'mm/yyyy' : 'mm/dd/yyyy'),
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
              AppIcon(AppIcons.calendar, size: 24, color: colors.icon.accent),
            ],
          ),
        ),
      ),
    );
  }
}
