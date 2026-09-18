import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Coarse user-facing stages, independent of device connection/readiness state.
enum LedgerSigningStage { preparing, sending, reviewing, finishing }

typedef LedgerSigningProgressReporter =
    void Function(String phase, {String? deviceModel});

class LedgerSigningProgress {
  const LedgerSigningProgress(this.accountUuid, this.stage, {this.deviceModel});
  final String accountUuid;
  final LedgerSigningStage stage;

  /// The device selected for this attempt, not persisted account metadata.
  final String? deviceModel;
}

class LedgerSigningProgressController extends Notifier<LedgerSigningProgress?> {
  int _generation = 0;

  @override
  LedgerSigningProgress? build() {
    ref.onDispose(() => _generation++);
    return null;
  }

  /// Each attempt owns its observer. Late native/USB events cannot update a retry.
  LedgerSigningProgressReporter begin(String accountUuid) {
    final generation = ++_generation;
    state = LedgerSigningProgress(accountUuid, LedgerSigningStage.preparing);
    return (phase, {deviceModel}) {
      if (generation != _generation) return;
      final stage = switch (phase) {
        'preparing' => LedgerSigningStage.preparing,
        'sending' => LedgerSigningStage.sending,
        'reviewing' => LedgerSigningStage.reviewing,
        'finishing' => LedgerSigningStage.finishing,
        _ => null,
      };
      final current = state;
      if (stage == null || current == null) return;
      final nextStage = stage.index > current.stage.index
          ? stage
          : current.stage;
      final nextModel = deviceModel ?? current.deviceModel;
      if (nextStage == current.stage && nextModel == current.deviceModel) {
        return;
      }
      state = LedgerSigningProgress(
        accountUuid,
        nextStage,
        deviceModel: nextModel,
      );
    };
  }

  void cancel() {
    final generation = ++_generation;
    // Callers also cancel from widget disposal. Invalidate events immediately,
    // but notify UI listeners after that lifecycle has finished.
    scheduleMicrotask(() {
      if (generation == _generation) state = null;
    });
  }
}

final ledgerSigningProgressProvider =
    NotifierProvider<LedgerSigningProgressController, LedgerSigningProgress?>(
      LedgerSigningProgressController.new,
    );

extension LedgerSigningStageCopy on LedgerSigningStage {
  String get title => switch (this) {
    LedgerSigningStage.preparing => 'Preparing transaction',
    LedgerSigningStage.sending => 'Processing with Ledger',
    LedgerSigningStage.reviewing => 'Check your Ledger',
    LedgerSigningStage.finishing => 'Finishing transaction',
  };
  String get message => messageForDevice(null);

  String messageForDevice(String? deviceModel) => switch (this) {
    LedgerSigningStage.preparing =>
      'Please wait while Vizor prepares your transaction.',
    LedgerSigningStage.sending =>
      ledgerHasShortSigningWait(deviceModel)
          ? 'Keep your Ledger connected. This may take up to 10 seconds.'
          : 'Keep your Ledger connected. This may take about 30 seconds.',
    LedgerSigningStage.reviewing =>
      'Review and approve when prompted on your Ledger.',
    LedgerSigningStage.finishing => 'Keep Vizor open.',
  };
  String get status => switch (this) {
    LedgerSigningStage.sending => 'Preparing to sign',
    LedgerSigningStage.reviewing => 'Review on device',
    _ => 'Please wait',
  };
}

/// Accept model identifiers exposed by USB and native Bluetooth discovery.
/// Unknown and future models use the longer guidance.
bool ledgerHasShortSigningWait(String? deviceModel) {
  final model = (deviceModel ?? '')
      .toLowerCase()
      .replaceAll(RegExp('[^a-z0-9]'), '')
      .replaceFirst(RegExp('^ledger'), '');
  return const {
    'stax',
    'flex',
    'staxflex',
    'flexstax',
    'europa',
  }.contains(model);
}
