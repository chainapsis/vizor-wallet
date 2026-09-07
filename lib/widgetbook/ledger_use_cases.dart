// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import '../src/features/ledger/services/ledger_connection_recovery.dart';
import 'dart:typed_data';

import 'package:flutter/material.dart' show Material, MaterialApp, ThemeMode;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:widgetbook/widgetbook.dart';

import '../src/app_bootstrap.dart';
import '../src/core/config/rpc_endpoint_config.dart';
import '../src/core/widgets/app_button.dart';
import '../src/features/accounts/screens/hardware_account_details_screen.dart';
import '../src/features/accounts/widgets/ledger_wallet_rename_modal.dart';
import '../src/features/ledger/ledger_capability.dart';
import '../src/features/ledger/services/ledger_app_readiness_service.dart';
import '../src/features/ledger/services/ledger_mobile_ble_service.dart';
import '../src/features/ledger/widgets/ledger_device_app_prompt.dart';
import '../src/features/ledger/widgets/ledger_signing_modal.dart';
import '../src/features/ledger/widgets/mobile_ledger_signing_surface.dart';
import '../src/features/onboarding/mobile/mobile_ledger_device_sheet.dart';
import '../src/features/voting/screens/voting_status_screen.dart';
import '../src/providers/account_provider.dart';
import '../src/providers/sync_provider.dart';
import '../src/providers/voting/voting_state.dart';
import '../src/rust/api/ledger.dart' as rust_ledger;
import 'screen_use_cases.dart';

