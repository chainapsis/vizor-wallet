import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Coarse user-facing stages, independent of device connection/readiness state.
enum LedgerSigningStage { preparing, sending, reviewing, finishing }

class LedgerSigningProgress {
  const LedgerSigningProgress(this.accountUuid, this.stage);
  final String accountUuid;
  final LedgerSigningStage stage;
}

class LedgerSigningProgressController extends Notifier<LedgerSigningProgress?> {
  int _generation = 0;

  @override
  LedgerSigningProgress? build() {
    ref.onDispose(() => _generation++);
    return null;
  }

  /// Each attempt owns its observer. Late native/USB events cannot update a retry.
  void Function(String) begin(String accountUuid) {
    final generation = ++_generation;
    state = LedgerSigningProgress(accountUuid, LedgerSigningStage.preparing);
    return (phase) {
      if (generation != _generation) return;
      final stage = switch (phase) {
        'sending' => LedgerSigningStage.sending,
        'reviewing' => LedgerSigningStage.reviewing,
        'finishing' => LedgerSigningStage.finishing,
        _ => null,
      };
      if (stage != null && stage.index > (state?.stage.index ?? -1)) {
        state = LedgerSigningProgress(accountUuid, stage);
      }
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
  String get message => switch (this) {
    LedgerSigningStage.preparing =>
      'Please wait while Vizor prepares your transaction.',
    LedgerSigningStage.sending =>
      'Keep your Ledger connected. This may take a while.',
    LedgerSigningStage.reviewing =>
      'Review and approve when prompted on your Ledger.',
    LedgerSigningStage.finishing => 'Keep Vizor open.',
  };
  String get status =>
      this == LedgerSigningStage.reviewing ? 'Review on device' : 'Please wait';
}
