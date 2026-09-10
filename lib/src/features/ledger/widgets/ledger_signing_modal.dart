import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_modal_card.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../ledger_capability.dart';
import '../services/ledger_app_readiness_service.dart';
import '../services/ledger_connection_recovery.dart';
import '../services/ledger_connection_service.dart';
import '../services/ledger_pairing_code_provider.dart';
import '../../onboarding/mobile/mobile_ledger_connect_screen.dart';
import 'ledger_device_signing_content.dart';
import 'ledger_app_step_card.dart';
import '../ledger_app_instructions.dart' show ledgerZcashAppName;

enum LedgerSigningModalPhase {
  preparing,
  connecting,
  coolingDown,
  cancelling,
  reconnecting,
  cancelled,
  readyToRetry,
  awaitingDevice,
  saving,
  broadcasting,
  failed,
}

class LedgerSigningFailurePresentation {
  const LedgerSigningFailurePresentation({
    required this.title,
    required this.statusLabel,
    required this.message,
    this.actionLabel,
    this.isError = true,
    this.requiresReconnect = false,
    this.canChangeConnection = true,
  });

  final String title;
  final String statusLabel;
  final String message;
  final String? actionLabel;
  final bool isError;
  final bool requiresReconnect;
  final bool canChangeConnection;
}

/// The device signed, but Vizor could not save the signed operation. Nothing
/// was broadcast, so retrying the save never asks the device again and Cancel
/// abandons the signature.
const kLedgerCheckpointFailurePresentation = LedgerSigningFailurePresentation(
  title: 'Could not save signed transaction',
  statusLabel: 'Signature preserved',
  message:
      'Your Ledger signature is preserved. Retry saving without approving another transaction, or cancel to discard the signed transaction.',
  actionLabel: 'Retry saving',
);

class LedgerSigningModal extends ConsumerStatefulWidget {
  const LedgerSigningModal({
    required this.phase,
    required this.failure,
    required this.onCancel,
    required this.onFailureAction,
    this.cancelLabel = 'Cancel',
    this.recoveryActionLabel = 'Try again',
    this.recoveryReadyMessage =
        'Choose Try again when you’re ready to review the transaction on your Ledger.',
    this.accountUuid,
    this.roundNumber = 1,
    this.roundCount = 1,
    this.showWaitingHint = false,
    this.pageLayout = false,
    super.key,
  }) : assert(roundNumber > 0 && roundNumber <= roundCount),
       assert(roundCount > 0),
       assert(
         phase == LedgerSigningModalPhase.failed || failure == null,
         'Failure presentation is only valid for the failed phase.',
       ),
       assert(
         phase != LedgerSigningModalPhase.failed || failure != null,
         'The failed phase requires an explicit presentation.',
       );

  final LedgerSigningModalPhase phase;
  final LedgerSigningFailurePresentation? failure;
  final VoidCallback? onCancel;
  final VoidCallback? onFailureAction;
  final String cancelLabel;
  final String recoveryActionLabel;
  final String recoveryReadyMessage;
  final String? accountUuid;
  final int roundNumber;
  final int roundCount;
  final bool showWaitingHint;
  final bool pageLayout;

  @override
  ConsumerState<LedgerSigningModal> createState() => _LedgerSigningModalState();
}

class _LedgerSigningModalState extends ConsumerState<LedgerSigningModal> {
  final _recovery = LedgerConnectionRecoveryController();
  bool _pairingConfirmed = false;
  LedgerSigningModalPhase? get _recoveryPhase => switch (_recovery.phase) {
    LedgerConnectionRecoveryPhase.reconnecting =>
      LedgerSigningModalPhase.reconnecting,
    LedgerConnectionRecoveryPhase.ready => LedgerSigningModalPhase.readyToRetry,
    _ => null,
  };
  String? get _recoveryError => _recovery.message;

  @override
  void initState() {
    super.initState();
    _recovery.addListener(_onRecoveryChanged);
  }

  void _onRecoveryChanged() {
    if (mounted) setState(() {});
  }

  Object _context(LedgerSigningModal modal) => (
    modal.accountUuid,
    modal.phase,
    modal.roundNumber,
    modal.failure?.message,
    modal.failure?.actionLabel,
    modal.failure?.requiresReconnect,
  );

