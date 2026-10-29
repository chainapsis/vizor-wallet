import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/mobile/mobile_surface_card.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../ledger/ledger_device_label.dart';
import '../../ledger/ledger_onboarding_policy.dart';
import '../../ledger/services/ledger_account_service.dart';
import '../../ledger/services/ledger_app_readiness_service.dart';
import '../../ledger/services/ledger_bluetooth_access.dart';
import '../../ledger/services/ledger_bluetooth_connection.dart';
import '../../ledger/services/ledger_device_request.dart';
import '../../ledger/services/ledger_failure_guidance.dart';
import '../../ledger/services/ledger_mobile_ble_service.dart';
import '../../ledger/services/ledger_signing_service.dart';
import '../../ledger/widgets/ledger_device_app_prompt.dart';
import '../../ledger/widgets/mobile/mobile_ledger_bluetooth_content.dart';
import '../../ledger/widgets/ledger_procedure.dart';
import '../../ledger/widgets/mobile/mobile_ledger_sheet_content.dart';
import '../../ledger/widgets/mobile_ledger_signing_surface.dart';
import '../ledger/ledger_setup_args.dart';
import 'mobile_ledger_device_sheet.dart';
import 'mobile_onboarding_progress.dart';
import 'mobile_onboarding_progress_scope.dart';
import 'mobile_onboarding_scaffold.dart';

class MobileLedgerConnectScreen extends ConsumerStatefulWidget {
  const MobileLedgerConnectScreen({super.key});

  @override
  ConsumerState<MobileLedgerConnectScreen> createState() =>
      _MobileLedgerConnectScreenState();
}