WidgetbookFolder buildLedgerWidgetbookFolder() {
  return WidgetbookFolder(
    name: 'Ledger',
    children: [
      WidgetbookFolder(
        name: 'Onboarding & import',
        children: [
          WidgetbookComponent(
            name: 'Additional account',
            useCases: [
              WidgetbookUseCase(
                name: 'Desktop',
                builder: buildLedgerAdditionalAccountUseCase,
              ),
              WidgetbookUseCase(
                name: 'Mobile',
                builder: buildMobileLedgerAdditionalAccountUseCase,
              ),
            ],
          ),
          WidgetbookComponent(
            name: 'Device app prompt',
            useCases: [
              WidgetbookUseCase(
                name: 'Mainnet',
                builder: buildLedgerDeviceAppPromptUseCase,
              ),
            ],
          ),
        ],
      ),
      WidgetbookFolder(
        name: 'Accounts',
        children: [
          WidgetbookComponent(
            name: 'Ledger family',
            useCases: [
              WidgetbookUseCase(
                name: 'Desktop',
                builder: buildAccountsLedgerFamilyUseCase,
              ),
              WidgetbookUseCase(
                name: 'Mobile',
                builder: buildMobileAccountsLedgerFamilyUseCase,
              ),
            ],
          ),
          WidgetbookComponent(
            name: 'Account details',
            useCases: [
              WidgetbookUseCase(
                name: 'Desktop',
                builder: buildLedgerAccountDetailsUseCase,
              ),
              WidgetbookUseCase(
                name: 'Mobile',
                builder: buildMobileLedgerAccountDetailsUseCase,
              ),
            ],
          ),
          WidgetbookComponent(
            name: 'Rename group',
            useCases: [
              WidgetbookUseCase(
                name: 'Interactive',
                builder: buildLedgerRenameUseCase,
              ),
            ],
          ),
        ],
      ),
      WidgetbookFolder(
        name: 'Signing',
        children: [
          WidgetbookComponent(
            name: 'Signing modal',
            useCases: [
              WidgetbookUseCase(
                name: 'Playground',
                builder: buildLedgerSigningPlaygroundUseCase,
              ),
              WidgetbookUseCase(
                name: 'Recovery flow',
                builder: (_) => const LedgerSigningRecoveryPreview(),
              ),
            ],
          ),
        ],
      ),
      WidgetbookFolder(
        name: 'Mobile device picker',
        children: [
          WidgetbookComponent(
            name: 'Discovery',
            useCases: [
              WidgetbookUseCase(
                name: 'Devices found',
                builder: buildLedgerDevicePickerFoundUseCase,
              ),
              WidgetbookUseCase(
                name: 'Empty',
                builder: buildLedgerDevicePickerEmptyUseCase,
              ),
              WidgetbookUseCase(
                name: 'Permission denied',
                builder: buildLedgerDevicePickerPermissionDeniedUseCase,
              ),
            ],
          ),
        ],
      ),
      WidgetbookFolder(
        name: 'Voting',
        children: [
          WidgetbookComponent(
            name: 'Bundle approval',
            useCases: [
              WidgetbookUseCase(
                name: 'Playground',
                builder: buildLedgerVotingPlaygroundUseCase,
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

Widget buildLedgerDeviceAppPromptUseCase(BuildContext context) {
  return const Center(child: LedgerDeviceAppPrompt(networkName: 'main'));
}

Widget buildLedgerAccountDetailsUseCase(BuildContext context) {
  return const _LedgerAccountDetailsPreview(mobile: false);
}

Widget buildMobileLedgerAccountDetailsUseCase(BuildContext context) {
  return const _LedgerAccountDetailsPreview(mobile: true);
}

Widget buildLedgerRenameUseCase(BuildContext context) {
  return Material(
    color: const Color(0x00000000),
    child: Center(
      child: LedgerWalletRenameModal(
        initialName: 'Rowan Ledger',
        onCancel: () {},
        onRename: (_) async {},
      ),
    ),
  );
}

enum LedgerSigningPlaygroundReadiness {
  idle,
  checkingDevice,
  confirmOpening,
  ready,
  failed,
}

enum LedgerSigningPlaygroundFailure {
  retry,
  openApp,
  reconnect,
  accountMismatch,
  saving,
}

Widget buildLedgerSigningPlaygroundUseCase(BuildContext context) {
  final phase = context.knobs.object.dropdown<LedgerSigningModalPhase>(
    label: 'Phase',
    options: LedgerSigningModalPhase.values,
    initialOption: LedgerSigningModalPhase.awaitingDevice,
    labelBuilder: (value) => value.name,
  );
  final readiness = context.knobs.object
      .dropdown<LedgerSigningPlaygroundReadiness>(
        label: 'App readiness',
        options: LedgerSigningPlaygroundReadiness.values,
        initialOption: LedgerSigningPlaygroundReadiness.ready,
        labelBuilder: (value) => value.name,
      );
  final failure = context.knobs.object.dropdown<LedgerSigningPlaygroundFailure>(
    label: 'Failure action',
    options: LedgerSigningPlaygroundFailure.values,
    initialOption: LedgerSigningPlaygroundFailure.retry,
    labelBuilder: (value) => value.name,
  );
  final roundCount = context.knobs.int.slider(
    label: 'Transaction count',
    initialValue: 1,
    min: 1,
    max: 4,
  );
  final roundNumber = context.knobs.int.slider(
    label: 'Current transaction',
    initialValue: 1,
    min: 1,
    max: roundCount,
  );
  final mobile = context.knobs.boolean(label: 'Mobile', initialValue: false);
  final showWaitingHint = context.knobs.boolean(label: 'Show delayed hint');

  return buildLedgerSigningPreview(
    phase: phase,
    readiness: readiness,
    failureMode: failure,
    roundNumber: roundNumber > roundCount ? roundCount : roundNumber,
    roundCount: roundCount,
    mobile: mobile,
    showWaitingHint: showWaitingHint,
  );
}

Widget buildLedgerSigningPreview({
  required LedgerSigningModalPhase phase,
  LedgerSigningPlaygroundReadiness readiness =
      LedgerSigningPlaygroundReadiness.ready,
  LedgerSigningPlaygroundFailure failureMode =
      LedgerSigningPlaygroundFailure.retry,
  int roundNumber = 1,
  int roundCount = 1,
  bool mobile = false,
  bool showWaitingHint = false,
  VoidCallback? onCancel,
  VoidCallback? onFailureAction,
}) {
  final locked =
      phase == LedgerSigningModalPhase.cancelling ||
      phase == LedgerSigningModalPhase.reconnecting ||
      phase == LedgerSigningModalPhase.saving ||
      phase == LedgerSigningModalPhase.broadcasting;
  final modal = LedgerSigningModal(
    phase: phase,
    failure: phase == LedgerSigningModalPhase.failed
        ? _failurePresentation(
            failureMode,
            internalReconnect: onFailureAction == null,
          )
        : null,
    onCancel: locked ? null : onCancel ?? () {},
    onFailureAction: onFailureAction ?? () {},
    showWaitingHint: showWaitingHint,
    accountUuid: _ledgerAccount.uuid,
    roundNumber: roundNumber,
    roundCount: roundCount,
  );
  return ProviderScope(
    overrides: [
      ledgerReconnectProvider.overrideWithValue(
        (_) => Future<void>.delayed(const Duration(milliseconds: 700)),
      ),
      appBootstrapProvider.overrideWithValue(_ledgerBootstrap),
      accountProvider.overrideWith(_LedgerPreviewAccountNotifier.new),
      ledgerTargetPlatformProvider.overrideWithValue(
        mobile ? TargetPlatform.iOS : TargetPlatform.macOS,
      ),
      ledgerAppReadinessStateProvider.overrideWith(
        () => _LedgerPreviewReadinessController(_readinessState(readiness)),
      ),
    ],
    child: mobile
        ? SizedBox(
            width: 393,
            height: 852,
            child: MobileLedgerSigningSurface(
              onBack: () {},
              canLeave: !locked,
              child: modal,
            ),
          )
        : Center(child: modal),
  );
}

/// UI-only lifecycle controls. No Ledger, wallet storage, or broadcast calls.
class LedgerSigningRecoveryPreview extends StatefulWidget {
  const LedgerSigningRecoveryPreview({super.key});

  @override
  State<LedgerSigningRecoveryPreview> createState() =>
      _LedgerSigningRecoveryPreviewState();
}

class _LedgerSigningRecoveryPreviewState
    extends State<LedgerSigningRecoveryPreview> {
  LedgerSigningModalPhase _phase = LedgerSigningModalPhase.coolingDown;
  bool _hint = false;
  bool _mobile = false;
  bool _reconnect = false;

  void _setPhase(LedgerSigningModalPhase phase) => setState(() {
    _phase = phase;
    _hint = false;
  });

  @override
  Widget build(BuildContext context) {
    final readyToAdvance = switch (_phase) {
      LedgerSigningModalPhase.coolingDown => 'Simulate 3-second guard complete',
      LedgerSigningModalPhase.connecting => 'Simulate request sent',
      LedgerSigningModalPhase.cancelling => 'Simulate previous request cleared',
      LedgerSigningModalPhase.reconnecting => 'Simulate connected',
      _ => null,
    };
    return SingleChildScrollView(
      child: Column(
        children: [
          const Text('UI preview only · No device requests are sent'),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              AppButton(
                onPressed: () => setState(() => _mobile = !_mobile),
                child: Text(_mobile ? 'Show desktop' : 'Show mobile'),
              ),
              AppButton(
                onPressed: () {
                  _reconnect = false;
                  _setPhase(LedgerSigningModalPhase.coolingDown);
                },
                child: const Text('Restart preview'),
              ),
              if (readyToAdvance != null)
                AppButton(
                  onPressed: () => _setPhase(switch (_phase) {
                    LedgerSigningModalPhase.coolingDown =>
                      LedgerSigningModalPhase.connecting,
                    LedgerSigningModalPhase.connecting =>
                      LedgerSigningModalPhase.awaitingDevice,
                    LedgerSigningModalPhase.cancelling =>
                      _reconnect
                          ? LedgerSigningModalPhase.failed
                          : LedgerSigningModalPhase.cancelled,
                    LedgerSigningModalPhase.reconnecting =>
                      LedgerSigningModalPhase.readyToRetry,
                    _ => _phase,
                  }),
                  child: Text(readyToAdvance),
                ),
              if (_phase == LedgerSigningModalPhase.awaitingDevice) ...[
                AppButton(
                  onPressed: () => setState(() => _hint = true),
                  child: const Text('Simulate slow response'),
                ),
                AppButton(
                  onPressed: () {
                    _reconnect = true;
                    _setPhase(LedgerSigningModalPhase.cancelling);
                  },
                  child: const Text('Simulate timeout'),
                ),
                AppButton(
                  onPressed: () => _setPhase(LedgerSigningModalPhase.cancelled),
                  child: const Text('Simulate device rejection'),
                ),
              ],
            ],
          ),
          const SizedBox(height: 24),
          buildLedgerSigningPreview(
            phase: _phase,
            mobile: _mobile,
            showWaitingHint: _hint,
            failureMode: LedgerSigningPlaygroundFailure.reconnect,
            onCancel: () {
              _reconnect = false;
              _setPhase(
                _phase == LedgerSigningModalPhase.cancelled ||
                        _phase == LedgerSigningModalPhase.readyToRetry ||
                        _phase == LedgerSigningModalPhase.failed
                    ? LedgerSigningModalPhase.preparing
                    : LedgerSigningModalPhase.cancelling,
              );
            },
            onFailureAction: () => _setPhase(
              _phase == LedgerSigningModalPhase.failed
                  ? LedgerSigningModalPhase.reconnecting
                  : LedgerSigningModalPhase.coolingDown,
            ),
          ),
        ],
      ),
    );
  }
}

Widget buildLedgerVotingPlaygroundUseCase(BuildContext context) {
  final bundleCount = context.knobs.int.slider(
    label: 'Bundle count',
    initialValue: 2,
    min: 1,
    max: 6,
  );
  final requestedBundle = context.knobs.int.slider(
    label: 'Starting bundle',
    initialValue: 1,
    min: 1,
    max: bundleCount,
  );
  final memo = context.knobs.string(
    label: 'Display memo',
    initialValue:
        'Approve voting delegation\nAmount: 0.00000100 ZEC\nRound: community-grants',
  );
  return buildLedgerVotingPreview(
    bundleNumber: requestedBundle > bundleCount ? bundleCount : requestedBundle,
    bundleCount: bundleCount,
    displayMemo: memo,
  );
}

Widget buildLedgerVotingPreview({
  required int bundleNumber,
  required int bundleCount,
  required String displayMemo,
}) {
  assert(bundleNumber > 0 && bundleNumber <= bundleCount);
  return _LedgerVotingPlayground(
    key: ValueKey(
      'ledger-voting-playground-$bundleNumber-$bundleCount-$displayMemo',
    ),
    initialBundleNumber: bundleNumber,
    bundleCount: bundleCount,
    displayMemo: displayMemo,
  );
}

enum _LedgerVotingPreviewStage {
  preparingDevice,
  awaitingApproval,
  delegating,
  castingVotes,
  finalizing,
  complete,
  cancelled,
}

class _LedgerVotingPlayground extends StatefulWidget {
  const _LedgerVotingPlayground({
    required this.initialBundleNumber,
    required this.bundleCount,
    required this.displayMemo,
    super.key,
  });

  final int initialBundleNumber;
  final int bundleCount;
  final String displayMemo;

  @override
  State<_LedgerVotingPlayground> createState() =>
      _LedgerVotingPlaygroundState();
}

class _LedgerVotingPlaygroundState extends State<_LedgerVotingPlayground> {
  _LedgerVotingPreviewStage _stage = _LedgerVotingPreviewStage.preparingDevice;
  late int _bundleNumber = widget.initialBundleNumber;

  void _advance() {
    setState(() {
      switch (_stage) {
        case _LedgerVotingPreviewStage.preparingDevice:
          _stage = _LedgerVotingPreviewStage.awaitingApproval;
        case _LedgerVotingPreviewStage.awaitingApproval:
          if (_bundleNumber < widget.bundleCount) {
            _bundleNumber++;
          } else {
            _stage = _LedgerVotingPreviewStage.delegating;
          }
        case _LedgerVotingPreviewStage.delegating:
          _stage = _LedgerVotingPreviewStage.castingVotes;
        case _LedgerVotingPreviewStage.castingVotes:
          _stage = _LedgerVotingPreviewStage.finalizing;
        case _LedgerVotingPreviewStage.finalizing:
          _stage = _LedgerVotingPreviewStage.complete;
        case _LedgerVotingPreviewStage.complete ||
            _LedgerVotingPreviewStage.cancelled:
          _restart();
      }
    });
  }

  void _cancel() {
    setState(() {
      _stage = _LedgerVotingPreviewStage.cancelled;
    });
  }

  void _restart() {
    _stage = _LedgerVotingPreviewStage.preparingDevice;
    _bundleNumber = widget.initialBundleNumber;
  }

  @override
  Widget build(BuildContext context) {
    final signing =
        _stage == _LedgerVotingPreviewStage.preparingDevice ||
        _stage == _LedgerVotingPreviewStage.awaitingApproval;
    final complete = _stage == _LedgerVotingPreviewStage.complete;
    final cancelled = _stage == _LedgerVotingPreviewStage.cancelled;
    final phase = switch (_stage) {
      _LedgerVotingPreviewStage.preparingDevice ||
      _LedgerVotingPreviewStage.awaitingApproval =>
        VotingSessionPhase.ledgerSigning,
      _LedgerVotingPreviewStage.delegating => VotingSessionPhase.delegating,
      _LedgerVotingPreviewStage.castingVotes => VotingSessionPhase.castingVotes,
      _LedgerVotingPreviewStage.finalizing =>
        VotingSessionPhase.submittingShares,
      _LedgerVotingPreviewStage.complete => VotingSessionPhase.done,
      _LedgerVotingPreviewStage.cancelled => VotingSessionPhase.error,
    };
    final readiness = _stage == _LedgerVotingPreviewStage.preparingDevice
        ? LedgerSigningPlaygroundReadiness.checkingDevice
        : LedgerSigningPlaygroundReadiness.ready;

    return ProviderScope(
      key: ValueKey('ledger-voting-readiness-${readiness.name}'),
      overrides: [
        ledgerAppReadinessStateProvider.overrideWith(
          () => _LedgerPreviewReadinessController(_readinessState(readiness)),
        ),
      ],
      child: Column(
        children: [
          Expanded(
            child: VotingStatusContent(
              phase: phase,
              voteSubmissionDetail:
                  _stage == _LedgerVotingPreviewStage.castingVotes
                  ? '1 of 2 ballots submitted'
                  : null,
              voteSubmissionProgress:
                  _stage == _LedgerVotingPreviewStage.castingVotes
                  ? 0.5
                  : _stage == _LedgerVotingPreviewStage.finalizing || complete
                  ? 1
                  : null,
              delegationProgress: _stage == _LedgerVotingPreviewStage.delegating
                  ? 0.55
                  : null,
              completedSubmission: complete,
              submissionJobComplete: complete,
              submissionJobInFlight: !complete && !cancelled,
              isHardwareAccount: true,
              isLedgerAccount: true,
              ledgerDisplayMemo: signing ? widget.displayMemo : null,
              ledgerSigningBundleIndex: signing ? _bundleNumber - 1 : null,
              ledgerSigningBundleCount: widget.bundleCount,
              errorMessage: cancelled
                  ? 'Ledger voting approval was cancelled.'
                  : null,
              onRetry: cancelled ? () => setState(_restart) : null,
              onCancelLedger: signing ? _cancel : null,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                const Text(
                  'Widgetbook simulation — no device request is sent.',
                ),
                AppButton(
                  key: const ValueKey('ledger_voting_preview_advance'),
                  onPressed: _advance,
                  variant: AppButtonVariant.primary,
                  child: Text(_advanceLabel),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String get _advanceLabel => switch (_stage) {
    _LedgerVotingPreviewStage.preparingDevice => 'Device ready',
    _LedgerVotingPreviewStage.awaitingApproval => 'Simulate Ledger approval',
    _LedgerVotingPreviewStage.delegating => 'Advance to vote submission',
    _LedgerVotingPreviewStage.castingVotes => 'Advance to finalizing',
    _LedgerVotingPreviewStage.finalizing => 'Complete preview',
    _LedgerVotingPreviewStage.complete ||
    _LedgerVotingPreviewStage.cancelled => 'Restart preview',
  };
}

Widget buildLedgerDevicePickerFoundUseCase(BuildContext context) {
  return _buildDevicePicker(
    _ScriptedLedgerMobileBleService(
      updates: const [
        LedgerDevicesDiscovered([
          LedgerBleDevice(
            id: 'flex-1',
            name: 'Ledger Flex',
            model: 'Ledger Flex',
          ),
          LedgerBleDevice(
            id: 'stax-1',
            name: 'Ledger Stax',
            model: 'Ledger Stax',
          ),
        ]),
      ],
    ),
    key: const ValueKey('ledger_picker_devices_found'),
  );
}

Widget buildLedgerDevicePickerEmptyUseCase(BuildContext context) {
  return _buildDevicePicker(
    _ScriptedLedgerMobileBleService(updates: const [LedgerDiscoveryEnded()]),
    key: const ValueKey('ledger_picker_empty'),
  );
}

Widget buildLedgerDevicePickerPermissionDeniedUseCase(BuildContext context) {
  return _buildDevicePicker(
    _ScriptedLedgerMobileBleService(permissionGranted: false),
    key: const ValueKey('ledger_picker_permission_denied'),
  );
}

Widget _buildDevicePicker(LedgerMobileBleService service, {required Key key}) {
  return Center(
    child: SizedBox(
      width: 393,
      child: MobileLedgerDeviceSheet(
        key: key,
        service: service,
        onSelected: (_) {},
        onClose: () {},
      ),
    ),
  );
}

LedgerSigningFailurePresentation _failurePresentation(
  LedgerSigningPlaygroundFailure mode, {
  bool internalReconnect = true,
}) {
  return switch (mode) {
    LedgerSigningPlaygroundFailure.retry =>
      const LedgerSigningFailurePresentation(
        title: 'Ledger signing failed',
        statusLabel: 'Signature not received',
        message: 'Check your Ledger, then try signing again.',
        showDeviceAppPrompt: false,
        actionLabel: 'Try again',
      ),
    LedgerSigningPlaygroundFailure.openApp =>
      const LedgerSigningFailurePresentation(
        title: 'Open the Zcash app',
        statusLabel: 'Zcash app is not ready',
        message: 'Open the Zcash app on your Ledger, then try again.',
        showDeviceAppPrompt: true,
        actionLabel: 'Try again',
      ),
    LedgerSigningPlaygroundFailure.reconnect => LedgerSigningFailurePresentation(
      requiresReconnect: internalReconnect,
      title: 'Let’s reconnect your Ledger',
      statusLabel: 'Ready to reconnect',
      message:
          'Keep your Ledger unlocked. Reconnect first, then choose when to try signing again.',
      isError: false,
      showDeviceAppPrompt: true,
      actionLabel: 'Reconnect',
    ),
    LedgerSigningPlaygroundFailure.accountMismatch =>
      const LedgerSigningFailurePresentation(
        title: 'Check the signing account',
        statusLabel: 'Transaction could not be verified',
        message:
            'Ledger could not match this transaction to the selected account. Go back and check the account before continuing.',
        showDeviceAppPrompt: false,
        actionLabel: 'Back to review',
      ),
    LedgerSigningPlaygroundFailure.saving =>
      const LedgerSigningFailurePresentation(
        title: 'Your signature is ready',
        statusLabel: 'Save to continue',
        message:
            'Vizor could not save the signed transaction. Try saving again. You won’t need to approve it on your Ledger again.',
        isError: false,
        showDeviceAppPrompt: false,
        actionLabel: 'Retry saving',
      ),
  };
}

LedgerAppReadinessState _readinessState(
  LedgerSigningPlaygroundReadiness readiness,
) {
  return switch (readiness) {
    LedgerSigningPlaygroundReadiness.idle =>
      const LedgerAppReadinessState.idle(),
    LedgerSigningPlaygroundReadiness.checkingDevice =>
      const LedgerAppReadinessState.inProgress(
        LedgerAppReadinessPhase.checkingDevice,
      ),
    LedgerSigningPlaygroundReadiness.confirmOpening =>
      const LedgerAppReadinessState.inProgress(
        LedgerAppReadinessPhase.confirmOpening,
      ),
    LedgerSigningPlaygroundReadiness.ready =>
      const LedgerAppReadinessState.ready('3.9.3'),
    LedgerSigningPlaygroundReadiness.failed =>
      const LedgerAppReadinessState.failed(
        failure: LedgerAppReadinessFailure.disconnected,
        message: 'Reconnect your Ledger and open the Zcash app.',
      ),
  };
}

class _LedgerAccountDetailsPreview extends StatefulWidget {
  const _LedgerAccountDetailsPreview({required this.mobile});

  final bool mobile;

  @override
  State<_LedgerAccountDetailsPreview> createState() =>
      _LedgerAccountDetailsPreviewState();
}

class _LedgerAccountDetailsPreviewState
    extends State<_LedgerAccountDetailsPreview> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = GoRouter(
      initialLocation: '/ledger-details',
      routes: [
        GoRoute(
          path: '/ledger-details',
          builder: (_, _) => widget.mobile
              ? const MobileHardwareAccountDetailsScreen(
                  accountUuid: _ledgerAccountUuid,
                )
              : const HardwareAccountDetailsScreen(
                  accountUuid: _ledgerAccountUuid,
                ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        appBootstrapProvider.overrideWithValue(_ledgerBootstrap),
        accountProvider.overrideWith(_LedgerPreviewAccountNotifier.new),
        syncProvider.overrideWith(_LedgerPreviewSyncNotifier.new),
        ledgerTargetPlatformProvider.overrideWithValue(
          widget.mobile ? TargetPlatform.iOS : TargetPlatform.macOS,
        ),
      ],
      child: SizedBox(
        width: widget.mobile ? 393 : 1160,
        height: widget.mobile ? 852 : 760,
        child: MaterialApp.router(routerConfig: _router),
      ),
    );
  }
}

class _LedgerPreviewAccountNotifier extends AccountNotifier {
  @override
  FutureOr<AccountState> build() => _ledgerAccountState;

  @override
  Future<void> updateLedgerConnectionPreference(
    String uuid,
    LedgerConnectionPreference preference,
  ) async {
    final previous = state.value ?? _ledgerAccountState;
    state = AsyncData(
      previous.copyWith(
        accounts: [
          for (final account in previous.accounts)
            if (account.uuid == uuid)
              account.copyWith(ledgerConnectionPreference: preference)
            else
              account,
        ],
      ),
    );
  }

  @override
  Future<void> recordLedgerConnection({
    required String uuid,
    required LedgerConnectionTransport transport,
    String? deviceId,
    String? deviceName,
    String? deviceModel,
  }) async {
    final previous = state.value ?? _ledgerAccountState;
    state = AsyncData(
      previous.copyWith(
        accounts: [
          for (final account in previous.accounts)
            if (account.uuid == uuid)
              account.copyWith(
                ledgerLastTransport: transport,
                ledgerDeviceId: deviceId,
                ledgerDeviceName: deviceName,
                ledgerDeviceModel: deviceModel,
              )
            else
              account,
        ],
      ),
    );
  }
}

class _LedgerPreviewReadinessController extends LedgerAppReadinessController {
  _LedgerPreviewReadinessController(this.initialState);

  final LedgerAppReadinessState initialState;

  @override
  LedgerAppReadinessState build() => initialState;
}

class _LedgerPreviewSyncNotifier extends SyncNotifier {
  @override
  Future<SyncState> build() async => SyncState(
    accountUuid: _ledgerAccountUuid,
    hasAccountScopedData: true,
    isSyncing: false,
    isSyncComplete: true,
    percentage: 1,
  );
}

class _ScriptedLedgerMobileBleService implements LedgerMobileBleService {
  _ScriptedLedgerMobileBleService({
    this.permissionGranted = true,
    this.updates = const [],
  });

  final bool permissionGranted;
  final List<LedgerDiscoveryUpdate> updates;
  String? _connectedDeviceId;

  @override
  String? get connectedDeviceId => _connectedDeviceId;

  @override
  Future<void> cancelSigning() async {}

  @override
  Future<void> connect(LedgerBleDevice device) async {
    _connectedDeviceId = device.id;
  }

  @override
  Future<LedgerMobileAppInfo> currentApp() async =>
      const LedgerMobileAppInfo(name: 'Zcash', version: '3.9.3');

  @override
  Stream<LedgerDiscoveryUpdate> discoverDevices() =>
      Stream.fromIterable(updates);

  @override
  Future<void> disconnect() async {
    _connectedDeviceId = null;
  }

  @override
  Future<List<Uint8List>> exchangeApdus(
    List<rust_ledger.LedgerApduCommand> commands,
  ) async => <Uint8List>[];

  @override
  Future<List<Uint8List>> exchangeUfvk(
    rust_ledger.LedgerUfvkApduPlan plan,
  ) async => <Uint8List>[];

  @override
  Future<bool> requestPermissions() async => permissionGranted;

  @override
  Future<LedgerMobileAppInfo> requestOpenZcashApp() async =>
      const LedgerMobileAppInfo(name: 'Zcash', version: '3.9.3');

  @override
  Future<void> stopDiscovery() async {}
}

const _ledgerAccountUuid = 'widgetbook-ledger-account';
const _ledgerAccount = AccountInfo(
  uuid: _ledgerAccountUuid,
  name: 'Ledger account 1',
  order: 0,
  isHardware: true,
  hardwareSignerKind: HardwareSignerKind.ledger,
  birthdayHeight: 2870000,
  zip32AccountIndex: 0,
  ledgerConnectionPreference: LedgerConnectionPreference.automatic,
  ledgerLastTransport: LedgerConnectionTransport.usb,
  ledgerDeviceId: 'widgetbook-ledger-flex',
  ledgerDeviceName: 'Ledger Flex',
  ledgerDeviceModel: 'Ledger Flex',
  ledgerWalletName: 'Rowan Ledger',
);

const _ledgerAccountState = AccountState(
  accounts: [_ledgerAccount],
  activeAccountUuid: _ledgerAccountUuid,
  activeAddress: 'u1widgetbookledgeraddress',
);

final _ledgerBootstrap = AppBootstrapState(
  initialLocation: '/ledger-details',
  initialAccountState: _ledgerAccountState,
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.system,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);