  @override
  void didUpdateWidget(LedgerSigningModal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_context(oldWidget) != _context(widget)) {
      _recovery.reset();
    }
  }

  Future<void> _reconnect() {
    final originalContext = _context(widget);
    return _recovery.reconnect(widget.accountUuid!, (uuid) async {
      final account = ref
          .read(accountProvider)
          .value
          ?.accounts
          .where((account) => account.uuid == uuid)
          .firstOrNull;
      final mobile = isLedgerMobilePlatform(
        ref.read(ledgerTargetPlatformProvider),
      );
      if (mobile &&
          account?.isLedger == true &&
          (account!.ledgerDeviceId?.isNotEmpty != true)) {
        final connected = await Navigator.of(context, rootNavigator: true)
            .push<bool>(
              MaterialPageRoute(
                builder: (_) =>
                    MobileLedgerConnectScreen(connectionAccountUuid: uuid),
              ),
            );
        if (!mounted || _context(widget) != originalContext) return;
        if (connected != true) {
          throw const LedgerConnectionRequiredException(
            'Connect your Ledger before retrying.',
          );
        }
        return;
      }
      await ref.read(ledgerReconnectProvider)(uuid);
    });
  }

  @override
  void dispose() {
    _recovery.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final phase = _recoveryPhase ?? widget.phase;
    final accountUuid = widget.accountUuid;
    final onCancel = widget.onCancel;
    final cancelLabel = widget.cancelLabel;
    final roundNumber = widget.roundNumber;
    final roundCount = widget.roundCount;
    final showWaitingHint = widget.showWaitingHint;
    final needsReconnect =
        widget.failure?.requiresReconnect == true && accountUuid != null;
    final onFailureAction =
        needsReconnect && _recoveryPhase != LedgerSigningModalPhase.readyToRetry
        ? () => unawaited(_reconnect())
        : widget.onFailureAction;
    final networkName = ref.watch(
      rpcEndpointProvider.select((endpoint) => endpoint.networkName),
    );
    final appName = ledgerZcashAppName(networkName);
    final readiness = ref.watch(ledgerAppReadinessStateProvider);
    final account = _ledgerAccount(ref, accountUuid);
    final failed = phase == LedgerSigningModalPhase.failed;
    final failure = widget.failure;
    final destructive = failed && failure!.isError && !needsReconnect;
    final settling =
        phase == LedgerSigningModalPhase.cancelling ||
        phase == LedgerSigningModalPhase.reconnecting;
    final approving = switch (phase) {
      LedgerSigningModalPhase.preparing ||
      LedgerSigningModalPhase.connecting ||
      LedgerSigningModalPhase.coolingDown ||
      LedgerSigningModalPhase.awaitingDevice => true,
      _ => false,
    };
    var title = switch (phase) {
      LedgerSigningModalPhase.preparing => 'Preparing for Ledger',
      LedgerSigningModalPhase.connecting => 'Connecting to your Ledger',
      LedgerSigningModalPhase.coolingDown => 'Getting your Ledger ready',
      LedgerSigningModalPhase.cancelling => 'Finishing your request',
      LedgerSigningModalPhase.reconnecting => 'Reconnecting your Ledger',
      LedgerSigningModalPhase.cancelled => 'Request canceled',
      LedgerSigningModalPhase.readyToRetry => 'Your Ledger is connected',
      LedgerSigningModalPhase.awaitingDevice => 'Review on your Ledger',
      LedgerSigningModalPhase.saving => 'Saving signed transaction',
      LedgerSigningModalPhase.broadcasting => 'Sending transaction',
      LedgerSigningModalPhase.failed => failure!.title,
    };
    var message = switch (phase) {
      LedgerSigningModalPhase.preparing =>
        'Vizor is preparing the transaction for secure device review.',
      LedgerSigningModalPhase.connecting =>
        'Keep your Ledger connected and unlocked.',
      LedgerSigningModalPhase.coolingDown =>
        'This will only take a moment. Keep your Ledger connected.',
      LedgerSigningModalPhase.cancelling =>
        'Vizor is waiting for the previous device request to finish before you can try again.',
      LedgerSigningModalPhase.reconnecting =>
        'Keep your Ledger connected and unlocked. Reconnecting will not send a new signing request.',
      LedgerSigningModalPhase.cancelled =>
        'You can go back or try again when you’re ready.',
      LedgerSigningModalPhase.readyToRetry => widget.recoveryReadyMessage,
      LedgerSigningModalPhase.awaitingDevice =>
        'Review every transaction detail on the device, then approve or reject it.',
      LedgerSigningModalPhase.saving =>
        'Keep Vizor open while the signed transaction is saved securely.',
      LedgerSigningModalPhase.broadcasting =>
        'Keep Vizor open while the transaction is sent.',
      LedgerSigningModalPhase.failed => failure!.message,
    };

    var statusLabel = failed ? failure!.statusLabel : null;
    if (failed && needsReconnect) {
      title = 'Let’s reconnect your Ledger';
      message =
          _recoveryError ??
          'Your signing request was interrupted. Reconnect first, then choose when to try signing again.';
    }
    if (!needsReconnect &&
        phase == LedgerSigningModalPhase.failed &&
        readiness.phase == LedgerAppReadinessPhase.failed) {
      title = 'Ledger needs attention';
      statusLabel = 'Action needed';
      message = readiness.message!;
    }
    if (approving) {
      title = 'Approve with Ledger';
      message = 'Keep your Ledger connected and unlocked.';
      if (phase == LedgerSigningModalPhase.awaitingDevice) {
        if (readiness.phase == LedgerAppReadinessPhase.confirmOpening) {
          message = 'Confirm the app opening request on your Ledger.';
        } else if (readiness.phase != LedgerAppReadinessPhase.checkingDevice) {
          message = 'Check the details on your Ledger before approving.';
        }
      }
    }
    final String? actionLabel = failed
        ? needsReconnect
              ? 'Reconnect'
              : failure!.actionLabel
        : phase == LedgerSigningModalPhase.saving
        ? 'Saving'
        : null;
    final opening =
        phase == LedgerSigningModalPhase.awaitingDevice &&
        readiness.phase == LedgerAppReadinessPhase.confirmOpening;
    final reviewing =
        phase == LedgerSigningModalPhase.awaitingDevice &&
        readiness.phase == LedgerAppReadinessPhase.ready;
    final ready = phase == LedgerSigningModalPhase.readyToRetry;
    final cancelled = phase == LedgerSigningModalPhase.cancelled;
    // Linux pairs through Vizor's own agent, so the code to compare with the
    // Ledger is shown here rather than in a system prompt. A pairing can
    // surface during any connect this request makes, so every in-flight
    // phase watches for it.
    final pairingCode = !failed && !ready && !cancelled
        ? ref.watch(ledgerPairingCodeProvider).value
        : null;
    // A confirmation belongs to one code: a new prompt asks again.
    ref.listen<AsyncValue<String?>>(ledgerPairingCodeProvider, (
      previous,
      next,
    ) {
      if (_pairingConfirmed && next.value != previous?.value) {
        setState(() => _pairingConfirmed = false);
      }
    });
    final pairingPrompt = pairingCode != null && !_pairingConfirmed;
    final appStep = _appStepFor(
      phase: phase,
      readiness: readiness,
      needsReconnect: needsReconnect,
      pairing: pairingCode != null,
    );
    final guidanceTitle = pairingCode != null
        ? _pairingConfirmed
              ? 'Approve pairing on your Ledger'
              : 'Confirm pairing on your Ledger'
        : approving
        ? opening
              ? 'Open the $appName app'
              : reviewing
              ? 'Your turn on Ledger'
              : 'Getting ready'
        : ready
        ? 'Ready when you are'
        : title;
    const reconnectMessage =
        'Keep your Ledger connected and unlocked. Reconnecting will not send a new signing request.';
    final guidanceMessage = pairingCode != null
        ? _pairingConfirmed
              ? 'Approve the pairing on your Ledger to continue.'
              : 'Pair only if your Ledger shows the same code.'
        : showWaitingHint && reviewing
        ? 'No request on your Ledger? Make sure it’s unlocked and the $appName app is open.'
        : approving && !opening && !reviewing
        ? 'Keep your Ledger connected and unlocked.'
        : message;
    // The status card heading says what the device is doing right now; the
    // header keeps the request's headline, so the two never repeat.
    final statusTitle = pairingCode != null
        ? 'Pairing code'
        : reviewing
        ? 'Waiting for your approval'
        : opening
        ? 'Waiting for you on Ledger'
        : failed
        ? (statusLabel ?? 'Action needed')
        : switch (phase) {
            LedgerSigningModalPhase.preparing => 'Preparing transaction',
            LedgerSigningModalPhase.connecting => 'Connecting',
            LedgerSigningModalPhase.coolingDown => 'Almost ready',
            LedgerSigningModalPhase.reconnecting => 'Reconnecting',
            LedgerSigningModalPhase.cancelling =>
              'Finishing the previous request',
            LedgerSigningModalPhase.cancelled => 'Canceled',
            LedgerSigningModalPhase.readyToRetry => 'Connected',
            LedgerSigningModalPhase.awaitingDevice => 'Checking your Ledger',
            LedgerSigningModalPhase.saving => 'Securing transaction',
            LedgerSigningModalPhase.broadcasting =>
              'Broadcasting to the network',
            LedgerSigningModalPhase.failed => statusLabel ?? 'Action needed',
          };
    final content = LedgerDeviceSigningContent(
      pageLayout: widget.pageLayout,
      accountName: account?.name ?? 'Ledger',
      appStep: LedgerAppStepCard(
        appName: appName,
        hint: appStep.hint,
        state: appStep.state,
      ),
      title: guidanceTitle,
      statusTitle: statusTitle,
      badge: roundCount > 1 && !failed && !ready && !cancelled
          ? '$roundNumber of $roundCount'
          : null,
      detailLabel: pairingCode,
      connectionPicker:
          failed &&
              failure!.canChangeConnection &&
              account != null &&
              (ref.watch(ledgerTargetPlatformProvider) ==
                      TargetPlatform.macOS ||
                  ref.watch(ledgerTargetPlatformProvider) ==
                      TargetPlatform.windows ||
                  ref.watch(ledgerTargetPlatformProvider) ==
                      TargetPlatform.linux)
          ? _LedgerFailureConnectionPicker(account: account)
          : null,
      message: guidanceMessage,
      busy:
          pairingCode == null &&
          !failed &&
          !ready &&
          !cancelled &&
          !opening &&
          !reviewing,
      attention: pairingCode != null || opening || reviewing,
      destructive: destructive,
      complete: ready,
      reservedMessages: [reconnectMessage, widget.recoveryReadyMessage],
      primaryLabel: pairingPrompt
          ? 'Codes match'
          : ready
          ? widget.recoveryActionLabel
          : cancelled
          ? 'Try again'
          : failed
          ? actionLabel
          : null,
      onPrimary: pairingPrompt
          ? () => unawaited(_answerPairing(true))
          : settling
          ? null
          : (ready || cancelled || failed)
          ? onFailureAction
          : null,
      secondaryLabel: pairingPrompt
          ? 'Codes differ'
          : cancelled
          ? 'Back'
          : cancelLabel,
      showSecondary: pairingPrompt || onCancel != null || settling,
      onSecondary: pairingPrompt
          ? () => unawaited(_answerPairing(false))
          : settling
          ? null
          : onCancel,
    );
    if (widget.pageLayout) return content;
    return AppModalCard(
      width: 360,
      child: SingleChildScrollView(child: content),
    );
  }

  /// Where the device app stands: connecting and pairing fold into it, since
  /// nothing can be open before the device is reachable.
  static ({LedgerAppStepState state, String hint}) _appStepFor({
    required LedgerSigningModalPhase phase,
    required LedgerAppReadinessState readiness,
    required bool needsReconnect,
    required bool pairing,
  }) {
    if (pairing) {
      return (
        state: LedgerAppStepState.active,
        hint: 'Confirm the pairing code',
      );
    }
    return switch (phase) {
      LedgerSigningModalPhase.preparing ||
      LedgerSigningModalPhase.connecting ||
      LedgerSigningModalPhase.coolingDown ||
      LedgerSigningModalPhase.reconnecting => (
        state: LedgerAppStepState.active,
        hint: 'Connecting to your Ledger',
      ),
      LedgerSigningModalPhase.readyToRetry => (
        state: LedgerAppStepState.done,
        hint: 'Connected',
      ),
      LedgerSigningModalPhase.awaitingDevice => switch (readiness.phase) {
        LedgerAppReadinessPhase.ready => (
          state: LedgerAppStepState.done,
          hint: 'Open on your Ledger',
        ),
        LedgerAppReadinessPhase.confirmOpening => (
          state: LedgerAppStepState.active,
          hint: 'Confirm on your Ledger',
        ),
        LedgerAppReadinessPhase.failed => (
          state: LedgerAppStepState.failed,
          hint: 'Not open',
        ),
        LedgerAppReadinessPhase.idle ||
        LedgerAppReadinessPhase.checkingDevice => (
          state: LedgerAppStepState.active,
          hint: 'Checking',
        ),
      },
      LedgerSigningModalPhase.failed when needsReconnect => (
        state: LedgerAppStepState.failed,
        hint: 'Reconnect your Ledger',
      ),
      LedgerSigningModalPhase.failed
          when readiness.phase == LedgerAppReadinessPhase.failed =>
        (state: LedgerAppStepState.failed, hint: 'Not open'),
      LedgerSigningModalPhase.cancelling ||
      LedgerSigningModalPhase.cancelled ||
      LedgerSigningModalPhase.saving ||
      LedgerSigningModalPhase.broadcasting ||
      LedgerSigningModalPhase.failed => (
        state: LedgerAppStepState.done,
        hint: 'Open on your Ledger',
      ),
    };
  }

  Future<void> _answerPairing(bool accept) async {
    if (accept) setState(() => _pairingConfirmed = true);
    try {
      await ref.read(ledgerPairingAnswerProvider)(accept: accept);
    } catch (_) {
      // The pending connect reports the outcome either way.
    }
  }

  static AccountInfo? _ledgerAccount(WidgetRef ref, String? uuid) {
    if (uuid == null) return null;
    final accounts = ref.watch(accountProvider).value?.accounts ?? const [];
    for (final account in accounts) {
      if (account.uuid == uuid && account.isLedger) return account;
    }
    return null;
  }
}