class _MobileLedgerConnectScreenState
    extends ConsumerState<MobileLedgerConnectScreen> {
  final _accountIndexController = TextEditingController(text: '0');
  final _advancedKey = GlobalKey();
  final _errorKey = GlobalKey();
  late final LedgerOperationCanceller _cancelLedgerOperation;
  LedgerBleDevice? _selectedDevice;
  bool _showAdvancedOptions = false;
  bool _invalidAccountIndex = false;
  bool _sessionOpen = false;
  bool _connectingAccount = false;
  bool _reconnectingAccount = false;
  bool _closing = false;
  bool _cancelFailed = false;
  bool _returnToPickerAfterCancel = false;
  int _accountIndex = 0;
  int _generation = 0;
  int _pickerGeneration = 0;
  String? _error;
  Object? _requestError;

  @override
  void initState() {
    super.initState();
    _cancelLedgerOperation = ref.read(ledgerOperationCancellerProvider);
  }

  @override
  void dispose() {
    _generation++;
    if (_connectingAccount) unawaited(_cancelLedgerOperation());
    _accountIndexController.dispose();
    super.dispose();
  }

  void _toggleAdvancedOptions() {
    if (_sessionOpen) return;
    if (_showAdvancedOptions) FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _showAdvancedOptions = !_showAdvancedOptions);
    if (_showAdvancedOptions) _revealContent(_advancedKey);
  }

  void _revealContent(GlobalKey key) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = key.currentContext;
      if (mounted && target != null) {
        Scrollable.ensureVisible(
          target,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        );
      }
    });
  }

  void _startSession() {
    if (_sessionOpen) return;
    final index = parseLedgerOnboardingAccountIndex(
      _accountIndexController.text,
    );
    if (index == null) {
      setState(() {
        _showAdvancedOptions = true;
        _invalidAccountIndex = true;
      });
      _revealContent(_errorKey);
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _accountIndex = index;
      _invalidAccountIndex = false;
      _sessionOpen = true;
      _selectedDevice = null;
      _error = null;
      _requestError = null;
      _cancelFailed = false;
      _pickerGeneration++;
    });
  }

  void _selected(LedgerBleDevice device) {
    if (_closing || !_sessionOpen) return;
    setState(() => _selectedDevice = device);
    unawaited(_readAccount());
  }

  Future<void> _readAccount({bool reconnect = false}) async {
    final device = _selectedDevice;
    if (device == null || _connectingAccount || _closing || _cancelFailed) {
      return;
    }
    final generation = ++_generation;
    setState(() {
      _connectingAccount = true;
      _reconnectingAccount = reconnect;
      _error = null;
      _requestError = null;
    });
    try {
      final check = ref.read(ledgerDeviceRequestsProvider).capture();
      void checkCurrent() {
        check();
        if (!_isCurrent(generation)) {
          throw const LedgerMobileException(
            LedgerMobileFailure.cancelled,
            'Ledger operation was cancelled.',
          );
        }
      }

      if (reconnect) {
        await reconnectLedgerBluetoothDevice(
          service: ref.read(ledgerMobileBleServiceProvider),
          device: device,
          checkCurrent: checkCurrent,
        );
        setState(() => _reconnectingAccount = false);
      }
      checkCurrent();
      final account = await ref.read(ledgerBluetoothAccountConnectorProvider)(
        _accountIndex,
        device,
      );
      check();
      if (!mounted || !_isCurrent(generation)) return;
      setState(() => _sessionOpen = false);
      context.pushOnboarding(
        '/onboarding/ledger/birthday',
        extra: LedgerBirthdayArgs(account: account),
      );
    } catch (error) {
      if (!_isCurrent(generation)) return;
      setState(() {
        _requestError = error;
        _error =
            LedgerRequestFailure.fromError(error) ==
                LedgerRequestFailure.declined
            ? 'The viewing key request was declined on Ledger. Try again when you’re ready.'
            : ledgerFailureGuidance(
                    error,
                    requestKind: LedgerRequestKind.viewingKey,
                  )?.message ??
                  'Vizor could not read this Ledger account. Check the connection and try again.';
      });
    } finally {
      if (mounted && generation == _generation) {
        setState(() {
          _connectingAccount = false;
          _reconnectingAccount = false;
        });
      }
    }
  }

  bool _isCurrent(int generation) =>
      mounted && _sessionOpen && !_closing && generation == _generation;

  Future<void> _cancelSession() => _leaveSession();

  void _chooseAnotherDevice() => unawaited(_leaveSession(returnToPicker: true));

  Future<void> _leaveSession({bool returnToPicker = false}) async {
    if (_closing || !_sessionOpen) return;
    final service = ref.read(ledgerMobileBleServiceProvider);
    _generation++;
    setState(() {
      _closing = true;
      _returnToPickerAfterCancel = returnToPicker;
    });
    try {
      if (_connectingAccount || _cancelFailed) await _cancelLedgerOperation();
      if (!mounted) return;
      // Retire the native connection before another scan. A transport that
      // still owns a device response can require the user to finish it first.
      if (returnToPicker) await service.disconnect();
      if (!mounted) return;
      setState(() {
        _sessionOpen = returnToPicker;
        _connectingAccount = false;
        _reconnectingAccount = false;
        _closing = false;
        _cancelFailed = false;
        _error = null;
        _requestError = null;
        _selectedDevice = null;
        if (returnToPicker) _pickerGeneration++;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _closing = false;
        _cancelFailed = true;
        _error =
            ledgerFailureGuidance(error)?.message ??
            'Could not finish cancelling. Try again.';
      });
    }
  }

  Widget _accountContent(LedgerAppReadinessState readiness, String appName) {
    final close = _closing ? null : () => unawaited(_cancelSession());
    final failure = _requestError == null
        ? null
        : LedgerRequestFailure.fromError(_requestError!);
    final guidance = _requestError == null
        ? null
        : ledgerFailureGuidance(
            _requestError!,
            requestKind: LedgerRequestKind.viewingKey,
          );
    if (!_cancelFailed &&
        guidance?.bluetoothRecovery == true &&
        ref.read(ledgerMobileBleServiceProvider) is LedgerBluetoothAccess) {
      return MobileLedgerBluetoothContent(
        service: ref.read(ledgerMobileBleServiceProvider),
        onRetry: () => unawaited(_readAccount(reconnect: true)),
        onClose: close,
        purpose: 'add your account',
      );
    }
    final current = _reconnectingAccount
        ? 0
        : failure == LedgerRequestFailure.declined ||
              readiness.phase == LedgerAppReadinessPhase.ready
        ? 2
        : 1;
    final opening = readiness.phase == LedgerAppReadinessPhase.confirmOpening;
    final pending = _closing || (_connectingAccount && _error == null);
    final pairingRecovery = guidance?.pairingRecovery == true;
    return MobileLedgerSheetContent(
      title: _cancelFailed
          ? 'Could not cancel Ledger request'
          : failure == LedgerRequestFailure.declined
          ? 'Request declined'
          : _error != null
          ? 'Could not add Ledger account'
          : 'Add Ledger account',
      onClose: close,
      action: _error == null || _closing
          ? null
          : MobileLedgerAction(
              pairingRecovery ? 'Find my Ledger' : 'Try again',
              onPressed: _cancelFailed
                  ? () => unawaited(
                      _leaveSession(returnToPicker: _returnToPickerAfterCancel),
                    )
                  : pairingRecovery
                  ? _chooseAnotherDevice
                  : () => unawaited(_readAccount(reconnect: true)),
            ),
      children: [
        MobileLedgerIdentity(
          ledgerDeviceLabel(_selectedDevice!),
          topPadding: 0,
        ),
        LedgerProcedure(
          currentStep: current,
          steps: [
            LedgerStep('Connect Ledger', busy: current == 0 && pending),
            LedgerStep(
              'Open $appName',
              message: current == 1
                  ? _closing
                        ? 'Cancelling the Ledger request…'
                        : _error ??
                              (opening
                                  ? 'Confirm opening Zcash on Ledger.'
                                  : 'Keep Ledger connected while Vizor checks the app.')
                  : null,
              note: current == 1 && opening && _error == null
                  ? 'Keep $appName open.'
                  : null,
              busy: current == 1 && pending,
              requiresDeviceAction: opening && pending && !_closing,
            ),
            LedgerStep(
              'Add account',
              message: current == 2
                  ? _closing
                        ? 'Cancelling the Ledger request…'
                        : _error ??
                              ledgerViewingKeyApprovalMessage(
                                _accountIndex,
                                readiness.version,
                              )
                  : null,
              note: current == 2 && _error == null && !_closing
                  ? 'View your balance and activity in Vizor. Transactions still need approval on Ledger.'
                  : null,
              busy: current == 2 && pending,
              requiresDeviceAction: pending && !_closing,
            ),
          ],
        ),
      ],
    );
  }

  Widget _accountIndexMessage() => Stack(
    key: _errorKey,
    children: [
      // Preserve the helper's wrapping height when showing validation feedback.
      Visibility(
        visible: !_invalidAccountIndex,
        maintainState: true,
        maintainAnimation: true,
        maintainSize: true,
        child: Text(
          'Keep 0 unless you used a different index for this Ledger account.',
          style: AppTypography.bodySmall.copyWith(
            color: context.colors.text.secondary,
          ),
        ),
      ),
      if (_invalidAccountIndex)
        Positioned.fill(
          child: Semantics(
            liveRegion: true,
            child: Text(
              kLedgerOnboardingAccountIndexError,
              key: const ValueKey('mobile_ledger_connect_error'),
              style: AppTypography.bodySmall.copyWith(
                color: context.colors.text.destructive,
              ),
            ),
          ),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final readiness = ref.watch(ledgerAppReadinessStateProvider);
    final appName = ledgerZcashAppName(
      ref.watch(rpcEndpointProvider).networkName,
    );
    return Stack(
      children: [
        MobileOnboardingStepScaffold(
          progress: MobileOnboardingProgressScope.of(
            context,
          ).at(OnboardingFlow.ledger, OnboardingStage.deviceConnect).value,
          title: 'Connect Ledger',
          subtitle: 'Prepare your Ledger wallet.',
          onBack: () => context.pop(),
          bottomArea: AppButton(
            key: const ValueKey('mobile_ledger_import_button'),
            expand: true,
            growWithContent: true,
            constrainContent: true,
            onPressed: _sessionOpen ? null : _startSession,
            trailing: const AppIcon(AppIcons.chevronForward),
            child: const Text('Connect Ledger'),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: colors.background.ground,
                  borderRadius: BorderRadius.circular(AppRadii.large),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const AppIcon(AppIcons.ledger, size: 24),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: Text(
                            'On your Ledger',
                            style: AppTypography.bodyLarge.copyWith(
                              fontWeight: FontWeight.w500,
                              color: colors.text.accent,
                            ),
                          ),
                        ),
                      ],
                    ),
                    for (final (index, text) in const [
                      'Unlock with your PIN.',
                      'Enable Bluetooth and keep Ledger nearby.',
                    ].indexed) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 20,
                            child: Text(
                              '${index + 1}.',
                              style: AppTypography.bodyMedium,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Expanded(
                            child: Text(
                              text,
                              style: AppTypography.bodyMedium.copyWith(
                                color: colors.text.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.base),
              MobileSurfaceCard(
                padding: EdgeInsets.zero,
                cornerRadius: AppRadii.large,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Semantics(
                      key: const ValueKey(
                        'mobile_ledger_advanced_options_disclosure',
                      ),
                      button: true,
                      enabled: !_sessionOpen,
                      expanded: _showAdvancedOptions,
                      label: 'Advanced options',
                      onTap: _sessionOpen ? null : _toggleAdvancedOptions,
                      child: ExcludeSemantics(
                        child: AppButton(
                          variant: AppButtonVariant.ghost,
                          expand: true,
                          growWithContent: true,
                          constrainContent: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.s,
                            vertical: AppSpacing.sm,
                          ),
                          borderRadius: BorderRadius.circular(AppRadii.large),
                          onPressed: _sessionOpen
                              ? null
                              : _toggleAdvancedOptions,
                          child: Row(
                            children: [
                              const Expanded(child: Text('Advanced options')),
                              const SizedBox(width: AppSpacing.sm),
                              RotatedBox(
                                quarterTurns: _showAdvancedOptions ? 2 : 0,
                                child: const AppIcon(
                                  AppIcons.arrowDown,
                                  size: 20,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (_showAdvancedOptions)
                      Padding(
                        key: _advancedKey,
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.sm,
                          0,
                          AppSpacing.sm,
                          AppSpacing.sm,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _accountIndexMessage(),
                            const SizedBox(height: AppSpacing.sm),
                            AppTextField(
                              key: const ValueKey(
                                'mobile_ledger_account_index_field',
                              ),
                              label: 'Account index (0–100)',
                              controller: _accountIndexController,
                              surface: AppTextFieldSurface.secondary,
                              tone: _invalidAccountIndex
                                  ? AppTextFieldTone.destructive
                                  : AppTextFieldTone.neutral,
                              enabled: !_sessionOpen,
                              keyboardType: TextInputType.number,
                              textInputAction: TextInputAction.done,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              onChanged: (value) {
                                final invalid =
                                    parseLedgerOnboardingAccountIndex(value) ==
                                    null;
                                if (_invalidAccountIndex != invalid) {
                                  setState(
                                    () => _invalidAccountIndex = invalid,
                                  );
                                  if (invalid) _revealContent(_errorKey);
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'See your balance and activity in Vizor.\nApprove transactions on Ledger.',
                style: AppTypography.bodyMedium.copyWith(
                  color: colors.text.accent,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        if (_sessionOpen)
          MobileLedgerSigningSurface(
            canLeave: !_closing,
            onBack: () => unawaited(_cancelSession()),
            onPrevious: _selectedDevice == null ? null : _chooseAnotherDevice,
            title: 'Add Ledger account',
            child: Stack(
              children: [
                // Keep discovery's connection owner alive until this session ends.
                // Its disposal must not race app readiness or the viewing-key APDUs.
                Offstage(
                  offstage: _selectedDevice != null,
                  child: TickerMode(
                    enabled: _selectedDevice == null,
                    child: MobileLedgerDeviceSheet(
                      key: ValueKey(_pickerGeneration),
                      service: ref.read(ledgerMobileBleServiceProvider),
                      onSelected: _selected,
                      onClose: () => unawaited(_cancelSession()),
                    ),
                  ),
                ),
                if (_selectedDevice != null)
                  _accountContent(readiness, appName),
              ],
            ),
          ),
      ],
    );
  }
}
