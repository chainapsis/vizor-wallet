import 'dart:async';

import 'package:flutter/cupertino.dart'
    show CupertinoDatePicker, CupertinoDatePickerMode;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../main.dart' show log;
import '../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/app_security_provider.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../providers/wallet_mutation_guard.dart';
import '../import/import_birthday_estimator.dart';
import '../shared/onboarding_error_messages.dart';
import '../shared/onboarding_flow_args.dart';
import 'mobile_onboarding_scaffold.dart';

/// Mobile wallet-birthday step. No mobile Figma frame exists yet, so
/// this adapts the desktop screen's two entry modes — wallet creation
/// date (estimated to a height through the shared estimator) or a
/// block height typed directly — into the onboarding card style.
class MobileImportBirthdayScreen extends ConsumerStatefulWidget {
  const MobileImportBirthdayScreen({
    required this.args,
    this.loadChainMetadata = true,
    super.key,
  });

  final ImportBirthdayArgs args;

  /// Test seam — widget tests disable the lightwalletd metadata fetch.
  @visibleForTesting
  final bool loadChainMetadata;

  @override
  ConsumerState<MobileImportBirthdayScreen> createState() =>
      _MobileImportBirthdayScreenState();
}

class _MobileImportBirthdayScreenState
    extends ConsumerState<MobileImportBirthdayScreen> {
  final _heightController = TextEditingController();
  final _heightFocusNode = FocusNode();
  ImportBirthdayMetadata? _metadata;
  DateTime? _selectedDate;
  bool _estimating = false;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.loadChainMetadata) {
      unawaited(_loadMetadata());
    }
    _heightController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _heightController.dispose();
    _heightFocusNode.dispose();
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

  int? _typedHeight() {
    final raw = _heightController.text.trim();
    if (raw.isEmpty) return null;
    return int.tryParse(raw);
  }

  int? _resolvedHeight() => _typedHeight();

  bool get _canContinue {
    final height = _resolvedHeight();
    if (height == null) return false;
    if (height < _minHeight) return false;
    final tip = _metadata?.tipHeight;
    if (tip != null && height > tip) return false;
    return true;
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    var candidate = _selectedDate ?? now.subtract(const Duration(days: 30));
    await showAppMobileSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: SizedBox(
          height: 320,
          child: Column(
            children: [
              SizedBox(
                height: 220,
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.date,
                  initialDateTime: candidate,
                  minimumDate: _metadata?.saplingActivationDate,
                  maximumDate: now,
                  onDateTimeChanged: (value) => candidate = value,
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: SizedBox(
                  width: double.infinity,
                  child: AppButton(
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    child: const Text('Use this date'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    setState(() {
      _selectedDate = candidate;
      _estimating = true;
      _error = null;
    });
    try {
      final endpoint = ref.read(rpcEndpointProvider);
      final height = await ImportBirthdayEstimator.estimateBirthdayHeight(
        endpoint: endpoint,
        selectedDate: candidate,
      );
      if (!mounted) return;
      setState(() {
        _heightController.text = '$height';
        _estimating = false;
      });
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

  Future<void> _submit() async {
    final height = _resolvedHeight();
    if (height == null || _submitting || !_canContinue) return;

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
    return MobileOnboardingStepScaffold(
      progress: 0.8,
      onBack: _submitting ? null : () => Navigator.of(context).maybePop(),
      title: 'Wallet Birthday',
      subtitle:
          'When was this wallet created? Sync starts from there instead '
          'of scanning the whole chain.',
      bottomArea: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ...[
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: AppTypography.bodySmall.copyWith(
                color: colors.text.destructive,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
          AppButton(
            key: const ValueKey('mobile_import_birthday_continue'),
            onPressed: !_canContinue || _submitting || _estimating
                ? null
                : _submit,
            child: Text(_submitting ? 'Importing wallet...' : 'Continue'),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: colors.background.ground,
              borderRadius: BorderRadius.circular(AppRadii.large),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Block height',
                  style: AppTypography.labelMedium.copyWith(
                    color: colors.text.secondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                EditableText(
                  key: const ValueKey('mobile_import_birthday_height'),
                  controller: _heightController,
                  focusNode: _heightFocusNode,
                  style: AppTypography.headlineMedium.copyWith(
                    color: colors.text.accent,
                  ),
                  cursorColor: colors.text.accent,
                  backgroundCursorColor: colors.background.overlay,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  _metadata == null
                      ? 'At least $_minHeight.'
                      : 'Between $_minHeight and ${_metadata!.tipHeight}.',
                  style: AppTypography.bodySmall.copyWith(
                    color: colors.text.muted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          AppButton(
            key: const ValueKey('mobile_import_birthday_date'),
            variant: AppButtonVariant.secondary,
            onPressed: _estimating ? null : _pickDate,
            child: Text(
              _estimating
                  ? 'Estimating height...'
                  : _selectedDate == null
                  ? 'Estimate from a date instead'
                  : 'Estimated from '
                        '${_selectedDate!.year}-'
                        '${_selectedDate!.month.toString().padLeft(2, '0')}-'
                        '${_selectedDate!.day.toString().padLeft(2, '0')}',
            ),
          ),
        ],
      ),
    );
  }
}