class _LedgerFailureConnectionPicker extends ConsumerWidget {
  const _LedgerFailureConnectionPicker({required this.account});

  final AccountInfo account;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bluetoothAvailable =
        account.ledgerDeviceId != null &&
        ledgerBluetoothTransportCapabilityForModel(
              model: account.ledgerDeviceModel,
              platform: ref.watch(ledgerTargetPlatformProvider),
            ) !=
            LedgerBluetoothCapability.unsupported;
    return Container(
      key: const ValueKey('ledger_failure_connection_picker'),
      padding: const EdgeInsets.all(AppSpacing.s),
      decoration: BoxDecoration(
        color: context.colors.background.neutralSubtleOpacity,
        borderRadius: BorderRadius.circular(AppRadii.medium),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Try another connection',
            style: AppTypography.bodySmall.copyWith(
              color: context.colors.text.secondary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final option in LedgerConnectionPreference.values) ...[
                if (option != LedgerConnectionPreference.automatic)
                  const SizedBox(height: AppSpacing.xxs),
                Semantics(
                  selected: account.ledgerConnectionPreference == option,
                  child: AppButton(
                    key: ValueKey('ledger_connection_${option.name}'),
                    onPressed:
                        option == LedgerConnectionPreference.bluetooth &&
                            !bluetoothAvailable
                        ? null
                        : () => unawaited(
                            ref
                                .read(accountProvider.notifier)
                                .updateLedgerConnectionPreference(
                                  account.uuid,
                                  option,
                                ),
                          ),
                    variant: account.ledgerConnectionPreference == option
                        ? AppButtonVariant.primary
                        : AppButtonVariant.secondary,
                    size: AppButtonSize.medium,
                    constrainContent: true,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(switch (option) {
                            LedgerConnectionPreference.automatic => 'Auto',
                            LedgerConnectionPreference.usb => 'USB',
                            LedgerConnectionPreference.bluetooth => 'Bluetooth',
                          }),
                        ),
                        if (account.ledgerConnectionPreference == option)
                          AppIcon(
                            AppIcons.check,
                            key: ValueKey(
                              'ledger_connection_selected_${option.name}',
                            ),
                            size: 16,
                          )
                        else
                          const SizedBox(width: 16),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (!bluetoothAvailable) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'Set up Bluetooth from Account details before using it for signing.',
              style: AppTypography.bodySmall.copyWith(
                color: context.colors.text.secondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
